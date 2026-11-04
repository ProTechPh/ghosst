import 'package:flutter/material.dart';

import '../announcement_banner.dart';
import '../services/worker_backend.dart';
import '../theme.dart';

/// Every announcement still published, so a user can re-read the ones the
/// banner already rotated out.
class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key, this.load, this.embedded = false});

  /// Injectable for tests; defaults to the API.
  final Future<List<Announcement>> Function()? load;

  /// True when shown as a shell tab (the shell supplies the bar).
  final bool embedded;

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  List<Announcement> items = const [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
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
        ? const Center(
            child: Text("Wala pang announcement.", style: TextStyle(color: AppColors.textDim)),
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
              return GlowCard(
                padding: const EdgeInsets.all(AppSpace.md),
                onTap: () => showAnnouncementSheet(context, a),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.title, style: AppText.subtitle.copyWith(fontSize: 15)),
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
