import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/api_exception.dart';
import '../services/worker_backend.dart';
import '../theme.dart';
import 'direct_chat_screen.dart' show ReportContent;
import 'reel_comments_screen.dart';

class ReelsScreen extends StatefulWidget {
  const ReelsScreen({
    super.key,
    this.load,
    this.onLike,
    this.onUnlike,
    this.onOpenProfile,
    this.onReport,
    this.onOpenUpload,
    this.loadComments,
    this.submitComment,
    this.onDeleteReel,
    this.initialReelId,
    this.initialCreatorId,
    this.active = true,
    this.embedded = true,
  });

  final Future<ReelFeedPage> Function(String feed, int offset)? load;
  final Future<void> Function(String reelId)? onLike;
  final Future<void> Function(String reelId)? onUnlike;
  final ValueChanged<String>? onOpenProfile;
  final ReportContent? onReport;
  final VoidCallback? onOpenUpload;
  final Future<List<ReelComment>> Function(String reelId, int offset)?
  loadComments;
  final Future<void> Function(String reelId, String text)? submitComment;
  final Future<void> Function(String reelId)? onDeleteReel;
  final String? initialReelId;
  final String? initialCreatorId;
  final bool active;
  final bool embedded;

  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> {
  String _feed = 'for-you';
  int _requestId = 0;
  List<Reel> _reels = [];
  int _nextOffset = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  bool _unconfigured = false;
  final Map<String, bool> _liked = {};
  final Set<String> _liking = {};

  @override
  void initState() {
    super.initState();
    _loading = widget.active;
    if (widget.active) unawaited(_load(reset: true));
  }

  @override
  void didUpdateWidget(covariant ReelsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active && _reels.isEmpty && !_loading) {
      unawaited(_load(reset: true));
    }
  }

