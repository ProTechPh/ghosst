import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/worker_backend.dart';
import '../theme.dart';

enum SocialListDirection { followers, following }

class SocialListScreen extends StatefulWidget {
  const SocialListScreen({
    super.key,
    required this.userId,
    required this.direction,
    this.load,
    this.onOpenProfile,
  });

  final String userId;
  final SocialListDirection direction;
  final Future<List<PublicUser>> Function(int offset)? load;
  final ValueChanged<String>? onOpenProfile;

  @override
  State<SocialListScreen> createState() => _SocialListScreenState();
}

class _SocialListScreenState extends State<SocialListScreen> {
  static const _pageSize = 20;
  final _scroll = ScrollController();
  final _ids = <String>{};
  List<PublicUser> _users = [];
  int _offset = 0;
  bool _loading = false;
  bool _failed = false;
  bool _hasMore = true;

  String get _title => widget.direction == SocialListDirection.followers
      ? 'Followers'
      : 'Following';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients || _loading || _failed || !_hasMore) return;
    if (_scroll.position.extentAfter < 240) _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final List<PublicUser> page;
      if (widget.load != null) {
        page = await widget.load!(_offset);
      } else if (widget.direction == SocialListDirection.followers) {
        page = await Backend.followers(widget.userId, offset: _offset);
      } else {
        page = await Backend.following(widget.userId, offset: _offset);
      }
      final fresh = page.where((user) => _ids.add(user.id)).toList();
      if (!mounted) return;
      setState(() {
        _users = [..._users, ...fresh];
        _offset += page.length;
        _hasMore = page.length >= _pageSize;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: Text(_title)),
      body: _loading && _users.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _failed && _users.isEmpty
          ? EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load ${_title.toLowerCase()}',
              action: TextButton(onPressed: _load, child: const Text('Retry')),
            )
          : _users.isEmpty
          ? EmptyState(
              icon: Icons.people_outline,
              title: widget.direction == SocialListDirection.followers
                  ? 'No followers yet'
                  : 'Not following anyone yet',
            )
          : ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(AppSpace.lg),
              itemCount: _users.length + (_hasMore && _loading ? 1 : 0),
              itemBuilder: (_, i) {
                if (i >= _users.length) {
                  return const Padding(
                    padding: EdgeInsets.all(AppSpace.lg),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final user = _users[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.sm),
                  child: GlowCard(
                    onTap: widget.onOpenProfile == null
                        ? null
                        : () => widget.onOpenProfile!(user.id),
                    child: Row(
                      children: [
                        _avatar(user),
                        const SizedBox(width: AppSpace.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(user.displayName, style: AppText.subtitle),
                              if (user.username.isNotEmpty)
                                Text(
                                  '@${user.username}',
                                  style: AppText.caption,
                                ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          color: AppColors.textDim,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _avatar(PublicUser user) {
    final photo = user.avatarUrl;
    return Container(
      width: 44,
      height: 44,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surfaceHigh,
        border: Border.all(color: AppColors.border),
      ),
      child: photo == null
          ? Center(child: Text(user.initial))
          : CachedNetworkImage(
              imageUrl: photo,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => Center(child: Text(user.initial)),
            ),
    );
  }
}
