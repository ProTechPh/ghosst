import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/direct_chat_service.dart';
import '../services/worker_backend.dart';
import '../theme.dart';
import 'direct_chat_screen.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({
    super.key,
    this.client,
    this.loadUser,
    this.searchUsers,
    this.onOpenThread,
  });

  final DirectChatClient? client;
  final Future<ChatUserSummary> Function(String id)? loadUser;
  final Future<List<ChatUserSummary>> Function(String query)? searchUsers;
  final void Function(DirectThread thread, ChatUserSummary peer)? onOpenThread;

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

  @override
  void initState() {
    super.initState();
    _subscribe();
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
              _loadPeers(sorted);
            },
            onError: (Object _) {
              if (!mounted) return;
              setState(() {
                _loading = false;
                _failed = true;
              });
            },
          );
        })
        .catchError((Object _) {
          if (mounted) {
            setState(() {
              _loading = false;
              _failed = true;
            });
          }
        });
  }

  Future<void> _loadPeers(List<DirectThread> threads) async {
    final myId = _myId;
    if (myId == null) return;
    for (final thread in threads) {
      final peerId = thread.peerId(myId);
      if (peerId.isEmpty || _users.containsKey(peerId)) continue;
      try {
        final user = await (widget.loadUser ?? Backend.chatUser)(peerId);
        if (mounted) setState(() => _users[peerId] = user);
      } catch (_) {
        if (mounted) {
          setState(() {
            _users[peerId] = ChatUserSummary(
              id: peerId,
              name: 'Member #$peerId',
            );
          });
        }
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
    await _client.markRead(thread.id);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Inbox'),
        actions: [
          IconButton(
            tooltip: 'New message',
            onPressed: _newMessage,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
          ? EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load messages',
              message: 'Check your connection and try again.',
              action: TextButton(
                onPressed: _subscribe,
                child: const Text('Retry'),
              ),
            )
          : _threads.isEmpty
          ? EmptyState(
              icon: Icons.forum_outlined,
              title: 'No private messages yet',
              message: 'Start a conversation with another Ghosst member.',
              action: TextButton(
                onPressed: _newMessage,
                child: const Text('New message'),
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
            ),
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
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary,
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
