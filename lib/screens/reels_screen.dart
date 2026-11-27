import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_exception.dart';
import '../services/ad_service.dart';
import '../services/worker_backend.dart';
import '../services/youtube.dart';
import '../theme.dart';
import 'direct_chat_screen.dart' show ReportContent;
import 'reel_comments_screen.dart';
import 'tutorials_screen.dart' show TutorialDetailScreen, TutorialThumb;

class ReelAdSlot {
  const ReelAdSlot(this.index);

  // Slot index is stable as more posts are appended to the feed.
  final int index;
}

List<Object> reelsFeedEntries(List<Reel> reels, bool adsEnabled) {
  final entries = <Object>[];
  var slot = 0;
  for (var i = 0; i < reels.length; i++) {
    entries.add(reels[i]);
    if (adsEnabled && (i + 1) % 5 == 0) entries.add(ReelAdSlot(slot++));
  }
  return entries;
}

class _ReelAdSlot extends StatefulWidget {
  const _ReelAdSlot({super.key, required this.slot});

  final ReelAdSlot slot;

  @override
  State<_ReelAdSlot> createState() => _ReelAdSlotState();
}

class _ReelAdSlotState extends State<_ReelAdSlot> {
  BannerAd? _ad;

  @override
  void initState() {
    super.initState();
    if (AdService.adsEnabled) unawaited(_load());
  }

