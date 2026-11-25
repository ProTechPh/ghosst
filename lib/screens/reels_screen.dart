import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../api/api_exception.dart';
import '../services/worker_backend.dart';
import '../theme.dart';
import 'direct_chat_screen.dart' show ReportContent;
import 'reel_comments_screen.dart';

abstract class ReelPlayback {
  Future<void> initialize();
  Future<void> play();
  Future<void> pause();
  Future<void> setMuted(bool muted);
  bool get isPlaying;
  Widget view();
  void dispose();
}

typedef ReelPlaybackFactory = ReelPlayback Function(String url);

class _VideoReelPlayback implements ReelPlayback {
  _VideoReelPlayback(String url)
    : _controller = VideoPlayerController.networkUrl(Uri.parse(url));

  final VideoPlayerController _controller;

  @override
  Future<void> initialize() async {
    await _controller.initialize();
    await _controller.setLooping(true);
    await _controller.setVolume(0);
  }

  @override
  Future<void> play() => _controller.play();

  @override
  Future<void> pause() => _controller.pause();

  @override
  Future<void> setMuted(bool muted) => _controller.setVolume(muted ? 0 : 1);

  @override
  bool get isPlaying => _controller.value.isPlaying;

  @override
  Widget view() => VideoPlayer(_controller);

  @override
  void dispose() => _controller.dispose();
}

