import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../premium.dart';
import '../services/worker_backend.dart';
import '../social_shell.dart';
import '../theme.dart';

class ProfileHubScreen extends StatefulWidget {
  const ProfileHubScreen({
    super.key,
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    required this.isAdmin,
    required this.onOpenKeys,
    required this.onOpenWallet,
    required this.onOpenFeedback,
    required this.onOpenAdmin,
    required this.onOpenSettings,
    required this.onOpenShare,
    this.loadProfile,
    this.loadReels,
    this.onOpenReel,
  });

  final String userId;
  final String displayName;
  final String? avatarUrl;
  final bool isAdmin;
  final VoidCallback onOpenKeys;
  final VoidCallback onOpenWallet;
  final VoidCallback onOpenFeedback;
  final VoidCallback onOpenAdmin;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenShare;
  final Future<PublicUser> Function(String id)? loadProfile;
  final Future<List<Reel>> Function(String id, int offset)? loadReels;
  final ValueChanged<Reel>? onOpenReel;

  @override
  State<ProfileHubScreen> createState() => _ProfileHubScreenState();
}

class _ProfileHubScreenState extends State<ProfileHubScreen> {
  PublicUser? _profile;
  List<Reel> _reels = const [];
  bool _profileLoading = true;
  bool _profileFailed = false;
  bool _reelsLoading = false;
  bool _reelsFailed = false;
  int _reelOffset = 0;
  bool _hasMoreReels = true;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    unawaited(_loadProfile());
    unawaited(_loadReels());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients ||
        !_hasMoreReels ||
        _reelsLoading ||
        _reelsFailed ||
        _scroll.position.extentAfter > 240) {
      return;
    }
    unawaited(_loadReels());
  }

  Future<void> _loadProfile() async {
    setState(() {
      _profileLoading = true;
      _profileFailed = false;
    });
    try {
      final profile = await (widget.loadProfile ?? Backend.publicUser)(
        widget.userId,
      );
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _profileLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _profileLoading = false;
        _profileFailed = true;
      });
    }
  }

  Future<void> _loadReels({bool reset = false}) async {
    if (reset) {
      setState(() {
        _reels = const [];
        _reelOffset = 0;
        _hasMoreReels = true;
        _reelsLoading = false;
        _reelsFailed = false;
      });
    }
    if (_reelsLoading || !_hasMoreReels) return;
    setState(() {
      _reelsLoading = true;
      _reelsFailed = false;
    });
    try {
      final List<Reel> rows = await (widget.loadReels ?? Backend.userReels)(
        widget.userId,
        _reelOffset,
      );
      if (!mounted) return;
      setState(() {
        _reels = [..._reels, ...rows];
        _reelOffset += rows.length;
        _hasMoreReels = rows.length == 20;
        _reelsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _reelsLoading = false;
        _reelsFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final name = profile?.displayName ?? widget.displayName;
    final username = profile?.username ?? '';
    final avatar = profile?.avatarUrl ?? widget.avatarUrl;
    final initial = name.trim().isEmpty ? 'G' : name.trim()[0].toUpperCase();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: SocialAppBar(
        title: 'Profile',
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: widget.onOpenSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            tooltip: 'Share app',
            onPressed: widget.onOpenShare,
            icon: const Icon(Icons.share_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        onRefresh: () async {
          await _loadProfile();
          await _loadReels(reset: true);
        },
        child: ListView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg,
            AppSpace.lg,
            AppSpace.lg,
            AppSpace.xxl,
          ),
          children: [
            Center(
              child: CircleAvatar(
                radius: 42,
                backgroundImage: avatar == null || avatar.isEmpty
                    ? null
                    : CachedNetworkImageProvider(avatar),
                child: avatar == null || avatar.isEmpty
                    ? Text(initial, style: AppText.display)
                    : null,
              ),
            ),
            const SizedBox(height: AppSpace.md),
            Text(
              name.isEmpty ? 'Ghosst member' : name,
              style: AppText.title,
              textAlign: TextAlign.center,
            ),
            if (username.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                '@$username',
                style: AppText.caption,
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: AppSpace.sm),
            const Text(
              'Official drops, updates, and community reels.',
              style: AppText.caption,
              textAlign: TextAlign.center,
            ),
            if (_profileLoading) ...[
              const SizedBox(height: AppSpace.sm),
              const LinearProgressIndicator(),
            ],
            if (_profileFailed) ...[
              const SizedBox(height: AppSpace.sm),
              const Text(
                'Could not load profile',
                style: AppText.caption,
                textAlign: TextAlign.center,
              ),
              TextButton(onPressed: _loadProfile, child: const Text('Retry')),
            ],
            const SizedBox(height: AppSpace.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _stat('Following', profile?.followingCount ?? 0),
                _stat('Followers', profile?.followerCount ?? 0),
                _stat('Reels', profile?.reelCount ?? _reels.length),
              ],
            ),
            const SizedBox(height: AppSpace.xl),
            Row(
              children: [
                _action(
                  icon: Icons.key_outlined,
                  label: 'Keys',
                  onTap: widget.onOpenKeys,
                ),
                _action(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Wallet',
                  onTap: widget.onOpenWallet,
                ),
                _action(
                  icon: Icons.feedback_outlined,
                  label: 'Feedback',
                  onTap: widget.onOpenFeedback,
                ),
                if (widget.isAdmin)
                  _action(
                    icon: Icons.admin_panel_settings_outlined,
                    label: 'Admin',
                    onTap: widget.onOpenAdmin,
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.xl),
            const SectionHeader(title: 'Your reels'),
            const SizedBox(height: AppSpace.sm),
            if (_reelsLoading && _reels.isEmpty)
              const LinearProgressIndicator()
            else if (_reelsFailed && _reels.isEmpty)
              EmptyState(
                icon: Icons.video_library_outlined,
                title: 'Could not load reels',
                message: 'Check your connection and try again.',
                action: TextButton(
                  onPressed: () => _loadReels(reset: true),
                  child: const Text('Retry'),
                ),
              )
            else if (_reels.isEmpty)
              const EmptyState(
                icon: Icons.video_library_outlined,
                title: 'No reels yet',
                message: 'Your image posts will appear here.',
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 3,
                  crossAxisSpacing: 3,
                ),
                itemCount: _reels.length,
                itemBuilder: (context, index) {
                  final reel = _reels[index];
                  final imageUrl =
                      reel.posterUrl ??
                      (reel.images.isEmpty ? '' : reel.images.first.url);
                  return Semantics(
                    button: widget.onOpenReel != null,
                    label: 'Reel ${reel.id}',
                    child: InkWell(
                      key: ValueKey('profile-reel-${reel.id}'),
                      onTap: widget.onOpenReel == null
                          ? null
                          : () => widget.onOpenReel!(reel),
                      child: imageUrl.isEmpty
                          ? const ColoredBox(
                              color: AppColors.surfaceHigh,
                              child: Center(
                                child: Icon(
                                  Icons.image_not_supported_outlined,
                                  color: AppColors.textDim,
                                ),
                              ),
                            )
                          : CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                              placeholder: (_, _) => const ColoredBox(
                                color: AppColors.surfaceHigh,
                              ),
                              errorWidget: (_, _, _) => const ColoredBox(
                                color: AppColors.surfaceHigh,
                                child: Center(
                                  child: Icon(
                                    Icons.broken_image_outlined,
                                    color: AppColors.textDim,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, int value) => Column(
    children: [
      Text(groupDigits(value), style: AppText.subtitle),
      Text(label, style: AppText.caption),
    ],
  );

  Widget _action({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) => Expanded(
    child: Card(
      margin: const EdgeInsets.only(right: AppSpace.xs),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
          child: Column(
            children: [
              Icon(icon, color: AppColors.primary),
              const SizedBox(height: AppSpace.xs),
              Text(label, style: AppText.caption),
            ],
          ),
        ),
      ),
    ),
  );
}
