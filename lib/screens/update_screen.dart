import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../premium.dart';
import '../theme.dart';

/// Hard launch gate: an install older than the API's `minVersionCode` cannot
/// use the app until it updates.
///
/// The copy is deliberately short — the only action is "update". The URL comes
/// from the server so a Play listing change never needs a release.
class UpdateScreen extends StatelessWidget {
  const UpdateScreen({
    super.key,
    required this.installedVersion,
    required this.requiredVersion,
    required this.updateUrl,
    required this.onRetry,
    this.onUpdate,
  });

  final int installedVersion;
  final int requiredVersion;
  final String updateUrl;
  final Future<void> Function() onRetry;

  /// Play's own immediate-update flow when Play reported the update; null on
  /// the direct flavor (the button opens [updateUrl] instead). False = Play
  /// refused to drive it, so the button must fall back to the listing.
  final Future<bool> Function()? onUpdate;

  Future<void> _update() async {
    final handled = await (onUpdate?.call() ?? Future.value(false));
    if (!handled) await _openStore();
  }

  Future<void> _openStore() async {
    if (updateUrl.isEmpty) return;
    try {
      await launchUrl(
        Uri.parse(updateUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // No browser/store handler — the user can still retry.
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpace.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: kNeonGradient,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.35),
                        blurRadius: 40,
                        spreadRadius: -8,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.system_update_rounded,
                    size: 42,
                    color: Color(0xFF04212A),
                  ),
                ),
                const SizedBox(height: AppSpace.lg),
                const Eyebrow(text: 'UPDATE REQUIRED'),
                const SizedBox(height: AppSpace.sm),
                Text(
                  'A newer Ghosst is out',
                  style: AppText.headline,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpace.sm),
                Text(
                  'This version can no longer connect. Update to keep earning '
                  'and claiming — it only takes a few seconds.',
                  textAlign: TextAlign.center,
                  style: AppText.body.copyWith(color: AppColors.textDim),
                ),
                const SizedBox(height: AppSpace.lg),
                Text(
                  'Installed $installedVersion · Required $requiredVersion',
                  textAlign: TextAlign.center,
                  style: monoStyle(fontSize: 12, color: AppColors.textDim),
                ),
                const SizedBox(height: AppSpace.xl),
                NeonButton(
                  expand: true,
                  onPressed: _update,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.download_rounded,
                        size: 19,
                        color: Color(0xFF04212A),
                      ),
                      SizedBox(width: AppSpace.sm),
                      Text('Update now'),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
                TextButton(
                  onPressed: () => onRetry(),
                  child: const Text("I've updated — retry"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
