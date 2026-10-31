import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../arcade.dart';
import '../premium.dart';
import '../services/ad_service.dart';
import '../services/worker_backend.dart';
import '../theme.dart';

/// Coins per rewarded ad. The Worker owns the real value
/// (`COINS_PER_REWARD`, default 10) and exposes no endpoint for it.
/// shortcut: update this mirror when the operator changes the Worker var.
const int _rewardCoins = 10;

class EarnScreen extends StatefulWidget {
  const EarnScreen({super.key, required this.coins, required this.onRefresh});

  final int coins;
  final Future<void> Function() onRefresh;

  @override
  State<EarnScreen> createState() => _EarnScreenState();
}

class _EarnScreenState extends State<EarnScreen> with WidgetsBindingObserver {
  final _ads = AdService();
  bool busy = false;
  String status = '';

  /// Persistent cooldown timestamp so users cannot spam AdMob and get flagged/throttled.
  static DateTime? _cooldownUntil;
  Timer? _ticker;
  int _remainingCooldown = 0;

  /// Length of the cooldown that started [_remainingCooldown] — drives the
  /// countdown bar's fill. Purely a display mirror of `_cooldownUntil`.
  int _cooldownSpan = 30;

  /// Server-poll verification state — drives the determinate progress bar
  /// so the waiting screen visibly moves instead of sitting on a dead line.
  bool verifying = false;
  double verifyProgress = 0;
  bool _lastActionSucceeded = false;
  Completer<void>? _verificationWakeup;

