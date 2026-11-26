import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/direct_chat_service.dart';
import '../services/worker_backend.dart';
import '../social_shell.dart';
import '../theme.dart';

typedef ReportContent =
    Future<void> Function({
      required String targetType,
      required String targetId,
      required String reason,
      String details,
      String? snapshot,
      String? threadId,
    });

class DirectChatScreen extends StatefulWidget {
  const DirectChatScreen({
    super.key,
    required this.peerId,
    required this.peerName,
    this.peerAvatarUrl,
    this.client,
    this.onReport,
    this.onOpenProfile,
  });

  final String peerId;
  final String peerName;
  final String? peerAvatarUrl;
  final DirectChatClient? client;
  final ReportContent? onReport;
  final ValueChanged<String>? onOpenProfile;

  @override
  State<DirectChatScreen> createState() => _DirectChatScreenState();
}

class _DirectChatScreenState extends State<DirectChatScreen> {
  late final DirectChatClient _client = widget.client ?? DirectChatService();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  StreamSubscription<DirectMessageFeed>? _sub;
  List<DirectMessage> _messages = const [];
  String? _myId;
  bool _loading = true;
  bool _failed = false;
  bool _sending = false;
  bool _blocked = false;
  bool _pendingWrites = false;
  int _lastMarkedTs = 0;

