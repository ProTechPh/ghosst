import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../premium.dart';
import '../services/backend.dart';
import '../services/security.dart';
import '../theme.dart';

/// Last-resort official APK link, used when the backend has **no** active
/// forced-update announcement to borrow a download from.
///
/// Point it at your current official share page (MediaFire, etc). Leave it
/// empty to show a disabled button rather than a dead link.
const String kOfficialApkUrl = '';

/// Full-screen, un-skippable integrity gate.
///
/// Replaces the entire app tree at launch when [SecurityReport.blocked] says
/// the running build was modified (re-signed, debug, patched). Same shape as
/// `UpdateRequiredScreen`: no route to pop, no close button — the only way
/// out is the official app.
///
/// Why the download opens in the browser instead of downloading in-app: a
/// modified build is **re-signed**, so Android refuses to install the
/// official APK over it (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`). The file has
/// to be fetched first (it lands in public Downloads, which survives the
/// uninstall), and only then can this copy be removed.
class TamperDetectedScreen extends StatelessWidget {
  const TamperDetectedScreen({
    super.key,
    this.info,
    this.flags = const <String>[],
  });

  /// Active forced-update announcement, when there is one — its `url` is the
  /// official APK the backend already points every other build at.
  final UpdateInfo? info;

  /// Native flags from the integrity check (what tripped it).
  final List<String> flags;

  /// Where the official APK can be fetched from.
  String? get _downloadUrl {
    final fromUpdate = info?.url.trim();
    if (fromUpdate != null && fromUpdate.isNotEmpty) return fromUpdate;
    final fallback = kOfficialApkUrl.trim();
    return fallback.isEmpty ? null : fallback;
  }

  List<String> get _reasons => flags.isEmpty
      ? <String>["This build doesn't match the official release"]
      : flags.map(securityReason).toList();

  Future<void> _openDownload(BuildContext context) async {
    final url = _downloadUrl;
    if (url == null) return;
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open the download — $url'),
          backgroundColor: AppColors.surfaceHigh,
        ),
      );
    }
  }

  Future<void> _removeCopy(BuildContext context) async {
    final opened = await Security.uninstallSelf();
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open the uninstall screen — remove Ghosst from '
            'Settings › Apps.',
          ),
          backgroundColor: AppColors.surfaceHigh,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = _downloadUrl;
    final reasons = _reasons;

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
                      const SectionLabel('App integrity'),
                      const Text(
                        'Official app required',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'This copy of Ghosst was modified before it was '
                        'installed. Modified builds aren’t supported — '
                        'install the official app to keep using your '
                        'account, keys and coins.',
                        style: TextStyle(
                          color: AppColors.textDim,
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ---- what tripped the check ----
                      DoubleBezel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SectionLabel('Why you see this'),
                            const SizedBox(height: 10),
                            for (var i = 0; i < reasons.length; i++) ...[
                              if (i > 0) const SizedBox(height: 8),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.gpp_maybe_outlined,
                                    size: 15,
                                    color: AppColors.gold,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      reasons[i],
                                      style: const TextStyle(
                                        color: AppColors.text,
                                        fontSize: 13.5,
                                        height: 1.45,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ---- how to get back in ----
                      DoubleBezel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SectionLabel('Get back in'),
                            const SizedBox(height: 10),
                            _Step(
                              n: 1,
                              text: url == null
                                  ? 'Download the official app — the '
                                        'official link isn’t available right '
                                        'now.'
                                  : 'Download the official app — the file '
                                        'lands in your Downloads folder.',
                            ),
                            const SizedBox(height: 8),
                            const _Step(
                              n: 2,
                              text: 'Remove this copy — Android won’t '
                                   'install the official APK over a modified '
                                   'one.',
                            ),
                            const SizedBox(height: 8),
                            const _Step(
                              n: 3,
                              text: 'Install the official APK and sign back '
                                   'in — your keys and coins live in the '
                                   'cloud.',
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),
                      IslandButton(
                        expand: true,
                        label: 'Download official app',
                        icon: Icons.download_rounded,
                        onPressed: url == null ? null : () => _openDownload(context),
                      ),
                      if (url != null) ...[
                        const SizedBox(height: 10),
                        // Shown verbatim so it can be typed into a browser
                        // later — the link outlives this app on the device.
                        Text(
                          url,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: monoStyle(
                            fontSize: 11,
                            color: AppColors.textDim,
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      IslandButton(
                        expand: true,
                        outline: true,
                        label: 'Remove this copy',
                        icon: Icons.delete_outline,
                        onPressed: () => _removeCopy(context),
                      ),
                      const SizedBox(height: 14),
                      const Center(
                        child: Text(
                          'YOUR ACCOUNT, KEYS AND COINS STAY · '
                          'THE OFFICIAL APP IS THE ONLY WAY IN',
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

/// Numbered instruction line — mono index, human copy.
class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text});

  final int n;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '0$n',
          style: monoStyle(fontSize: 12, color: AppColors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 13.5,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}
