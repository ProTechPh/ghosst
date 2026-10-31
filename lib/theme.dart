import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'premium.dart' show kPremiumCurve;

/// Press feedback: fast enough to feel instant. Transform only — never layout.
/// Lives here (not premium.dart) so the theme does not depend on a widget file.
const kMotionPress = Duration(milliseconds: 120);

/// Standard state transition (expands, fades, swaps).
const kMotionStandard = Duration(milliseconds: 220);

/// Dark-neon ("gamer") design system for Ghosst.
class AppColors {
  AppColors._();

  // Palette derived from the Ghosst emblem: teal-black canvas, glowing cyan,
  // brushed steel — no purple anywhere.
  static const Color bg = Color(0xFF050B0E);
  static const Color bgSoft = Color(0xFF08151A);
  static const Color surface = Color(0xFF0C1D23);
  static const Color surfaceHigh = Color(0xFF122A31);
  static const Color border = Color(0xFF1A3740);
  static const Color primary = Color(0xFF22D3EE);
  static const Color primaryDeep = Color(0xFF0E7490);
  static const Color cyan = Color(0xFF67E8F9);
  static const Color gold = Color(0xFFFBBF24);
  static const Color green = Color(0xFF34D399);
  static const Color red = Color(0xFFF43F5E);
  static const Color text = Color(0xFFF1FAFC);
  static const Color textDim = Color(0xFF8DA6AF);
}