class ReelsScreen extends StatefulWidget {
  const ReelsScreen({
    super.key,
    this.load,
    this.onLike,
    this.onUnlike,
    this.onOpenProfile,
    this.onReport,
    this.playbackFactory,
    this.loadComments,
    this.submitComment,
    this.onOpenUpload,
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
  final ReelPlaybackFactory? playbackFactory;
  final Future<List<ReelComment>> Function(String reelId, int offset)?
  loadComments;
  final Future<void> Function(String reelId, String text)? submitComment;
  final VoidCallback? onOpenUpload;
  final Future<void> Function(String reelId)? onDeleteReel;
  final String? initialReelId;
  final String? initialCreatorId;
  final bool active;
  final bool embedded;

  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> {
  final _page = PageController();
  String _feed = 'for-you';
  List<Reel> _reels = [];
  int _offset = 0;
  int _active = 0;
  bool _loading;
  bool _failed = false;
  bool _unavailable = false;
  int _requestGeneration = 0;
  final Set<String> _liked = {};
  final Map<String, ReelPlayback> _players = {};

  ReelPlayback _player(String id, String url) {
    final existing = _players[id];
    if (existing != null) return existing;
    final player = widget.playbackFactory?.call(url) ?? _VideoReelPlayback(url);
    _players[id] = player;
    return player;
  }

  Future<void> _pausePlayer(String id) async {
    final player = _players.remove(id);
    await player?.pause();
    player?.dispose();
    if (mounted) setState(() {});
  }

  Future<void> _disposePlayers({bool rebuild = true}) async {
    final players = _players.values.toList();
    _players.clear();
    for (final player in players) {
      await player.pause();
      player.dispose();
    }
    if (rebuild && mounted) setState(() {});
  }

  _ReelsScreenState() : _loading = true;

  @override
  void initState() {
    super.initState();
    _loading = !widget.active;
    if (widget.active) _load();
  }

  @override
  void didUpdateWidget(covariant ReelsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active && _reels.isEmpty) {
      if (_loading) {
        _loading = false;
      }
      _load();
    }
  }

  @override
  void dispose() {
    unawaited(_disposePlayers(rebuild: false));
    _page.dispose();
    super.dispose();
  }

  void _releaseInactivePlayers() {
    final oldPlayers = _players.keys.toSet();
    for (final id in oldPlayers) {
      final index = _reels.indexWhere((reel) => reel.id == id);
      if ((index - _active).abs() > 1) {
        unawaited(_pausePlayer(id));
      }
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading && _reels.isNotEmpty) return;
    final generation = ++_requestGeneration;
    final requestedFeed = _feed;
    if (reset) _offset = 0;
    setState(() {
      _loading = true;
      _failed = false;
      _unavailable = false;
    });
    try {
      final ReelFeedPage page;
      if (widget.load != null) {
        page = await widget.load!(requestedFeed, _offset);
      } else {
        page = await Backend.reels(feed: requestedFeed, offset: _offset);
      }
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        if (reset) {
          unawaited(_disposePlayers());
          _active = 0;
          _reels = [
            ...page.reels,
            if (widget.initialReelId != null)
              for (final item in page.reels.where(
                (r) => r.id != widget.initialReelId,
              ))
                item,
          ];
          _liked.clear();
        } else {
          _reels = [..._reels, ...page.reels];
        }
        if (_active == 0 &&
            (widget.initialReelId != null || widget.initialCreatorId != null)) {
          final reelIndex = _reels.indexWhere(
            (r) => r.id == widget.initialReelId,
          );
          final creatorIndex = _reels.indexWhere(
            (r) => r.creator.id == widget.initialCreatorId,
          );
          _active = reelIndex >= 0 ? reelIndex : creatorIndex;
          if (reelIndex > 0) {
            _reels.insert(0, _reels.removeAt(reelIndex));
            _active = 0;
          }
        }
        _liked.addAll(page.reels.where((r) => r.isLiked).map((r) => r.id));
        _offset = page.nextOffset;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_page.hasClients) return;
        _page.jumpToPage(_active);
      });
    } on ApiException catch (e) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _loading = false;
        _unavailable = e.code == 'reels_not_configured';
        _failed = !_unavailable;
      });
    } catch (_) {
      if (mounted && generation == _requestGeneration) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _changeFeed(String feed) async {
    if (feed == _feed) return;
    setState(() {
      _requestGeneration++;
      _feed = feed;
      _reels = [];
      _liked.clear();
      _offset = 0;
      _active = 0;
      _loading = true;
      _failed = false;
    });
    if (_page.hasClients) _page.jumpToPage(0);
    await _load(reset: true);
  }

  Future<void> _toggleLike(Reel reel) async {
    final liked = !_liked.contains(reel.id);
    setState(() {
      if (liked) {
        _liked.add(reel.id);
      } else {
        _liked.remove(reel.id);
      }
    });
    try {
      if (liked) {
        if (widget.onLike != null) {
          await widget.onLike!(reel.id);
        } else {
          await Backend.likeReel(reel.id);
        }
      } else {
        if (widget.onUnlike != null) {
          await widget.onUnlike!(reel.id);
        } else {
          await Backend.unlikeReel(reel.id);
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (liked) {
          _liked.remove(reel.id);
        } else {
          _liked.add(reel.id);
        }
      });
    }
  }

  Future<void> _report(String reelId) async {
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
            builder: (context, setSheetState) {
              final details = TextEditingController();
              var reason = 'spam';
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Report reel', style: AppText.title),
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
                      onPressed: () => Navigator.pop(sheetContext, {
                        'reason': reason,
                        'details': details.text.trim(),
                      }),
                      child: const Text('Submit report'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
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
        content: const Text(
          'This removes the reel and its video. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    try {
      await delete(reel.id);
      if (!mounted) return;
      setState(
        () => _reels = _reels.where((item) => item.id != reel.id).toList(),
      );
      await _pausePlayer(reel.id);
      if (_reels.isEmpty) {
        setState(() => _active = 0);
        await _load(reset: true);
      } else if (_active >= _reels.length) {
        setState(() => _active = _reels.length - 1);
      }
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
          load: widget.loadComments == null
              ? null
              : (offset) => widget.loadComments!(reel.id, offset),
          submit: widget.submitComment == null
              ? null
              : (text) => widget.submitComment!(reel.id, text),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: widget.embedded
          ? AppBar(backgroundColor: Colors.black, title: const Text('Reels'))
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'for-you', label: Text('For You')),
                      ButtonSegment(
                        value: 'following',
                        label: Text('Following'),
                      ),
                    ],
                    selected: {_feed},
                    onSelectionChanged: (selection) =>
                        unawaited(_changeFeed(selection.single)),
                  ),
                ),
                if (widget.onOpenUpload != null)
                  IconButton(
                    tooltip: 'Upload reel',
                    onPressed: widget.onOpenUpload,
                    icon: const Icon(Icons.add_box_outlined),
                  ),
              ],
            ),
          ),
          Expanded(child: _feedBody()),
        ],
      ),
    );
  }

  Widget _feedBody() {
    return _loading && _reels.isEmpty
        ? const Center(child: CircularProgressIndicator())
        : _unavailable
        ? const Center(child: Text('Reels unavailable'))
        : _failed && _reels.isEmpty
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not load reels'),
                TextButton(
                  onPressed: () => _load(reset: true),
                  child: const Text('Retry'),
                ),
              ],
            ),
          )
        : _reels.isEmpty
        ? const Center(child: Text('No reels yet'))
        : PageView.builder(
            controller: _page,
            scrollDirection: Axis.vertical,
            itemCount: _reels.length,
            onPageChanged: (i) {
              setState(() => _active = i);
              _releaseInactivePlayers();
              if (i >= _reels.length - 2 && !_loading) {
                _load();
              }
            },
            itemBuilder: (_, i) => _ReelPage(
              key: ValueKey(_reels[i].id),
              reel: _reels[i],
              active: widget.active && i == _active,
              liked: _liked.contains(_reels[i].id),
              playback: _player(_reels[i].id, _reels[i].videoUrl),
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
    super.key,
    required this.reel,
    required this.active,
    required this.liked,
    required this.playback,
    required this.onLike,
    required this.onComments,
    required this.onDelete,
    this.onProfile,
    required this.onReport,
  });

  final Reel reel;
  final bool active;
  final bool liked;
  final ReelPlayback playback;
  final VoidCallback onLike;
  final VoidCallback onComments;
  final VoidCallback onDelete;
  final ValueChanged<String>? onProfile;
  final VoidCallback onReport;

  @override
  State<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends State<_ReelPage> {
  late final ReelPlayback _playback;
  bool _ready = false;
  bool _failed = false;
  bool _initialized = false;
  bool _muted = true;

  @override
  void initState() {
    super.initState();
    _playback = widget.playback;
    _init();
  }

  Future<void> _init() async {
    try {
      await _playback.initialize();
      _initialized = true;
      await _playback.setMuted(_muted);
      if (!mounted) return;
      setState(() {
        _ready = true;
        _failed = false;
      });
      if (widget.active) await _playback.play();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void didUpdateWidget(covariant _ReelPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      if (!_initialized || _failed) return;
      if (widget.active) {
        unawaited(_playback.play());
      } else {
        unawaited(_playback.pause());
      }
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _toggle() {
    if (!_ready || _failed) return;
    if (_playback.isPlaying) {
      unawaited(_playback.pause());
    } else {
      unawaited(_playback.play());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Reel by ${widget.reel.creator.displayName}',
      child: GestureDetector(
        key: ValueKey('reel-video-${widget.reel.id}'),
        onTap: _toggle,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _ready
                ? _playback.view()
                : Center(
                    child: _failed
                        ? const Text(
                            'Video unavailable',
                            style: TextStyle(color: Colors.white),
                          )
                        : const CircularProgressIndicator(),
                  ),
            const ColoredBox(color: Color(0x33000000)),
            Positioned(
              right: 12,
              bottom: 96,
              child: Column(
                children: [
                  GestureDetector(
                    key: ValueKey(
                      'reel-profile-${widget.reel.creator.displayName}',
                    ),
                    onTap: widget.onProfile == null
                        ? null
                        : () => widget.onProfile!(widget.reel.creator.id),
                    child: CircleAvatar(
                      radius: 24,
                      backgroundImage: widget.reel.creator.avatarUrl == null
                          ? null
                          : CachedNetworkImageProvider(
                              widget.reel.creator.avatarUrl!,
                            ),
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
                    icon: const Icon(
                      Icons.chat_bubble_outline,
                      color: Colors.white,
                    ),
                  ),
                  if (widget.reel.isMine)
                    IconButton(
                      key: ValueKey('reel-delete-${widget.reel.id}'),
                      onPressed: widget.onDelete,
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.white,
                      ),
                    ),
                  IconButton(
                    key: ValueKey('reel-report-${widget.reel.id}'),
                    onPressed: widget.onReport,
                    icon: const Icon(Icons.flag_outlined, color: Colors.white),
                  ),
                  IconButton(
                    key: const ValueKey('reel-sound'),
                    onPressed: () => setState(() {
                      _muted = !_muted;
                      unawaited(_playback.setMuted(_muted));
                    }),
                    icon: Icon(
                      _muted ? Icons.volume_off : Icons.volume_up,
                      color: Colors.white,
                    ),
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
      ),
    );
  }
}
