import 'dart:async';

import 'package:flutter/material.dart';

import '../services/ad_service.dart';
import '../services/backend.dart';
import '../services/yandex_ad_service.dart';
import '../theme.dart';

class EarnScreen extends StatefulWidget {
  const EarnScreen({super.key, required this.coins, required this.onRefresh});

  final int coins;
  final Future<void> Function() onRefresh;

  @override
  State<EarnScreen> createState() => _EarnScreenState();
}

class _EarnScreenState extends State<EarnScreen> with WidgetsBindingObserver {
  final _ads = AdService();
  final _yandexAds = YandexAdService.instance;
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
  bool _lastActionSucceeded = false;
  Completer<void>? _verificationWakeup;

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
      unawaited(_yandexAds.preload());
    }
    _checkCooldown();
  }

  void _onAdsEnabled() {
    if (AdService.adsEnabled && mounted) {
      if (!_ads.ready) _ads.preload();
      if (!_ads.riReady) _ads.preloadRewardedInterstitial();
      unawaited(_yandexAds.preload());
      setState(() {});
    }
  }

  @override
  void dispose() {
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
      if (e.startsWith('No rewarded ads are available from any ad source')) {
        unawaited(_tryYandexAd());
        return;
      }
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
        userId: user.$id,
        preferInterstitial: instant,
        onEarned: (_) =>
            AdUnits.useTestAds ? _claimBetaBonus(afterTestAd: true) : _verify(),
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

  Future<void> _tryYandexAd() async {
    if (!mounted) return;
    setState(() {
      busy = true;
      status = 'Google ads unavailable — trying Yandex…';
    });

    var rewardStarted = false;
    await _yandexAds.showRewarded(
      onRewarded: (_) {
        rewardStarted = true;
        if (AdUnits.useTestAds) {
          unawaited(_claimBetaTestReward());
        } else {
          unawaited(_claimYandexReward());
        }
      },
      onError: (error) {
        debugPrint('[EarnScreen] Yandex fallback unavailable: $error');
        if (!rewardStarted) unawaited(_claimBetaBonus());
      },
      onClosed: () {
        if (!mounted || rewardStarted) return;
        if (status == 'Google ads unavailable — trying Yandex…') {
          setState(() {
            busy = false;
            status = 'Ad closed before a reward was earned.';
          });
          _startCooldown(15);
        }
      },
    );
  }

  Future<void> _claimBetaBonus({bool afterTestAd = false}) async {
    if (afterTestAd) {
      await _claimBetaTestReward();
      return;
    }
    if (!mounted) return;
    setState(() {
      busy = true;
      status = 'No ads available — checking your daily beta bonus…';
    });

    try {
      final result = await Backend.claimBetaBonus();
      if (!mounted) return;
      if (result.granted) {
        try {
          await widget.onRefresh();
        } catch (_) {
          // The server already committed the credit; a later refresh will show it.
        }
        if (!mounted) return;
        setState(() {
          busy = false;
          _lastActionSucceeded = true;
          status = '+${result.amount} coins daily beta bonus added!';
        });
        _startCooldown(30);
        return;
      }

      final alreadyClaimed = result.code == 'already_claimed';
      setState(() {
        busy = false;
        status = alreadyClaimed
            ? 'No ads available. Today’s beta bonus was already claimed; try ads again later.'
            : 'No ads available right now. Please try again in a few minutes.';
      });
      _startCooldown(alreadyClaimed ? 60 : 30);
    } catch (e) {
      debugPrint('[EarnScreen] Beta bonus exception: $e');
      if (!mounted) return;
      setState(() {
        busy = false;
        status =
            'No ads available right now. Please try again in a few minutes.';
      });
      _startCooldown(30);
    }
  }

  Future<void> _claimBetaTestReward() async {
    if (!mounted) return;
    setState(() {
      busy = true;
      status = 'Test ad completed — adding coins…';
    });

    try {
      final result = await Backend.claimBetaTestReward();
      if (!mounted) return;
      if (result.granted) {
        try {
          await widget.onRefresh();
        } catch (_) {
          // Credit is already committed server-side.
        }
        if (!mounted) return;
        setState(() {
          busy = false;
          _lastActionSucceeded = true;
          status = '+${result.amount} test-ad coins added!';
        });
        _startCooldown(30);
        return;
      }

      setState(() {
        busy = false;
        status = result.code == 'cooldown'
            ? 'Test reward cooldown is still active. Please wait a moment.'
            : 'Test ad completed, but coins could not be added right now.';
      });
      _startCooldown(30);
    } catch (e) {
      debugPrint('[EarnScreen] Beta test reward exception: $e');
      if (!mounted) return;
      setState(() {
        busy = false;
        status = 'Test ad completed, but coins could not be added right now.';
      });
      _startCooldown(30);
    }
  }

  Future<void> _claimYandexReward() async {
    if (!mounted) return;
    setState(() {
      busy = true;
      status = 'Yandex reward earned — adding coins…';
    });

    try {
      final result = await Backend.claimYandexReward();
      if (!mounted) return;
      if (result.granted) {
        try {
          await widget.onRefresh();
        } catch (_) {
          // Credit is already committed server-side.
        }
        if (!mounted) return;
        setState(() {
          busy = false;
          _lastActionSucceeded = true;
          status = '+${result.amount} Yandex ad coins added!';
        });
        _startCooldown(30);
        return;
      }

      setState(() {
        busy = false;
        status = switch (result.code) {
          'cooldown' =>
            'Reward cooldown is still active. Please wait a moment.',
          'daily_limit' =>
            'Today’s Yandex reward limit has been reached. Try again tomorrow.',
          _ => 'Ad completed, but coins could not be added right now.',
        };
      });
      _startCooldown(result.code == 'daily_limit' ? 60 : 30);
    } catch (e) {
      debugPrint('[EarnScreen] Yandex reward exception: $e');
      if (!mounted) return;
      setState(() {
        busy = false;
        status = 'Ad completed, but coins could not be added right now.';
      });
      _startCooldown(30);
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

      // Appwrite requests can be interrupted when an ad opens Play Store.
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

  @override
  Widget build(BuildContext context) {
    final success = status == 'Coins added!' || _lastActionSucceeded;
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
          onPressed: (busy || inCooldown)
              ? null
              : () => _watchAd(instant: true),
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
                    Icon(
                      Icons.flash_on_rounded,
                      size: 18,
                      color: AppColors.cyan,
                    ),
                    SizedBox(width: 8),
                    Text('Instant ad & earn coins'),
                  ],
                ),
        ),
        const SizedBox(height: 14),
        Text(
          inCooldown
              ? 'Short cooldown between ads protects your reward eligibility and prevents traffic limits.'
              : 'Rewards are verified before crediting. During beta, a small once-daily server bonus is used only when both ad formats have no inventory.',
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
