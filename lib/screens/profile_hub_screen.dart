import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_menu.dart';
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
    this.onSaveProfile,
    this.onPickCover,
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
  final Future<void> Function({required String bio, String? cover})?
  onSaveProfile;
  final Future<String> Function()? onPickCover;

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
      final List<Reel> rows;
      if (widget.loadReels != null) {
        rows = await widget.loadReels!(widget.userId, _reelOffset);
      } else {
        rows = await Backend.userReels(widget.userId, offset: _reelOffset);
      }
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
            key: const ValueKey('profile-edit'),
            tooltip: 'Edit profile',
            onPressed: _openEditSheet,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Share app',
            onPressed: widget.onOpenShare,
            icon: const Icon(Icons.share_outlined),
          ),
          AppMenuButton<String>(
            key: const ValueKey('profile-menu'),
            items: [
              const AppMenuItem(
                value: 'settings',
                label: 'Settings',
                icon: Icons.settings_outlined,
              ),
              const AppMenuItem(
                value: 'keys',
                label: 'Keys',
                icon: Icons.key_outlined,
              ),
              const AppMenuItem(
                value: 'wallet',
                label: 'Wallet',
                icon: Icons.account_balance_wallet_outlined,
              ),
              const AppMenuItem(
                value: 'feedback',
                label: 'Feedback',
                icon: Icons.feedback_outlined,
              ),
              if (widget.isAdmin)
                const AppMenuItem(
                  value: 'admin',
                  label: 'Admin',
                  icon: Icons.admin_panel_settings_outlined,
                ),
            ],
            onSelected: (value) {
              switch (value) {
                case 'settings':
                  widget.onOpenSettings();
                case 'keys':
                  widget.onOpenKeys();
                case 'wallet':
                  widget.onOpenWallet();
                case 'feedback':
                  widget.onOpenFeedback();
                case 'admin':
                  widget.onOpenAdmin();
              }
            },
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
          padding: EdgeInsets.zero,
          children: [
            _header(avatar, initial, profile?.coverUrl),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
              child: Column(
                children: [
                  const SizedBox(height: 50),
                  Text(
                    name.isEmpty ? 'Ghosst member' : name,
                    style: AppText.title.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (username.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      '@$username',
                      style: AppText.caption.copyWith(color: AppColors.textDim),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    key: const ValueKey('profile-bio'),
                    (profile?.bio ?? '').trim().isNotEmpty
                        ? (profile?.bio ?? '').trim()
                        : 'Official drops, updates, and community reels.',
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
                    TextButton(
                      onPressed: _loadProfile,
                      child: const Text('Retry'),
                    ),
                  ],
                  const SizedBox(height: AppSpace.lg),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(
                        child: _stat('Following', profile?.followingCount ?? 0),
                      ),
                      Expanded(
                        child: _stat('Followers', profile?.followerCount ?? 0),
                      ),
                      Expanded(
                        child: _stat('Reels', profile?.reelCount ?? _reels.length),
                      ),
                      Expanded(
                        child: _stat('Likes', profile?.likeCount ?? 0),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.md),
                  const Text(
                    'Posts',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    key: const ValueKey('profile-posts-indicator'),
                    width: 24,
                    height: 2,
                    color: AppColors.tiktokCoral,
                  ),
                  const SizedBox(height: AppSpace.sm),
                ],
              ),
            ),
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
                  mainAxisSpacing: 2,
                  crossAxisSpacing: 2,
                  childAspectRatio: 0.75,
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

  Future<String> _pickCover() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = picked?.files.singleOrNull?.path;
    if (path == null) return '';
    return Backend.uploadCover(path);
  }

  Future<void> _openEditSheet() async {
    final result = await showModalBottomSheet<Map<String, String?>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _ProfileEditSheet(
        bio: (_profile?.bio ?? '').trim(),
        onPickCover: widget.onPickCover ?? _pickCover,
      ),
    );
    if (result == null || !mounted) return;
    try {
      final save = widget.onSaveProfile ??
          ({required String bio, String? cover}) async {
            await Backend.updateBio(bio, cover: cover);
          };
      await save(bio: result['bio'] ?? '', cover: result['cover']);
      if (mounted) await _loadProfile();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save profile: $e')),
        );
      }
    }
  }

  Widget _header(String? avatar, String initial, String? coverUrl) => Stack(
    clipBehavior: Clip.none,
    children: [
      Container(
        key: const ValueKey('profile-tiktok-header'),
        width: double.infinity,
        height: 120,
        color: Colors.black,
        child: Container(
          key: const ValueKey('profile-cover-band'),
          child: coverUrl == null || coverUrl.isEmpty
              ? null
              : CachedNetworkImage(
                  imageUrl: coverUrl,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => const SizedBox.shrink(),
                ),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: -38,
        child: Center(
          child: CircleAvatar(
            radius: 42,
            backgroundColor: AppColors.surfaceHigh,
            backgroundImage: avatar == null || avatar.isEmpty
                ? null
                : CachedNetworkImageProvider(avatar),
            child: avatar == null || avatar.isEmpty
                ? Text(initial, style: AppText.display)
                : null,
          ),
        ),
      ),
    ],
  );

  Widget _stat(String label, int value) => Column(
    children: [
      Text(
        groupDigits(value),
        style: AppText.title.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
      Text(label, style: AppText.caption.copyWith(color: AppColors.textDim)),
    ],
  );
}

class _ProfileEditSheet extends StatefulWidget {
  const _ProfileEditSheet({required this.bio, required this.onPickCover});

  final String bio;
  final Future<String> Function() onPickCover;

  @override
  State<_ProfileEditSheet> createState() => _ProfileEditSheetState();
}

class _ProfileEditSheetState extends State<_ProfileEditSheet> {
  late final TextEditingController _bio = TextEditingController(text: widget.bio);
  String? _cover;

  @override
  void dispose() {
    _bio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      left: AppSpace.lg,
      right: AppSpace.lg,
      top: AppSpace.lg,
      bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpace.lg,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Edit profile', style: AppText.title),
        const SizedBox(height: AppSpace.md),
        TextField(
          key: const ValueKey('profile-bio-field'),
          controller: _bio,
          maxLength: 300,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Bio',
            filled: true,
            fillColor: AppColors.surfaceHigh,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        FilledButton.icon(
          key: const ValueKey('profile-cover-pick'),
          onPressed: () async {
            try {
              final url = await widget.onPickCover();
              if (url.isNotEmpty && mounted) setState(() => _cover = url);
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Could not upload cover: $e')),
                );
              }
            }
          },
          icon: const Icon(Icons.image_outlined),
          label: Text(_cover == null ? 'Change cover' : 'Cover updated'),
        ),
        const SizedBox(height: AppSpace.sm),
        FilledButton(
          key: const ValueKey('profile-save'),
          onPressed: () => Navigator.pop(context, {
            'bio': _bio.text.trim(),
            if (_cover != null) 'cover': _cover,
          }),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
