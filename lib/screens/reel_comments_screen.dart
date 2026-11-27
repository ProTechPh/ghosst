import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/worker_backend.dart';
import '../theme.dart';

class ReelCommentsScreen extends StatefulWidget {
  const ReelCommentsScreen({
    super.key,
    required this.reelId,
    this.load,
    this.submit,
    this.submitReply,
    this.onOpenProfile,
  });

  final String reelId;
  final Future<List<ReelComment>> Function(int offset)? load;
  final Future<void> Function(String)? submit;
  final Future<void> Function(String parentId, String text)? submitReply;
  final ValueChanged<String>? onOpenProfile;

  @override
  State<ReelCommentsScreen> createState() => _ReelCommentsScreenState();
}

class _ReelCommentsScreenState extends State<ReelCommentsScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<ReelComment> _comments = [];
  int _offset = 0;
  bool _loading = false;
  bool _failed = false;
  bool _hasMore = true;
  bool _sending = false;
  String? _error;
  String? _replyToId;
  String _replyToName = '';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.hasClients &&
        _hasMore &&
        _scroll.position.extentAfter < 200 &&
        !_loading &&
        !_failed) {
      _load();
    }
  }

  Future<void> _load() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final loaded = await (widget.load != null
          ? widget.load!(_offset)
          : Backend.reelComments(widget.reelId, offset: _offset));
      if (!mounted) return;
      setState(() {
        _comments = [..._comments, ...loaded];
        _offset += loaded.length;
        _hasMore = loaded.length == 20;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _submit() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final parentId = _replyToId;
      if (parentId != null && widget.submitReply != null) {
        await widget.submitReply!(parentId, text);
      } else if (widget.submit != null) {
        await widget.submit!(text);
      } else {
        await Backend.postReelComment(
          widget.reelId,
          text,
          parentId: parentId,
        );
      }
      if (!mounted) return;
      _input.clear();
      setState(() {
        _replyToId = null;
        _replyToName = '';
        _comments = [];
        _offset = 0;
        _hasMore = true;
        _failed = false;
        _error = null;
      });
      await _load();
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not post comment. Try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Container(
          key: const ValueKey('reel-comments-sheet'),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppRadius.hero),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  key: const ValueKey('reel-comments-handle'),
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(top: AppSpace.sm),
                  decoration: BoxDecoration(
                    color: AppColors.textDim.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpace.md),
                  child: Text('Comments', style: AppText.subtitle),
                ),
                Expanded(child: _buildList()),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpace.lg,
                      AppSpace.xs,
                      AppSpace.lg,
                      0,
                    ),
                    child: Text(
                      _error!,
                      style: AppText.caption.copyWith(color: AppColors.red),
                    ),
                  ),
                _composer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_loading && _comments.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_failed && _comments.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Could not load comments'),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_comments.isEmpty) {
      return const Center(child: Text('No comments yet'));
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.xs,
        AppSpace.lg,
        AppSpace.md,
      ),
      itemCount: _comments.length + (_hasMore ? 1 : 0),
      itemBuilder: (_, i) {
        if (i >= _comments.length) {
          return Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Center(
              child: TextButton(
                onPressed: _loading ? null : _load,
                child: const Text('Load more comments'),
              ),
            ),
          );
        }
        return _commentRow(_comments[i]);
      },
    );
  }

  Widget _commentRow(ReelComment comment) {
    final isReply = comment.parentId.isNotEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isReply ? AppSpace.xl : 0,
        AppSpace.sm,
        0,
        AppSpace.sm,
      ),
      child: Row(
        key: ValueKey('comment-row-${comment.id}'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isReply)
            Container(
              width: 2,
              height: 72,
              margin: const EdgeInsets.only(right: AppSpace.sm),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
          Semantics(
            key: ValueKey('comment-profile-${comment.id}'),
            button: widget.onOpenProfile != null,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onOpenProfile == null
                  ? null
                  : () => widget.onOpenProfile!(comment.user.id),
              child: CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.surfaceHigh,
                backgroundImage:
                    comment.user.avatarUrl == null ||
                        comment.user.avatarUrl!.isEmpty
                    ? null
                    : CachedNetworkImageProvider(comment.user.avatarUrl!),
                child: comment.user.avatarUrl == null ||
                        comment.user.avatarUrl!.isEmpty
                    ? Text(comment.user.initial)
                    : null,
              ),
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        comment.user.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption.copyWith(
                          color: AppColors.textDim,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Text(
                      _relativeTime(comment.createdAt),
                      style: AppText.caption.copyWith(
                        fontSize: 11,
                        color: AppColors.textDim,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.xs),
                if (comment.replyTo.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.xs),
                    child: Text(
                      'Replying to @${comment.replyTo}',
                      key: ValueKey('comment-reply-label-${comment.id}'),
                      style: AppText.caption.copyWith(color: AppColors.cyan),
                    ),
                  ),
                Text(comment.text, style: AppText.body.copyWith(fontSize: 14)),
                if (!isReply)
                  SizedBox(
                    height: kTouchMin,
                    child: TextButton.icon(
                      key: ValueKey('comment-reply-${comment.id}'),
                      onPressed: () => setState(() {
                        _replyToId = comment.id;
                        _replyToName = comment.user.displayName;
                      }),
                      icon: const Icon(Icons.reply_outlined, size: 16),
                      label: const Text('Reply'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _composer() {
    final emojis = ['❤️', '🔥', '👏', '😮'];
    return Container(
      key: const ValueKey('reel-comments-composer'),
      padding: const EdgeInsets.fromLTRB(
        AppSpace.md,
        AppSpace.sm,
        AppSpace.md,
        AppSpace.sm,
      ),
      decoration: const BoxDecoration(
        color: AppColors.bg,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_replyToId != null)
            Padding(
              key: const ValueKey('comment-reply-banner'),
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Replying to @$_replyToName',
                      style: AppText.caption.copyWith(color: AppColors.cyan),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('comment-reply-cancel'),
                    tooltip: 'Cancel reply',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() {
                      _replyToId = null;
                      _replyToName = '';
                    }),
                  ),
                ],
              ),
            ),
          SizedBox(
            height: kTouchMin,
            child: Row(
              children: [
                for (var i = 0; i < emojis.length; i++)
                  SizedBox(
                    width: kTouchMin,
                    height: kTouchMin,
                    child: IconButton(
                      key: ValueKey('reel-comments-emoji-$i'),
                      onPressed: () => _insertEmoji(emojis[i]),
                      icon: Text(
                        emojis[i],
                        style: const TextStyle(fontSize: 19),
                      ),
                      tooltip: 'Add ${emojis[i]}',
                    ),
                  ),
                const Spacer(),
              ],
            ),
          ),
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.surfaceHigh,
                child: const Icon(
                  Icons.person,
                  size: 18,
                  color: AppColors.cyan,
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: TextField(
                  controller: _input,
                  maxLength: 500,
                  decoration: InputDecoration(
                    hintText: _replyToId == null
                        ? 'Add a comment...'
                        : 'Reply to @$_replyToName...',
                    counterText: '',
                    filled: true,
                    fillColor: AppColors.surfaceHigh,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: AppSpace.md,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(
                        Radius.circular(AppRadius.pill),
                      ),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpace.xs),
              IconButton(
                key: const ValueKey('reel-comments-send'),
                tooltip: 'Send comment',
                onPressed: _sending ? null : _submit,
                constraints: const BoxConstraints.tightFor(
                  width: kTouchMin,
                  height: kTouchMin,
                ),
                icon: const Icon(Icons.send, color: AppColors.primary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _insertEmoji(String emoji) {
    final text = _input.text;
    _input.text = '$text$emoji';
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
  }

  String _relativeTime(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return '';
    final days = DateTime.now().difference(parsed).inDays;
    if (days >= 7) return '${days ~/ 7}w';
    if (days > 0) return '${days}d';
    final hours = DateTime.now().difference(parsed).inHours;
    if (hours > 0) return '${hours}h';
    final minutes = DateTime.now().difference(parsed).inMinutes;
    if (minutes > 0) return '${minutes}m';
    return 'now';
  }
}