  Future<ReelFeedPage> _loadPage(String feed, int offset) {
    final load = widget.load;
    if (load != null) return load(feed, offset);
    return Backend.reels(feed: feed, offset: offset);
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _unconfigured = false;
      });
    }
    final request = ++_requestId;
    final offset = reset ? 0 : _nextOffset;
    try {
      final page = await _loadPage(_feed, offset);
      if (!mounted || request != _requestId) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _nextOffset = page.nextOffset;
        final items = reset ? <Reel>[] : [..._reels];
        if (reset && widget.initialReelId != null) {
          items.addAll(page.reels.where((r) => r.id == widget.initialReelId));
          items.addAll(page.reels.where((r) => r.id != widget.initialReelId));
        } else {
          items.addAll(page.reels);
        }
        _reels = items;
        for (final reel in page.reels) {
          _liked.putIfAbsent(reel.id, () => reel.isLiked);
        }
      });
    } on ApiException catch (e) {
      if (!mounted || request != _requestId) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _unconfigured = e.code == 'reels_not_configured';
        _error = _unconfigured ? null : 'Could not load reels';
      });
    } catch (_) {
      if (!mounted || request != _requestId) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = 'Could not load reels';
      });
    }
  }

  Future<void> _toggleLike(Reel reel) async {
    if (_liking.contains(reel.id)) return;
    final liked = _liked[reel.id] ?? reel.isLiked;
    setState(() {
      _liking.add(reel.id);
      _liked[reel.id] = !liked;
    });
    try {
      if (liked) {
        await (widget.onUnlike ?? Backend.unlikeReel)(reel.id);
      } else {
        await (widget.onLike ?? Backend.likeReel)(reel.id);
      }
    } catch (_) {
      if (mounted) setState(() => _liked[reel.id] = liked);
    } finally {
      if (mounted) setState(() => _liking.remove(reel.id));
    }
  }

  Future<void> _report(String reelId) async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => const _ReportDialog(),
    );
    if (result == null || !mounted) return;
    final reel = _reels.firstWhere((item) => item.id == reelId);
    try {
      await (widget.onReport ?? Backend.reportContent)(
        targetType: 'reel',
        targetId: reelId,
        reason: result['reason'] ?? 'spam',
        details: result['details'] ?? '',
        snapshot: reel.caption,
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

  Future<void> _deleteReel(Reel reel) async {
    final delete = widget.onDeleteReel;
    if (delete == null) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete reel?'),
        content: const Text('This removes the reel from the feed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (approved != true) return;
    try {
      await delete(reel.id);
      if (!mounted) return;
      setState(() {
        _reels.removeWhere((item) => item.id == reel.id);
        _liked.remove(reel.id);
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete reel. Try again.')),
        );
      }
    }
  }

  void _openComments(Reel reel) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReelCommentsScreen(
          reelId: reel.id,
          load: (offset) => (widget.loadComments ?? Backend.reelComments)(
            reel.id,
            offset: offset,
          ),
          submit: (text) =>
              (widget.submitComment ?? Backend.postReelComment)(reel.id, text),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.embedded
        ? null
        : AppBar(backgroundColor: Colors.black, title: const Text('Reels'));
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: title,
      floatingActionButton: widget.onOpenUpload == null
          ? null
          : FloatingActionButton(
              heroTag: 'reels-upload',
              tooltip: 'Upload reel',
              onPressed: widget.onOpenUpload,
              child: const Icon(Icons.add_a_photo_outlined),
            ),
      body: Column(
        children: [
          if (widget.embedded)
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.md),
                child: Row(
                  children: [
                    _FeedChip(
                      label: 'For You',
                      selected: _feed == 'for-you',
                      onTap: () {
                        if (_feed == 'for-you') return;
                        setState(() => _feed = 'for-you');
                        unawaited(_load(reset: true));
                      },
                    ),
                    const SizedBox(width: AppSpace.sm),
                    _FeedChip(
                      label: 'Following',
                      selected: _feed == 'following',
                      onTap: () {
                        if (_feed == 'following') return;
                        setState(() => _feed = 'following');
                        unawaited(_load(reset: true));
                      },
                    ),
                  ],
                ),
              ),
            ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_unconfigured) {
      return const Center(
        child: Text('Reels unavailable', style: TextStyle(color: Colors.white)),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => unawaited(_load(reset: true)),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_reels.isEmpty) {
      return const Center(
        child: Text('No reels yet', style: TextStyle(color: Colors.white)),
      );
    }
    return PageView.builder(
      scrollDirection: Axis.vertical,
      itemCount: _reels.length,
      onPageChanged: (i) {
        if (!_loadingMore && i >= _reels.length - 2) {
          _loadingMore = true;
          unawaited(_load());
        }
      },
      itemBuilder: (_, i) => _ReelPage(
        reel: _reels[i],
        liked: _liked[_reels[i].id] ?? _reels[i].isLiked,
        onLike: () => unawaited(_toggleLike(_reels[i])),
        onComments: () => _openComments(_reels[i]),
        onDelete: () => unawaited(_deleteReel(_reels[i])),
        onProfile: widget.onOpenProfile,
        onReport: () => unawaited(_report(_reels[i].id)),
      ),
    );
  }
}

class _ReelPage extends StatefulWidget {
  const _ReelPage({
    required this.reel,
    required this.liked,
    required this.onLike,
    required this.onComments,
    required this.onDelete,
    required this.onReport,
    this.onProfile,
  });

  final Reel reel;
  final bool liked;
  final VoidCallback onLike;
  final VoidCallback onComments;
  final VoidCallback onDelete;
  final VoidCallback onReport;
  final ValueChanged<String>? onProfile;

  @override
  State<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends State<_ReelPage> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final images = widget.reel.images;
    return Semantics(
      label: 'Reel by ${widget.reel.creator.displayName}',
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (images.isEmpty)
            const Center(
              child: Icon(Icons.image_not_supported_outlined, color: Colors.white54),
            )
          else
            PageView.builder(
              key: ValueKey('reel-carousel-${widget.reel.id}'),
              itemCount: images.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => CachedNetworkImage(
                key: ValueKey('reel-image-${widget.reel.id}-${images[i].position}'),
                imageUrl: images[i].url,
                fit: BoxFit.cover,
                placeholder: (_, __) => const Center(child: CircularProgressIndicator()),
                errorWidget: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image_outlined, color: Colors.white54),
                ),
              ),
            ),
          const IgnorePointer(
            child: ColoredBox(color: Color(0x22000000)),
          ),
          if (images.length > 1)
            Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < images.length; i++)
                    Container(
                      key: ValueKey('reel-dot-${widget.reel.id}-$i'),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _index ? Colors.white : Colors.white38,
                      ),
                    ),
                ],
              ),
            ),
          Positioned(
            right: 12,
            bottom: 96,
            child: Column(
              children: [
                GestureDetector(
                  key: ValueKey('reel-profile-${widget.reel.creator.displayName}'),
                  onTap: widget.onProfile == null
                      ? null
                      : () => widget.onProfile!(widget.reel.creator.id),
                  child: CircleAvatar(
                    radius: 24,
                    backgroundImage: widget.reel.creator.avatarUrl == null
                        ? null
                        : CachedNetworkImageProvider(widget.reel.creator.avatarUrl!),
                    child: widget.reel.creator.avatarUrl == null
                        ? Text(widget.reel.creator.initial)
                        : null,
                  ),
                ),
                IconButton(
                  key: ValueKey('reel-like-${widget.reel.id}'),
                  onPressed: widget.onLike,
                  icon: Icon(
                    widget.liked ? Icons.favorite : Icons.favorite_border,
                    color: widget.liked ? AppColors.red : Colors.white,
                  ),
                ),
                IconButton(
                  key: ValueKey('reel-comments-${widget.reel.id}'),
                  onPressed: widget.onComments,
                  icon: const Icon(Icons.chat_bubble_outline, color: Colors.white),
                ),
                if (widget.reel.isMine)
                  IconButton(
                    key: ValueKey('reel-delete-${widget.reel.id}'),
                    onPressed: widget.onDelete,
                    icon: const Icon(Icons.delete_outline, color: Colors.white),
                  ),
                IconButton(
                  key: ValueKey('reel-report-${widget.reel.id}'),
                  onPressed: widget.onReport,
                  icon: const Icon(Icons.flag_outlined, color: Colors.white),
                ),
              ],
            ),
          ),
          Positioned(
            left: AppSpace.lg,
            right: 80,
            bottom: AppSpace.lg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '@${widget.reel.creator.username}',
                  style: AppText.subtitle.copyWith(color: Colors.white),
                ),
                if (widget.reel.caption.isNotEmpty)
                  Text(
                    widget.reel.caption,
                    style: AppText.caption.copyWith(color: Colors.white),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedChip extends StatelessWidget {
  const _FeedChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog();

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  String _reason = 'spam';
  final _details = TextEditingController();

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Report reel'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _reason,
            items: const [
              DropdownMenuItem(value: 'spam', child: Text('Spam')),
              DropdownMenuItem(value: 'harassment', child: Text('Harassment')),
              DropdownMenuItem(value: 'hate_speech', child: Text('Hate speech')),
              DropdownMenuItem(value: 'sexual_content', child: Text('Sexual content')),
              DropdownMenuItem(value: 'violence', child: Text('Violence')),
              DropdownMenuItem(value: 'illegal_content', child: Text('Illegal content')),
              DropdownMenuItem(value: 'other', child: Text('Other')),
            ],
            onChanged: (v) => setState(() => _reason = v ?? 'spam'),
          ),
          TextField(
            controller: _details,
            decoration: const InputDecoration(labelText: 'Details (optional)'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, {
            'reason': _reason,
            'details': _details.text.trim(),
          }),
          child: const Text('Submit report'),
        ),
      ],
    );
  }
}
