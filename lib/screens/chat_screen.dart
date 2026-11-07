import 'dart:async';

import 'package:flutter/material.dart';

import '../services/chat_service.dart';
import '../theme.dart';

/// World chat room. Identity is the backend UUID (see [ChatService]); there
/// is no Firebase login UI. Fail-open: when Firebase is not configured or
/// offline, the tab says "Chat unavailable" instead of breaking the shell.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    this.embedded = true,
    this.client,
    this.active = true,
    this.isAdmin = false,
    this.isModerator = false,
    this.onUnreadChanged,
  });

  /// True when shown as a shell tab (the shell supplies the bar).
  final bool embedded;

  /// Injectable for tests; defaults to [ChatService].
  final ChatClient? client;

  /// True when this tab is the selected one. IndexedStack builds every tab,
  /// so the listener waits for the first visit instead of billing a read on
  /// every app open (Spark daily cap).
  final bool active;

  /// True kapag admin ang naka-sign-in — lumalabas ang long-press mute menu.
  final bool isAdmin;
  final bool isModerator;
  final ValueChanged<bool>? onUnreadChanged;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final ChatClient _client = widget.client ?? ChatService();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  StreamSubscription<List<ChatMessage>>? _sub;
  List<ChatMessage> _messages = const [];
  bool _sending = false;
  bool _booting = false;
  bool _unavailable = false;
  bool _booted = false; // true pagkatapos ng unang snapshot (hindi empty state)
  bool _muted = false;
  String? _myUid;
  ChatMessage? _replyTo;
  bool _loadingMore = false;
  bool _hasMore = true;

  /// Ang ids ng mga naka-mute user (admin lang) — pangtanggal ng hula sa
  /// long-press dialog. Ni-refresh pagbalik sa tab at pagkatapos ng action.
  Set<String> _mutedIds = {};

  @override
  void initState() {
    super.initState();
    if (widget.active) _boot();
  }

  @override
  void didUpdateWidget(ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _boot();
      if (widget.isAdmin && _sub != null) _refreshMuted();
      // Ang mute status ay pwedeng nagbago habang wala sa tab (admin
      // nag-unmute/mute) — i-recheck sa bawat pagbalik, hindi sa restart.
      if (_sub != null) _recheckMuted();
      // Nalimutan na ang unread reply kapag binuksan ang tab.
      widget.onUnreadChanged?.call(false);
    }
  }

  /// Best-effort muted list refresh (admin lang); silent failure.
  Future<void> _refreshMuted() async {
    final users = await _client.mutedUsers();
    if (!mounted) return;
    setState(() => _mutedIds = {for (final u in users) u.id});
  }

  /// I-recheck ang sariling mute status mula sa backend (fresh /me + re-mint
  /// kung nagbago) — para makita agad ang unmute/mute nang hindi nagre-restart.
  Future<void> _recheckMuted() async {
    final muted = await _client.refreshMuted();
    if (!mounted) return;
    if (muted != _muted) setState(() => _muted = muted);
  }

  /// Sign in before listening: the rules deny reads to an anonymous client,
  /// and a denied snapshot listener never recovers. Failures show the same
  /// fallback as a dead Firebase init.
  Future<void> _boot() async {
    if (_sub != null || _booting) return;
    _booting = true;
    final sw = Stopwatch()..start();
    if (widget.client == null) {
      // `main()` starts the init; the tab may mount before it settles. The
      // future never completes in widget tests, so the fallback stays up.
      await ChatService.started;
    }
    if (!mounted) return;
    _booting = false;
    if (!_client.ready) return;

    if (_client.hasSession) {
      // Fast path: may persisted session na. Mag-subscribe agad gamit ito
      // (ang read rule ay kailangan lang ng auth — sapat ang lumang token),
      // at i-validate ang claims laban sa backend sa background. Ang /me at
      // token refresh ay hindi na nasa critical path ng unang paint.
      final uid = await _client.currentUid();
      final muted = await _client.isMuted();
      debugPrint('[ChatScreen] subscribing (session) in ${sw.elapsedMilliseconds}ms');
      if (mounted) {
        setState(() {
          _myUid = uid;
          _muted = muted;
          _subscribe();
        });
        // Ang muted list ay dialog state lang — pagkatapos ng subscribe para
        // hindi nito i-delay ang unang paint.
        if (widget.isAdmin) _refreshMuted();
      }
      // Background validation: nire-mint kung stale ang claims (walang signOut
      // kaya nabubuhay ang stream). Kung pumalya ito, ang send path ang
      // magre-validate ulit — hindi ito critical para sa pagbasang.
      unawaited(_client.ensureSignedIn());
      return;
    }

    // Slow path (bagong device): buong sign-in muna bago mag-subscribe, at
    // 25s timeout para hindi maging infinite loading ang mabagal na network.
    final ok = await _client.ensureSignedIn().timeout(
      const Duration(seconds: 25),
      onTimeout: () {
        debugPrint('[ChatScreen] boot timed out after ${sw.elapsedMilliseconds}ms');
        return false;
      },
    );
    if (!ok) {
      if (mounted) setState(() => _unavailable = true);
      return;
    }
    final uid = await _client.currentUid();
    final muted = await _client.isMuted();
    debugPrint('[ChatScreen] signed in + subscribing in ${sw.elapsedMilliseconds}ms');
    if (mounted) {
      setState(() {
        _myUid = uid;
        _muted = muted;
        _subscribe();
      });
      // Ang muted list ay dialog state lang — pagkatapos ng subscribe para
      // hindi nito i-delay ang unang paint.
      if (widget.isAdmin) _refreshMuted();
    }
  }

  void _subscribe() {
    final sw = Stopwatch()..start();
    _sub?.cancel();
    _sub = _client.messages().listen(
      (list) {
        if (!mounted) return;
        if (!_booted) {
          debugPrint(
              '[ChatScreen] first snapshot (${list.length} msgs) in ${sw.elapsedMilliseconds}ms');
        }
        final oldIds = _messages.map((m) => m.id).toSet();
        final hasNewReply = list.any((m) =>
            m.uid != _myUid &&
            m.replyToId != null &&
            _messages.any((o) => o.id == m.replyToId && o.uid == _myUid) &&
            !oldIds.contains(m.id));
        if (hasNewReply && !widget.active) {
          widget.onUnreadChanged?.call(true);
        }
        setState(() {
          _messages = list;
          _booted = true;
        });
      },
      onError: (Object e) {
        debugPrint('[ChatScreen] stream failed: $e');
        _sub?.cancel();
        _sub = null; // payagan ang re-boot pagbalik sa tab (retry)
        if (mounted) setState(() => _unavailable = true);
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Long-press sa message ng ibang user (admin lang): mute/unmute dialog.
  /// Ang enforcement ay server-side (muted claim sa rules); ito ay UI lang.
  /// Isang action button lang ang pinapakita, batay sa totoong mute state.
  Future<void> _onLongPress(ChatMessage m) async {
    if (!(widget.isAdmin || widget.isModerator) || m.uid == _myUid || m.name.isEmpty) return;
    final muted = _mutedIds.contains(m.uid);
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Chat moderation'),
        content: Text(
          muted ? '${m.name} is muted.' : 'Mute ${m.name} in world chat?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'cancel'),
            child: const Text('Cancel'),
          ),
          if (muted)
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'unmute'),
              child: const Text('Unmute'),
            )
          else
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'mute'),
              style: TextButton.styleFrom(foregroundColor: AppColors.red),
              child: const Text('Mute'),
            ),
        ],
      ),
    );
    if (action != 'mute' && action != 'unmute') return;
    if (!mounted) return;
    final toMuted = action == 'mute';
    final problem = await _client.setUserMuted(m.uid, toMuted);
    if (!mounted) return;
    if (problem == null) {
      setState(() {
        if (toMuted) {
          _mutedIds.add(m.uid);
        } else {
          _mutedIds.remove(m.uid);
        }
      });
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(problem ?? (toMuted ? 'User muted.' : 'User unmuted.'))),
    );
  }

  Future<void> _send() async {
    if (_input.text.trim().isEmpty || _sending) return;
    setState(() => _sending = true);
    final problem = await _client.send(_input.text, replyTo: _replyTo);
    if (!mounted) return;
    setState(() => _sending = false);
    if (problem != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(problem)));
      return;
    }
    _input.clear();
    // Bura ang reply preview sa success lang — sa failure nananatili para
    // makapag-retry nang hindi nawawala ang pinili.
    setState(() => _replyTo = null);
  }

  @override
  Widget build(BuildContext context) {
    final body = _unavailable || !_client.ready
        ? const Center(
            child: Text(
              'Chat unavailable',
              style: TextStyle(color: AppColors.textDim),
            ),
          )
        : Column(
            children: [
              Expanded(child: _messageList()),
              _composer(),
            ],
          );

    if (widget.embedded) return body;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('World chat')),
      body: body,
    );
  }

  Widget _messageList() {
    // Hanggang sa unang snapshot: loading, hindi ang empty state — kung hindi,
    // mukhang "walang history" ang tab sa bagong device habang nag-sign-in.
    if (!_booted) {
      return const Center(
        child: Text(
          'Loading chat…',
          style: TextStyle(color: AppColors.textDim),
        ),
      );
    }
    if (_messages.isEmpty) {
      return const Center(
        child: Text(
          'No messages yet. Be the first.',
          style: TextStyle(color: AppColors.textDim),
        ),
      );
    }
    // Firestore returns newest first; reversing puts the newest at the bottom.
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxBubble = constraints.maxWidth * 0.78;
        return ListView.separated(
          controller: _scroll,
          reverse: true,
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg,
            AppSpace.lg,
            AppSpace.lg,
            AppSpace.sm,
          ),
          itemCount: _messages.length + (_hasMore ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(height: AppSpace.sm),
          itemBuilder: (_, i) {
            if (i >= _messages.length) {
              return Center(
                child: TextButton(
                  onPressed: _loadingMore ? null : _loadMore,
                  child: _loadingMore
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Load older messages'),
                ),
              );
            }
            return _swipeable(_messages[i], maxBubble);
          },
        );
      },
    );
  }

  /// Swipe (kaliwa o kanan) = reply target. `confirmDismiss` ay laging false
  /// kaya nananatili ang bubble — Dismissible ang gesture, hindi ang delete.
  Widget _swipeable(ChatMessage m, double maxBubble) {
    final mine = m.uid == _myUid;
    return Dismissible(
      key: ValueKey(m.id),
      direction: DismissDirection.horizontal,
      background: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpace.lg),
          child: Icon(Icons.reply, color: AppColors.cyan),
        ),
      ),
      confirmDismiss: (_) async {
        setState(() => _replyTo = m);
        return false;
      },
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!mine) ...[
              _avatar(m.name, mine),
              const SizedBox(width: AppSpace.sm),
            ],
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxBubble - 36),
              child: GestureDetector(
                onLongPress: () => _onLongPress(m),
                child: _bubble(m, mine),
              ),
            ),
            if (mine) ...[
              const SizedBox(width: AppSpace.sm),
              _avatar(m.name, mine),
            ],
          ],
        ),
      ),
    );
  }

  void _jumpToReply(String? replyToId) {
    if (replyToId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Original message not available')),
      );
      return;
    }
    final idx = _messages.indexWhere((m) => m.id == replyToId);
    if (idx < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Original message not loaded')),
      );
      return;
    }
    // reversed list: index in ListView = (_messages.length - 1 - idx) + (hasMore?1:0)
    final listIndex = (_messages.length - 1 - idx);
    if (_scroll.hasClients) {
      _scroll.animateTo(
        listIndex * 80.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _messages.isEmpty) return;
    setState(() => _loadingMore = true);
    final older = await _client.loadOlder(_messages.last.tsMillis);
    if (!mounted) return;
    setState(() {
      if (older.isEmpty) {
        _hasMore = false;
      } else {
        final ids = _messages.map((m) => m.id).toSet();
        final newOnes = older.where((m) => !ids.contains(m.id)).toList();
        _messages = [..._messages, ...newOnes];
        if (newOnes.length < 50) _hasMore = false;
      }
      _loadingMore = false;
    });
  }

  Widget _avatar(String name, bool mine) {
    final letter = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: mine ? kNeonGradient : null,
        color: mine ? null : AppColors.surfaceHigh,
        shape: BoxShape.circle,
        border: Border.all(
          color: mine ? Colors.transparent : AppColors.border,
        ),
        boxShadow: [
          BoxShadow(
            color: (mine ? AppColors.primary : Colors.black)
                .withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        letter,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: mine ? const Color(0xFF04212A) : AppColors.text,
        ),
      ),
    );
  }

  Widget _bubble(ChatMessage m, bool mine) {
    final at = DateTime.fromMillisecondsSinceEpoch(m.tsMillis);
    final hour12 = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final period = at.hour >= 12 ? 'PM' : 'AM';
    final clock =
        '$hour12:${at.minute.toString().padLeft(2, '0')} $period';
    // Sariling bubble: cyan gradient + dark text (tulad ng NeonButton).
    final ink = mine ? const Color(0xFF04212A) : AppColors.text;
    final dim = mine ? const Color(0xB304212A) : AppColors.textDim;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.sm,
      ),
      decoration: BoxDecoration(
        gradient: mine ? kNeonGradient : null,
        color: mine ? null : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.button),
        border: mine ? null : Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (m.replyName != null || m.replyText != null)
            GestureDetector(
              onTap: () => _jumpToReply(m.replyToId),
              child: _quote(m, mine),
            ),
          if (!mine)
            Row(
              children: [
                Flexible(
                  child: Text(
                    m.name.isEmpty ? 'Deleted user' : m.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(
                      color: m.admin ? AppColors.gold : AppColors.cyan,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (m.admin) ...[
                  const SizedBox(width: AppSpace.sm),
                  const NeonPill(
                    label: 'ADMIN',
                    icon: Icons.verified,
                    color: AppColors.gold,
                  ),
                ],
              ],
            ),
          Text(
            m.text,
            style: AppText.body.copyWith(fontSize: 14, height: 1.4, color: ink),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              clock,
              style: AppText.caption.copyWith(fontSize: 11, color: dim),
            ),
          ),
        ],
      ),
    );
  }

  /// Quote block sa loob ng bubble (Telegram style): bar + pangalan + text.
  Widget _quote(ChatMessage m, bool mine) {
    final bar = mine ? const Color(0xFF04212A) : AppColors.primary;
    final nameColor = mine ? const Color(0xFF04212A) : AppColors.cyan;
    final textColor = mine ? const Color(0xB304212A) : AppColors.textDim;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsets.fromLTRB(
        AppSpace.sm,
        AppSpace.xs,
        AppSpace.sm,
        AppSpace.xs,
      ),
      decoration: BoxDecoration(
        color: mine
            ? Colors.white.withValues(alpha: 0.25)
            : AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border(left: BorderSide(color: bar, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            (m.replyName == null || m.replyName!.isEmpty)
                ? 'Deleted user'
                : m.replyName!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.caption.copyWith(
              color: nameColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (m.replyText != null)
            Text(
              m.replyText!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(color: textColor),
            ),
        ],
      ),
    );
  }

  /// "You are muted" bar kapalit ng composer (enforcement ay nasa rules).
  Widget _mutedBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.sm,
        AppSpace.lg,
        AppSpace.sm,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: AppColors.border),
      ),
      child: const Row(
        children: [
          Icon(Icons.block, size: 18, color: AppColors.red),
          SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              'You are muted in this chat.',
              style: AppText.caption,
            ),
          ),
        ],
      ),
    );
  }

  /// "Reply to ..." preview bar sa ibabaw ng input (tulad ng screenshot).
  Widget _replyPreview() {
    final target = _replyTo!;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.sm,
        AppSpace.lg,
        0,
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpace.md,
        AppSpace.sm,
        AppSpace.xs,
        AppSpace.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.reply, size: 18, color: AppColors.cyan),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reply to ${target.name.isEmpty ? 'Deleted user' : target.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(
                    color: AppColors.cyan,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  target.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: AppColors.textDim,
            tooltip: 'Cancel reply',
            onPressed: () => setState(() => _replyTo = null),
          ),
        ],
      ),
    );
  }

  Widget _composer() {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_replyTo != null && !_muted) _replyPreview(),
          if (_muted)
            _mutedBar()
          else
            Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.sm,
              AppSpace.sm,
              AppSpace.sm,
            ),
            child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                style: AppText.body.copyWith(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Message...',
                  hintStyle: AppText.caption.copyWith(
                    color: AppColors.textDim,
                  ),
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.md,
                    vertical: AppSpace.sm + 2,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    borderSide: const BorderSide(color: AppColors.primary),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpace.xs),
            IconButton(
              onPressed: _sending ? null : _send,
              icon: const Icon(Icons.send),
              color: AppColors.primary,
              tooltip: 'Send',
            ),
          ],
        ),
          ),
        ],
      ),
    );
  }
}
