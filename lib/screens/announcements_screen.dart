import 'package:flutter/material.dart';

import '../announcement_banner.dart';
import '../services/worker_backend.dart';
import '../theme.dart';

/// Every announcement still published, so a user can re-read the ones the
/// banner already rotated out.
class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({
    super.key,
    this.load,
    this.embedded = false,
    this.active = true,
  });

  /// Injectable for tests; defaults to the API.
  final Future<List<Announcement>> Function()? load;

  /// True when shown as a shell tab (the shell supplies the bar).
  final bool embedded;

  /// False when hidden inside `IndexedStack` — defers the fetch until the
  /// tab is first opened (same gate as `ChatScreen`/`MyKeysScreen`).
  final bool active;

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  List<Announcement> items = const [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    // IndexedStack mounts every tab at once — skip the fetch for a hidden
    // tab so shell open does not pay for News when the user never taps it.
    if (widget.active) _load();
  }

  @override
  void didUpdateWidget(covariant AnnouncementsScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _load();
  }

  Future<void> _load() async {
    final loaded = await (widget.load ?? Backend.announcements)();
    if (!mounted) return;
    setState(() {
      items = loaded;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final body = loading
        ? const Center(child: CircularProgressIndicator())
        : items.isEmpty
        ? const EmptyState(
            icon: Icons.campaign_outlined,
            title: 'No announcements yet',
            message: 'Check back later for updates.',
          )
        : ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.lg,
              AppSpace.lg,
              AppSpace.xxl,
            ),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpace.sm),
            itemBuilder: (_, i) {
              final a = items[i];
              return Stack(
                children: [
                  // Vertical timeline line.
                  if (i != items.length - 1)
                    Positioned(
                      left: 6,
                      top: 20,
                      bottom: 0,
                      child: Container(width: 2, color: AppColors.border),
                    ),
                  // Glowing dot.
                  Positioned(
                    left: 2,
                    top: 14,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.7),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 24),
                    child: GlowCard(
                      padding: const EdgeInsets.all(AppSpace.md),
                      onTap: () => showAnnouncementSheet(context, a),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a.title,
                            style: AppText.subtitle.copyWith(fontSize: 15),
                          ),
                          if (a.createdAt.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              a.createdAt,
                              style: AppText.caption.copyWith(
                                fontSize: 11,
                                color: AppColors.textDim.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                          const SizedBox(height: AppSpace.xs),
                          Text(
                            a.body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption.copyWith(
                              height: 1.4,
                              color: AppColors.textDim,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          );

    if (widget.embedded) return body;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Announcements')),
      body: body,
    );
  }
}
