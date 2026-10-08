import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

// ---------------------------------------------------------------------------
// Motion language
// ---------------------------------------------------------------------------

/// Signature curve for every premium transition: cubic-bezier(0.32, 0.72, 0, 1)
const kPremiumCurve = Cubic(0.32, 0.72, 0, 1);

/// Soft, springy ease-out used for staged reveals.
const kSpringCurve = Cubic(0.22, 1, 0.36, 1);

/// Gentle overshoot for check-marks / celebratory pops.
const kOvershootCurve = Cubic(0.34, 1.56, 0.64, 1);

const kMotionFast = Duration(milliseconds: 240);
const kMotionBase = Duration(milliseconds: 420);
const kMotionSlow = Duration(milliseconds: 800);

/// Monospace style for license keys, counters and technical data.
TextStyle monoStyle({
  double? fontSize,
  FontWeight? fontWeight,
  Color? color,
  double? letterSpacing,
  double? height,
}) {
  return TextStyle(
    fontFamily: 'JetBrainsMono',
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    letterSpacing: letterSpacing,
    height: height,
  );
}

String groupDigits(int value) {
  return value.toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (m) => ',',
      );
}

// ---------------------------------------------------------------------------
// ScrollReveal — viewport-entry fade-up, fires once
// ---------------------------------------------------------------------------

class ScrollReveal extends StatefulWidget {
  const ScrollReveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = const Offset(0, 0.08),
  });

  final Widget child;

  /// Stagger delay applied once the element enters the viewport.
  final Duration delay;

  /// Fraction-of-size slide the element travels from. Animate transform only.
  final Offset offset;

  @override
  State<ScrollReveal> createState() => _ScrollRevealState();
}

class _ScrollRevealState extends State<ScrollReveal> {
  bool _revealed = false;
  bool _scheduled = false;
  bool _pendingReveal = false;
  int _attempts = 0;
  ScrollPosition? _position;

  @override
  void initState() {
    super.initState();
    _scheduleCheck();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (!identical(position, _position)) {
      _position?.removeListener(_handleScroll);
      _position = position;
      _position?.addListener(_handleScroll);
    }
    _scheduleCheck();
  }

  @override
  void dispose() {
    _position?.removeListener(_handleScroll);
    super.dispose();
  }

  void _handleScroll() => _scheduleCheck();