  Future<void> _load() async {
    if (!AdService.adsEnabled || !mounted) return;
    late final BannerAd ad;
    ad = BannerAd(
      adUnitId: AdUnits.banner,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) {
            setState(() => _ad = ad);
          } else {
            ad.dispose();
          }
        },
        onAdFailedToLoad: (failed, error) {
          failed.dispose();
          AdService.logAdError('Banner', AdUnits.banner, error, action: 'load');
        },
      ),
    );
    await ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad == null) return const SizedBox.shrink();
    return Semantics(
      label: 'Advertisement',
      child: SizedBox(
        width: ad.size.width.toDouble(),
        height: ad.size.height.toDouble(),
        child: ColoredBox(color: AppColors.bg, child: AdWidget(ad: ad)),
      ),
    );
  }
}

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
    this.openCommentsOnLoad = false,
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
  final bool openCommentsOnLoad;
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
  bool _autoOpenedComments = false;
  List<Reel> _reels = [];
  List<Object> _entries = const [];
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
  final ScrollController _feedScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _feedScroll.addListener(_onFeedScroll);
    AdService.instance.adsEnabledNotifier.addListener(_rebuildEntries);
    _loading = widget.active;
    if (widget.active) unawaited(_load(reset: true));
  }

  void _rebuildEntries() {
    if (!mounted) return;
    setState(
      () => _entries = reelsFeedEntries(
        _reels,
        widget.active && AdService.adsEnabled,
      ),
    );
  }

  void _onFeedScroll() {
    if (!_feedScroll.hasClients ||
        _loading ||
        _loadingMore ||
        _unconfigured ||
        _error != null ||
        _feedScroll.position.extentAfter > 200) {
      return;
    }
    _loadingMore = true;
    unawaited(_load());
  }

  @override
  void dispose() {
    _feedScroll.removeListener(_onFeedScroll);
    AdService.instance.adsEnabledNotifier.removeListener(_rebuildEntries);
    _feedScroll.dispose();
    super.dispose();
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
    if (widget.active != oldWidget.active) _rebuildEntries();
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
        _entries = reelsFeedEntries(
          _reels,
          widget.active && AdService.adsEnabled,
        );
        for (final reel in page.reels) {
          _liked.putIfAbsent(reel.id, () => reel.isLiked);
          _likeCounts.putIfAbsent(reel.id, () => reel.likeCount);
        }
      });
      _maybeAutoOpenComments();
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
    const sections = ['tutorials', 'feedback', 'following', 'for-you'];
    final index = sections.indexOf(_section);
    if (index < 0) return;
    var nextIndex = dx < 0 ? index + 1 : index - 1;
    if (nextIndex < 0) nextIndex = 0;
    if (nextIndex >= sections.length) nextIndex = sections.length - 1;
    _switchSection(sections[nextIndex]);
  }

  void _switchSection(String section) {
    if (_section == section) return;
    setState(() {
      _section = section;
      _extraError = null;
      if (section == 'following' || section == 'for-you') _feed = section;
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
      if (mounted) {
        setState(() {
          _liked[reel.id] = liked;
          _likeCounts[reel.id] = count;
        });
      }
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
        _entries = reelsFeedEntries(
          _reels,
          widget.active && AdService.adsEnabled,
        );
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
      submitReply: (parentId, text) => widget.submitComment != null
          ? widget.submitComment!(reel.id, text)
          : Backend.postReelComment(reel.id, text, parentId: parentId),
      onOpenProfile: widget.onOpenProfile,
    ),
  );

  void _maybeAutoOpenComments() {
    if (!widget.openCommentsOnLoad || _autoOpenedComments) return;
    final id = widget.initialReelId;
    if (id == null) return;
    Reel? target;
    for (final item in _reels) {
      if (item.id == id) {
        target = item;
        break;
      }
    }
    if (target == null) return;
    _autoOpenedComments = true;
    unawaited(_openComments(target));
  }

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
                behavior: HitTestBehavior.translucent,
                onPointerDown: _onSwipeDown,
                onPointerUp: _onSwipeUp,
                child: SizedBox(
                  height: kTouchMin + AppSpace.xl,
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
                                child: Align(
                                  alignment: Alignment.centerLeft,
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
                                            selected: _section == 'tutorials',
                                            onTap: () =>
                                                _switchSection('tutorials'),
                                          ),
                                          _FeedTab(
                                            feedKey: 'feedback',
                                            label: 'Feedback',
                                            selected: _section == 'feedback',
                                            onTap: () =>
                                                _switchSection('feedback'),
                                          ),
                                          _FeedTab(
                                            feedKey: 'following',
                                            label: 'Following',
                                            selected: _section == 'following',
                                            onTap: () {
                                              if (_section == 'following') {
                                                return;
                                              }
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
                                            showChevron: true,
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
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        76,
        AppSpace.lg,
        AppSpace.xxl,
      ),
      itemCount: _siteFeedback.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: AppColors.border),
      itemBuilder: (_, i) => _FeedbackPostCard(item: _siteFeedback[i]),
    );
  }

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
    return ListView.separated(
      controller: _feedScroll,
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        76,
        AppSpace.lg,
        AppSpace.xxl,
      ),
      itemCount: _entries.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: AppColors.border),
      itemBuilder: (_, i) {
        final entry = _entries[i];
        if (entry is ReelAdSlot) {
          return _ReelAdSlot(
            key: ValueKey('reel-ad-slot-${entry.index}'),
            slot: entry,
          );
        }
        final reel = entry as Reel;
        return _PostCard(
          reel: reel,
          liked: _liked[reel.id] ?? reel.isLiked,
          likeCount: _likeCounts[reel.id] ?? reel.likeCount,
          following: _following[reel.id] ?? reel.isFollowing,
          onLike: () => unawaited(_toggleLike(reel)),
          onFollow: () => unawaited(_toggleFollow(reel)),
          onComments: () => unawaited(_openComments(reel)),
          onDelete: () => unawaited(_deleteReel(reel)),
          onProfile: widget.onOpenProfile,
          onReport: () => unawaited(_report(reel.id)),
        );
      },
    );
  }
}

class _FeedbackPostCard extends StatelessWidget {
  const _FeedbackPostCard({required this.item});

  final WebsiteFeedback item;