  String get _threadId => directThreadId(_myId ?? '', widget.peerId);

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final uid = await _client.currentUid();
      if (!mounted) return;
      if (uid == null || uid.isEmpty) throw StateError('No chat session');
      setState(() => _myId = uid);
      _sub = _client
          .messages(_threadId)
          .listen(
            (feed) {
              if (!mounted) return;
              final ordered = [...feed.messages]
                ..sort((a, b) => a.tsMillis.compareTo(b.tsMillis));
              setState(() {
                _messages = ordered;
                _pendingWrites = feed.hasPendingWrites;
                _loading = false;
                _failed = false;
              });
              _markNewRead(ordered);
              _jumpToBottom();
            },
            onError: (Object _) {
              if (!mounted) return;
              setState(() {
                _loading = false;
                _failed = true;
              });
            },
          );
      unawaited(_client.markRead(_threadId).catchError((_) {}));
      unawaited(
        _client
            .isBlocked(widget.peerId)
            .then((blocked) {
              if (mounted) setState(() => _blocked = blocked);
            })
            .catchError((_) {}),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  void _markNewRead(List<DirectMessage> messages) {
    if (messages.isEmpty) return;
    final newest = messages.last;
    if (newest.senderId == widget.peerId && newest.tsMillis > _lastMarkedTs) {
      _lastMarkedTs = newest.tsMillis;
      unawaited(_client.markRead(_threadId).catchError((_) {}));
    }
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send() async {
    final text = _input.text;
    final invalid = validateDirectMessage(text);
    if (invalid != null || _sending || _blocked) return;
    setState(() {
      _sending = true;
      _input.clear();
    });
    final problem = await _client.send(_threadId, text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (problem != null) {
      _input.text = text;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(problem)));
    }
  }

  Future<void> _block() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Block user?'),
        content: Text(
          'You will not be able to send or receive messages with ${widget.peerName}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    try {
      await _client.block(widget.peerId);
      if (mounted) setState(() => _blocked = true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not block user. Try again.')),
        );
      }
    }
  }

  Future<void> _unblock() async {
    try {
      await _client.unblock(widget.peerId);
      if (mounted) setState(() => _blocked = false);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not unblock user. Try again.')),
        );
      }
    }
  }

  Future<void> _report(DirectMessage message, {bool userTarget = false}) async {
    final details = TextEditingController();
    var reason = 'spam';
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpace.lg,
            AppSpace.md,
            AppSpace.lg,
            MediaQuery.viewInsetsOf(sheetContext).bottom + AppSpace.md,
          ),
          child: StatefulBuilder(
            builder: (context, setSheetState) => SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    userTarget ? 'Report user' : 'Report message',
                    style: AppText.title,
                  ),
                  const SizedBox(height: AppSpace.md),
                  DropdownButtonFormField<String>(
                    initialValue: reason,
                    decoration: const InputDecoration(labelText: 'Reason'),
                    items: const [
                      DropdownMenuItem(value: 'spam', child: Text('Spam')),
                      DropdownMenuItem(
                        value: 'harassment',
                        child: Text('Harassment'),
                      ),
                      DropdownMenuItem(
                        value: 'hate_speech',
                        child: Text('Hate speech'),
                      ),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (value) =>
                        setSheetState(() => reason = value ?? 'spam'),
                  ),
                  const SizedBox(height: AppSpace.md),
                  TextField(
                    controller: details,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      labelText: 'Details (optional)',
                    ),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, kTouchMin),
                      backgroundColor: AppColors.primary,
                      foregroundColor: const Color(0xFF04212A),
                    ),
                    onPressed: () => Navigator.pop(sheetContext, {
                      'reason': reason,
                      'details': details.text.trim(),
                    }),
                    child: const Text('Submit report'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    details.dispose();
    if (result == null || !mounted) return;
    try {
      await (widget.onReport ?? Backend.reportContent)(
        targetType: userTarget ? 'user' : 'message',
        targetId: userTarget ? widget.peerId : message.id,
        reason: result['reason'] ?? 'spam',
        details: result['details'] ?? '',
        snapshot: userTarget ? null : message.text,
        threadId: userTarget ? null : _threadId,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Report submitted.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not submit report. Try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: SocialAppBar(
        title: widget.peerName,
        titleContent: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onOpenProfile == null
              ? null
              : () => widget.onOpenProfile!(widget.peerId),
          child: Semantics(
            button: widget.onOpenProfile != null,
            label: 'Open ${widget.peerName} profile',
            child: Row(
              children: [
                _avatar(28),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(
                    widget.peerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More actions',
            onSelected: (value) {
              if (value == 'block') unawaited(_block());
              if (value == 'unblock') unawaited(_unblock());
              if (value == 'report_user') {
                unawaited(
                  _report(
                    DirectMessage(
                      id: widget.peerId,
                      senderId: widget.peerId,
                      text: '',
                      tsMillis: 0,
                    ),
                    userTarget: true,
                  ),
                );
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _blocked ? 'unblock' : 'block',
                child: Text(_blocked ? 'Unblock user' : 'Block user'),
              ),
              const PopupMenuItem(
                value: 'report_user',
                child: Text('Report user'),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
          ? EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load messages',
              action: TextButton(onPressed: _boot, child: const Text('Retry')),
            )
          : Column(
              children: [
                if (_blocked)
                  Container(
                    width: double.infinity,
                    color: AppColors.red.withValues(alpha: 0.10),
                    padding: const EdgeInsets.all(AppSpace.md),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.block_rounded,
                          size: 18,
                          color: AppColors.red,
                        ),
                        SizedBox(width: AppSpace.sm),
                        Expanded(
                          child: Text(
                            'You blocked this user.',
                            style: TextStyle(color: AppColors.red),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: _messages.isEmpty
                      ? const EmptyState(
                          icon: Icons.chat_bubble_outline_rounded,
                          title: 'No messages yet',
                          message: 'Say hello to start the conversation.',
                        )
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.all(AppSpace.lg),
                          itemCount: _messages.length,
                          itemBuilder: (_, i) => _bubble(_messages[i]),
                        ),
                ),
                if (_pendingWrites)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppSpace.md),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Pending',
                        style: TextStyle(color: AppColors.gold),
                      ),
                    ),
                  ),
                if (!_blocked) _composer(),
              ],
            ),
    );
  }

  Widget _composer() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.sm),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(hintText: 'Message'),
              ),
            ),
            IconButton(
              tooltip: 'Send message',
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bubble(DirectMessage message) {
    final mine = message.senderId == _myId;
    final bubble = Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.sm,
      ),
      decoration: BoxDecoration(
        color: mine
            ? AppColors.primary.withValues(alpha: 0.18)
            : AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: mine
              ? AppColors.primary.withValues(alpha: 0.35)
              : AppColors.border,
        ),
      ),
      child: Text(
        message.text,
        style: AppText.caption.copyWith(color: AppColors.text),
      ),
    );
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: mine
            ? bubble
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Report message',
                    onPressed: () => unawaited(_report(message)),
                    icon: const Icon(Icons.flag_outlined, size: 18),
                  ),
                  Flexible(
                    child: GestureDetector(
                      onLongPress: () => unawaited(_report(message)),
                      child: Semantics(
                        hint: 'Long press to report',
                        child: bubble,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _avatar(double size) {
    final photo = widget.peerAvatarUrl;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: AppColors.surfaceHigh,
        shape: BoxShape.circle,
      ),
      child: photo == null
          ? Center(
              child: Text(
                widget.peerName.trim().isEmpty
                    ? 'G'
                    : widget.peerName.trim()[0],
              ),
            )
          : CachedNetworkImage(
              imageUrl: photo,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => Center(
                child: Text(
                  widget.peerName.trim().isEmpty
                      ? 'G'
                      : widget.peerName.trim()[0],
                ),
              ),
            ),
    );
  }
}