  void _scheduleCheck() {
    if (_revealed || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || _revealed) return;
      _checkViewport();
    });
  }

  void _checkViewport() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) {
      if (++_attempts < 12) _scheduleCheck();
      return;
    }
    final origin = box.localToGlobal(Offset.zero);
    final screen = MediaQuery.sizeOf(context);
    // Visible as soon as any part of the element sits at/above the fold.
    if (origin.dy < screen.height) {
      _reveal();
    }
  }

  void _reveal() {
    if (_revealed || _pendingReveal) return;
    _pendingReveal = true;
    final delay = widget.delay;
    if (delay == Duration.zero) {
      if (mounted) setState(() => _revealed = true);
      return;
    }
    Future.delayed(delay, () {
      if (mounted && !_revealed) setState(() => _revealed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: _revealed ? Offset.zero : widget.offset,
      duration: kMotionSlow,
      curve: kPremiumCurve,
      child: AnimatedOpacity(
        opacity: _revealed ? 1 : 0,
        duration: kMotionSlow,
        curve: kPremiumCurve,
        child: widget.child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Double-Bezel card — outer shell + inner core (Doppelrand)
// ---------------------------------------------------------------------------

class DoubleBezel extends StatelessWidget {
  const DoubleBezel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.outerPadding = const EdgeInsets.all(6),
    this.radius = 28,
    this.innerColor = AppColors.bgSoft,
    this.gradient,
    this.borderColor,
    this.glowColor,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry outerPadding;
  final double radius;
  final Color innerColor;

  /// Replaces [innerColor] with a gradient core when provided.
  final Gradient? gradient;

  /// Hairline border colour for the outer shell.
  final Color? borderColor;

  /// Optional soft ambient glow (never a harsh dark shadow).
  final Color? glowColor;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final innerRadius = radius - 6;

    Widget core = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? innerColor : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(innerRadius),
        // Inset top highlight — the core reads as a separate pane of glass.
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.10),
            offset: const Offset(0, 1),
            blurRadius: 2,
            blurStyle: BlurStyle.inner,
          ),
        ],
      ),
      child: child,
    );

    if (onTap != null) {
      core = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(innerRadius),
          child: core,
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: outerPadding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(
          color: borderColor ?? Colors.white.withValues(alpha: 0.10),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: glowColor == null
            ? null
            : [
                BoxShadow(
                  color: glowColor!.withValues(alpha: 0.20),
                  blurRadius: 48,
                  spreadRadius: -12,
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(innerRadius),
        child: core,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Eyebrow tag — microscopic pill above display headings
// ---------------------------------------------------------------------------

class Eyebrow extends StatelessWidget {
  const Eyebrow({super.key, required this.text, this.color = AppColors.cyan});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.28)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
          height: 1.2,
          color: color,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// IslandButton — pill CTA with trailing icon nested in a circular island
// ---------------------------------------------------------------------------

class IslandButton extends StatefulWidget {
  const IslandButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon = CupertinoIcons.arrow_up_right,
    this.gradient,
    this.expand = true,
    this.outline = false,
    this.dense = false,
    this.busy = false,
    this.glow = true,
    this.textColor,
  });

  final VoidCallback? onPressed;
  final String label;
  final IconData icon;

  /// Defaults to the signature neon gradient.
  final Gradient? gradient;
  final bool expand;
  final bool outline;
  final bool dense;
  final bool busy;
  final bool glow;
  final Color? textColor;

  @override
  State<IslandButton> createState() => _IslandButtonState();
}

class _IslandButtonState extends State<IslandButton> {
  bool _down = false;

  bool get _enabled => widget.onPressed != null && !widget.busy;

  @override
  Widget build(BuildContext context) {
    final pressed = _down && _enabled;
    final isOutline = widget.outline;
    final labelColor = widget.textColor ??
        (isOutline ? AppColors.text : const Color(0xFF04212A));

    final Widget button = Container(
      padding: EdgeInsets.symmetric(
        // Dense buttons often sit side-by-side in a Row — keep the pill
        // tight so the label keeps as much width as possible.
        horizontal: widget.dense ? 14 : 24,
        vertical: widget.dense ? 11 : 17,
      ),
      decoration: BoxDecoration(
        color: isOutline ? Colors.transparent : null,
        gradient: isOutline
            ? null
            : (widget.gradient ??
                const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF67E8F9), Color(0xFF22D3EE)],
                )),
        border: isOutline
            ? Border.all(
                color: Colors.white.withValues(alpha: _enabled ? 0.16 : 0.08),
              )
            : null,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          if (!isOutline && widget.glow && _enabled)
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.30),
              blurRadius: 28,
              spreadRadius: -8,
            ),
          // Top sheen — glass, not drop shadow.
          if (!isOutline)
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.22),
              offset: const Offset(0, 1),
              blurRadius: 1,
              blurStyle: BlurStyle.inner,
            ),
        ],
      ),
      child: Row(
        mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: widget.expand
            ? MainAxisAlignment.spaceBetween
            : MainAxisAlignment.center,
        children: [
          if (widget.busy)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: labelColor,
              ),
            )
          else if (widget.expand)
            // Expanded buttons can be squeezed (e.g. side-by-side in a Row);
            // shrink + ellipsize instead of overflowing.
            Flexible(
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: labelColor,
                  fontSize: widget.dense ? 13.5 : 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            )
          else
            Text(
              widget.label,
              style: TextStyle(
                color: labelColor,
                fontSize: widget.dense ? 13.5 : 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          SizedBox(width: widget.dense ? 10 : 14),
          AnimatedSlide(
            offset: pressed ? const Offset(0.05, -0.05) : Offset.zero,
            duration: kMotionFast,
            curve: kPremiumCurve,
            child: AnimatedScale(
              scale: pressed ? 1.08 : 1,
              duration: kMotionFast,
              curve: kPremiumCurve,
              child: Container(
                width: widget.dense ? 26 : 30,
                height: widget.dense ? 26 : 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isOutline
                      ? Colors.white.withValues(alpha: 0.10)
                      : Colors.black.withValues(alpha: 0.22),
                  border: isOutline
                      ? Border.all(color: Colors.white.withValues(alpha: 0.14))
                      : null,
                ),
                child: Icon(widget.icon, size: 15, color: labelColor),
              ),
            ),
          ),
        ],
      ),
    );

    final Widget wrapped = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _enabled ? (_) => setState(() => _down = true) : null,
      onTapUp: _enabled ? (_) => setState(() => _down = false) : null,
      onTapCancel: _enabled ? () => setState(() => _down = false) : null,
      onTap: _enabled
          ? () {
              HapticFeedback.selectionClick().ignore();
              widget.onPressed!();
            }
          : null,
      child: AnimatedScale(
        scale: pressed ? 0.97 : 1,
        duration: kMotionFast,
        curve: kPremiumCurve,
        child: Opacity(
          opacity: _enabled ? 1 : 0.45,
          child: button,
        ),
      ),
    );

    if (!widget.expand) return wrapped;
    return SizedBox(width: double.infinity, child: wrapped);
  }
}

