import 'dart:async';

import 'package:appwrite/appwrite.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../premium.dart';
import '../services/backend.dart';
import '../theme.dart';

enum _Phase { processing, success, failure }

/// Cinematic full-screen claim flow.
///
/// Opens immediately with a staged "securing" checklist while [claim]
/// executes, then transitions to the key reveal (or an error state).
/// Returns `true` once the caller should refresh its state.
///
/// [kind] is `'key'` (license reveal) or `'app'` (MediaFire download unlock).
Future<bool> showClaimFlow({
  required BuildContext context,
  required Product product,
  required int balanceBefore,
  required Future<String> Function() claim,
  String kind = 'key',
  int? cost,
}) async {
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierLabel: kind == 'app' ? 'Unlock download' : 'Claim key',
    barrierColor: Colors.black.withValues(alpha: 0.8),
    transitionDuration: const Duration(milliseconds: 520),
    pageBuilder: (ctx, _, _) => _ClaimFlow(
      product: product,
      balanceBefore: balanceBefore,
      claim: claim,
      kind: kind,
      spent: cost,
    ),
    transitionBuilder: (ctx, anim, secondary, child) {
      final curved = CurvedAnimation(parent: anim, curve: kPremiumCurve);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.03),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
  return result ?? false;
}

class _ClaimFlow extends StatefulWidget {
  const _ClaimFlow({
    required this.product,
    required this.balanceBefore,
    required this.claim,
    required this.kind,
    this.spent,
  });

  final Product product;
  final int balanceBefore;
  final Future<String> Function() claim;

  /// `'key'` → license reveal · `'app'` → download unlock.
  final String kind;

  /// Amount actually charged — differs from [Product.cost] when the buyer
  /// picked a duration option. Falls back to the product's flat cost.
  final int? spent;

  int get _spent => spent ?? product.cost;

  @override
  State<_ClaimFlow> createState() => _ClaimFlowState();
}

