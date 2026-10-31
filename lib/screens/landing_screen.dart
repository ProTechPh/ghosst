import 'package:flutter/material.dart';

import '../arcade.dart';
import '../premium.dart';
import '../theme.dart';

/// Signed-out landing: small brand row, one oversized promise, a numbered
/// steps card, and the action pinned to the bottom so it never scrolls away.
class LandingScreen extends StatelessWidget {
  const LandingScreen({
    super.key,
    required this.onSignIn,
    required this.onSignUp,
  });

  final VoidCallback onSignIn;
  final VoidCallback onSignUp;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const _LandingBackdrop(),
        Positioned.fill(
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(
                        AppSpace.xl,
                        AppSpace.lg,
                        AppSpace.xl,
                        0,
                      ),
                      child: _BrandRow(),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpace.xl,
                          AppSpace.xxl,
                          AppSpace.xl,
                          AppSpace.xl,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ScrollReveal(
                              child: Text(
                                'Watch ads.',
                                style: AppText.display.copyWith(fontSize: 46),
                              ),
                            ),
                            ScrollReveal(
                              delay: const Duration(milliseconds: 70),
                              child: GradientText(
                                'Unlock keys.',
                                style: AppText.display.copyWith(fontSize: 46),
                              ),
                            ),
                            const SizedBox(height: AppSpace.lg),
                            const ScrollReveal(
                              delay: Duration(milliseconds: 140),
                              child: Text(
                                'One rewarded ad pays coins. Trade them for a license key or a verified app download.',
                                style: TextStyle(
                                  fontSize: 16,
                                  height: 1.5,
                                  color: AppColors.textDim,
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpace.xxl),
                            const ScrollReveal(
                              delay: Duration(milliseconds: 200),
                              child: _StepsCard(),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpace.xl,
                        AppSpace.sm,
                        AppSpace.xl,
                        AppSpace.xl,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          NeonButton(
                            expand: true,
                            onPressed: onSignUp,
                            child: const Text('Create account'),
                          ),
                          Center(
                            child: TextButton(
                              onPressed: onSignIn,
                              child: const Text('I already have an account'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Quiet brand row at the top — the headline below carries the screen.
class _BrandRow extends StatelessWidget {
  const _BrandRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const LogoBadge(size: 32),
        const SizedBox(width: AppSpace.sm + 2),
        Text(
          'GHOSST',
          style: AppText.label.copyWith(
            color: AppColors.textDim,
            letterSpacing: 3.2,
          ),
        ),
        const Spacer(),
        Text(
          'COIN ARCADE',
          style: monoStyle(
            fontSize: 10,
            letterSpacing: 1.6,
            color: AppColors.primary.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

/// The three promises as numbered steps in one framed card, not an icon list.
class _StepsCard extends StatelessWidget {
  const _StepsCard();

  static const _steps = <(String, String)>[
    ('Watch', 'One rewarded ad pays coins straight into your wallet.'),
    ('Spend', 'Trade coins for a license key or a verified app download.'),
    ('Keep', 'Every key and purchase stays listed in your account.'),
  ];

  @override
  Widget build(BuildContext context) {
    final hairline = Colors.white.withValues(alpha: 0.08);
    return CardFrame(
      tier: RarityTier.standard,
      radius: AppRadius.hero,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg,
          vertical: AppSpace.xs,
        ),
        child: Column(
          children: [
            for (var i = 0; i < _steps.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, color: hairline),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '0${i + 1}',
                      style: monoStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                        color: AppColors.primary.withValues(alpha: 0.75),
                      ),
                    ),
                    const SizedBox(width: AppSpace.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _steps[i].$1,
                            style: AppText.subtitle.copyWith(fontSize: 16),
                          ),
                          const SizedBox(height: AppSpace.xs),
                          Text(
                            _steps[i].$2,
                            style: AppText.caption.copyWith(
                              height: 1.45,
                              color: AppColors.textDim,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One light source: cyan bloom up top, near-black past the first third.
class _LandingBackdrop extends StatelessWidget {
  const _LandingBackdrop();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const MeshBackground(),
        const Positioned.fill(
          child: IgnorePointer(child: TableSurface()),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -1.05),
                  radius: 1.15,
                  colors: [
                    AppColors.primary.withValues(alpha: 0.20),
                    AppColors.primary.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: const Alignment(0, -0.2),
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.bg.withValues(alpha: 0),
                    AppColors.bg.withValues(alpha: 0.92),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