  /// Anchor for the payout token's start point.
  final GlobalKey _ctaKey = GlobalKey();
  OverlayEntry? _coinEntry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AdService.instance.adsEnabledNotifier.addListener(_onAdsEnabled);
    if (AdService.adsEnabled) {
      _ads.preload();
      if (!_ads.riReady) {
        _ads.preloadRewardedInterstitial();
      }
    }
    _checkCooldown();
  }

  void _onAdsEnabled() {
    if (AdService.adsEnabled && mounted) {
      if (!_ads.ready) _ads.preload();
      if (!_ads.riReady) _ads.preloadRewardedInterstitial();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _endCeremony();
    WidgetsBinding.instance.removeObserver(this);
    AdService.instance.adsEnabledNotifier.removeListener(_onAdsEnabled);
    final wakeup = _verificationWakeup;
    if (wakeup != null && !wakeup.isCompleted) wakeup.complete();
    _ticker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    _checkCooldown();

    // An ad click can temporarily move the user to Play Store. Wake the SSV
    // poll immediately on return instead of leaving the UI on "Verifying".
    final wakeup = _verificationWakeup;
    if (verifying && wakeup != null && !wakeup.isCompleted) wakeup.complete();
  }

  void _startCooldown([int seconds = 30]) {
    _cooldownUntil = DateTime.now().add(Duration(seconds: seconds));
    _cooldownSpan = seconds;
    // _checkCooldown may create its own ticker; drop this one first so it is
    // never orphaned.
    _ticker?.cancel();
    _ticker = null;
    _checkCooldown();
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _checkCooldown();
    });
  }

  void _checkCooldown() {
    final until = _cooldownUntil;
    if (until == null) {
      if (_remainingCooldown != 0) setState(() => _remainingCooldown = 0);
      return;
    }
    final diff = until.difference(DateTime.now()).inSeconds;
    if (diff <= 0) {
      _cooldownUntil = null;
      _ticker?.cancel();
      _ticker = null;
      if (mounted) setState(() => _remainingCooldown = 0);
    } else {
      if (mounted && _remainingCooldown != diff) {
        setState(() => _remainingCooldown = diff);
      }
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        _checkCooldown();
      });
    }
  }

  /// [instant] prefers the rewarded interstitial. If that unit has no fill,
  /// AdService automatically tries the other rewarded format. Both reward
  /// coins through the same SSV callback.
  Future<void> _watchAd({bool instant = false}) async {
    if (_remainingCooldown > 0) return;

    final user = await Backend.currentUser();
    if (user == null) {
      setState(() => status = 'Sign in first.');
      return;
    }
    setState(() {
      busy = true;
      _lastActionSucceeded = false;
      status = 'Loading ad…';
    });

    // Let the Watch-button pointer sequence and route animation fully finish
    // before attaching a third-party fullscreen ad. This prevents the launch
    // tap from being interpreted as an accidental creative/CTA click by an
    // adapter that can present a cached ad immediately.
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;

    void onError(String e) {
      if (mounted) {
        setState(() {
          busy = false;
          status = e;
        });
      }
    }

    void onClosed() {
      // _verify keeps busy=true until verification finishes.
      if (mounted && status == 'Loading ad…') {
        setState(() {
          busy = false;
          status = 'Ad closed before a reward was earned.';
        });
        _startCooldown(15);
      }
    }

    try {
      await _ads.showRewardedWithFallback(
        userId: user.id,
        preferInterstitial: instant,
        onEarned: (_) {
          if (AdUnits.useTestAds) {
            if (!mounted) return;
            setState(() {
              busy = false;
              status = 'Test ad completed. Test ads do not award coins.';
            });
            _startCooldown(30);
            return;
          }
          unawaited(_verify());
        },
        onError: onError,
        onClosed: onClosed,
      );
    } catch (e) {
      debugPrint('[EarnScreen] Ad exception: $e');
      if (mounted) {
        setState(() {
          busy = false;
          status = 'Unable to play ad right now. Please try again in a moment.';
        });
      }
    }
  }

  /// Called from onEarned (ad still on screen). Polls the profile until
  /// AdMob's SSV callback has credited the coins server-side.
  Future<void> _verify() async {
    if (!mounted || verifying) return;
    setState(() {
      verifying = true;
      verifyProgress = 0;
      status = 'Reward earned — verifying with server…';
    });
    final before = widget.coins;
    final deadline = DateTime.now().add(const Duration(seconds: 75));
    for (var i = 0; i < 23; i++) {
      await _waitForVerificationPoll();
      if (!mounted) return;

      // The request can be interrupted when an ad opens the Play Store.
      // Bound every poll so one suspended socket can never strand the UI.
      final now = await Backend.coins()
          .timeout(const Duration(seconds: 6), onTimeout: () => before)
          .catchError((_) => before);
      if (!mounted) return;
      setState(() {
        status = 'Verifying reward…';
        verifyProgress = (i + 1) / 23;
      });
      if (now > before) {
        try {
          await widget.onRefresh();
        } catch (_) {
          // Balance already refreshed by the poll — never strand `busy`.
        }
        if (mounted) {
          setState(() {
            verifying = false;
            busy = false;
            status = 'Coins added!';
          });
          _startCooldown(30);
          _celebrate();
        }
        return;
      }
      if (DateTime.now().isAfter(deadline)) break;
    }
    if (mounted) {
      setState(() {
        verifying = false;
        busy = false;
        status =
            'Verification is taking longer than usual. Your coins will be added automatically once your reward is confirmed.';
      });
      _startCooldown(30);
      // A late SSV credit must become visible without waiting for the next
      // ad — re-read the balance once after giving up.
      try {
        await widget.onRefresh();
      } catch (_) {
        // Balance stays on its last known value; Retry lives in the shell.
      }
    }
  }

  Future<void> _waitForVerificationPoll() async {
    final wakeup = Completer<void>();
    _verificationWakeup = wakeup;
    await Future.any<void>([
      Future<void>.delayed(const Duration(seconds: 2)),
      wakeup.future,
    ]);
    if (identical(_verificationWakeup, wakeup)) {
      _verificationWakeup = null;
    }
  }

  /// One gold token per verified payout: button → app-bar coin pill.
  /// Firing from `_verify` (not `build`) is what keeps it once-per-reward.
  void _celebrate() {
    if (!mounted) return;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    final size = MediaQuery.sizeOf(context);
    final box = _ctaKey.currentContext?.findRenderObject() as RenderBox?;
    var start = box != null && box.attached
        ? box.localToGlobal(box.size.center(Offset.zero))
        : Offset(size.width / 2, size.height - 160);
    if (!(Offset.zero & size).contains(start)) {
      start = Offset(size.width / 2, size.height - 160);
    }
    final end = Offset(
      size.width * 0.82,
      MediaQuery.paddingOf(context).top + 40,
    );

    _endCeremony();
    final entry = OverlayEntry(
      builder: (_) => FloatingCoin(
        from: start,
        to: end,
        label: '+$_rewardCoins',
        onLanded: () {
          _endCeremony();
          HapticFeedback.lightImpact();
        },
      ),
    );
    _coinEntry = entry;
    overlay.insert(entry);
  }

  void _endCeremony() {
    final entry = _coinEntry;
    if (entry == null) return;
    entry.remove();
    entry.dispose();
    _coinEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    final success = status == 'Coins added!' || _lastActionSucceeded;
    final statusColor = success ? AppColors.green : AppColors.cyan;
    final inCooldown = _remainingCooldown > 0;
    final cooldownFill = _cooldownSpan <= 0
        ? 0.0
        : (_remainingCooldown / _cooldownSpan).clamp(0.0, 1.0);

    return Stack(
      children: [
        const Positioned.fill(child: IgnorePointer(child: TableSurface())),
        ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg,
            AppSpace.sm,
            AppSpace.lg,
            AppSpace.huge,
          ),
          children: [
            _hero(inCooldown),
            const SizedBox(height: AppSpace.lg),
            _statsRow(success),
            const SizedBox(height: AppSpace.xl),
            if (status.isNotEmpty) ...[
              _statusPanel(statusColor, success),
              const SizedBox(height: AppSpace.md),
            ],
            KeyedSubtree(
              key: _ctaKey,
              child: _primaryAction(inCooldown, cooldownFill),
            ),
            if (!inCooldown) ...[
              const SizedBox(height: AppSpace.md),
              _secondAction(inCooldown),
            ],
            const SizedBox(height: AppSpace.lg),
            Text(
              inCooldown
                  ? 'Short cooldown between ads protects your reward eligibility and prevents traffic limits.'
                  : 'Rewards are verified before crediting. During beta, a small once-daily server bonus is used only when both ad formats have no inventory.',
              textAlign: TextAlign.center,
              style: AppText.caption.copyWith(height: 1.55),
            ),
            const SizedBox(height: AppSpace.xxl),
            const SectionHeader(title: 'How it works'),
            const SizedBox(height: AppSpace.md),
            Row(
              children: [
                _step('1', 'Watch an ad'),
                const SizedBox(width: AppSpace.sm),
                _step('2', 'Earn coins'),
                const SizedBox(width: AppSpace.sm),
                _step('3', 'Claim keys'),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // ---- hero -------------------------------------------------------------

  Widget _hero(bool inCooldown) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0B242C), Color(0xFF051216)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.hero),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.16),
            blurRadius: 32,
            spreadRadius: -8,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.hero),
        child: Stack(
          children: [
            // Ambient cyan light pooling behind the balance figure.
            Positioned(
              top: -70,
              left: -40,
              child: IgnorePointer(
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.primary.withValues(alpha: 0.20),
                        AppColors.primary.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.xl,
                AppSpace.lg,
                AppSpace.xl,
                AppSpace.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.monetization_on_rounded,
                        size: 15,
                        color: AppColors.gold,
                      ),
                      const SizedBox(width: AppSpace.xs + 2),
                      Text(
                        'YOUR BALANCE',
                        style: AppText.label.copyWith(color: AppColors.textDim),
                      ),
                      const Spacer(),
                      if (!inCooldown)
                        const NeonPill(
                          icon: Icons.bolt_rounded,
                          label: 'LIVE',
                          color: AppColors.cyan,
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.lg),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      groupDigits(widget.coins),
                      maxLines: 1,
                      style: AppText.figure.copyWith(
                        fontSize: 54,
                        fontWeight: FontWeight.w800,
                        height: 1,
                        letterSpacing: -2.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Container(
                    width: 54,
                    height: 1,
                    color: AppColors.gold.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Text('coins ready to spend', style: AppText.caption),
                ],
              ),
            ),
            Positioned(
              right: AppSpace.xl,
              bottom: AppSpace.xl,
              child: const ChipStack(count: 4, size: 42),
            ),
          ],
        ),
      ),
    );
  }

  // ---- live stats -------------------------------------------------------

  Widget _statsRow(bool success) {
    final inCooldown = _remainingCooldown > 0;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.lg,
        vertical: AppSpace.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: StatCell(
              label: 'Cooldown',
              value: inCooldown ? '${_remainingCooldown}s' : 'ready',
              icon: Icons.timer_outlined,
              color: inCooldown ? AppColors.textDim : AppColors.green,
            ),
          ),
          Container(width: 1, height: 30, color: AppColors.border),
          const SizedBox(width: AppSpace.lg),
          Expanded(
            child: StatCell(
              label: 'Verification',
              value: verifying
                  ? '${(verifyProgress * 100).round()}%'
                  : (success ? 'done' : '—'),
              icon: Icons.verified_outlined,
              color: verifying
                  ? AppColors.cyan
                  : (success ? AppColors.green : AppColors.textDim),
            ),
          ),
        ],
      ),
    );
  }

  // ---- status -----------------------------------------------------------

  Widget _statusPanel(Color statusColor, bool success) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.md,
        AppSpace.lg,
        AppSpace.md,
      ),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: statusColor.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!verifying)
                Icon(
                  success
                      ? Icons.check_circle_rounded
                      : (busy
                            ? Icons.hourglass_top_rounded
                            : Icons.info_outline_rounded),
                  size: 17,
                  color: statusColor,
                ),
              if (!verifying) const SizedBox(width: AppSpace.sm + 2),
              Expanded(
                child: Text(
                  status,
                  style: AppText.body.copyWith(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          if (verifying) ...[
            const SizedBox(height: AppSpace.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                value: verifyProgress,
                minHeight: 3,
                backgroundColor: AppColors.border,
                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
              ),
            ),
            const SizedBox(height: AppSpace.sm + 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'Your coins will be added automatically once your reward is confirmed.',
                    style: AppText.caption.copyWith(
                      fontSize: 11.5,
                      height: 1.45,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Text(
                  '${(verifyProgress * 100).round()}%',
                  style: monoStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: statusColor.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ---- actions ----------------------------------------------------------

  Widget _primaryAction(bool inCooldown, double cooldownFill) {
    return NeonButton(
      expand: true,
      onPressed: (busy || inCooldown) ? null : () => _watchAd(),
      child: busy
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: AppSpace.sm + 2),
                Text(
                  status == 'Loading ad…' ? 'Loading ad…' : 'Verifying reward…',
                ),
              ],
            )
          : inCooldown
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.timer_outlined,
                      size: 17,
                      color: AppColors.textDim,
                    ),
                    const SizedBox(width: AppSpace.sm),
                    const Text('Next ad in'),
                    const SizedBox(width: AppSpace.xs + 2),
                    Text(
                      '${_remainingCooldown}s',
                      style: monoStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.sm + 2),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: LinearProgressIndicator(
                    value: cooldownFill,
                    minHeight: 3,
                    backgroundColor: AppColors.border,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.primary.withValues(alpha: 0.55),
                    ),
                  ),
                ),
              ],
            )
          : Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.play_circle_fill_rounded,
                    size: 19,
                    color: AppColors.bg,
                  ),
                  const SizedBox(width: AppSpace.sm),
                  const Text('Watch ad'),
                  const SizedBox(width: AppSpace.xs + 2),
                  Text(
                    '· +$_rewardCoins coins',
                    style: monoStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _secondAction(bool inCooldown) {
    final enabled = !busy && !inCooldown;
    return NeonButton(
      expand: true,
      outline: true,
      glow: false,
      onPressed: enabled ? () => _watchAd(instant: true) : null,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            inCooldown ? Icons.hourglass_empty_rounded : Icons.flash_on_rounded,
            size: 17,
            color: enabled ? AppColors.cyan : AppColors.textDim,
          ),
          const SizedBox(width: AppSpace.sm),
          if (inCooldown) ...[
            const Text('Cooldown'),
            const SizedBox(width: AppSpace.xs + 2),
            Text(
              '${_remainingCooldown}s',
              style: monoStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.textDim,
              ),
            ),
          ] else ...[
            Text(
              'Instant ad',
              style: TextStyle(
                color: enabled ? AppColors.cyan : AppColors.textDim,
              ),
            ),
            const SizedBox(width: AppSpace.xs + 2),
            Text(
              '· +$_rewardCoins coins',
              style: monoStyle(
                fontWeight: FontWeight.w700,
                color: enabled ? AppColors.cyan : AppColors.textDim,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _step(String n, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpace.md + 2,
          horizontal: AppSpace.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(AppRadius.input),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                n,
                style: monoStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              label,
              textAlign: TextAlign.center,
              style: AppText.caption.copyWith(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