// ---------------------------------------------------------------------------
// PressableScale — tap feedback for cards and rows
// ---------------------------------------------------------------------------

class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.98,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final pressed = _down && widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap != null ? (_) => setState(() => _down = true) : null,
      onTapUp: widget.onTap != null ? (_) => setState(() => _down = false) : null,
      onTapCancel: widget.onTap != null ? () => setState(() => _down = false) : null,
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: pressed ? widget.scale : 1,
        duration: kMotionFast,
        curve: kPremiumCurve,
        child: widget.child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// AnimatedCounter — count-up numerals
// ---------------------------------------------------------------------------

class AnimatedCounter extends StatelessWidget {
  const AnimatedCounter({
    super.key,
    required this.value,
    this.style,
    this.duration = const Duration(milliseconds: 900),
    this.prefix = '',
    this.suffix = '',
  });

  final int value;
  final TextStyle? style;
  final Duration duration;
  final String prefix;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: value),
      duration: duration,
      curve: kPremiumCurve,
      builder: (context, current, _) {
        return Text(
          '$prefix${groupDigits(current)}$suffix',
          style: style,
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// GrainOverlay — fixed, pointer-events-none film grain
// ---------------------------------------------------------------------------

class GrainOverlay extends StatelessWidget {
  const GrainOverlay({super.key, this.opacity = 0.035});

  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _GrainPainter(opacity),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _GrainPainter extends CustomPainter {
  _GrainPainter(this.opacity);

  final double opacity;

  // Deterministic normalised scatter, generated once for the whole app.
  static final List<Offset> _dots = () {
    final rng = math.Random(1337);
    return List<Offset>.generate(
      2600,
      (_) => Offset(rng.nextDouble(), rng.nextDouble()),
    );
  }();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final paint = Paint()..color = Colors.white.withValues(alpha: opacity);
    for (final dot in _dots) {
      canvas.drawCircle(
        Offset(dot.dx * size.width, dot.dy * size.height),
        0.7,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_GrainPainter oldDelegate) =>
      oldDelegate.opacity != opacity;
}

// ---------------------------------------------------------------------------
// MeshBackground — static radial gradient orbs (no blur filters)
// ---------------------------------------------------------------------------

class MeshBackground extends StatelessWidget {
  const MeshBackground({super.key});

  static Widget _orb({
    required double size,
    required Color color,
    required double alpha,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: alpha),
            color.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      // Own layer: these gradients are static, so the per-frame animations
      // painted around them must never re-rasterise them.
      child: RepaintBoundary(
        child: Container(
          color: AppColors.bg,
          child: Stack(
            children: [
              Positioned(
                top: -140,
                left: -110,
                child: _orb(
                  size: 420,
                  color: AppColors.primary,
                  alpha: 0.22,
                ),
              ),
              Positioned(
                top: 180,
                right: -160,
                child: _orb(size: 380, color: AppColors.cyan, alpha: 0.10),
              ),
              Positioned(
                bottom: -160,
                left: -60,
                child: _orb(
                  size: 460,
                  color: const Color(0xFF0E7490),
                  alpha: 0.20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
