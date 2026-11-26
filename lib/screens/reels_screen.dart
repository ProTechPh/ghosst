import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_exception.dart';
import '../services/worker_backend.dart';
import '../services/youtube.dart';
import '../theme.dart';
import 'direct_chat_screen.dart' show ReportContent;
import 'reel_comments_screen.dart';
import 'tutorials_screen.dart' show TutorialDetailScreen, TutorialThumb;

class ReelsScreen extends StatefulWidget {
  const ReelsScreen({
    super.key,
    this.load,
    this.onLike,
    this.onUnlike,
    this.onFollow,
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
    this.refreshToken = 0,
    this.coins = 0,
    this.onOpenWallet,
    this.onOpenTutorials,
    this.onOpenFeedback,
    this.loadTutorials,
    this.loadSiteFeedback,
    this.onOpenTutorial,
  });

  final Future<ReelFeedPage> Function(String feed, int offset)? load;
  final Future<void> Function(String reelId)? onLike;
  final Future<void> Function(String reelId)? onUnlike;
  final Future<void> Function(String creatorId)? onFollow;
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
  final int refreshToken;
  final int coins;
  final VoidCallback? onOpenWallet;
  final VoidCallback? onOpenTutorials;
  final VoidCallback? onOpenFeedback;
  final Future<List<Tutorial>> Function()? loadTutorials;
  final Future<List<WebsiteFeedback>> Function()? loadSiteFeedback;
  final ValueChanged<Tutorial>? onOpenTutorial;

  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> {
  String _feed = 'for-you';
  String _section = 'for-you';
  List<Tutorial> _tutorials = const [];
  List<WebsiteFeedback> _siteFeedback = const [];
  bool _extraLoading = false;
  String? _extraError;
  int _requestId = 0;
  List<Reel> _reels = [];
  int _nextOffset = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  bool _unconfigured = false;
  final Map<String, bool> _liked = {};
  final Map<String, int> _likeCounts = {};
  final Set<String> _liking = {};
  final Map<String, bool> _following = {};
  final Set<String> _followingBusy = {};

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
    if (widget.active && widget.refreshToken != oldWidget.refreshToken) {
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
          _likeCounts.putIfAbsent(reel.id, () => reel.likeCount);
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

  double? _swipeStartX;
  double? _swipeStartY;

  void _onSwipeDown(PointerDownEvent e) {
    _swipeStartX = e.localPosition.dx;
    _swipeStartY = e.localPosition.dy;
  }

  void _onSwipeUp(PointerUpEvent e) {
    final startX = _swipeStartX;
    final startY = _swipeStartY;
    _swipeStartX = null;
    _swipeStartY = null;
    if (startX == null || startY == null || startY > 112) return;
    final dx = e.localPosition.dx - startX;
    if (dx.abs() < 60) return;
    final next = dx < 0 ? 'following' : 'for-you';
    if (_section == next) return;
    setState(() {
      _section = next;
      _feed = next;
    });
    unawaited(_load(reset: true));
  }

  void _switchSection(String section) {
    if (_section == section) return;
    setState(() {
      _section = section;
      _extraError = null;
    });
    if (section == 'tutorials' || section == 'feedback') {
      unawaited(_loadExtra(section));
    } else if (_reels.isEmpty && !_loading) {
      unawaited(_load(reset: true));
    }
  }

  Future<void> _loadExtra(String section) async {
    setState(() {
      _extraLoading = true;
      _extraError = null;
    });
    try {
      final rows = section == 'tutorials'
          ? await (widget.loadTutorials ?? Backend.tutorials)()
          : await (widget.loadSiteFeedback ?? Backend.publicFeedback)();
      if (!mounted) return;
      setState(() {
        if (section == 'tutorials') {
          _tutorials = rows as List<Tutorial>;
        } else {
          _siteFeedback = rows as List<WebsiteFeedback>;
        }
        _extraLoading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _extraLoading = false;
          _extraError = 'Could not load $section.';
        });
      }
    }
  }

  Future<void> _toggleLike(Reel reel) async {
    if (_liking.contains(reel.id)) return;
    final liked = _liked[reel.id] ?? reel.isLiked;
    final count = _likeCounts[reel.id] ?? reel.likeCount;
    final nextCount = count + (liked ? -1 : 1);
    setState(() {
      _liking.add(reel.id);
      _liked[reel.id] = !liked;
      _likeCounts[reel.id] = nextCount < 0 ? 0 : nextCount;
    });
    try {
      if (liked) {
        await (widget.onUnlike ?? Backend.unlikeReel)(reel.id);
      } else {
        await (widget.onLike ?? Backend.likeReel)(reel.id);
      }
    } catch (_) {
      if (mounted)
        setState(() {
          _liked[reel.id] = liked;
          _likeCounts[reel.id] = count;
        });
    } finally {
      if (mounted) setState(() => _liking.remove(reel.id));
    }
  }

  Future<void> _toggleFollow(Reel reel) async {
    if (_followingBusy.contains(reel.id)) return;
    final following = _following[reel.id] ?? reel.isFollowing;
    setState(() {
      _followingBusy.add(reel.id);
      _following[reel.id] = true;
    });
    try {
      if (widget.onFollow != null) {
        await widget.onFollow!(reel.creator.id);
      } else {
        await Backend.followUser(reel.creator.id);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _following[reel.id] = following);
      }
    } finally {
      if (mounted) setState(() => _followingBusy.remove(reel.id));
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

  Future<void> _openComments(Reel reel) => showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.82,
    ),
    builder: (_) => ReelCommentsScreen(
      reelId: reel.id,
      load: (offset) => (widget.loadComments ?? Backend.reelComments)(
        reel.id,
        offset: offset,
      ),
      submit: (text) =>
          (widget.submitComment ?? Backend.postReelComment)(reel.id, text),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final title = widget.embedded
        ? null
        : AppBar(backgroundColor: Colors.black, title: const Text('Reels'));
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: title,
      floatingActionButton: widget.embedded || widget.onOpenUpload == null
          ? null
          : FloatingActionButton(
              heroTag: 'reels-upload',
              tooltip: 'Upload reel',
              onPressed: widget.onOpenUpload,
              child: const Icon(Icons.add_a_photo_outlined),
            ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildBody(),
          if (widget.embedded)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Listener(
                key: const ValueKey('reels-swipe-area'),
                behavior: HitTestBehavior.opaque,
                onPointerDown: _onSwipeDown,
                onPointerUp: _onSwipeUp,
                child: SizedBox(
                  height: kTouchMin * 2 + AppSpace.lg,
                  child: Stack(
                    children: [
                      const Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            key: ValueKey('reels-top-scrim'),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black54,
                                  Colors.black26,
                                  Colors.transparent,
                                ],
                                stops: [0, 0.55, 1],
                              ),
                            ),
                          ),
                        ),
                      ),
                      SafeArea(
                        bottom: false,
                        child: SizedBox(
                          height: kTouchMin + AppSpace.md,
                          child: Stack(
                            children: [
                              Positioned(
                                left: AppSpace.sm,
                                right: AppSpace.sm,
                                top: 0,
                                bottom: 0,
                                child: Center(
                                  child: SizedBox(
                                    height: kTouchMin,
                                    child: SingleChildScrollView(
                                      key: const ValueKey('reels-tabs-scroll'),
                                      scrollDirection: Axis.horizontal,
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _FeedTab(
                                            feedKey: 'tutorials',
                                            label: 'Tutorials',
                                            width: 76,
                                            selected: _section == 'tutorials',
                                            onTap: () =>
                                                _switchSection('tutorials'),
                                          ),
                                          _FeedTab(
                                            feedKey: 'feedback',
                                            label: 'Feedback',
                                            width: 76,
                                            selected: _section == 'feedback',
                                            onTap: () =>
                                                _switchSection('feedback'),
                                          ),
                                          _FeedTab(
                                            feedKey: 'following',
                                            label: 'Following',
                                            width: 76,
                                            selected: _section == 'following',
                                            onTap: () {
                                              if (_section == 'following')
                                                return;
                                              setState(() {
                                                _section = 'following';
                                                _feed = 'following';
                                              });
                                              unawaited(_load(reset: true));
                                            },
                                          ),
                                          _FeedTab(
                                            feedKey: 'for-you',
                                            label: 'For You',
                                            width: 76,
                                            selected: _section == 'for-you',
                                            onTap: () {
                                              if (_section == 'for-you') return;
                                              setState(() {
                                                _section = 'for-you';
                                                _feed = 'for-you';
                                              });
                                              unawaited(_load(reset: true));
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openTutorial(Tutorial item) async {
    final id = youtubeId(item.videoUrl);
    if (id != null) {
      await launchUrl(
        Uri.parse('https://www.youtube.com/watch?v=$id'),
        mode: LaunchMode.externalApplication,
      );
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TutorialDetailScreen(tutorial: item),
      ),
    );
  }

  Widget _extraContent() {
    if (_extraLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_extraError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_extraError!, style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => unawaited(_loadExtra(_section)),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_section == 'tutorials') {
      if (_tutorials.isEmpty) {
        return const Center(
          child: Text(
            'Nothing here yet',
            style: TextStyle(color: Colors.white),
          ),
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.lg,
          72,
          AppSpace.lg,
          AppSpace.lg,
        ),
        itemCount: _tutorials.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpace.md),
        itemBuilder: (_, i) {
          final t = _tutorials[i];
          return GlowCard(
            key: ValueKey('reel-tutorial-${t.id}'),
            onTap: widget.onOpenTutorial != null
                ? () => widget.onOpenTutorial!(t)
                : () => unawaited(_openTutorial(t)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TutorialThumb(videoUrl: t.videoUrl),
                Padding(
                  padding: const EdgeInsets.all(AppSpace.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (t.category.isNotEmpty)
                        Text(
                          t.category.toUpperCase(),
                          style: AppText.label.copyWith(
                            fontSize: 10,
                            color: AppColors.cyan,
                          ),
                        ),
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        t.title,
                        style: AppText.subtitle.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (t.content.isNotEmpty) ...[
                        const SizedBox(height: AppSpace.sm),
                        Text(t.content, style: AppText.body),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    }
    if (_siteFeedback.isEmpty) {
      return const Center(
        child: Text('Nothing here yet', style: TextStyle(color: Colors.white)),
      );
    }
    return PageView.builder(
      scrollDirection: Axis.vertical,
      itemCount: _siteFeedback.length,
      itemBuilder: (_, i) => _feedbackPage(_siteFeedback[i]),
    );
  }

  Widget _feedbackPage(WebsiteFeedback item) => Stack(
    fit: StackFit.expand,
    children: [
      if (item.imageUrl != null)
        CachedNetworkImage(
          imageUrl: item.imageUrl!,
          fit: BoxFit.contain,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          memCacheWidth: 1000,
          placeholder: (_, _) => const ColoredBox(color: AppColors.bgSoft),
          errorWidget: (_, _, _) =>
              const ColoredBox(color: AppColors.surfaceHigh),
        )
      else
        const ColoredBox(color: AppColors.bgSoft),
      const IgnorePointer(child: ColoredBox(color: Color(0x33000000))),
      Positioned(
        left: AppSpace.lg,
        right: AppSpace.lg,
        bottom: AppSpace.xl,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              item.username.isEmpty ? 'Member' : '@${item.username}',
              style: AppText.subtitle.copyWith(color: Colors.white),
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              item.comment,
              style: AppText.body.copyWith(color: Colors.white),
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              '★' * item.rating,
              style: const TextStyle(color: AppColors.gold, fontSize: 16),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _buildBody() {
    if (_section == 'tutorials' || _section == 'feedback') {
      return _extraContent();
    }
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
        likeCount: _likeCounts[_reels[i].id] ?? _reels[i].likeCount,
        following: _following[_reels[i].id] ?? _reels[i].isFollowing,
        onLike: () => unawaited(_toggleLike(_reels[i])),
        onFollow: () => unawaited(_toggleFollow(_reels[i])),
        onComments: () => unawaited(_openComments(_reels[i])),
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
    required this.likeCount,
    required this.following,
    required this.onLike,
    required this.onFollow,
    required this.onComments,
    required this.onDelete,
    required this.onReport,
    this.onProfile,
  });

  final Reel reel;
  final bool liked;
  final int likeCount;
  final bool following;
  final VoidCallback onLike;
  final VoidCallback onFollow;
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
              child: Icon(
                Icons.image_not_supported_outlined,
                color: Colors.white54,
              ),
            )
          else
            PageView.builder(
              key: ValueKey('reel-carousel-${widget.reel.id}'),
              itemCount: images.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => CachedNetworkImage(
                key: ValueKey(
                  'reel-image-${widget.reel.id}-${images[i].position}',
                ),
                imageUrl: images[i].url,
                fit: BoxFit.contain,
                placeholder: (_, _) =>
                    const Center(child: CircularProgressIndicator()),
                errorWidget: (_, _, _) => const Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white54,
                  ),
                ),
              ),
            ),
          const IgnorePointer(child: ColoredBox(color: Color(0x22000000))),
          if (images.length > 1)
            Positioned(
              bottom: 96,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < images.length; i++)
                    Semantics(
                      key: ValueKey('reel-dot-semantics-${widget.reel.id}-$i'),
                      label: 'Image ${images[i].position} of ${images.length}',
                      selected: i == _index,
                      child: Container(
                        key: ValueKey('reel-dot-${widget.reel.id}-$i'),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == _index ? Colors.white : Colors.white38,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Positioned(
            right: AppSpace.sm,
            bottom: 96,
            child: Column(
              children: [
                GestureDetector(
                  key: ValueKey(
                    'reel-profile-${widget.reel.creator.displayName}',
                  ),
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onProfile == null
                      ? null
                      : () => widget.onProfile!(widget.reel.creator.id),
                  child: SizedBox(
                    width: 60,
                    height: 60,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: AppColors.surfaceHigh,
                          backgroundImage: widget.reel.creator.avatarUrl == null
                              ? null
                              : CachedNetworkImageProvider(
                                  widget.reel.creator.avatarUrl!,
                                ),
                          child: widget.reel.creator.avatarUrl == null
                              ? Text(widget.reel.creator.initial)
                              : null,
                        ),
                        if (!widget.reel.isMine && !widget.following)
                          Positioned(
                            right: 2,
                            bottom: 0,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: widget.onFollow,
                              child: Semantics(
                                button: true,
                                label:
                                    'Follow ${widget.reel.creator.displayName}',
                                child: SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: Center(
                                    child: Container(
                                      key: ValueKey(
                                        'reel-follow-badge-${widget.reel.id}',
                                      ),
                                      width: 20,
                                      height: 20,
                                      decoration: const BoxDecoration(
                                        color: AppColors.primary,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.add,
                                        size: 14,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                _RailAction(
                  key: ValueKey('reel-like-${widget.reel.id}'),
                  tooltip: widget.liked ? 'Unlike' : 'Like',
                  icon: Icons.favorite,
                  color: widget.liked ? AppColors.red : Colors.white,
                  count: widget.likeCount,
                  onTap: widget.onLike,
                ),
                _RailAction(
                  key: ValueKey('reel-comments-${widget.reel.id}'),
                  tooltip: 'Comments',
                  icon: Icons.mode_comment,
                  count: widget.reel.commentCount,
                  onTap: widget.onComments,
                ),
                if (widget.reel.isMine)
                  _RailAction(
                    key: ValueKey('reel-delete-${widget.reel.id}'),
                    tooltip: 'Delete',
                    icon: Icons.delete,
                    onTap: widget.onDelete,
                  ),
                _RailAction(
                  key: ValueKey('reel-report-${widget.reel.id}'),
                  tooltip: 'Report',
                  icon: Icons.flag,
                  onTap: widget.onReport,
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

String _compactCount(int value) {
  if (value < 1000) return '$value';
  if (value >= 1000000000) {
    return '${(value / 1000000000).toStringAsFixed(value < 10000000000 ? 1 : 0)}B';
  }
  if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(value < 10000000 ? 1 : 0)}M';
  }
  return '${(value / 1000).toStringAsFixed(value < 10000 ? 1 : 0)}K';
}

class _RailAction extends StatelessWidget {
  const _RailAction({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.color = Colors.white,
    this.count,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      value: count == null ? null : _compactCount(count!),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 76,
          height: count == null ? kTouchMin : 64,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 30,
                color: color,
                shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
              ),
              if (count != null) ...[
                const SizedBox(height: AppSpace.xs),
                Text(
                  _compactCount(count!),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.figure.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    shadows: const [
                      Shadow(color: Colors.black54, blurRadius: 4),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedTab extends StatelessWidget {
  const _FeedTab({
    required this.feedKey,
    required this.label,
    required this.selected,
    required this.onTap,
    this.width = 72,
  });

  final String feedKey;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: ValueKey('reel-feed-$feedKey'),
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: width,
          height: kTouchMin,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.subtitle.copyWith(
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: Colors.white.withValues(alpha: selected ? 1 : 0.65),
                ),
              ),
              const SizedBox(height: AppSpace.xs),
              if (selected)
                Container(
                  key: ValueKey('reel-feed-underline-$feedKey'),
                  width: 24,
                  height: 2,
                  color: Colors.white,
                )
              else
                const SizedBox(width: 24, height: 2),
            ],
          ),
        ),
      ),
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
              DropdownMenuItem(
                value: 'hate_speech',
                child: Text('Hate speech'),
              ),
              DropdownMenuItem(
                value: 'sexual_content',
                child: Text('Sexual content'),
              ),
              DropdownMenuItem(value: 'violence', child: Text('Violence')),
              DropdownMenuItem(
                value: 'illegal_content',
                child: Text('Illegal content'),
              ),
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
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
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
