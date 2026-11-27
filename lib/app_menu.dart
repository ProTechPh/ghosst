import 'package:flutter/material.dart';

import 'theme.dart';

/// Isang menu row: value, label, icon, at opsyonal na disabled/destructive state.
class AppMenuItem<T> {
  const AppMenuItem({
    required this.value,
    required this.label,
    required this.icon,
    this.enabled = true,
    this.destructive = false,
  });

  final T value;
  final String label;
  final IconData icon;
  final bool enabled;
  final bool destructive;
}

/// Shared overflow menu — dark rounded card, icon rows, 52px touch targets.
class AppMenuButton<T> extends StatelessWidget {
  const AppMenuButton({
    super.key,
    required this.items,
    required this.onSelected,
    this.icon = Icons.more_vert,
    this.tooltip = 'More',
  });

  final List<AppMenuItem<T>> items;
  final ValueChanged<T> onSelected;
  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      icon: Icon(icon),
      tooltip: tooltip,
      color: AppColors.surfaceHigh,
      surfaceTintColor: AppColors.surfaceHigh,
      elevation: 8,
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: const BorderSide(color: AppColors.border),
      ),
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final item in items)
          PopupMenuItem<T>(
            value: item.value,
            enabled: item.enabled,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
              child: Row(
                children: [
                  Icon(
                    item.icon,
                    size: 20,
                    color: item.destructive ? AppColors.red : AppColors.cyan,
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Text(
                      item.label,
                      style: AppText.body.copyWith(
                        color: item.destructive ? AppColors.red : Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
