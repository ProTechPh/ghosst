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
  });

  /// True when shown as a shell tab (the shell supplies the bar).
  final bool embedded;

  /// Injectable for tests; defaults to [ChatService].
  final ChatClient? client;

  /// True when this tab is the selected one. IndexedStack builds every tab,
  /// so the listener waits for the first visit instead of billing a read on
  /// every app open (Spark daily cap).
  final bool active;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final ChatClient _client = widget.client ?? ChatService();
  final _input = TextEditingController();
  StreamSubscription<List<ChatMessage>>? _sub;
  List<ChatMessage> _messages = const [];
  bool _sending = false;
  bool _booting = false;
  bool _unavailable = false;
  bool _booted = false; // true pagkatapos ng unang snapshot (hindi empty state)
  String? _myUid;
  ChatMessage? _replyTo;

  @override
  void initState() {
    super.initState();
    if (widget.active) _boot();
  }

  @override
  void didUpdateWidget(ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _boot();
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
    if (!await _client.ensureSignedIn()) {
      if (mounted) setState(() => _unavailable = true);
      return;
    }
    final uid = await _client.currentUid();
    debugPrint('[ChatScreen] signed in + subscribing in ${sw.elapsedMilliseconds}ms');
    if (mounted) {
      setState(() {
        _myUid = uid;
        _subscribe();
      });
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
        setState(() {
          _messages = list;
          _booted = true;
        });
      },
      onError: (Object e) {
        debugPrint('[ChatScreen] stream failed: $e');
        _sub?.cancel();
        if (mounted) setState(() => _unavailable = true);
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _input.dispose();
    super.dispose();
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
          'Naglo-load ng chat…',
          style: TextStyle(color: AppColors.textDim),
        ),
      );
    }
    if (_messages.isEmpty) {
      return const Center(
        child: Text(
          'Wala pang mensahe. Ikaw ang mauna.',
          style: TextStyle(color: AppColors.textDim),
        ),
      );
    }
    // Firestore returns newest first; reversing puts the newest at the bottom.
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxBubble = constraints.maxWidth * 0.78;
        return ListView.separated(
          reverse: true,
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg,
            AppSpace.lg,
            AppSpace.lg,
            AppSpace.sm,
          ),
          itemCount: _messages.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpace.sm),
          itemBuilder: (_, i) => _swipeable(_messages[i], maxBubble),
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
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxBubble),
          child: _bubble(m, mine),
        ),
      ),
    );
  }

  Widget _bubble(ChatMessage m, bool mine) {
    final at = DateTime.fromMillisecondsSinceEpoch(m.tsMillis);
    final clock =
        '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
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
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (m.replyName != null || m.replyText != null) _quote(m, mine),
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
          if (_replyTo != null) _replyPreview(),
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
                  hintText: 'Mensahe...',
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
