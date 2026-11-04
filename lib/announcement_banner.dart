import 'package:flutter/material.dart';

import 'services/models.dart';
import 'theme.dart';

/// Dismissible strip for a manual announcement. Same card grammar as the rest
/// of the app, so it reads as part of the table, not a system overlay.
class AnnouncementBanner extends StatelessWidget {
  const AnnouncementBanner({
    super.key,
    required this.announcement,
    required this.onDismiss,
  });

  final Announcement announcement;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return GlowCard(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.xs, AppSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  announcement.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.subtitle.copyWith(fontSize: 15),
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  announcement.body,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(height: 1.4, color: AppColors.textDim),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            icon: const Icon(Icons.close, size: 18),
            color: AppColors.textDim,
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}
