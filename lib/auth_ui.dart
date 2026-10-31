import 'package:flutter/material.dart';

import 'premium.dart';
import 'theme.dart';

// Shared chrome for the signed-out screens, so sign in and sign up read as two
// states of one form instead of two hand-built pages.

/// Backdrop + fixed back affordance + a 420px column that centres when the
/// form is short and scrolls when the keyboard opens.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.onBack, required this.children});

  final VoidCallback onBack;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const MeshBackground(),
        SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.xl,
                  AppSpace.sm,
                  AppSpace.xl,
                  0,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _BackButton(onTap: onBack),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const padTop = AppSpace.lg;
                    const padBottom = AppSpace.xxl;
                    final minHeight = (constraints.maxHeight - padTop - padBottom)
                        .clamp(0.0, double.infinity);
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpace.xl,
                        padTop,
                        AppSpace.xl,
                        padBottom,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: 420,
                            minHeight: minHeight,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: children,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Brand lockup, page title and one line of context.
class AuthHeader extends StatelessWidget {
  const AuthHeader({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const LogoBadge(size: 44),
            const SizedBox(width: AppSpace.md),
            Text(
              'GHOSST',
              style: AppText.label.copyWith(
                color: AppColors.textDim,
                letterSpacing: 3.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.xl + 4),
        Text(title, style: AppText.display.copyWith(fontSize: 34)),
        const SizedBox(height: AppSpace.sm + 2),
        Text(
          subtitle,
          style: AppText.body.copyWith(color: AppColors.textDim, height: 1.45),
        ),
      ],
    );
  }
}

/// Uppercase micro-label above an input.
class AuthFieldLabel extends StatelessWidget {
  const AuthFieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Text(
        text.toUpperCase(),
        style: AppText.caption.copyWith(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.6,
          color: AppColors.textDim,
        ),
      ),
    );
  }
}

/// Icon, hint and inline error in one place — the border/error styling is
/// inherited from the theme, so screens never rebuild OutlineInputBorders.
InputDecoration authDecoration({
  required String hint,
  required IconData icon,
  String? errorText,
  String? helperText,
  Widget? suffixIcon,
}) {
  return InputDecoration(
    hintText: hint,
    prefixIcon: Icon(icon, size: 19),
    suffixIcon: suffixIcon,
    errorText: errorText,
    helperText: helperText,
    errorStyle: AppText.caption.copyWith(fontSize: 11.5, color: AppColors.red),
    helperStyle: AppText.caption.copyWith(
      fontSize: 11.5,
      color: AppColors.textDim.withValues(alpha: 0.75),
    ),
  );
}

/// Form-level failure (wrong password, email taken) above the submit button.
class AuthErrorBox extends StatelessWidget {
  const AuthErrorBox({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: kMotionBase,
      curve: kPremiumCurve,
      alignment: Alignment.topCenter,
      child: message.isEmpty
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: AppSpace.lg),
              padding: const EdgeInsets.all(AppSpace.md),
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppRadius.input),
                border: Border.all(
                  color: AppColors.red.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 18,
                    color: AppColors.red,
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Text(
                      message,
                      style: AppText.caption.copyWith(color: AppColors.red),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Primary form action — a solid block, not the landing page's pill CTA.
class AuthSubmit extends StatelessWidget {
  const AuthSubmit({
    super.key,
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return NeonButton(
      expand: true,
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.textDim,
              ),
            )
          : Text(label),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.92,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(AppRadius.input),
          border: Border.all(color: AppColors.border),
        ),
        child: const Icon(
          Icons.arrow_back_rounded,
          size: 19,
          color: AppColors.text,
        ),
      ),
    );
  }
}