const Gradient kNeonGradient = LinearGradient(
  colors: [Color(0xFF67E8F9), Color(0xFF22D3EE)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

const Gradient kTealGradient = LinearGradient(
  colors: [Color(0xFF0E7490), Color(0xFF164E63)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

const Gradient kGoldGradient = LinearGradient(
  colors: [Color(0xFFFDE68A), Color(0xFFF59E0B)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

/// Spacing scale — every gap is one of these, never a magic number.
class AppSpace {
  AppSpace._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double huge = 48;
}

/// Radius scale — tight inner elements, soft containers.
class AppRadius {
  AppRadius._();

  static const double chip = 8;
  static const double input = 12;
  static const double button = 16;
  static const double card = 22;
  static const double hero = 28;
  static const double pill = 999;
}

/// Type scale. Sizes, weights, heights and tracking are set here once so the
/// app reads as one deliberate type system, not per-screen guesses.
///
/// Numbers (coins, keys, timers, prices) use [figure] — JetBrainsMono with
/// tabular figures so columns of digits never jitter.
class AppText {
  AppText._();

  static const String _sans = 'SpaceGrotesk';
  static const String _mono = 'JetBrainsMono';

  static const TextStyle display = TextStyle(
    fontFamily: _sans,
    fontSize: 34,
    fontWeight: FontWeight.w800,
    height: 1.05,
    letterSpacing: -1.0,
    color: AppColors.text,
  );

  static const TextStyle headline = TextStyle(
    fontFamily: _sans,
    fontSize: 26,
    fontWeight: FontWeight.w800,
    height: 1.08,
    letterSpacing: -0.6,
    color: AppColors.text,
  );

  static const TextStyle title = TextStyle(
    fontFamily: _sans,
    fontSize: 19,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.3,
    color: AppColors.text,
  );

  static const TextStyle subtitle = TextStyle(
    fontFamily: _sans,
    fontSize: 15.5,
    fontWeight: FontWeight.w600,
    height: 1.35,
    color: AppColors.text,
  );

  static const TextStyle body = TextStyle(
    fontFamily: _sans,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppColors.text,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: _sans,
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    height: 1.45,
    color: AppColors.textDim,
  );

  /// Uppercase, wide-tracked eyebrow above sections.
  static const TextStyle label = TextStyle(
    fontFamily: _sans,
    fontSize: 11.5,
    fontWeight: FontWeight.w800,
    height: 1.2,
    letterSpacing: 2,
    color: AppColors.cyan,
  );

  static const TextStyle figure = TextStyle(
    fontFamily: _mono,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.2,
    color: AppColors.text,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      fontFamily: 'SpaceGrotesk',
    );
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.primary,
        onPrimary: Colors.white,
        secondary: AppColors.cyan,
        surface: AppColors.surface,
        onSurface: AppColors.text,
        error: AppColors.red,
        outline: AppColors.border,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.text,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.text,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shadowColor: AppColors.primary.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: AppColors.primary.withValues(alpha: 0.16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.hero),
          side: const BorderSide(color: AppColors.border),
        ),
        titleTextStyle: AppText.title,
        contentTextStyle: AppText.body.copyWith(color: AppColors.textDim),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.hero),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        indicatorColor: AppColors.primary.withValues(alpha: 0.20),
        indicatorShape: const StadiumBorder(),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? AppColors.primary : AppColors.textDim,
            size: 24,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return AppText.caption.copyWith(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.primary : AppColors.textDim,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceHigh.withValues(alpha: 0.55),
        hintStyle: AppText.caption,
        labelStyle: AppText.caption,
        prefixIconColor: AppColors.textDim,
        suffixIconColor: AppColors.textDim,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg,
          vertical: AppSpace.lg,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: AppColors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: AppColors.red, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.xl,
            vertical: AppSpace.lg,
          ),
          textStyle: AppText.subtitle.copyWith(fontSize: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.cyan,
          textStyle: AppText.caption.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceHigh,
        contentTextStyle: AppText.caption.copyWith(color: AppColors.text),
        actionTextColor: AppColors.cyan,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
      ),
      textTheme: base.textTheme.copyWith(
        displayLarge: AppText.display,
        displayMedium: AppText.display.copyWith(fontSize: 30),
        headlineLarge: AppText.headline,
        headlineMedium: AppText.headline.copyWith(fontSize: 22),
        headlineSmall: AppText.headline.copyWith(fontSize: 20),
        titleLarge: AppText.title,
        titleMedium: AppText.subtitle,
        titleSmall: AppText.subtitle.copyWith(fontSize: 14),
        bodyLarge: AppText.body.copyWith(fontSize: 15),
        bodyMedium: AppText.body,
        bodySmall: AppText.caption,
        labelLarge: AppText.subtitle.copyWith(fontWeight: FontWeight.w700),
        labelMedium: AppText.caption.copyWith(fontWeight: FontWeight.w600),
        labelSmall: AppText.label,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.textDim,
        textColor: AppColors.text,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
      ),
      iconTheme: const IconThemeData(color: AppColors.textDim),
    );
  }
}

/// Circular brand emblem — renders the Ghosst logo asset with a neon glow.
/// [fontSize] is retained for API compatibility and is unused.
class LogoBadge extends StatelessWidget {
  const LogoBadge({super.key, this.size = 40, this.fontSize = 20});

  final double size;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.34),
            blurRadius: size * 0.45,
            spreadRadius: 1,
          ),
          // Inner top highlight — light comes from above.
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.10),
            offset: const Offset(0, 1),
            blurRadius: 1,
            blurStyle: BlurStyle.inner,
          ),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/images/logo.jpg',
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            decoration: const BoxDecoration(
              gradient: kNeonGradient,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              'G',
              style: TextStyle(
                color: const Color(0xFF04212A),
                fontSize: fontSize,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Text filled with a neon gradient (via shader mask).
class GradientText extends StatelessWidget {
  const GradientText(
    this.text, {
    super.key,
    this.style,
    this.gradient = kNeonGradient,
  });

  final String text;
  final TextStyle? style;
  final Gradient gradient;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => gradient.createShader(bounds),
      blendMode: BlendMode.srcIn,
      child: Text(
        text,
        style: (style ?? const TextStyle()).copyWith(color: Colors.white),
      ),
    );
  }
}

/// Gradient CTA button with neon glow. Disabled when [onPressed] is null.
class NeonButton extends StatefulWidget {
  const NeonButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.gradient = kNeonGradient,
    this.expand = false,
    this.outline = false,
    this.dense = false,
    this.glow = true,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final Gradient gradient;
  final bool expand;
  final bool outline;
  final bool dense;
  final bool glow;

  @override
  State<NeonButton> createState() => _NeonButtonState();
}

