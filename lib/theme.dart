import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.border),
        ),
        titleTextStyle: const TextStyle(
          color: AppColors.text,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
        contentTextStyle: const TextStyle(
          color: AppColors.textDim,
          fontSize: 14.5,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        indicatorColor: AppColors.primary.withValues(alpha: 0.20),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? AppColors.primary : AppColors.textDim,
            size: 24,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.primary : AppColors.textDim,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        hintStyle: const TextStyle(color: AppColors.textDim),
        prefixIconColor: AppColors.textDim,
        suffixIconColor: AppColors.textDim,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.cyan,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceHigh,
        contentTextStyle: const TextStyle(color: AppColors.text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerTheme:
          const DividerThemeData(color: AppColors.border, thickness: 1),
      textTheme:
          base.textTheme.apply(bodyColor: AppColors.text, displayColor: AppColors.text),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.textDim,
        textColor: AppColors.text,
      ),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: AppColors.primary),
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
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.40),
            blurRadius: size * 0.45,
            spreadRadius: 1,
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
class NeonButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final radius = BorderRadius.circular(16);
    final decoration = BoxDecoration(
      gradient: enabled && !outline ? gradient : null,
      color: enabled
          ? (outline ? Colors.transparent : null)
          : AppColors.surfaceHigh,
      borderRadius: radius,
      border: Border.all(
        color: enabled && outline ? AppColors.border : (enabled ? Colors.transparent : AppColors.border),
      ),
      boxShadow: enabled && glow && !outline
          ? [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ]
          : null,
    );

    final content = Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: radius,
        onTap: onPressed,
        child: Padding(
          padding: dense
              ? const EdgeInsets.symmetric(horizontal: 16, vertical: 10)
              : const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          child: DefaultTextStyle(
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: dense ? 13.5 : 15,
              letterSpacing: 0.2,
              color: outline
                  ? (enabled ? AppColors.cyan : AppColors.textDim)
                  : (enabled ? const Color(0xFF04212A) : Colors.white),
            ),
            textAlign: TextAlign.center,
            child: child,
          ),
        ),
      ),
    );

    final button = DecoratedBox(decoration: decoration, child: content);
    if (expand) return SizedBox(width: double.infinity, child: button);
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
    final radius = BorderRadius.circular(20);
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
        gradient: gradient ??
            const LinearGradient(
              colors: [Color(0xFF0C1C22), Color(0xFF071317)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
        borderRadius: radius,
        border: Border.all(color: AppColors.border),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.18),
                  blurRadius: 26,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        gradient: kGoldGradient,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.monetization_on_rounded,
              size: 16, color: Color(0xFF422006)),
          const SizedBox(width: 6),
          Text(
            '$coins',
            style: const TextStyle(
              color: Color(0xFF422006),
              fontWeight: FontWeight.w900,
              fontSize: 14,
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
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.35),
                ),
              ),
              child: Icon(icon, size: 34, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                style: const TextStyle(
                    color: AppColors.textDim, fontSize: 13.5, height: 1.5),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 16),
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
  const SectionLabel(
    this.text, {
    super.key,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 6),
      child: Text(
        text.toUpperCase(),
        maxLines: maxLines,
        overflow: overflow,
        style: const TextStyle(
          color: AppColors.cyan,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 2,
        ),
      ),
    );
  }
}
