import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../arcade.dart';
import '../premium.dart';
import '../services/ad_service.dart';
import '../services/worker_backend.dart';
import '../theme.dart';

/// One rewarded ad pays `coinsPerReward` from `/ads/status` (the SSV handler
/// owns the real value; 10 is the fallback while the status fetch is pending).
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

  /// Balance before the reward — a late SSV credit is compared against this so
  /// the user can re-check without watching another ad.
  int _rewardBaseline = 0;
  bool _verifyTimedOut = false;
  bool _rechecking = false;

  /// Rolling 24h budget; null until the first status fetch lands.
  AdsRewardStatus? _rewardStatus;
  Timer? _capTimer;

  /// Payout the server will actually credit — never a hardcoded mirror.
  int get _rewardCoins => _rewardStatus?.coinsPerReward ?? 10;

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
    }
    _checkCooldown();
    unawaited(_loadRewardStatus());
  }

  /// Advisory budget check: disables the button at 0 so nobody watches an ad
  /// that the API's daily cap would drop. Failures never block the button.
  Future<void> _loadRewardStatus() async {
    try {
      if (await Backend.currentUser() == null) return;
      final status = await Backend.adsRewardStatus();
      if (!mounted) return;
      setState(() => _rewardStatus = status);
      if (status.atCap) {
        // A rolling window frees a slot at an arbitrary time; re-check so the
        // button does not stay dead while the user sits on this tab.
        _capTimer ??= Timer(const Duration(minutes: 5), () {
          _capTimer = null;
          if (mounted) unawaited(_loadRewardStatus());
        });
      } else {
        _capTimer?.cancel();
        _capTimer = null;
      }
    } catch (_) {
      // Network/API blip — keep the last known status.
    }
  }

  void _onAdsEnabled() {
    if (AdService.adsEnabled && mounted) {
      if (!_ads.ready) _ads.preload();
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
    _capTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    _checkCooldown();

    // SSV can land while the app was backgrounded — check again instead of
    // leaving the "taking longer than usual" message up.
    if (_verifyTimedOut && !_rechecking) unawaited(_recheck());
    unawaited(_loadRewardStatus());

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

  /// Plays the standard rewarded ad; SSV credits the coins server-side.
  Future<void> _watchAd() async {
    if (_remainingCooldown > 0) return;

    final user = await Backend.currentUser();
    if (user == null) {
      setState(() => status = 'Sign in first.');
      return;
    }
    setState(() {
      busy = true;
      _lastActionSucceeded = false;
      _verifyTimedOut = false;
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
      _verifyTimedOut = false;
      status = 'Reward earned — verifying with server…';
    });
    _rewardBaseline = widget.coins;
    final before = _rewardBaseline;
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
            _verifyTimedOut = false;
            status = 'Coins added!';
          });
          _startCooldown(30);
          _celebrate();
          unawaited(_loadRewardStatus());
        }
        return;
      }
      if (DateTime.now().isAfter(deadline)) break;
    }
    if (mounted) {
      setState(() {
        verifying = false;
        busy = false;
        _verifyTimedOut = true;
        status =
            'Verification is taking longer than usual. Your coins will be added automatically once your reward is confirmed.';
      });
      _startCooldown(30);
      unawaited(_loadRewardStatus());
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

  /// Second look after the 75 s window. SSV can land late, so this compares
  /// the balance against what it was when the reward was earned.
  Future<void> _recheck() async {
    if (_rechecking) return;
    setState(() {
      _rechecking = true;
      status = 'Checking your balance…';
    });
    final now = await Backend.coins()
        .timeout(const Duration(seconds: 6), onTimeout: () => _rewardBaseline)
        .catchError((_) => _rewardBaseline);
    if (!mounted) return;
    if (now > _rewardBaseline) {
      try {
        await widget.onRefresh();
      } catch (_) {
        // The pill catches up on the next shell refresh.
      }
      if (!mounted) return;
      setState(() {
        _rechecking = false;
        _verifyTimedOut = false;
        status = 'Coins added!';
      });
      _celebrate();
      unawaited(_loadRewardStatus());
      return;
    }
    setState(() {
      _rechecking = false;
      status =
          'Still not confirmed. Coins land automatically once the reward is verified — try again in a minute.';
    });
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
    final atCap = _rewardStatus?.atCap ?? false;
    final shownStatus = atCap && !busy && !verifying
        ? 'Daily limit reached (${_rewardStatus!.limit} ads / 24h). Coins unlock again as older rewards expire.'
        : status;
    final success = (status == 'Coins added!' || _lastActionSucceeded) && !atCap;
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
            _statsGrid(inCooldown),
            const SizedBox(height: AppSpace.lg),
            if (shownStatus.isNotEmpty) ...[
              _statusPanel(shownStatus, statusColor, success),
              const SizedBox(height: AppSpace.md),
            ],
            KeyedSubtree(
              key: _ctaKey,
              child: _primaryAction(inCooldown, cooldownFill, atCap),
            ),
            const SizedBox(height: AppSpace.md),
            if (inCooldown) ...[
              _cooldownProgress(cooldownFill),
              const SizedBox(height: 6),
              Text(
                'Cooldown: ${_remainingCooldown}s remaining',
                textAlign: TextAlign.center,
                style: AppText.caption.copyWith(
                  fontSize: 10,
                  color: AppColors.textDim,
                  letterSpacing: 0.5,
                ),
              ),
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
            const SizedBox(height: AppSpace.sm),
            _stepRow('1', 'Watch an ad', 'One rewarded ad pays $_rewardCoins coins.'),
            _stepRow('2', 'Earn coins', 'Verified before they land in your balance.'),
            _stepRow('3', 'Claim keys', 'Spend them in the store on a key or app.'),
          ],
        ),
      ],
    );
  }

  // ---- hero -------------------------------------------------------------

  Widget _hero(bool inCooldown) {
    return Column(
      children: [
        Row(
          children: [
            Text(
              'EARN COINS',
              style: AppText.label.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                color: AppColors.cyan,
              ),
            ),
            const Spacer(),
            if (!inCooldown)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.green.withValues(alpha: 0.6)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'LIVE',
                      style: AppText.label.copyWith(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: AppColors.green,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
        Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              center: Alignment(-0.3, -0.3),
              colors: [Color(0xFFFDE68A), Color(0xFFF59E0B), Color(0xFFB45309)],
              stops: [0.0, 0.4, 0.85],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.gold.withValues(alpha: 0.4),
                blurRadius: 60,
                spreadRadius: -10,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                margin: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 2,
                  ),
                ),
              ),
              Text(
                'G',
                style: AppText.figure.copyWith(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF422006),
                  height: 1,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            groupDigits(widget.coins),
            maxLines: 1,
            style: AppText.figure.copyWith(
              fontSize: 52,
              fontWeight: FontWeight.w900,
              height: 1,
              letterSpacing: -2,
              color: AppColors.gold,
              shadows: [
                Shadow(
                  color: AppColors.gold.withValues(alpha: 0.4),
                  blurRadius: 30,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'COINS READY TO SPEND',
          style: AppText.label.copyWith(
            fontSize: 10,
            color: AppColors.textDim,
            letterSpacing: 2.5,
          ),
        ),
      ],
    );
  }

  // ---- stats grid -------------------------------------------------------

  Widget _statsGrid(bool inCooldown) {
    return Row(
      children: [
        Expanded(child: _statCard(value: '$_rewardCoins', label: 'PER AD')),
        const SizedBox(width: 10),
        Expanded(
          child: _statCard(
            value: inCooldown ? '${_remainingCooldown}s' : '30s',
            label: 'COOLDOWN',
          ),
        ),
      ],
    );
  }

  Widget _statCard({required String value, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.bgSoft.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: AppText.figure.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.cyan,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppText.label.copyWith(
              fontSize: 9,
              color: AppColors.textDim,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cooldownProgress(double fill) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: Container(
        height: 4,
        color: Colors.white.withValues(alpha: 0.08),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: fill.clamp(0.0, 1.0),
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.cyan, Color(0xFF67E8F9), AppColors.gold],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.cyan.withValues(alpha: 0.5),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- status -----------------------------------------------------------

  Widget _statusPanel(String text, Color statusColor, bool success) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.md,
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
                      : (busy ? Icons.hourglass_top_rounded : Icons.info_outline_rounded),
                  size: 17,
                  color: statusColor,
                ),
              if (!verifying) const SizedBox(width: AppSpace.sm + 2),
              Expanded(
                child: Text(
                  text,
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
          if (_verifyTimedOut && !verifying && !(_rewardStatus?.atCap ?? false)) ...[
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _rechecking ? null : _recheck,
                icon: _rechecking
                    ? const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 16),
                label: Text(_rechecking ? 'Checking…' : 'Check again'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.cyan,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
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
                    style: AppText.caption.copyWith(fontSize: 11.5, height: 1.45),
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

  Widget _primaryAction(bool inCooldown, double cooldownFill, bool atCap) {
    return NeonButton(
      expand: true,
      onPressed: (busy || inCooldown || atCap) ? null : () => _watchAd(),
      child: busy
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                ),
                const SizedBox(width: AppSpace.sm + 2),
                Text(status == 'Loading ad…' ? 'Loading ad…' : 'Verifying reward…'),
              ],
            )
          : inCooldown
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.timer_outlined, size: 17, color: AppColors.textDim),
                const SizedBox(width: AppSpace.sm),
                const Text('Next ad in'),
                const SizedBox(width: AppSpace.xs + 2),
                Text('${_remainingCooldown}s', style: monoStyle(fontWeight: FontWeight.w800)),
              ],
            )
          : atCap
          ? const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.block, size: 18, color: AppColors.textDim),
                SizedBox(width: AppSpace.sm),
                Text('Daily limit reached'),
              ],
            )
          : Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.play_circle_fill_rounded, size: 19, color: AppColors.bg),
                  const SizedBox(width: AppSpace.sm),
                  const Text('Watch ad'),
                  const SizedBox(width: AppSpace.xs + 2),
                  Text('· +$_rewardCoins coins', style: monoStyle(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
    );
  }

  Widget _stepRow(String n, String title, String caption) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 24, height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withValues(alpha: 0.1),
              border: Border.all(color: AppColors.cyan.withValues(alpha: 0.6)),
            ),
            alignment: Alignment.center,
            child: Text(n, style: AppText.label.copyWith(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.cyan)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.subtitle.copyWith(fontSize: 12, fontWeight: FontWeight.w600)),
                Text(caption, style: AppText.caption.copyWith(fontSize: 10, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
