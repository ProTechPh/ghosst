import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/api_exception.dart';
import '../premium.dart';
import '../services/direct_chat_service.dart';
import '../services/worker_backend.dart';
import '../theme.dart';
import 'social_list_screen.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({
    super.key,
    required this.userId,
    this.initialName,
    this.loader,
    this.loadBlocked,
    required this.onMessage,
    required this.onReport,
    this.onBlock,
    this.onUnblock,
    this.onFollow,
    this.onUnfollow,
    this.onOpenSocialList,
    this.loadReels,
    this.onOpenReel,
  });

  final String userId;
  final String? initialName;
  final Future<PublicUser> Function(String id)? loader;
  final Future<bool> Function(String id)? loadBlocked;
  final ValueChanged<PublicUser> onMessage;
  final VoidCallback onReport;
  final Future<bool> Function()? onBlock;
  final Future<bool> Function()? onUnblock;
  final Future<FollowState> Function(String id)? onFollow;
  final Future<FollowState> Function(String id)? onUnfollow;
  final ValueChanged<SocialListDirection>? onOpenSocialList;
  final Future<List<Reel>> Function(String userId, int offset)? loadReels;
  final ValueChanged<Reel>? onOpenReel;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  late ScrollController _scroll = ScrollController();
  PublicUser? _user;
  bool _loading = true;
  bool _failed = false;
  bool _notFound = false;
  bool _blocked = false;
  bool _blocking = false;
  bool _following = false;
  int _followerCount = 0;
  bool _followBusy = false;
  List<Reel> _reels = const [];
  int _reelOffset = 0;
  bool _reelsLoading = false;
  bool _reelsFailed = false;
  bool _hasMoreReels = true;
  final _reelScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _reelScroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _scroll.dispose();
    _scroll = ScrollController();
    setState(() {
      _loading = true;
      _failed = false;
      _notFound = false;
    });
    try {
      final user = await (widget.loader ?? Backend.publicUser)(widget.userId);
      if (!mounted) return;
      setState(() {
        _user = user;
        _following = user.isFollowing;
        _followerCount = user.followerCount;
        _loading = false;
      });
      unawaited(_loadBlocked());
      unawaited(_loadReels());
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _notFound = e.kind == ApiErrorKind.notFound;
          _failed = !_notFound;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _loadBlocked() async {
    try {
      final blocked =
          await (widget.loadBlocked ?? DirectChatService().isBlocked)(
            widget.userId,
          );
      if (mounted) setState(() => _blocked = blocked);
    } catch (_) {
      // Block state is independent from the public profile.
    }
  }

  Future<void> _loadReels({bool reset = false}) async {
    if (reset) {
      _reels = const [];
      _reelOffset = 0;
      _hasMoreReels = true;
      _reelsLoading = false;
    }
    if (_reelsLoading || !_hasMoreReels) return;
    setState(() {
      _reelsLoading = true;
      _reelsFailed = false;
    });
    try {
      final List<Reel> rows;
      if (widget.loadReels != null) {
        rows = await widget.loadReels!(widget.userId, _reelOffset);
      } else {
        rows = await Backend.userReels(widget.userId, offset: _reelOffset);
      }
      final loaded = rows.length;
      if (!mounted) return;
      setState(() {
        _reels = [..._reels, ...rows];
        _reelOffset += loaded;
        _hasMoreReels = loaded == 20;
        _reelsLoading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _reelsLoading = false;
          _reelsFailed = true;
        });
      }
    }
  }

  Future<void> _block() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Block user?'),
        content: const Text(
          'You will not be able to send or receive private messages with this user.',
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
    setState(() => _blocking = true);
    final ok = await widget.onBlock?.call() ?? false;
    if (!mounted) return;
    setState(() => _blocking = false);
    if (ok) {
      setState(() => _blocked = true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not block user. Try again.')),
      );
    }
  }

  Future<void> _unblock() async {
    setState(() => _blocking = true);
    final ok = await widget.onUnblock?.call() ?? false;
    if (!mounted) return;
    setState(() => _blocking = false);
    if (ok) {
      setState(() => _blocked = false);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not unblock user. Try again.')),
      );
    }
  }

  Future<void> _toggleFollow() => _setFollowing(!_following);

  Future<void> _setFollowing(bool next) async {
    if (_followBusy || _user == null || _user!.isSelf) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    final previous = _following;
    final previousCount = _followerCount;
    setState(() {
      _followBusy = true;
      _following = next;
      _followerCount = (previousCount + (next ? 1 : -1))
          .clamp(0, 1 << 31)
          .toInt();
    });
    try {
      final state = next
          ? await widget.onFollow?.call(widget.userId)
          : await widget.onUnfollow?.call(widget.userId);
      if (state == null) throw StateError('Follow action unavailable');
      if (!mounted) return;
      setState(() {
        _followBusy = false;
        _following = state.isFollowing;
        _followerCount = state.followerCount;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _followBusy = false;
        _following = previous;
        _followerCount = previousCount;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not ${next ? 'follow' : 'unfollow'}. Try again.',
          ),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () => unawaited(_setFollowing(next)),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More actions',
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'report') widget.onReport();
              if (value == 'block') unawaited(_block());
              if (value == 'unblock') _unblock();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'report', child: Text('Report user')),
              if (widget.onBlock != null || widget.onUnblock != null)
                PopupMenuItem(
                  value: _blocked ? 'unblock' : 'block',
                  enabled: !_blocking,
                  child: Text(_blocked ? 'Unblock user' : 'Block user'),
                ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notFound
          ? const EmptyState(
              icon: Icons.person_off_outlined,
              title: 'Profile unavailable',
              message: 'This account is no longer available.',
            )
          : _failed
          ? EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load profile',
              action: TextButton(onPressed: _load, child: const Text('Retry')),
            )
          : _body(_user!),
    );
  }

  Widget _body(PublicUser user) {
    return Stack(
      children: [
        const MeshBackground(),
        SafeArea(
          top: false,
          child: ListView(
            controller: _scroll,
            key: const ValueKey('profile-scroll'),
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.md,
              AppSpace.lg,
              AppSpace.xxl,
            ),
            children: [
              GlowCard(
                glow: true,
                padding: const EdgeInsets.all(AppSpace.lg),
                child: Column(
                  children: [
                    _avatar(user),
                    const SizedBox(height: AppSpace.md),
                    Text(
                      _displayName(user),
                      textAlign: TextAlign.center,
                      style: AppText.title.copyWith(fontSize: 24),
                    ),
                    if (user.username.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text('@${user.username}', style: AppText.caption),
                    ],
                    if (user.isAdmin || user.isModerator) ...[
                      const SizedBox(height: AppSpace.sm),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (user.isAdmin) ...[
                            const NeonPill(
                              label: 'ADMIN',
                              icon: Icons.verified,
                              color: AppColors.gold,
                            ),
                            const SizedBox(width: AppSpace.xs),
                          ],
                          if (user.isModerator)
                            const NeonPill(
                              label: 'MODERATOR',
                              icon: Icons.shield_outlined,
                              color: AppColors.cyan,
                            ),
                        ],
                      ),
                    ],
                    if (_memberSince(user.createdAt).isNotEmpty) ...[
                      const SizedBox(height: AppSpace.sm),
                      Text(
                        'Member since ${_memberSince(user.createdAt)}',
                        style: AppText.caption,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              GlowCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.md,
                  vertical: AppSpace.lg,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.onOpenSocialList == null
                            ? null
                            : () => widget.onOpenSocialList!(
                                SocialListDirection.followers,
                              ),
                        child: Semantics(
                          button: widget.onOpenSocialList != null,
                          child: StatCell(
                            label: 'Followers',
                            value: groupDigits(_followerCount),
                          ),
                        ),
                      ),
                    ),
                    _divider(),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.onOpenSocialList == null
                            ? null
                            : () => widget.onOpenSocialList!(
                                SocialListDirection.following,
                              ),
                        child: Semantics(
                          button: widget.onOpenSocialList != null,
                          child: StatCell(
                            label: 'Following',
                            value: groupDigits(user.followingCount),
                          ),
                        ),
                      ),
                    ),
                    _divider(),
                    Expanded(
                      child: StatCell(
                        label: 'Reels',
                        value: groupDigits(user.reelCount),
                      ),
                    ),
                  ],
                ),
              ),
              if (!user.isSelf)
                Row(
                  children: [
                    Expanded(
                      child: IslandButton(
                        label: _blocked ? 'Blocked' : 'Message',
                        icon: Icons.chat_bubble_outline_rounded,
                        onPressed: _blocked || _blocking
                            ? null
                            : () => widget.onMessage(_user!),
                      ),
                    ),
                    if (widget.onFollow != null ||
                        widget.onUnfollow != null) ...[
                      const SizedBox(width: AppSpace.sm),
                      Semantics(
                        label: _following
                            ? 'Unfollow ${_displayName(user)}'
                            : 'Follow ${_displayName(user)}',
                        child: FilledButton(
                          onPressed: _followBusy ? null : _toggleFollow,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 48),
                          ),
                          child: Text(_following ? 'Following' : 'Follow'),
                        ),
                      ),
                    ],
                  ],
                ),
              const SizedBox(height: AppSpace.xl),
              const SectionHeader(title: 'Reels'),
              const SizedBox(height: AppSpace.sm),
              _reelsSection(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _reelsSection() {
    if (_reelsLoading && _reels.isEmpty) {
      return const SizedBox(
        height: 120,
        child: ColoredBox(color: AppColors.surface),
      );
    }
    if (widget.onOpenReel != null) {
      return GridView.builder(
        controller: _reelScroll,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
        ),
        itemCount: _reels.length,
        itemBuilder: (_, index) {
          final reel = _reels[index];
          return GestureDetector(
            key: ValueKey('profile-reel-${reel.id}'),
            onTap: () => widget.onOpenReel!(reel),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (reel.posterUrl != null)
                  CachedNetworkImage(
                    imageUrl: reel.posterUrl!,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => _reelPlaceholder(),
                  )
                else
                  _reelPlaceholder(),
                const Center(
                  child: Icon(Icons.play_arrow_rounded, color: Colors.white),
                ),
              ],
            ),
          );
        },
      );
    }
    if (_reelsFailed && _reels.isEmpty) {
      return Center(
        child: TextButton(
          onPressed: () => _loadReels(reset: true),
          child: const Text('Could not load reels. Retry'),
        ),
      );
    }
    if (_reels.isEmpty) {
      return const GlowCard(
        padding: EdgeInsets.all(AppSpace.xl),
        child: Column(
          children: [
            Icon(
              Icons.movie_outlined,
              color: AppColors.textDim,
              size: AppIcon.xl,
            ),
            SizedBox(height: AppSpace.sm),
            Text('No reels yet', style: AppText.subtitle),
          ],
        ),
      );
    }
    return GridView.builder(
      controller: _reelScroll,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: _reels.length,
      itemBuilder: (_, index) {
        final reel = _reels[index];
        return GestureDetector(
          key: ValueKey('profile-reel-${reel.id}'),
          onTap: widget.onOpenReel == null
              ? null
              : () => widget.onOpenReel!(reel),
          child: SizedBox(
            height: 160,
            child: Semantics(
              label: 'Open reel ${index + 1}',
              button: widget.onOpenReel != null,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.input),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (reel.posterUrl != null)
                      CachedNetworkImage(
                        imageUrl: reel.posterUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => _reelPlaceholder(),
                      )
                    else
                      _reelPlaceholder(),
                    const Center(
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _reelPlaceholder() => const ColoredBox(
    color: AppColors.surface,
    child: Center(child: Icon(Icons.movie_outlined, color: AppColors.textDim)),
  );

  Widget _divider() => Container(
    width: 1,
    height: 34,
    margin: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
    color: AppColors.border,
  );

  Widget _avatar(PublicUser user) {
    final photo = user.avatarUrl;
    return Container(
      width: 88,
      height: 88,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: kNeonGradient,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 24,
            spreadRadius: -8,
          ),
        ],
      ),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.surface,
        ),
        child: photo == null
            ? Center(child: Text(_initial(user), style: AppText.headline))
            : CachedNetworkImage(
                imageUrl: photo,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => Center(child: Text(_initial(user))),
              ),
      ),
    );
  }

  static String _displayName(PublicUser user) {
    final name = user.displayName.trim();
    if (name.isNotEmpty) return name;
    if (user.username.trim().isNotEmpty) return user.username.trim();
    return 'Member #${user.id}';
  }

  static String _initial(PublicUser user) {
    final name = _displayName(user);
    return name.isEmpty ? 'G' : String.fromCharCode(name.runes.first);
  }

  static String _memberSince(String raw) {
    final date = DateTime.tryParse(raw);
    if (date == null) return '';
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }
}
