import 'package:flutter/material.dart';

import '../services/worker_backend.dart';
import '../theme.dart';

class ReelCommentsScreen extends StatefulWidget {
  const ReelCommentsScreen({
    super.key,
    required this.reelId,
    this.load,
    this.submit,
  });

  final String reelId;
  final Future<List<ReelComment>> Function(int offset)? load;
  final Future<void> Function(String)? submit;

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
      if (widget.submit != null) {
        await widget.submit!(text);
      } else {
        await Backend.postReelComment(widget.reelId, text);
      }
      if (!mounted) return;
      _input.clear();
      setState(() {
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.surfaceHigh,
            child: Text(comment.user.initial),
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
                Text(comment.text, style: AppText.body.copyWith(fontSize: 14)),
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
                  decoration: const InputDecoration(
                    hintText: 'Add a comment...',
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
