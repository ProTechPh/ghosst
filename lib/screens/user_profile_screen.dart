import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../premium.dart';
import '../services/direct_chat_service.dart';
import '../services/worker_backend.dart';
import '../theme.dart';

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
  });

  final String userId;
  final String? initialName;
  final Future<PublicUser> Function(String id)? loader;
  final Future<bool> Function(String id)? loadBlocked;
  final VoidCallback onMessage;
  final VoidCallback onReport;
  final VoidCallback? onBlock;
  final VoidCallback? onUnblock;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  PublicUser? _user;
  bool _loading = true;
  bool _failed = false;
  bool _blocked = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final results = await Future.wait([
        (widget.loader ?? Backend.publicUser)(widget.userId),
        if (widget.loadBlocked != null)
          widget.loadBlocked!(widget.userId)
        else
          DirectChatService().isBlocked(widget.userId),
      ]);
      if (!mounted) return;
      setState(() {
        _user = results[0] as PublicUser;
        _blocked = results[1] as bool;
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
    widget.onBlock?.call();
    setState(() => _blocked = true);
  }

  void _unblock() {
    widget.onUnblock?.call();
    setState(() => _blocked = false);
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
                  child: Text(_blocked ? 'Unblock user' : 'Block user'),
                ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
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
                      child: StatCell(
                        label: 'Followers',
                        value: groupDigits(user.followerCount),
                      ),
                    ),
                    _divider(),
                    Expanded(
                      child: StatCell(
                        label: 'Following',
                        value: groupDigits(user.followingCount),
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
              if (!user.isSelf) ...[
                const SizedBox(height: AppSpace.lg),
                IslandButton(
                  label: _blocked ? 'Blocked' : 'Message',
                  icon: Icons.chat_bubble_outline_rounded,
                  onPressed: _blocked ? null : widget.onMessage,
                ),
              ],
              const SizedBox(height: AppSpace.xl),
              const SectionHeader(title: 'Reels'),
              const SizedBox(height: AppSpace.sm),
              GlowCard(
                padding: const EdgeInsets.all(AppSpace.xl),
                child: const Column(
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
              ),
            ],
          ),
        ),
      ],
    );
  }

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
