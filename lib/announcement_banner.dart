import 'package:flutter/material.dart';

import 'services/models.dart';
import 'theme.dart';

/// Dismissible strip for a manual announcement. Same card grammar as the rest
/// of the app, so it reads as part of the table, not a system overlay.
///
/// The strip is capped to a couple of lines; tapping it opens the whole text
/// in a sheet, so a long announcement is never cut off by the banner height.
class AnnouncementBanner extends StatelessWidget {
  const AnnouncementBanner({
    super.key,
    required this.announcement,
    required this.onDismiss,
  });

  final Announcement announcement;
  final VoidCallback onDismiss;

  void _open(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg,
            AppSpace.lg,
            AppSpace.lg,
            AppSpace.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(announcement.title, style: AppText.subtitle),
              const SizedBox(height: AppSpace.sm),
              Flexible(
                child: SingleChildScrollView(
                  child: Text(
                    announcement.body,
                    style: AppText.caption.copyWith(
                      height: 1.5,
                      color: AppColors.textDim,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.md),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlowCard(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.xs, AppSpace.sm),
      onTap: () => _open(context),
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
