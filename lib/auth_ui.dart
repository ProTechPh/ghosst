import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'api/api_exception.dart';
import 'arcade.dart';
import 'premium.dart';
import 'services/google_auth.dart';
import 'services/worker_backend.dart';
import 'theme.dart';

// Shared chrome for the signed-out screens, so sign in and sign up read as two
// states of one form instead of two hand-built pages.

/// Backdrop + fixed back affordance + a 420px column that centres when the
/// form is short and scrolls when the keyboard opens.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.onBack,
    required this.children,
    this.footer,
  });

  final VoidCallback onBack;
  final List<Widget> children;

  /// Pinned under the scroll area — the legal line, so it never floats in the
  /// middle of a tall screen.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    // Material ancestor: without it every Text merges into the engine's debug
    // fallback style (yellow underline) and inherits no sensible defaults.
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          const ArcadeBackdrop(),
          const Positioned(
            top: 40,
            right: -120,
            child: KeyMark(size: 300, angle: -0.72, opacity: 0.05),
          ),
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
                    final minHeight =
                        (constraints.maxHeight - padTop - padBottom).clamp(
                          0.0,
                          double.infinity,
                        );
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
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: children,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (footer != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.xl,
                    AppSpace.sm,
                    AppSpace.xl,
                    AppSpace.xl,
                  ),
                  child: footer!,
                ),
            ],
          ),
        ),
      ],
      ),
    );
  }
}

/// Icon, hint and inline error in one place.
///
/// Borderless on purpose: the field is a soft filled chip, so the form reads as
/// one calm column instead of a grid of boxes. Focus and errors still light up.
/// [label] is the screen-reader name (the placeholder is the visual hint).
InputDecoration authDecoration({
  required String hint,
  required IconData icon,
  String? errorText,
  String? helperText,
  Widget? suffixIcon,
  String? label,
}) {
  final radius = BorderRadius.circular(AppRadius.hero - 8);
  return InputDecoration(
    hintText: hint,
    labelText: label,
    filled: true,
    fillColor: AppColors.surfaceHigh.withValues(alpha: 0.55),
    // Walang floating label: ang hint/placeholder ang visual label.
    floatingLabelBehavior: FloatingLabelBehavior.never,
    prefixIcon: ExcludeSemantics(child: Icon(icon, size: AppIcon.md)),
    suffixIcon: suffixIcon,
    errorText: errorText,
    helperText: helperText,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppSpace.lg,
      vertical: AppSpace.lg,
    ),
    border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
    enabledBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: const BorderSide(color: AppColors.red, width: 1.2),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: const BorderSide(color: AppColors.red, width: 1.4),
    ),
    errorStyle: AppText.caption.copyWith(fontSize: 11.5, color: AppColors.red),
    helperStyle: AppText.caption.copyWith(
      fontSize: 11.5,
      color: AppColors.textDim.withValues(alpha: 0.75),
    ),
  );
}

/// Form-level failure (wrong password, email taken) above the submit button.
/// Takes focus on failure so the error summary is the next thing announced.
class AuthErrorBox extends StatefulWidget {
  const AuthErrorBox({super.key, required this.message});

  final String message;

  @override
  State<AuthErrorBox> createState() => _AuthErrorBoxState();
}

class _AuthErrorBoxState extends State<AuthErrorBox> {
  late final FocusNode _focusNode = FocusNode();

