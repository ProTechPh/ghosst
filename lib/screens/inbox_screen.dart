import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../announcement_banner.dart';
import '../services/direct_chat_service.dart';
import '../services/worker_backend.dart';
import '../theme.dart';
import 'direct_chat_screen.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({
    super.key,
    this.client,
    this.loadUsers,
    this.searchUsers,
    this.onOpenThread,
    this.embedded = false,
    this.onOpenWorldChat,
    this.onUnreadChanged,
    this.loadAnnouncements,
    this.loadReelNotifications,
    this.markReelNotificationsRead,
    this.onOpenReelNotification,
  });

  /// Latest app announcements, shown as the Inbox notification card.
  final Future<List<Announcement>> Function()? loadAnnouncements;

  /// Reel activity on the separate Activity page of this inbox.
  final Future<
    ({List<ReelNotification> notifications, int unreadCount, int nextOffset})
  >
  Function()?
  loadReelNotifications;
  final Future<int> Function({String? id})? markReelNotificationsRead;
  final void Function(String reelId, {required bool openComments})?
  onOpenReelNotification;

  final DirectChatClient? client;
  final Future<List<ChatUserSummary>> Function(List<String> ids)? loadUsers;
  final Future<List<ChatUserSummary>> Function(String query)? searchUsers;
  final void Function(DirectThread thread, ChatUserSummary peer)? onOpenThread;
  final bool embedded;
  final VoidCallback? onOpenWorldChat;
  final ValueChanged<int>? onUnreadChanged;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  late final DirectChatClient _client = widget.client ?? DirectChatService();
  StreamSubscription<List<DirectThread>>? _sub;
  List<DirectThread> _threads = const [];
  final Map<String, ChatUserSummary> _users = {};
  String? _myId;
  bool _loading = true;
  bool _failed = false;
  List<Announcement> _notifications = const [];
  String _notificationsSeenAt = '';
  String _page = 'messages';
  List<ReelNotification> _activity = const [];
  int _activityUnread = 0;
  bool _activityLoading = true;
  bool _activityFailed = false;

  @override
  void initState() {
    super.initState();
    _subscribe();
    unawaited(_loadNotifications());
    unawaited(_loadActivity());
  }

  Future<void> _loadActivity() async {
    setState(() {
      _activityLoading = true;
      _activityFailed = false;
    });
    try {
      final page =
          await (widget.loadReelNotifications ?? Backend.reelNotifications)();
      if (!mounted) return;
      setState(() {
        _activity = page.notifications;
        _activityUnread = page.unreadCount;
        _activityLoading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _activityLoading = false;
          _activityFailed = true;
        });
      }
    }
  }

  void _openActivityNotification(ReelNotification item) {
    widget.onOpenReelNotification?.call(
      item.reelId,
      openComments: item.type != 'like',
    );
    unawaited(_markActivityNotificationRead(item));
  }

  Future<void> _markActivityNotificationRead(ReelNotification item) async {
    try {
      final unread =
          await (widget.markReelNotificationsRead ??
              Backend.markReelNotificationsRead)(id: item.id);
      if (!mounted) return;
      setState(() {
        _activityUnread = unread;
        _activity = [
          for (final row in _activity)
            row.id == item.id
                ? ReelNotification(
                    id: row.id,
                    type: row.type,
                    actor: row.actor,
                    reelId: row.reelId,
                    commentId: row.commentId,
                    text: row.text,
                    createdAt: row.createdAt,
                    isRead: true,
                  )
                : row,
        ];
      });
    } catch (_) {
      // Best effort: the row stays unread until the next reload.
    }
  }

  Future<void> _markActivityRead() async {
    try {
      final unread =
          await (widget.markReelNotificationsRead ??
              Backend.markReelNotificationsRead)();
      if (mounted) {
        setState(() {
          _activityUnread = unread;
          _activity = [
            for (final row in _activity)
              ReelNotification(
                id: row.id,
                type: row.type,
                actor: row.actor,
                reelId: row.reelId,
                commentId: row.commentId,
                text: row.text,
                createdAt: row.createdAt,
                isRead: true,
              ),
          ];
        });
      }
    } catch (_) {
      // Best effort: the page keeps its unread state for the next retry.
    }
  }

  bool _announcementUnread(Announcement item, String seen) {
    final created = Backend.readTimestamp(item.createdAt);
    if (created.isEmpty || seen.isEmpty) return true;
    return created.compareTo(seen) > 0;
  }

  Future<void> _loadNotifications() async {
    try {
      final items = await (widget.loadAnnouncements ?? Backend.announcements)();
      if (!mounted) return;
      setState(() => _notifications = items);
      if (items.isEmpty) return;
      try {
        final seen = (await Backend.reads())?.announcementsSeenAt ?? '';
        if (mounted) {
          setState(() => _notificationsSeenAt = seen);
        }
      } catch (_) {
        // Reads are optional — never block the inbox.
      }
    } catch (_) {
      // Notifications are optional — never block the inbox.
    }
  }

  Future<void> _openNotification(Announcement item) async {
    await showAnnouncementSheet(context, item);
    await Backend.markReads(
      announcementsSeenAt: DateTime.now().toUtc().toIso8601String(),
    ).catchError((Object _) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _subscribe() {
    _sub?.cancel();
    setState(() {
      _loading = true;
      _failed = false;
    });
    _client
        .currentUid()
        .then((id) {
          if (!mounted) return;
          if (id == null || id.isEmpty) {
            setState(() {
              _loading = false;
              _failed = true;
            });
            widget.onUnreadChanged?.call(0);
            return;
          }
          setState(() => _myId = id);
          _sub = _client.threads().listen(
            (threads) {
              if (!mounted) return;
              final sorted = [...threads]
                ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
              setState(() {
                _threads = sorted;
                _loading = false;
                _failed = false;
              });
              widget.onUnreadChanged?.call(
                sorted.where((thread) => thread.isUnread(id)).length,
              );
              _loadPeers(sorted);
            },
            onError: (Object _) {
              if (!mounted) return;
              setState(() {
                _loading = false;
                _failed = true;
              });
              widget.onUnreadChanged?.call(0);
            },
          );
        })
        .catchError((Object _) {
          if (mounted) {
            setState(() {
              _loading = false;
              _failed = true;
            });
            widget.onUnreadChanged?.call(0);
          }
        });
  }

  Future<void> _loadPeers(List<DirectThread> threads) async {
    final myId = _myId;
    if (myId == null) return;
    final missing = <String>{
      for (final thread in threads)
        if (thread.peerId(myId).isNotEmpty &&
            !_users.containsKey(thread.peerId(myId)))
          thread.peerId(myId),
    }.toList();
    if (missing.isEmpty) return;
    try {
      final users = await (widget.loadUsers ?? Backend.chatUsers)(missing);
      if (mounted) {
        setState(() {
          for (final user in users) {
            _users[user.id] = user;
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          for (final id in missing) {
            _users[id] = ChatUserSummary(id: id, name: 'Member #$id');
          }
        });
      }
    }
  }

  Future<void> _newMessage() async {
    final peer = await showModalBottomSheet<ChatUserSummary>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg,
      builder: (_) =>
          _NewMessageSheet(search: widget.searchUsers ?? Backend.searchUsers),
    );
    if (peer == null || !mounted) return;
    _openPeer(peer);
  }

  void _openPeer(ChatUserSummary peer) {
    final myId = _myId;
    if (myId == null || peer.id == myId) return;
    final id = directThreadId(myId, peer.id);
    final thread = DirectThread(
      id: id,
      participants: id.split('__'),
      lastMessage: '',
      lastMessageAt: 0,
      lastSenderId: '',
      lastReadAt: const {},
      createdAt: 0,
      updatedAt: 0,
    );
    _openThread(thread, peer);
  }

  Future<void> _openThread(DirectThread thread, ChatUserSummary peer) async {
    unawaited(_client.markRead(thread.id).catchError((_) {}));
    if (!mounted) return;
    final callback = widget.onOpenThread;
    if (callback != null) {
      callback(thread, peer);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DirectChatScreen(
          peerId: peer.id,
          peerName: peer.name,
          peerAvatarUrl: peer.avatarUrl,
          client: _client,
        ),
      ),
    );
  }

  Widget _circle({
    required String label,
    required VoidCallback onTap,
    Key? key,
    String? avatarUrl,
    String? initial,
    IconData? icon,
    Color ring = AppColors.primary,
    double itemWidth = 68,
  }) => GestureDetector(
    key: key,
    onTap: onTap,
    child: SizedBox(
      width: itemWidth,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: ring, width: 2),
              ),
              child: CircleAvatar(
                backgroundColor: AppColors.surfaceHigh,
                backgroundImage: avatarUrl == null || avatarUrl.isEmpty
                    ? null
                    : CachedNetworkImageProvider(avatarUrl),
                child: icon != null
                    ? Icon(icon, color: AppColors.primary, size: 24)
                    : Text(initial ?? '?', style: AppText.subtitle),
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _circleShelf() => LayoutBuilder(
    key: const ValueKey('inbox-circles'),
    builder: (context, constraints) {
      final raw = (constraints.maxWidth - AppSpace.lg * 2) / 4;
      final itemWidth = raw < 72 ? 72.0 : raw;
      return SizedBox(
        height: 104,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.lg,
            vertical: AppSpace.sm,
          ),
          children: [
            _circle(
              label: 'Create',
              icon: Icons.add,
              onTap: _newMessage,
              itemWidth: itemWidth,
            ),
            _circle(
              key: const ValueKey('inbox-world'),
              label: 'World chat',
              icon: Icons.public,
              ring: AppColors.tiktokCoral,
              onTap: widget.onOpenWorldChat ?? () {},
              itemWidth: itemWidth,
            ),
            for (final thread in _threads.take(12)) ...[
              _circle(
                label: _users[thread.peerId(_myId ?? '')]?.name ?? 'Member',
                avatarUrl: _users[thread.peerId(_myId ?? '')]?.avatarUrl,
                initial: () {
                  final name = _users[thread.peerId(_myId ?? '')]?.name ?? 'M';
                  return name.isEmpty
                      ? 'M'
                      : name.substring(0, 1).toUpperCase();
                }(),
                ring: AppColors.tiktokCoral,
                itemWidth: itemWidth,
                onTap: () => _openThread(
                  thread,
                  _users[thread.peerId(_myId ?? '')] ??
                      ChatUserSummary(
                        id: thread.peerId(_myId ?? ''),
                        name: 'Member',
                      ),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: [
        _pageTabs(),
        Expanded(
          child: _page == 'activity' ? _activityContent() : _messagesContent(),
        ),
      ],
    );
    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        leading: IconButton(
          key: const ValueKey('inbox-add'),
          tooltip: 'New message',
          onPressed: _newMessage,
          icon: const Icon(Icons.person_add_alt_1_outlined),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Inbox'),
            const SizedBox(width: 6),
            Icon(Icons.arrow_drop_down, size: 18, color: AppColors.textDim),
          ],
        ),
        actions: [
          IconButton(
            key: const ValueKey('inbox-search'),
            tooltip: 'Search people',
            onPressed: _newMessage,
            icon: const Icon(Icons.search),
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _messagesContent() {
    return Column(
      children: [
        _circleShelf(),
        if (_notifications.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.md,
              AppSpace.lg,
              AppSpace.sm,
            ),
            child: Column(
              key: const ValueKey('inbox-notifications'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NOTIFICATIONS',
                  style: AppText.caption.copyWith(color: AppColors.primary),
                ),
                const SizedBox(height: AppSpace.xs),
                for (final item in _notifications)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.xs),
                    child: GlowCard(
                      key: ValueKey('inbox-notification-${item.id}'),
                      onTap: () => unawaited(_openNotification(item)),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(
                                AppRadius.input,
                              ),
                            ),
                            child: const Icon(
                              Icons.campaign_outlined,
                              color: AppColors.primary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: AppSpace.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  style: AppText.subtitle.copyWith(
                                    fontSize: 14,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  item.body,
                                  style: AppText.caption,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          if (_announcementUnread(item, _notificationsSeenAt))
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(right: AppSpace.sm),
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          const Icon(
                            Icons.chevron_right,
                            color: AppColors.textDim,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(child: _threadContent()),
      ],
    );
  }

  Widget _pageTabs() {
    return Container(
      key: const ValueKey('inbox-page-tabs'),
      decoration: const BoxDecoration(
        color: AppColors.bg,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          for (final page in ['messages', 'activity'])
            Expanded(
              child: Semantics(
                key: ValueKey('inbox-tab-$page'),
                button: true,
                selected: _page == page,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    setState(() => _page = page);
                    if (page == 'activity') unawaited(_loadActivity());
                  },
                  child: SizedBox(
                    height: kTouchMin,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          page == 'messages' ? 'Messages' : 'Activity',
                          style: AppText.subtitle.copyWith(
                            fontSize: 14,
                            fontWeight: _page == page
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: _page == page
                                ? Colors.white
                                : AppColors.textDim,
                          ),
                        ),
                        if (page == 'activity' && _activityUnread > 0) ...[
                          const SizedBox(width: AppSpace.xs),
                          Container(
                            key: const ValueKey('inbox-activity-badge'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: const BoxDecoration(
                              color: AppColors.tiktokCoral,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '$_activityUnread',
                              style: AppText.caption.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _activityContent() {
    if (_activityLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_activityFailed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Could not load activity'),
            TextButton(
              key: const ValueKey('inbox-notifications-retry'),
              onPressed: () => unawaited(_loadActivity()),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_activity.isEmpty) {
      return EmptyState(
        key: const ValueKey('inbox-notifications-empty'),
        icon: Icons.favorite_border,
        title: 'No activity yet',
        message: 'Likes and comments on your reels will show up here.',
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg,
            AppSpace.md,
            AppSpace.lg,
            AppSpace.xs,
          ),
          child: Row(
            children: [
              Text(
                'ACTIVITY',
                style: AppText.caption.copyWith(color: AppColors.primary),
              ),
              const Spacer(),
              TextButton(
                key: const ValueKey('inbox-notifications-read-all'),
                onPressed: () => unawaited(_markActivityRead()),
                child: const Text('Mark all read'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.xs,
              AppSpace.lg,
              AppSpace.xxl,
            ),
            itemCount: _activity.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpace.sm),
            itemBuilder: (_, i) => _activityRow(_activity[i]),
          ),
        ),
      ],
    );
  }

  String _activityTime(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return '';
    final age = DateTime.now().difference(parsed.toLocal());
    if (age.inDays >= 7) return '${age.inDays ~/ 7}w';
    if (age.inDays > 0) return '${age.inDays}d';
    if (age.inHours > 0) return '${age.inHours}h';
    if (age.inMinutes > 0) return '${age.inMinutes}m';
    return 'now';
  }

  Widget _activityRow(ReelNotification item) {
    final name = item.actor.displayName.isEmpty
        ? 'Member'
        : item.actor.displayName;
    final action = switch (item.type) {
      'like' => 'liked your reel',
      'comment' => 'commented on your reel',
      'reply' => 'replied to your comment',
      _ => 'posted on your reel',
    };
    return GlowCard(
      key: ValueKey('inbox-notification-${item.id}'),
      onTap: () => _openActivityNotification(item),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.surfaceHigh,
            backgroundImage:
                item.actor.avatarUrl == null || item.actor.avatarUrl!.isEmpty
                ? null
                : CachedNetworkImageProvider(item.actor.avatarUrl!),
            child: Text(
              name.substring(0, 1).toUpperCase(),
              style: AppText.caption,
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppText.subtitle.copyWith(fontSize: 14)),
                Text(action, style: AppText.caption),
                if (item.text.isNotEmpty && item.type != 'like')
                  Text(
                    item.text,
                    style: AppText.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.xs),
          Text(
            _activityTime(item.createdAt),
            style: AppText.caption.copyWith(
              fontSize: 11,
              color: AppColors.textDim,
            ),
          ),
          if (!item.isRead)
            Semantics(
              label: 'Unread activity',
              child: Container(
                key: ValueKey('inbox-notification-unread-${item.id}'),
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.tiktokCoral,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _threadContent() {
    return _loading
        ? const Center(child: CircularProgressIndicator())
        : _failed
        ? SingleChildScrollView(
            child: EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load messages',
              message: 'Check your connection and try again.',
              action: TextButton(
                onPressed: _subscribe,
                child: const Text('Retry'),
              ),
            ),
          )
        : _threads.isEmpty
        ? SingleChildScrollView(
            child: EmptyState(
              icon: Icons.forum_outlined,
              title: 'No private messages yet',
              message: 'Start a conversation with another Ghosst member.',
              action: TextButton(
                onPressed: _newMessage,
                child: const Text('New message'),
              ),
            ),
          )
        : ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.md,
              AppSpace.lg,
              AppSpace.xxl,
            ),
            itemCount: _threads.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpace.sm),
            itemBuilder: (_, i) => _row(_threads[i]),
          );
  }

  Widget _row(DirectThread thread) {
    final myId = _myId ?? '';
    final peerId = thread.peerId(myId);
    final peer =
        _users[peerId] ?? ChatUserSummary(id: peerId, name: 'Member #$peerId');
    final unread = thread.isUnread(myId);
    return GlowCard(
      key: ValueKey('thread-${thread.id}'),
      padding: const EdgeInsets.all(AppSpace.md),
      onTap: () => _openThread(thread, peer),
      child: Row(
        children: [
          _avatar(peer),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  peer.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.subtitle.copyWith(fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  thread.lastMessage.isEmpty
                      ? 'Start a conversation'
                      : thread.lastMessage,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_timeLabel(thread.updatedAt), style: AppText.caption),
              if (unread) ...[
                const SizedBox(height: AppSpace.xs),
                Semantics(
                  label: 'Unread messages',
                  child: Container(
                    key: ValueKey('unread-${thread.id}'),
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.tiktokCoral,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _avatar(ChatUserSummary user) {
    final photo = user.avatarUrl;
    return Container(
      width: 48,
      height: 48,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.border),
      ),
      child: photo == null
          ? Center(child: Text(user.initial, style: AppText.subtitle))
          : CachedNetworkImage(
              imageUrl: photo,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => Center(child: Text(user.initial)),
            ),
    );
  }

  static String _timeLabel(int millis) {
    if (millis <= 0) return '';
    final time = DateTime.fromMillisecondsSinceEpoch(millis);
    final now = DateTime.now();
    if (time.year == now.year &&
        time.month == now.month &&
        time.day == now.day) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
    return '${time.month}/${time.day}';
  }
}

class _NewMessageSheet extends StatefulWidget {
  const _NewMessageSheet({required this.search});

  final Future<List<ChatUserSummary>> Function(String query) search;

  @override
  State<_NewMessageSheet> createState() => _NewMessageSheetState();
}

class _NewMessageSheetState extends State<_NewMessageSheet> {
  final _query = TextEditingController();
  List<ChatUserSummary> _results = const [];
  bool _loading = false;
  bool _failed = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.length < 2) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final results = await widget.search(query);
      if (mounted) setState(() => _results = results);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpace.lg,
          AppSpace.md,
          AppSpace.lg,
          MediaQuery.viewInsetsOf(context).bottom + AppSpace.md,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('New message', style: AppText.title),
              const SizedBox(height: AppSpace.md),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _query,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _search(),
                      decoration: const InputDecoration(
                        hintText: 'Name or username',
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  FilledButton(
                    onPressed: _loading ? null : _search,
                    child: const Text('Search'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.md),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else if (_failed)
                const Text(
                  'Search failed. Try again.',
                  style: TextStyle(color: AppColors.red),
                )
              else if (_results.isEmpty)
                const Text(
                  'Search for at least 2 characters.',
                  style: TextStyle(color: AppColors.textDim),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _results.length,
                  itemBuilder: (_, i) => ListTile(
                    title: Text(_results[i].name),
                    subtitle: Text('@${_results[i].name}'),
                    onTap: () => Navigator.pop(context, _results[i]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
