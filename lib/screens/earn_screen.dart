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

  @override
  void initState() {
    super.initState();
    _ads.preload();
  }

  @override
  void dispose() {
    _ads.dispose();
    super.dispose();
  }

  Future<void> _watchAd() async {
    final user = await Backend.currentUser();
    if (user == null) {
      setState(() => status = 'Sign in first.');
      return;
    }
    setState(() {
      busy = true;
      status = 'Loading ad…';
    });
    try {
      await _ads.show(
        userId: user.$id,
        onEarned: (_) => _verify(),
        onError: (e) {
          if (mounted) {
            setState(() {
              busy = false;
              status = e;
            });
          }
        },
        onClosed: () {
          // _verify keeps busy=true until verification finishes.
          if (mounted && status == 'Loading ad…') {
            setState(() {
              busy = false;
              status = 'Ad closed before a reward was earned.';
            });
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          status = 'Ad error: $e';
        });
      }
    }
  }

  /// Called from onEarned (ad still on screen). Polls the profile until
  /// AdMob's SSV callback has credited the coins server-side.
  Future<void> _verify() async {
    setState(() => status = 'Reward earned — verifying with server…');
    final before = widget.coins;
    for (var i = 0; i < 23; i++) {
      await Future.delayed(const Duration(seconds: 2));
      final now = await Backend.coins().catchError((_) => before);
      if (mounted) {
        setState(() => status = 'Verifying reward… ($i)');
      }
      if (now > before) {
        await widget.onRefresh();
        if (mounted) {
          setState(() {
            busy = false;
            status = 'Coins added!';
          });
        }
        return;
      }
    }
    if (mounted) {
      setState(() {
        busy = false;
        status =
            'Verification is taking longer than usual. Your coins will be added automatically once Google confirms the reward.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final success = status == 'Coins added!';
    final statusColor = success ? AppColors.green : AppColors.cyan;

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
                child: const Icon(Icons.monetization_on_rounded,
                    color: Color(0xFF422006), size: 30),
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
              border:
                  Border.all(color: statusColor.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
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
          ),
        ],

        // ---- CTA ----
        NeonButton(
          expand: true,
          onPressed: busy ? null : _watchAd,
          child: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.4, color: Colors.white),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.play_circle_rounded,
                        size: 20, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Watch ad & earn coins'),
                  ],
                ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Rewards are verified by Google (SSV) and credited to your balance within a few minutes.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.5),
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