class _ClaimFlowState extends State<_ClaimFlow> {
  _Phase _phase = _Phase.processing;
  int _step = 0;
  String _key = '';
  String _error = '';
  bool _copied = false;
  bool _running = false;
  final List<Timer> _stageTimers = [];

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    for (final t in _stageTimers) {
      t.cancel();
    }
    super.dispose();
  }

  void _cancelStages() {
    for (final t in _stageTimers) {
      t.cancel();
    }
    _stageTimers.clear();
  }

  Future<void> _run() async {
    if (_running) return;
    _running = true;
    final watch = Stopwatch()..start();

    _cancelStages();
    _stageTimers.addAll([
      Timer(const Duration(milliseconds: 650), () {
        if (mounted && _phase == _Phase.processing) setState(() => _step = 1);
      }),
      Timer(const Duration(milliseconds: 1450), () {
        if (mounted && _phase == _Phase.processing) setState(() => _step = 2);
      }),
    ]);

    try {
      final key = await widget.claim();
      // Let the staged checklist play out before the reveal beat.
      final remaining = 2100 - watch.elapsedMilliseconds;
      if (remaining > 0) {
        await Future<void>.delayed(Duration(milliseconds: remaining));
      }
      if (!mounted) return;
      setState(() {
        _key = key;
        _step = 3;
      });
      await Future<void>.delayed(const Duration(milliseconds: 550));
      if (!mounted) return;
      await HapticFeedback.mediumImpact();
      setState(() => _phase = _Phase.success);
    } catch (e) {
      final msg = e is AppwriteException ? (e.message ?? 'Claim failed') : '$e';
      final remaining = 900 - watch.elapsedMilliseconds;
      if (remaining > 0) {
        await Future<void>.delayed(Duration(milliseconds: remaining));
      }
      if (!mounted) return;
      setState(() {
        _error = msg;
        _phase = _Phase.failure;
      });
    } finally {
      _cancelStages();
      _running = false;
    }
  }

  void _retry() {
    setState(() {
      _phase = _Phase.processing;
      _step = 0;
      _error = '';
      _copied = false;
      _key = '';
    });
    _run();
  }

  Future<void> _copy() async {
    if (_key.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _key));
    await HapticFeedback.lightImpact();
    if (mounted) setState(() => _copied = true);
  }

  // ---- pieces ----------------------------------------------------------

  /// App-store unlock vs license-key reveal.
  bool get _isApp => widget.kind == 'app';

  Widget _island({
    required IconData icon,
    required Color color,
    required bool spin,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.4, end: 1),
      duration: const Duration(milliseconds: 650),
      curve: kOvershootCurve,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: 0.95),
              color.withValues(alpha: 0.75),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.40),
              blurRadius: 44,
              spreadRadius: -6,
            ),
          ],
        ),
        child: spin
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  color: Colors.white,
                ),
              )
            : Icon(icon, color: Colors.white, size: 34),
      ),
    );
  }

  Widget _checkRow(String label, int index) {
    final done = _step > index;
    final active = _step == index && _phase == _Phase.processing;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          AnimatedContainer(
            duration: kMotionBase,
            curve: kPremiumCurve,
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done
                  ? AppColors.green.withValues(alpha: 0.14)
                  : active
                  ? AppColors.cyan.withValues(alpha: 0.10)
                  : Colors.white.withValues(alpha: 0.04),
              border: Border.all(
                color: done
                    ? AppColors.green.withValues(alpha: 0.55)
                    : active
                    ? AppColors.cyan.withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.10),
              ),
            ),
            child: done
                ? const Icon(
                    Icons.check_rounded,
                    size: 14,
                    color: AppColors.green,
                  )
                : active
                ? const Padding(
                    padding: EdgeInsets.all(5),
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: AppColors.cyan,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 13),
          AnimatedDefaultTextStyle(
            duration: kMotionBase,
            curve: kPremiumCurve,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: done ? FontWeight.w600 : FontWeight.w500,
              color: done ? AppColors.text : AppColors.textDim,
            ),
            child: Text(label),
          ),
        ],
      ),
    );
  }

  Widget _processingView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _island(
          icon: _isApp ? Icons.download_rounded : Icons.key_outlined,
          color: AppColors.primary,
          spin: false,
        ),
        const SizedBox(height: 30),
        Eyebrow(
          text: _isApp ? 'Secure unlock' : 'Secure claim',
          color: AppColors.cyan,
        ),
        const SizedBox(height: 18),
        Text(
          widget.product.name,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _isApp ? 'Securing your download…' : 'Securing your key…',
          style: const TextStyle(color: AppColors.textDim, fontSize: 14),
        ),
        const SizedBox(height: 34),
        DoubleBezel(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _checkRow('Verifying balance', 0),
              _checkRow(_isApp ? 'Reserving download' : 'Reserving key', 1),
              _checkRow(_isApp ? 'Unlocking file' : 'Revealing key', 2),
            ],
          ),
        ),
      ],
    );
  }

  /// Open the product's YouTube tutorial after purchase. The raw URL is
  /// passed straight through — youtu.be / watch / shorts links all resolve —
  /// and the dialog stays open so "Download now" is still one tap away.
  Future<void> _openTutorial() async {
    final url = widget.product.youtubeUrl.trim();
    if (url.isEmpty) return;
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      // No handler available — nothing else to fall back to here.
    }
  }

  Widget _successView() {
    final after = (widget.balanceBefore - widget._spent).clamp(0, 1 << 30);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _island(icon: Icons.check_rounded, color: AppColors.green, spin: false),
        const SizedBox(height: 30),
        Eyebrow(
          text: _isApp ? 'Download unlocked' : 'Key unlocked',
          color: AppColors.green,
        ),
        const SizedBox(height: 18),
        Text(
          widget.product.name,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _isApp ? 'Your download is ready' : 'Your license key is ready',
          style: const TextStyle(color: AppColors.textDim, fontSize: 14),
        ),
        const SizedBox(height: 28),

        // ---- balance delta ---------------------------------------------
        DoubleBezel(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'BALANCE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2.2,
                        color: AppColors.textDim,
                      ),
                    ),
                    const SizedBox(height: 6),
                    AnimatedCounter(
                      value: after,
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: AppColors.gold,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'SPENT',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.2,
                      color: AppColors.textDim,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '-${widget._spent}',
                    style: monoStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.red,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // The raw download URL is intentionally hidden for app/file
        // purchases — buyers go through "Download now" instead of copying
        // the file-host link themselves.
        if (!_isApp) ...[
          const SizedBox(height: 16),

          // ---- key card ---------------------------------------------------
          DoubleBezel(
            padding: const EdgeInsets.fromLTRB(20, 18, 16, 14),
            glowColor: AppColors.green,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isApp ? 'FILE LINK' : 'YOUR KEY',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.2,
                    color: AppColors.textDim,
                  ),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  _key,
                  style: monoStyle(
                    fontSize: _isApp ? 13.5 : 15.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: _isApp ? 0 : 1.3,
                    color: AppColors.text,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.07),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    AnimatedOpacity(
                      opacity: _copied ? 1 : 0,
                      duration: kMotionFast,
                      curve: kPremiumCurve,
                      child: const Text(
                        'COPIED',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                          color: AppColors.green,
                        ),
                      ),
                    ),
                    PressableScale(
                      onTap: _copy,
                      child: AnimatedContainer(
                        duration: kMotionFast,
                        curve: kPremiumCurve,
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _copied
                              ? AppColors.green.withValues(alpha: 0.16)
                              : Colors.white.withValues(alpha: 0.07),
                          border: Border.all(
                            color: _copied
                                ? AppColors.green.withValues(alpha: 0.55)
                                : Colors.white.withValues(alpha: 0.14),
                          ),
                        ),
                        child: AnimatedSwitcher(
                          duration: kMotionFast,
                          transitionBuilder: (child, anim) => ScaleTransition(
                            scale: anim,
                            child: FadeTransition(opacity: anim, child: child),
                          ),
                          child: _copied
                              ? const Icon(
                                  Icons.check_rounded,
                                  key: ValueKey('check'),
                                  size: 17,
                                  color: AppColors.green,
                                )
                              : const Icon(
                                  Icons.copy_outlined,
                                  key: ValueKey('copy'),
                                  size: 16,
                                  color: AppColors.text,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 26),
        IslandButton(
          label: _isApp ? 'Download now' : 'Done',
          icon: _isApp ? Icons.download_rounded : CupertinoIcons.checkmark,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF34D399), Color(0xFF10B981)],
          ),
          onPressed: () => Navigator.of(context).pop(true),
        ),
        // Tutorial for app/file products — only when the admin set a link.
        if (_isApp && widget.product.youtubeUrl.trim().isNotEmpty) ...[
          const SizedBox(height: 14),
          IslandButton(
            label: 'Watch tutorial',
            icon: Icons.play_circle_outline_rounded,
            outline: true,
            glow: false,
            onPressed: _openTutorial,
          ),
        ],
      ],
    );
  }

  Widget _failureView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _island(icon: Icons.close_rounded, color: AppColors.red, spin: false),
        const SizedBox(height: 30),
        const Eyebrow(text: 'Claim failed', color: AppColors.red),
        const SizedBox(height: 18),
        Text(
          widget.product.name,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 22),
        DoubleBezel(
          padding: const EdgeInsets.all(18),
          borderColor: AppColors.red.withValues(alpha: 0.35),
          child: Text(
            _error.isEmpty ? 'Something went wrong.' : _error,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.red,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 26),
        IslandButton(label: 'Try again', onPressed: _retry),
        const SizedBox(height: 14),
        IslandButton(
          label: 'Close',
          icon: CupertinoIcons.xmark,
          outline: true,
          glow: false,
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final view = switch (_phase) {
      _Phase.processing => _processingView(),
      _Phase.success => _successView(),
      _Phase.failure => _failureView(),
    };

    // `showGeneralDialog` has no Material ancestor, so Texts here would
    // inherit MaterialApp's _errorTextStyle (yellow double underline +
    // monospace fallback). A transparent Material resets DefaultTextStyle.
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          const MeshBackground(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(26, 40, 26, 40),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 500),
                  switchInCurve: kPremiumCurve,
                  switchOutCurve: kPremiumCurve,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.04),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(key: ValueKey(_phase), child: view),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
