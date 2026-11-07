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
    if (mounted) setState(_subscribe);
  }

  void _subscribe() {
    _sub?.cancel();
    _sub = _client.messages().listen(
      (list) {
        if (!mounted) return;
        setState(() => _messages = list);
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
    final problem = await _client.send(_input.text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (problem != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(problem)));
      return;
    }
    _input.clear();
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
    if (_messages.isEmpty) {
      return const Center(
        child: Text(
          'Wala pang mensahe. Ikaw ang mauna.',
          style: TextStyle(color: AppColors.textDim),
        ),
      );
    }
    // Firestore returns newest first; reversing puts the newest at the bottom.
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
      itemBuilder: (_, i) {
        final m = _messages[i];
        final at = DateTime.fromMillisecondsSinceEpoch(m.tsMillis);
        final clock =
            '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
        return GlowCard(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      m.name.isEmpty ? 'Deleted user' : m.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(
                        color: AppColors.cyan,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (m.admin) ...[
                    const SizedBox(width: AppSpace.sm),
                    NeonPill(
                      label: 'ADMIN',
                      icon: Icons.verified,
                      color: AppColors.gold,
                    ),
                  ],
                  const Spacer(),
                  const SizedBox(width: AppSpace.sm),
                  Text(
                    clock,
                    style: AppText.caption.copyWith(
                      fontSize: 11,
                      color: AppColors.textDim.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                m.text,
                style: AppText.body.copyWith(fontSize: 14, height: 1.4),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _composer() {
    return SafeArea(
      top: false,
      child: Padding(
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
    );
  }
}
