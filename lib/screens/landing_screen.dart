import 'package:flutter/material.dart';

import '../arcade.dart';
import '../premium.dart';
import '../theme.dart';

/// Signed-out landing: brand row, one oversized promise, a small table of
/// cards for the product, three moves, and the action pinned to the bottom.
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
        const ArcadeBackdrop(),
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
                          AppSpace.lg,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ScrollReveal(
                              child: Text(
                                'Watch ads.',
                                style: AppText.display.copyWith(fontSize: 44),
                              ),
                            ),
                            ScrollReveal(
                              delay: const Duration(milliseconds: 70),
                              child: GradientText(
                                'Unlock keys.',
                                style: AppText.display.copyWith(fontSize: 44),
                              ),
                            ),
                            const SizedBox(height: AppSpace.md),
                            const ScrollReveal(
                              delay: Duration(milliseconds: 140),
                              child: Text(
                                'One rewarded ad pays coins. Trade them for a license key or a verified app download.',
                                style: TextStyle(
                                  fontSize: 15.5,
                                  height: 1.5,
                                  color: AppColors.textDim,
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpace.xl),
                            const ScrollReveal(
                              delay: Duration(milliseconds: 200),
                              child: _HeroTable(),
                            ),
                            const SizedBox(height: AppSpace.xl),
                            const ScrollReveal(
                              delay: Duration(milliseconds: 260),
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

/// Two cards fanned on the table with a coin medallion sitting on the corner:
/// the product itself as the hero image, without inventing a screenshot.
class _HeroTable extends StatelessWidget {
  const _HeroTable();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 238,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 30,
            child: Transform.rotate(
              angle: -0.13,
              child: const _TableCard(
                tier: RarityTier.plus,
                label: 'LICENSE KEY',
              ),
            ),
          ),
          Positioned(
            top: 12,
            child: Transform.rotate(
              angle: 0.07,
              child: const _TableCard(
                tier: RarityTier.vault,
                label: 'PRIME KEY',
                holo: true,
              ),
            ),
          ),
          const Positioned(right: 0, bottom: 2, child: CoinMedallion(size: 78)),
        ],
      ),
    );
  }
}

class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.tier,
    required this.label,
    this.holo = false,
  });

  final RarityTier tier;
  final String label;
  final bool holo;

  @override
  Widget build(BuildContext context) {
    return CardFrame(
      tier: tier,
      holo: holo,
      radius: AppRadius.card,
      child: SizedBox(
        width: 132,
        height: 170,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: monoStyle(
                  fontSize: 9,
                  letterSpacing: 1.4,
                  color: AppColors.textDim,
                ),
              ),
              const Spacer(),
              Text(
                '•••• ••••',
                style: monoStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: AppColors.text,
                ),
              ),
              const Spacer(),
              const ChipStack(count: 3, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

/// The three promises as numbered steps in one framed card, not an icon list.
class _StepsCard extends StatelessWidget {
  const _StepsCard();

  static const _steps = <(String, String)>[
    ('Watch', 'One rewarded ad pays 10 coins.'),
    ('Spend', 'Trade them for a license key or an app download.'),
    ('Keep', 'Every purchase stays saved in your account.'),
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
                padding: const EdgeInsets.symmetric(vertical: AppSpace.md + 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '0${i + 1}',
                      style: monoStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        height: 1.3,
                        color: AppColors.primary.withValues(alpha: 0.75),
                      ),
                    ),
                    const SizedBox(width: AppSpace.md + 2),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _steps[i].$1,
                            style: AppText.subtitle.copyWith(fontSize: 15.5),
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
