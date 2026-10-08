import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../premium.dart';
import '../services/apk_download.dart';
import '../services/backend.dart';
import '../services/mediafire.dart';
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
/// Why the download is fetched in-app but into public Downloads: a modified
/// build is **re-signed**, so Android refuses to install the official APK
/// over it (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`). The file has to be saved
/// first — in the public `Downloads` folder, which survives the uninstall —
/// and only then can this copy be removed and the APK installed.
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
                                  : 'Download the official app — the app '
                                        'saves it straight to your Downloads '
                                        'folder.',
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
                              text: 'Open Ghosst.apk to install it, then '
                                   'sign back in — your keys and coins live '
                                   'in the cloud.',
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),
                      if (url == null) ...[
                        const IslandButton(
                          expand: true,
                          label: 'Download official app',
                          icon: Icons.download_rounded,
                          onPressed: null,
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'The official link isn’t available right now — '
                          'try again a little later.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textDim,
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                      ] else
                        _DownloadOfficialApk(url: url),
                      const SizedBox(height: 14),
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

enum _DownloadPhase { idle, working, saved, failed }

/// The download half of the recovery flow: fetches the official APK inside
/// the app (live progress) with the system DownloadManager, which writes it
/// to the public `Downloads` folder so the file outlives this copy.
///
/// The install itself deliberately happens *after* the uninstall — Android
/// won't lay the official signature over a modified one — so the finished
/// state hands the user to step 02/03 instead of opening the installer.
class _DownloadOfficialApk extends StatefulWidget {
  const _DownloadOfficialApk({required this.url});

  final String url;

  @override
  State<_DownloadOfficialApk> createState() => _DownloadOfficialApkState();
}

class _DownloadOfficialApkState extends State<_DownloadOfficialApk> {
  static const _fileName = 'Ghosst.apk';
  static const _tickEvery = Duration(milliseconds: 300);

  _DownloadPhase _phase = _DownloadPhase.idle;
  Timer? _poll;
  int _id = 0;
  bool _checking = false;
  String _error = '';
  int _received = 0;
  int _total = 0;
  int _speed = 0;
  int _lastReceived = 0;
  DateTime _lastTick = DateTime.now();

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _phase = _DownloadPhase.working;
      _error = '';
      _received = 0;
      _total = 0;
      _speed = 0;
      _lastReceived = 0;
      _lastTick = DateTime.now();
    });
    try {
      // MediaFire share pages need the direct link first; every other host
      // passes through untouched.
      final direct = await MediaFire.resolveDirectUrl(widget.url);
      _id = await OfficialApk.start(url: direct, name: _fileName);
      if (!mounted) return;
      _poll = Timer.periodic(_tickEvery, (_) => _check());
      await _check();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _DownloadPhase.failed;
        _error = _friendly(e);
      });
    }
  }

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    try {
      final s = await OfficialApk.status(_id);
      if (!mounted) return;
      final now = DateTime.now();
      final ms = now.difference(_lastTick).inMilliseconds;
      if (ms > 0) {
        final speed = ((s.received - _lastReceived) * 1000 / ms).round();
        _speed = speed < 0 ? 0 : speed;
      }
      _lastReceived = s.received;
      _lastTick = now;
      if (s.done) {
        _stopPolling();
        setState(() {
          _phase = _DownloadPhase.saved;
          _received = s.received;
          _total = s.total > 0 ? s.total : s.received;
          _speed = 0;
        });
      } else if (s.failed) {
        _stopPolling();
        setState(() {
          _phase = _DownloadPhase.failed;
          _error = s.message.isEmpty
              ? 'The download failed — try again.'
              : s.message;
        });
      } else {
        setState(() {
          _received = s.received;
          _total = s.total;
        });
      }
    } catch (e) {
      _stopPolling();
      if (!mounted) return;
      setState(() {
        _phase = _DownloadPhase.failed;
        _error = _friendly(e);
      });
    } finally {
      _checking = false;
    }
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  /// Last-resort escape hatch: a device that can't reach DownloadManager
  /// still gets a way to the file instead of a dead end.
  Future<void> _openInBrowser() async {
    final opened = await launchUrl(
      Uri.parse(widget.url),
      mode: LaunchMode.externalApplication,
    ).catchError((_) => false);
    if (opened || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not open the link — copy it from SETUP.md'),
        backgroundColor: AppColors.surfaceHigh,
      ),
    );
  }

  String _friendly(Object e) {
    if (e is DownloadLinkException || e is MediaFireException) return '$e';
    if (e is TimeoutException) {
      return 'The download took too long to start — try again.';
    }
    if (e is PlatformException) {
      return e.message ?? 'Could not start the download';
    }
    if (e is MissingPluginException) {
      return 'In-app download isn’t available on this device.';
    }
    return 'Download failed: $e';
  }

  String _fmt(int bytes) {
    if (bytes >= 1048576) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  @override
  Widget build(BuildContext context) {
    final working = _phase == _DownloadPhase.working;
    final fraction = _total > 0 ? (_received / _total).clamp(0.0, 1.0) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_phase == _DownloadPhase.failed && _error.isNotEmpty) ...[
          Text(
            _error,
            style: const TextStyle(
              color: AppColors.red,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _openInBrowser,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'Open the link in your browser instead',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 12,
                  color: AppColors.primary,
                  decoration: TextDecoration.underline,
                  decorationColor: AppColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],

        // ---- live progress while the APK streams into Downloads ----
        if (working) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              color: AppColors.primary,
              backgroundColor: AppColors.surfaceHigh,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _total > 0 ? '${_fmt(_received)} / ${_fmt(_total)}' : _fmt(
                  _received,
                ),
                style: monoStyle(fontSize: 11.5, color: AppColors.textDim),
              ),
              Text(
                '${_fmt(_speed)}/s',
                style: monoStyle(fontSize: 11.5, color: AppColors.textDim),
              ),
            ],
          ),
          const SizedBox(height: 14),
        ],

        if (_phase == _DownloadPhase.saved)
          Container(
            padding: const EdgeInsets.fromLTRB(18, 15, 18, 15),
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  size: 20,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Saved to Downloads',
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Next: remove this copy, then tap $_fileName to '
                        'install.',
                        style: const TextStyle(
                          color: AppColors.textDim,
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          IslandButton(
            expand: true,
            busy: working,
            label: switch (_phase) {
              _DownloadPhase.working => 'Downloading…',
              _DownloadPhase.failed => 'Try again',
              _ => 'Download official app',
            },
            icon: switch (_phase) {
              _DownloadPhase.failed => Icons.refresh_rounded,
              _ => Icons.download_rounded,
            },
            onPressed: working ? null : _start,
          ),
      ],
    );
  }
}