  @override
  Widget build(BuildContext context) {
    final name = item.username.isEmpty ? 'Member' : item.username;
    return Padding(
      key: ValueKey('feedback-post-${item.id}'),
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.surfaceHigh,
            child: Text(name[0].toUpperCase(), style: AppText.caption),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: AppText.subtitle.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '@${name.toLowerCase()}',
                      style: AppText.caption.copyWith(color: AppColors.textDim),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.xs),
                Text(item.comment, style: AppText.body.copyWith(fontSize: 13)),
                const SizedBox(height: AppSpace.xs),
                Text(
                  '★' * item.rating,
                  style: const TextStyle(color: AppColors.gold, fontSize: 14),
                ),
                if (item.imageUrl != null) ...[
                  const SizedBox(height: AppSpace.sm),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: CachedNetworkImage(
                        imageUrl: item.imageUrl!,
                        fit: BoxFit.contain,
                        fadeInDuration: Duration.zero,
                        placeholder: (_, _) =>
                            const ColoredBox(color: AppColors.bgSoft),
                        errorWidget: (_, _, _) =>
                            const ColoredBox(color: AppColors.surfaceHigh),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PostCarousel extends StatefulWidget {
  const _PostCarousel({required this.reel});

  final Reel reel;

  @override
  State<_PostCarousel> createState() => _PostCarouselState();
}

class _PostCarouselState extends State<_PostCarousel> {
  int _index = 0;

  void _openViewer() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _ReelImageViewer(
          reelId: widget.reel.id,
          images: widget.reel.images,
          initialIndex: _index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reel = widget.reel;
    final images = reel.images;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Semantics(
        key: ValueKey('reel-image-open-${reel.id}'),
        button: true,
        label: 'View image ${_index + 1} of ${images.length} full screen',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _openViewer,
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                PageView.builder(
                  key: ValueKey('reel-carousel-${reel.id}'),
                  itemCount: images.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (_, i) => CachedNetworkImage(
                    key: ValueKey(
                      'reel-image-${reel.id}-${images[i].position}',
                    ),
                    imageUrl: images[i].url,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => const Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white54,
                      ),
                    ),
                  ),
                ),
                if (images.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.xs),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < images.length; i++)
                          Semantics(
                            key: ValueKey('reel-dot-semantics-${reel.id}-$i'),
                            label:
                                'Image ${images[i].position} of ${images.length}',
                            selected: i == _index,
                            child: Container(
                              key: ValueKey('reel-dot-${reel.id}-$i'),
                              width: 6,
                              height: 6,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i == _index
                                    ? Colors.white
                                    : Colors.white38,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReelImageViewer extends StatefulWidget {
  const _ReelImageViewer({
    required this.reelId,
    required this.images,
    required this.initialIndex,
  });

  final String reelId;
  final List<ReelImage> images;
  final int initialIndex;

  @override
  State<_ReelImageViewer> createState() => _ReelImageViewerState();
}

class _ReelImageViewerState extends State<_ReelImageViewer> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.images;
    return Scaffold(
      key: const ValueKey('reel-image-viewer'),
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1} of ${images.length}'),
        leading: IconButton(
          key: const ValueKey('reel-image-viewer-close'),
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: PageView.builder(
        key: const ValueKey('reel-viewer-pages'),
        controller: _controller,
        itemCount: images.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => Semantics(
          label: 'Image ${i + 1} of ${images.length}',
          child: CachedNetworkImage(
            key: ValueKey('reel-viewer-image-${widget.reelId}-${i + 1}'),
            imageUrl: images[i].url,
            fit: BoxFit.contain,
            errorWidget: (_, _, _) => const Center(
              child: Icon(Icons.broken_image_outlined, color: Colors.white54),
            ),
          ),
        ),
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({
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
  Widget build(BuildContext context) {
    final creator = reel.creator;
    final images = reel.images;
    return Padding(
      key: ValueKey('reel-post-${reel.id}'),
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            key: ValueKey('reel-profile-${creator.displayName}'),
            button: onProfile != null,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onProfile == null ? null : () => onProfile!(creator.id),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.surfaceHigh,
                    backgroundImage:
                        creator.avatarUrl == null || creator.avatarUrl!.isEmpty
                        ? null
                        : CachedNetworkImageProvider(creator.avatarUrl!),
                    child:
                        creator.avatarUrl == null || creator.avatarUrl!.isEmpty
                        ? Text(creator.initial, style: AppText.caption)
                        : null,
                  ),
                  if (!reel.isMine && !following)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onFollow,
                        child: Container(
                          key: ValueKey('reel-follow-badge-${reel.id}'),
                          width: 18,
                          height: 18,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.add,
                            size: 12,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        creator.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.subtitle.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (creator.isAdmin || creator.isModerator)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpace.xs),
                        child: Icon(
                          Icons.verified,
                          size: 14,
                          color: AppColors.cyan,
                        ),
                      ),
                    Text(
                      '@${creator.username}',
                      style: AppText.caption.copyWith(color: AppColors.textDim),
                    ),
                  ],
                ),
                if (reel.caption.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    reel.caption,
                    style: AppText.body.copyWith(fontSize: 13),
                  ),
                ],
                if (images.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.sm),
                  _PostCarousel(reel: reel),
                ],
                const SizedBox(height: AppSpace.xs),
                Row(
                  children: [
                    _action(
                      key: ValueKey('reel-comments-${reel.id}'),
                      icon: Icons.chat_bubble_outline,
                      label: _compactCount(reel.commentCount),
                      onTap: onComments,
                    ),
                    const SizedBox(width: AppSpace.lg),
                    _action(
                      key: ValueKey('reel-like-${reel.id}'),
                      icon: liked ? Icons.favorite : Icons.favorite_border,
                      label: _compactCount(likeCount),
                      color: liked ? AppColors.red : AppColors.textDim,
                      onTap: onLike,
                    ),
                    const SizedBox(width: AppSpace.lg),
                    _action(
                      key: ValueKey('reel-report-${reel.id}'),
                      icon: Icons.flag_outlined,
                      label: '',
                      onTap: onReport,
                    ),
                    if (reel.isMine) ...[
                      const SizedBox(width: AppSpace.lg),
                      _action(
                        key: ValueKey('reel-delete-${reel.id}'),
                        icon: Icons.delete_outline,
                        label: '',
                        onTap: onDelete,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _action({
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color color = AppColors.textDim,
  }) => Semantics(
    key: key,
    button: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            if (label.isNotEmpty) ...[
              const SizedBox(width: AppSpace.xs),
              Text(label, style: AppText.caption.copyWith(color: color)),
            ],
          ],
        ),
      ),
    ),
  );
}

String _compactCount(int value) {
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(value >= 10000 ? 0 : 1)}K';
  }
  return '$value';
}

class _FeedTab extends StatelessWidget {
  const _FeedTab({
    required this.feedKey,
    required this.label,
    required this.selected,
    required this.onTap,
    this.showChevron = false,
  });

  final String feedKey;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool showChevron;

  @override
  Widget build(BuildContext context) => Semantics(
    key: ValueKey('reel-feed-$feedKey'),
    button: true,
    selected: selected,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
        child: SizedBox(
          height: kTouchMin,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.subtitle.copyWith(
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected ? Colors.white : AppColors.textDim,
                    ),
                  ),
                  if (showChevron) ...[
                    const SizedBox(width: 2),
                    Icon(
                      Icons.keyboard_arrow_down,
                      size: 16,
                      color: selected ? Colors.white : AppColors.textDim,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpace.xs),
              if (selected)
                Container(
                  key: ValueKey('reel-feed-underline-$feedKey'),
                  width: 36,
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                )
              else
                const SizedBox(width: 36, height: 3),
            ],
          ),
        ),
      ),
    ),
  );
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
