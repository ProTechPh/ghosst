import 'package:flutter/material.dart';

import '../arcade.dart';
import '../premium.dart';
import '../theme.dart';

/// Signed-out landing page: emblem, one promise, and a three-point list.
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.xl,
                AppSpace.xxl,
                AppSpace.xl,
                AppSpace.xxl,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 540),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const ScrollReveal(
                        child: _HeroCard(),
                      ),
                      const SizedBox(height: AppSpace.xxl),

                      const ScrollReveal(
                        delay: Duration(milliseconds: 200),
                        child: _ValueList(),
                      ),
                      const SizedBox(height: AppSpace.xxl),

                      ScrollReveal(
                        delay: const Duration(milliseconds: 260),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            NeonButton(
                              expand: true,
                              onPressed: onSignUp,
                              child: const Text('Create account'),
                            ),
                            const SizedBox(height: AppSpace.sm),
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
        ),
      ],
    );
  }
}

/// The first thing anyone sees: the brand as a card on the table.
class _HeroCard extends StatelessWidget {
  const _HeroCard();

  @override
  Widget build(BuildContext context) {
    return CardFrame(
      tier: RarityTier.vault,
      radius: AppRadius.hero,
      holo: true,
      glow: true,
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: CoinMedallion(size: 104, child: LogoBadge(size: 54)),
            ),
            const SizedBox(height: AppSpace.xl),
            GradientText(
              'Ghosst',
              style: AppText.display.copyWith(fontSize: 52),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              'Watch an ad, get coins. Spend them on keys.',
              style: TextStyle(
                fontSize: 16.5,
                height: 1.45,
                color: AppColors.textDim,
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            Container(height: 1, width: 96, decoration: BoxDecoration(
              gradient: rarityEdge(RarityTier.vault),
            )),
          ],
        ),
      ),
    );
  }
}
/// The three promises, one list rather than three equal tiles.
class _ValueList extends StatelessWidget {
  const _ValueList();

  static const _points = <({IconData icon, String title, String body})>[
    (
      icon: Icons.play_circle_outline,
      title: 'Watch',
      body: 'One rewarded ad pays coins straight into your wallet.',
    ),
    (
      icon: Icons.key_outlined,
      title: 'Spend',
      body: 'Trade coins for a license key or a verified app download.',
    ),
    (
      icon: Icons.inventory_2_outlined,
      title: 'Keep',
      body: 'Every key and purchase stays listed in your account.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final hairline = Colors.white.withValues(alpha: 0.08);
    return Column(
      children: [
        for (var i = 0; i < _points.length; i++) ...[
          if (i > 0) Divider(height: 1, thickness: 1, color: hairline),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '0${i + 1}',
                  style: monoStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: AppColors.primary.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppRadius.input),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Icon(
                    _points[i].icon,
                    size: 18,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: AppSpace.md + 2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _points[i].title,
                        style: AppText.subtitle.copyWith(fontSize: 15),
                      ),
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        _points[i].body,
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
