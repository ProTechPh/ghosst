import 'package:flutter/material.dart';

import '../premium.dart';
import '../services/backend.dart';
import '../theme.dart';
import 'apk_installer.dart';

/// Full-screen, un-skippable update gate.
///
/// Replaces the entire app tree at launch whenever the backend announces a
/// newer build: there is no route to pop and no close button — users update
/// or they don't get in. The APK downloads inside the app (live progress),
/// then the system installer takes over; cancelling the install sheet just
/// lands back here with an "Install now" retry (no re-download).
///
/// The download itself lives in [ApkInstaller], shared with the
/// modified-app gate.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({
    super.key,
    required this.info,
    required this.currentBuild,
  });

  final UpdateInfo info;

  /// This build's `buildNumber` (from `pubspec` `1.0.0+N`).
  final int currentBuild;

  @override
  Widget build(BuildContext context) {
    final newName = info.versionName.trim().isEmpty
        ? 'v${info.versionCode}'
        : info.versionName.trim();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          const MeshBackground(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionLabel('Update required'),
                      const Text(
                        'A new Ghosst version is ready',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Please update to keep using the app — '
                        'this only takes a moment.',
                        style: TextStyle(
                          color: AppColors.textDim,
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ---- version comparison card ----
                      DoubleBezel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'INSTALLED',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 2.2,
                                          color: AppColors.textDim,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'build $currentBuild',
                                        style: monoStyle(
                                          fontSize: 14,
                                          color: AppColors.textDim,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 17,
                                  color: AppColors.gold,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.end,
                                    children: [
                                      const Text(
                                        'NEW VERSION',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 2.2,
                                          color: AppColors.gold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '$newName · build ${info.versionCode}',
                                        textAlign: TextAlign.right,
                                        style: monoStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.text,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (info.message.trim().isNotEmpty) ...[
                              const SizedBox(height: 14),
                              Divider(
                                height: 1,
                                color: Colors.white.withValues(alpha: 0.08),
                              ),
                              const SizedBox(height: 14),
                              const SectionLabel("What's new"),
                              Text(
                                info.message.trim(),
                                style: const TextStyle(
                                  color: AppColors.text,
                                  fontSize: 13.5,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      // error + live progress + CTA
                      ApkInstaller(info: info),

                      const SizedBox(height: 14),
                      const Center(
                        child: Text(
                          'YOUR ACCOUNT, KEYS AND COINS STAY · '
                          'THE UPDATE INSTALLS OVER THIS APP',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.6,
                            color: AppColors.textDim,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