  @override
  void didUpdateWidget(covariant AuthErrorBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.message.isNotEmpty && widget.message != oldWidget.message) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: kMotionBase,
      curve: kPremiumCurve,
      alignment: Alignment.topCenter,
      child: widget.message.isEmpty
          ? const SizedBox(width: double.infinity)
          : Focus(
              focusNode: _focusNode,
              canRequestFocus: true,
              child: Semantics(
                liveRegion: true,
                label: widget.message,
                child: Container(
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
                      const ExcludeSemantics(
                        child: Icon(
                          Icons.error_outline,
                          size: AppIcon.sm,
                          color: AppColors.red,
                        ),
                      ),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(
                        child: Text(
                          widget.message,
                          style: AppText.caption.copyWith(color: AppColors.red),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

/// Primary form action â€” a solid block, not the landing page's pill CTA.
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
          : FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label),
            ),
    );
  }
}

/// "Continue with Google" â€” ang Google ang gumagawa ng bagong account, kaya
/// wala nang sign-up form.
///
/// [primary] = filled hero CTA (landing). `false` = ghost, para manatiling
/// malinaw na ang email form ang bida sa sign-in screen. May sariling error
/// line para magamit sa dalawang screen nang walang extra callback.
class AuthGoogleButton extends StatefulWidget {
  const AuthGoogleButton({
    super.key,
    required this.onSignedIn,
    this.primary = true,
  });

  final VoidCallback onSignedIn;
  final bool primary;

  @override
  State<AuthGoogleButton> createState() => _AuthGoogleButtonState();
}

class _AuthGoogleButtonState extends State<AuthGoogleButton> {
  bool busy = false;
  String error = '';

  Future<void> _tap() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final token = await GoogleAuth.idToken();
      if (token == null || token.isEmpty) throw StateError('no idToken');
      await Backend.signInWithGoogle(token);
      // Success: papalitan na ng bagong screen â€” walang setState pagkatapos.
      widget.onSignedIn();
    } on GoogleSignInException catch (e) {
      debugPrint('Google sign-in: ${e.code} ${e.description}');
      if (!mounted) return;
      setState(() {
        busy = false;
        if (e.code != GoogleSignInExceptionCode.canceled) {
          error = 'Google sign-in is not available right now.';
        }
      });
    } on ApiException catch (e) {
      debugPrint('Google sign-in API: ${e.code} ${e.message}');
      if (!mounted) return;
      setState(() {
        busy = false;
        error = e.userMessage;
      });
    } catch (e) {
      debugPrint('Google sign-in: $e');
      if (!mounted) return;
      setState(() {
        busy = false;
        error = 'Google sign-in failed. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final filled = widget.primary && !busy;
    // Filled: dark ink on the neon gradient. Ghost: white on the plate.
    final ink = filled ? const Color(0xFF04212A) : AppColors.text;
    final markBg = filled ? Colors.white.withValues(alpha: 0.92) : AppColors.surfaceHigh;
    final markBorder = filled ? Colors.transparent : AppColors.border;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NeonButton(
          expand: true,
          glow: widget.primary,
          outline: !widget.primary,
          onPressed: busy ? null : _tap,
          child: busy
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: filled ? const Color(0xFF04212A) : AppColors.textDim,
                  ),
                )
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Monochrome "G" â€” walang brand asset, tugma sa palette.
                      Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: markBg,
                          border: Border.all(color: markBorder),
                        ),
                        child: Text(
                          'G',
                          style: TextStyle(
                            fontFamily: 'SpaceGrotesk',
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            height: 1,
                            color: filled ? const Color(0xFF04212A) : AppColors.text,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpace.sm + 2),
                      Text('Continue with Google', style: TextStyle(color: ink)),
                    ],
                  ),
                ),
        ),
        if (error.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          Text(
            error,
            textAlign: TextAlign.center,
            style: AppText.caption.copyWith(color: AppColors.red),
          ),
        ],
      ],
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
      semanticLabel: 'Back',
      child: SizedBox(
        // 48dp hit area, 40dp visual.
        width: kTouchMin,
        height: kTouchMin,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(AppRadius.input),
            border: Border.all(color: AppColors.border),
          ),
          child: const ExcludeSemantics(
            child: Icon(
              Icons.arrow_back_rounded,
              size: AppIcon.md,
              color: AppColors.text,
            ),
          ),
        ),
      ),
    );
  }
}