class _NeonButtonState extends State<NeonButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final outline = widget.outline;
    final radius = BorderRadius.circular(AppRadius.button);
    final decoration = BoxDecoration(
      gradient: enabled && !outline ? widget.gradient : null,
      color: enabled
          ? (outline ? Colors.transparent : null)
          : AppColors.surfaceHigh.withValues(alpha: 0.55),
      borderRadius: radius,
      border: Border.all(
        color: enabled && !outline
            ? Colors.transparent
            : (outline && enabled
                  ? Colors.white.withValues(alpha: 0.16)
                  : AppColors.border),
      ),
      boxShadow: enabled && !outline
          ? [
              if (widget.glow)
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.30),
                  blurRadius: 24,
                  spreadRadius: -6,
                  offset: const Offset(0, 8),
                ),
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.14),
                offset: const Offset(0, 1),
                blurRadius: 1,
                blurStyle: BlurStyle.inner,
              ),
            ]
          : null,
    );

    final content = Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: radius,
        onTap: widget.onPressed,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        child: Padding(
          padding: widget.dense
              ? const EdgeInsets.symmetric(
                  horizontal: AppSpace.lg,
                  vertical: AppSpace.sm + 2,
                )
              : const EdgeInsets.symmetric(
                  horizontal: AppSpace.xl,
                  vertical: AppSpace.lg,
                ),
          child: DefaultTextStyle(
            style: AppText.subtitle.copyWith(
              fontSize: widget.dense ? 13.5 : 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
              color: outline
                  ? (enabled ? AppColors.cyan : AppColors.textDim)
                  : (enabled ? const Color(0xFF04212A) : AppColors.textDim),
            ),
            textAlign: TextAlign.center,
            child: widget.child,
          ),
        ),
      ),
    );

    final button = AnimatedScale(
      scale: _down && enabled ? 0.98 : 1,
      duration: kMotionPress,
      curve: kPremiumCurve,
      child: DecoratedBox(decoration: decoration, child: content),
    );
    if (widget.expand) return SizedBox(width: double.infinity, child: button);
    return button;
  }
}

/// Elevated card with subtle surface gradient and optional neon glow.
class GlowCard extends StatelessWidget {
  const GlowCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.glow = false,
    this.onTap,
    this.gradient,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool glow;
  final VoidCallback? onTap;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.card);
    Widget content = child;
    if (onTap != null) {
      content = Material(
        type: MaterialType.transparency,
        child: InkWell(borderRadius: radius, onTap: onTap, child: content),
      );
    }
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient:
            gradient ??
            const LinearGradient(
              colors: [Color(0xFF0C1C22), Color(0xFF071317)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
        borderRadius: radius,
        border: Border.all(color: AppColors.border),
        boxShadow: [
          // One light source, above: a soft cyan-tinted cast, never pure black.
          BoxShadow(
            color: AppColors.primary.withValues(alpha: glow ? 0.18 : 0.08),
            blurRadius: glow ? 30 : 18,
            spreadRadius: -6,
            offset: const Offset(0, 10),
          ),
          // 1px inner top highlight so the top edge catches light.
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.06),
            offset: const Offset(0, 1),
            blurRadius: 1,
            blurStyle: BlurStyle.inner,
          ),
        ],
      ),
      child: content,
    );
  }
}

/// Small rounded status/price pill with icon.
class NeonPill extends StatelessWidget {
  const NeonPill({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.sm,
        vertical: AppSpace.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: AppSpace.xs),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Gold gradient coin balance pill (app bar).
class CoinPill extends StatelessWidget {
  const CoinPill({super.key, required this.coins, this.onTap});

  final int coins;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.sm - 1,
      ),
      decoration: BoxDecoration(
        gradient: kGoldGradient,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withValues(alpha: 0.30),
            blurRadius: 14,
            spreadRadius: -4,
            offset: const Offset(0, 4),
          ),
          // Inner top highlight — the pill is raised, lit from above.
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.30),
            offset: const Offset(0, 1),
            blurRadius: 1,
            blurStyle: BlurStyle.inner,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.monetization_on_rounded,
            size: 16,
            color: Color(0xFF422006),
          ),
          const SizedBox(width: AppSpace.xs + 2),
          Text(
            '$coins',
            // Tabular mono digits — the balance never wiggles as it counts.
            style: AppText.figure.copyWith(
              color: const Color(0xFF422006),
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return pill;
    return GestureDetector(onTap: onTap, child: pill);
  }
}

/// Centered empty/error state with glowing icon.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.12),
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.10),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.30),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.16),
                      blurRadius: 24,
                      spreadRadius: -8,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(icon, size: 30, color: AppColors.primary),
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            Text(
              title,
              style: AppText.title.copyWith(fontSize: 17),
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpace.sm),
              Text(
                message!,
                style: AppText.caption,
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpace.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Small uppercase cyan section label.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.maxLines, this.overflow});

  final String text;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm, top: AppSpace.xs),
      child: Text(
        text.toUpperCase(),
        maxLines: maxLines,
        overflow: overflow,
        style: AppText.label,
      ),
    );
  }
}
