import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/models.dart';
import '../social_shell.dart';
import '../theme.dart';

class ProfileHubScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final initial = displayName.trim().isEmpty
        ? 'G'
        : displayName.trim()[0].toUpperCase();
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const SocialAppBar(title: 'Profile'),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 42,
              backgroundImage: avatarUrl == null || avatarUrl!.isEmpty
                  ? null
                  : CachedNetworkImageProvider(avatarUrl!),
              child: avatarUrl == null || avatarUrl!.isEmpty
                  ? Text(initial, style: AppText.display)
                  : null,
            ),
            const SizedBox(height: AppSpace.md),
            Text(
              displayName.isEmpty ? 'Ghosst member' : displayName,
              style: AppText.title,
            ),
            const SizedBox(height: AppSpace.lg),
            FilledButton(
              onPressed: onOpenSettings,
              child: const Text('Account settings'),
            ),
          ],
        ),
      ),
    );
  }
}
