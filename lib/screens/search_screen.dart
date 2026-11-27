import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/worker_backend.dart';
import '../theme.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    this.searchUsers,
    this.searchReels,
    this.onOpenProfile,
    this.onOpenReel,
  });

  final Future<List<ChatUserSummary>> Function(String)? searchUsers;
  final Future<List<Reel>> Function(String)? searchReels;
  final ValueChanged<String>? onOpenProfile;
  final ValueChanged<Reel>? onOpenReel;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _input = TextEditingController();
  Timer? _debounce;
  String _query = '';
  List<ChatUserSummary> _users = const [];
  List<Reel> _reels = const [];
  bool _usersLoading = false;
  bool _reelsLoading = false;
  bool _usersFailed = false;
  bool _reelsFailed = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _input.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    setState(() {
      _query = query;
      _users = const [];
      _reels = const [];
      _usersLoading = false;
      _reelsLoading = false;
      _usersFailed = false;
      _reelsFailed = false;
    });
    if (query.length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_runUsers(query));
      unawaited(_runReels(query));
    });
  }

  Future<void> _runUsers(String query) async {
    setState(() {
      _usersLoading = true;
      _usersFailed = false;
    });
    try {
      final rows = await (widget.searchUsers ?? Backend.searchUsers)(query);
      if (!mounted) return;
      setState(() {
        _users = rows;
        _usersLoading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _usersLoading = false;
          _usersFailed = true;
        });
      }
    }
  }

  Future<void> _runReels(String query) async {
    setState(() {
      _reelsLoading = true;
      _reelsFailed = false;
    });
    try {
      final rows = await (widget.searchReels ?? Backend.searchReels)(query);
      if (!mounted) return;
      setState(() {
        _reels = rows;
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

  void _openUser(ChatUserSummary user) {
    Navigator.of(context).pop();
    widget.onOpenProfile?.call(user.id);
  }

  void _openReel(Reel reel) {
    Navigator.of(context).pop();
    widget.onOpenReel?.call(reel);
  }

  Widget _section({
    required String title,
    required bool loading,
    required bool failed,
    required bool empty,
    required String emptyKey,
    required String retryKey,
    required VoidCallback onRetry,
    required Widget child,
  }) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg,
            AppSpace.md,
            AppSpace.lg,
            AppSpace.xs,
          ),
          child: Text(
            title,
            style: AppText.caption.copyWith(color: AppColors.primary),
          ),
        ),
        if (loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (failed)
          Expanded(
            child: Center(
              key: ValueKey(retryKey.replaceFirst('-retry', '-error')),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Could not load results'),
                  TextButton(
                    key: ValueKey(retryKey),
                    onPressed: onRetry,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          )
        else if (empty)
          Expanded(child: Center(child: Text('Nothing here', key: ValueKey(emptyKey))))
        else
          Expanded(child: child),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: TextField(
          key: const ValueKey('search-input'),
          controller: _input,
          autofocus: true,
          onChanged: _onChanged,
          style: AppText.body,
          decoration: const InputDecoration(
            hintText: 'Search people and reels',
            border: InputBorder.none,
          ),
        ),
        actions: [
          IconButton(
            key: const ValueKey('search-clear'),
            tooltip: 'Clear search',
            icon: const Icon(Icons.close),
            onPressed: () {
              _input.clear();
              _onChanged('');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _section(
            title: 'PEOPLE',
            loading: _usersLoading,
            failed: _usersFailed,
            empty: _users.isEmpty && !_usersLoading && !_usersFailed,
            emptyKey: 'search-no-users',
            retryKey: 'search-users-retry',
            onRetry: () => unawaited(_runUsers(_query)),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.lg,
                vertical: AppSpace.sm,
              ),
              itemCount: _users.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: AppSpace.md),
              itemBuilder: (_, i) => _userRow(_users[i]),
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          _section(
            title: 'REELS',
            loading: _reelsLoading,
            failed: _reelsFailed,
            empty: _reels.isEmpty && !_reelsLoading && !_reelsFailed,
            emptyKey: 'search-no-reels',
            retryKey: 'search-reels-retry',
            onRetry: () => unawaited(_runReels(_query)),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.lg,
                vertical: AppSpace.sm,
              ),
              itemCount: _reels.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: AppSpace.md),
              itemBuilder: (_, i) => _reelRow(_reels[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _userRow(ChatUserSummary user) => GlowCard(
    key: ValueKey('search-user-${user.id}'),
    onTap: () => _openUser(user),
    child: Row(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: AppColors.surfaceHigh,
          backgroundImage:
              user.avatarUrl == null || user.avatarUrl!.isEmpty
              ? null
              : CachedNetworkImageProvider(user.avatarUrl!),
          child: Text(user.initial, style: AppText.caption),
        ),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.name, style: AppText.subtitle.copyWith(fontSize: 14)),
              Text('@${user.name.toLowerCase()}', style: AppText.caption),
            ],
          ),
        ),
        const Icon(Icons.chevron_right, color: AppColors.textDim),
      ],
    ),
  );

  Widget _reelRow(Reel reel) => GlowCard(
    key: ValueKey('search-reel-${reel.id}'),
    onTap: () => _openReel(reel),
    child: Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.input),
          child: SizedBox(
            width: 64,
            height: 64,
            child: reel.posterUrl == null || reel.posterUrl!.isEmpty
                ? const ColoredBox(color: AppColors.surfaceHigh)
                : CachedNetworkImage(
                    imageUrl: reel.posterUrl!,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) =>
                        const ColoredBox(color: AppColors.surfaceHigh),
                  ),
          ),
        ),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                reel.caption.isEmpty ? 'Reel' : reel.caption,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.body.copyWith(fontSize: 13),
              ),
              const SizedBox(height: AppSpace.xs),
              Row(
                children: [
                  Icon(
                    Icons.favorite_border,
                    size: 14,
                    color: AppColors.textDim,
                  ),
                  Text(' ${reel.likeCount}', style: AppText.caption),
                  const SizedBox(width: AppSpace.md),
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 14,
                    color: AppColors.textDim,
                  ),
                  Text(' ${reel.commentCount}', style: AppText.caption),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
