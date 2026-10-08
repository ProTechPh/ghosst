import 'dart:async';

import 'package:flutter/material.dart';

import '../services/ad_service.dart';
import '../services/backend.dart';
import '../theme.dart';

class EarnScreen extends StatefulWidget {
  const EarnScreen({super.key, required this.coins, required this.onRefresh});

  final int coins;
  final Future<void> Function() onRefresh;

  @override
  State<EarnScreen> createState() => _EarnScreenState();
}

class _EarnScreenState extends State<EarnScreen> {
  final _ads = AdService();
  bool busy = false;
  String status = '';

  /// Persistent cooldown timestamp so users cannot spam AdMob and get flagged/throttled.
  static DateTime? _cooldownUntil;
  Timer? _ticker;
  int _remainingCooldown = 0;

  /// Server-poll verification state — drives the determinate progress bar
  /// so the waiting screen visibly moves instead of sitting on a dead line.
  bool verifying = false;
  double verifyProgress = 0;

  @override
  void initState() {
    super.initState();
    // Both earn formats preloaded so either button responds instantly.
    _ads.preload();
    _ads.preloadRewardedInterstitial();
    _checkCooldown();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _startCooldown([int seconds = 30]) {
    _cooldownUntil = DateTime.now().add(Duration(seconds: seconds));
    _ticker?.cancel();
    _checkCooldown();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
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

  /// [instant] picks the rewarded interstitial (second earn method);
  /// both reward coins through the same SSV callback.
  Future<void> _watchAd({bool instant = false}) async {
    if (_remainingCooldown > 0) return;

    final user = await Backend.currentUser();
    if (user == null) {
      setState(() => status = 'Sign in first.');
      return;
    }
    setState(() {
      busy = true;
      status = 'Loading ad…';
    });

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
      if (instant) {
        await _ads.showRewardedInterstitial(
          userId: user.$id,
          onEarned: (_) => _verify(),
          onError: onError,
          onClosed: onClosed,
        );
      } else {
        await _ads.show(
          userId: user.$id,
          onEarned: (_) => _verify(),
          onError: onError,
          onClosed: onClosed,
        );
      }
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
    setState(() {
      verifying = true;
      verifyProgress = 0;
      status = 'Reward earned — verifying with server…';
    });
    final before = widget.coins;
    for (var i = 0; i < 23; i++) {
      await Future.delayed(const Duration(seconds: 2));
      final now = await Backend.coins().catchError((_) => before);
      if (mounted) {
        setState(() {
          status = 'Verifying reward…';
          verifyProgress = (i + 1) / 23;
        });
      }
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
        }
        return;
      }
    }
    if (mounted) {
      setState(() {
        verifying = false;
        busy = false;
        status = 'Verification is taking longer than usual. Your coins will be added automatically once your reward is confirmed.';
      });
      _startCooldown(30);
    }
  }

  @override
  Widget build(BuildContext context) {
    final success = status == 'Coins added!';
    final statusColor = success ? AppColors.green : AppColors.cyan;
    final inCooldown = _remainingCooldown > 0;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // ---- Balance hero card ----
        GlowCard(
          glow: true,
          padding: const EdgeInsets.all(20),
          gradient: const LinearGradient(
            colors: [Color(0xFF0B242C), Color(0xFF051216)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: const BoxDecoration(
                  gradient: kGoldGradient,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.monetization_on_rounded,
                  color: Color(0xFF422006),
                  size: 30,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'YOUR BALANCE',
                      style: TextStyle(
                        color: AppColors.textDim,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${widget.coins} coins',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const NeonPill(
                icon: Icons.bolt_rounded,
                label: 'LIVE',
                color: AppColors.cyan,
              ),
            ],
          ),
        ),

        const SizedBox(height: 22),

        // ---- How it works ----
        const SectionLabel('How it works'),
        Row(
          children: [
            _step('1', 'Watch an ad'),
            const SizedBox(width: 8),
            _step('2', 'Earn coins'),
            const SizedBox(width: 8),
            _step('3', 'Claim keys'),
          ],
        ),

        const SizedBox(height: 22),

        // ---- Status ----
        if (status.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: statusColor.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (busy)
                      SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.1,
                          color: statusColor,
                        ),
                      )
                    else
                      Icon(
                        success
                            ? Icons.check_circle_rounded
                            : Icons.info_outline_rounded,
                        size: 18,
                        color: statusColor,
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        status,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
                if (verifying) ...[
                  const SizedBox(height: 12),
                  // Determinate bar (attempt n of 23) — the waiting state
                  // visibly moves instead of freezing on one line of text.
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: verifyProgress,
                      minHeight: 6,
                      backgroundColor: AppColors.surfaceHigh,
                      valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Hang tight — verifying your reward, usually under a minute.',
                    style: TextStyle(
                      color: statusColor.withValues(alpha: 0.8),
                      fontSize: 11.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],

        // ---- CTA ----
        NeonButton(
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
                    const SizedBox(width: 10),
                    Text(
                      status == 'Loading ad…'
                          ? 'Loading ad…'
                          : 'Verifying reward…',
                    ),
                  ],
                )
              : inCooldown
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.timer_outlined,
                          size: 19,
                          color: AppColors.textDim,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Next ad in ${_remainingCooldown}s',
                          style: const TextStyle(
                            color: AppColors.textDim,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.play_circle_rounded,
                          size: 20,
                          color: Colors.white,
                        ),
                        SizedBox(width: 8),
                        Text('Watch ad & earn coins'),
                      ],
                    ),
        ),
        const SizedBox(height: 12),
        // Second earn method — rewarded interstitial (same SSV payout).
        NeonButton(
          expand: true,
          outline: true,
          glow: false,
          onPressed: (busy || inCooldown) ? null : () => _watchAd(instant: true),
          child: inCooldown
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.hourglass_empty_rounded,
                      size: 17,
                      color: AppColors.textDim,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Cooldown active (${_remainingCooldown}s)',
                      style: const TextStyle(
                        color: AppColors.textDim,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.flash_on_rounded, size: 18, color: AppColors.cyan),
                    SizedBox(width: 8),
                    Text('Instant ad & earn coins'),
                  ],
                ),
        ),
        const SizedBox(height: 14),
        Text(
          inCooldown
              ? 'Short cooldown between ads protects your reward eligibility and prevents traffic limits.'
              : 'Rewards are verified before being credited to your balance within a few minutes.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textDim,
            fontSize: 12.5,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _step(String n, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.18),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.45),
                ),
              ),
              child: Text(
                n,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textDim,
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
