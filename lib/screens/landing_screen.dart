import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../premium.dart';
import '../theme.dart';

/// Signed-out landing page — editorial hero + Z-axis "how it works" steps.
class LandingScreen extends StatelessWidget {
  const LandingScreen({
    super.key,
    required this.onSignIn,
    required this.onSignUp,
  });

  final VoidCallback onSignIn;
  final VoidCallback onSignUp;

  Widget _stepCard({
    required int index,
    required String title,
    required String body,
    required IconData icon,
    required Color accent,
    required bool wide,
    required Duration delay,
  }) {
    final rotations = <double>[-0.019, 0.016, -0.013];
    Widget card = DoubleBezel(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.10),
              border: Border.all(color: accent.withValues(alpha: 0.30)),
            ),
            child: Icon(icon, size: 21, color: accent),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '0$index',
                  style: monoStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.4,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: AppColors.textDim,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (wide) {
      // Z-axis: slight rotation + lift so later cards ride over earlier ones.
      card = Transform.translate(
        offset: index == 1
            ? const Offset(6, -26)
            : index == 2
                ? const Offset(-4, -26)
                : Offset.zero,
        child: Transform.rotate(
          angle: rotations[(index - 1) % rotations.length],
          alignment: Alignment.center,
          child: card,
        ),
      );
    }

    return ScrollReveal(
      delay: delay,
      child: card,
    );
  }

  /// Static "key unlocked" preview — shows the payoff before signup.
  Widget _keyPreview({required bool wide}) {
    Widget card = DoubleBezel(
      padding: const EdgeInsets.fromLTRB(20, 18, 18, 16),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF0D2027), Color(0xFF071418)],
      ),
      glowColor: AppColors.green,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Eyebrow(text: 'Key unlocked', color: AppColors.green),
              const Spacer(),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.green.withValues(alpha: 0.12),
                  border: Border.all(
                    color: AppColors.green.withValues(alpha: 0.35),
                  ),
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 17,
                  color: AppColors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'GHST-7F3K-9QX2-M8VZ',
            style: TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.6,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.07)),
          const SizedBox(height: 12),
          const Row(
            children: [
              Icon(
                Icons.shield_outlined,
                size: 14,
                color: AppColors.textDim,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Genuine premium license · delivered instantly',
                  style: TextStyle(fontSize: 12, color: AppColors.textDim),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (wide) {
      // Desktop only: the preview leans in like a physical card on a desk.
      card = Transform.rotate(angle: -0.02, child: card);
    }

    return ScrollReveal(
      delay: const Duration(milliseconds: 320),
      child: card,
    );
  }

  Widget _chip(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 768;
    final stepSpacing =
        wide ? const SizedBox(height: 22) : const SizedBox(height: 16);

    return Stack(
      children: [
        const MeshBackground(),
        Positioned.fill(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(wide ? 64 : 24, 44, wide ? 64 : 24, 56),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ---- Hero (editorial, left-aligned) ---------------------
                    const ScrollReveal(
                      child: LogoBadge(size: 76, fontSize: 37),
                    ),
                    const SizedBox(height: 28),
                    const ScrollReveal(
                      delay: Duration(milliseconds: 80),
                      child: Eyebrow(text: 'Ad-powered key vault'),
                    ),
                    const SizedBox(height: 18),
                    const ScrollReveal(
                      delay: Duration(milliseconds: 140),
                      child: GradientText(
                        'GHOSST',
                        style: TextStyle(
                          fontSize: 58,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 6,
                          height: 1.02,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const ScrollReveal(
                      delay: Duration(milliseconds: 200),
                      child: Text(
                        'Watch ads. Earn coins.\nClaim premium license keys.',
                        style: TextStyle(
                          color: AppColors.textDim,
                          fontSize: 16,
                          height: 1.55,
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),

                    // ---- chips --------------------------------------------
                    ScrollReveal(
                      delay: const Duration(milliseconds: 260),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _chip(
                            'Free to start',
                            Icons.bolt_outlined,
                            AppColors.cyan,
                          ),
                          _chip(
                            'Instant keys',
                            Icons.lock_open_outlined,
                            AppColors.primary,
                          ),
                          _chip(
                            'No subscriptions',
                            Icons.block_outlined,
                            AppColors.gold,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),

                    // ---- key preview ---------------------------------------
                    _keyPreview(wide: wide),
                    const SizedBox(height: 26),

                    // ---- CTAs ----------------------------------------------
                    ScrollReveal(
                      delay: const Duration(milliseconds: 120),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          IslandButton(
                            label: 'Sign in',
                            onPressed: onSignIn,
                          ),
                          const SizedBox(height: 14),
                          IslandButton(
                            label: 'Create account',
                            outline: true,
                            glow: false,
                            icon: CupertinoIcons.arrow_up_right,
                            onPressed: onSignUp,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                    const ScrollReveal(
                      delay: Duration(milliseconds: 200),
                      child: Text(
                        'KEYS DELIVERED INSTANTLY',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2.4,
                          color: AppColors.textDim,
                        ),
                      ),
                    ),

                    // ---- How it works ----------------------------------------
                    const SizedBox(height: 76),
                    const ScrollReveal(
                      child: SectionLabel('HOW IT WORKS'),
                    ),
                    const SizedBox(height: 18),
                    _stepCard(
                      index: 1,
                      title: 'Watch ads',
                      body:
                          'Play a short rewarded ad. Every view pays out coins instantly.',
                      icon: Icons.play_circle_outline,
                      accent: AppColors.cyan,
                      wide: wide,
                      delay: const Duration(milliseconds: 150),
                    ),
                    stepSpacing,
                    _stepCard(
                      index: 2,
                      title: 'Collect coins',
                      body:
                          'Balances stack as you watch. No caps, no waiting periods.',
                      icon: Icons.monetization_on_outlined,
                      accent: AppColors.gold,
                      wide: wide,
                      delay: const Duration(milliseconds: 240),
                    ),
                    stepSpacing,
                    _stepCard(
                      index: 3,
                      title: 'Claim keys',
                      body:
                          'Redeem your coins for genuine premium license keys — delivered on the spot.',
                      icon: Icons.key_outlined,
                      accent: AppColors.primary,
                      wide: wide,
                      delay: const Duration(milliseconds: 330),
                    ),

                    // ---- closing CTA ----------------------------------------
                    const SizedBox(height: 64),
                    ScrollReveal(
                      delay: const Duration(milliseconds: 120),
                      child: IslandButton(
                        label: 'Create your account',
                        icon: CupertinoIcons.arrow_up_right,
                        onPressed: onSignUp,
                      ),
                    ),
                    const SizedBox(height: 28),
                    const Center(
                      child: Text(
                        'GHOSST · WATCH · EARN · CLAIM',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2.4,
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
    );
  }
}
