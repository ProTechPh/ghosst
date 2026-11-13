import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api/api_exception.dart';
import 'auth_ui.dart';
import 'services/worker_backend.dart';
import 'theme.dart';
import 'validation.dart';

class SignIn extends StatefulWidget {
  const SignIn({
    super.key,
    required this.onSignedIn,
    this.onBack,
  });

  final VoidCallback onSignedIn;

  /// Returns to the signed-out landing page. Null pops when this route was
  /// pushed; either way the screen is never a dead end.
  final VoidCallback? onBack;

  @override
  State<SignIn> createState() => _SignInState();
}

class _SignInState extends State<SignIn> {
  final email = TextEditingController();
  final password = TextEditingController();
  final emailFocus = FocusNode();
  final passFocus = FocusNode();
  String error = '';
  String? emailErr;
  String? passErr;
  bool busy = false;
  bool obscure = true;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    emailFocus.dispose();
    passFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (busy) return;
    final emailMsg = validateEmail(email.text);
    final passwordMsg = validatePassword(password.text, enforceLength: true);
    if (emailMsg != null || passwordMsg != null) {
      setState(() {
        emailErr = emailMsg;
        passErr = passwordMsg;
      });
      if (emailMsg != null) {
        emailFocus.requestFocus();
      } else {
        passFocus.requestFocus();
      }
      return;
    }
    setState(() {
      error = '';
      busy = true;
    });
    try {
      await Backend.signIn(email.text.trim(), password.text);
      widget.onSignedIn();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          error = e.code == 'invalid_credentials'
              ? 'Wrong email or password.'
              : e.userMessage;
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = 'Sign in failed');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _back() {
    final back = widget.onBack;
    if (back != null) {
      back();
    } else {
      Navigator.maybePop(context);
    }
  }

  void _clearErrors() {
    if (emailErr != null || passErr != null || error.isNotEmpty) {
      setState(() {
        emailErr = null;
        passErr = null;
        error = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      onBack: _back,
      footer: const _LegalLine(),
      children: [
        Row(
          children: [
            const LogoBadge(size: 30),
            const SizedBox(width: AppSpace.sm + 2),
            Text(
              'GHOSST',
              style: AppText.label.copyWith(
                color: AppColors.textDim,
                letterSpacing: 3.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.xl + 8),
        Text(
          'Sign in',
          style: AppText.headline.copyWith(fontSize: 30, letterSpacing: -0.8),
        ),
        const SizedBox(height: AppSpace.sm),
        Text(
          'Sign in with your email, or continue with Google.',
          style: AppText.body.copyWith(color: AppColors.textDim, height: 1.45),
        ),
        const SizedBox(height: AppSpace.xl + 4),
        TextField(
          controller: email,
          focusNode: emailFocus,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          autofillHints: const [AutofillHints.email],
          onChanged: (_) => _clearErrors(),
          onSubmitted: (_) => FocusScope.of(context).nextFocus(),
          decoration: authDecoration(
            hint: 'Email address',
            label: 'Email',
            icon: Icons.alternate_email_rounded,
            errorText: emailErr,
          ),
        ),
        const SizedBox(height: AppSpace.md),
        TextField(
          controller: password,
          focusNode: passFocus,
          obscureText: obscure,
          textInputAction: TextInputAction.done,
          keyboardType: TextInputType.visiblePassword,
          autofillHints: const [AutofillHints.password],
          onChanged: (_) => _clearErrors(),
          onSubmitted: (_) => _submit(),
          decoration: authDecoration(
            hint: 'Password',
            label: 'Password',
            icon: Icons.lock_outline_rounded,
            errorText: passErr,
            suffixIcon: IconButton(
              tooltip: obscure ? 'Show password' : 'Hide password',
              icon: Icon(
                obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              onPressed: () => setState(() => obscure = !obscure),
            ),
          ),
        ),
        AuthErrorBox(message: error),
        const SizedBox(height: AppSpace.lg),
        AuthSubmit(label: 'Sign in', busy: busy, onPressed: _submit),
        const SizedBox(height: AppSpace.xl),
        const _OrDivider(),
        const SizedBox(height: AppSpace.xl),
        AuthGoogleButton(onSignedIn: widget.onSignedIn, primary: false),
      ],
    );
  }
}

/// "or" with hairlines either side — the seam between the email form and the
/// Google button.
class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(height: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
          child: Text('or', style: AppText.caption),
        ),
        const Expanded(child: Divider(height: 1)),
      ],
    );
  }
}

/// Legal line under the buttons. Both pages are the Play-required ones.
class _LegalLine extends StatelessWidget {
  const _LegalLine();

  static const _terms = 'https://ghossthub.com/terms.php';
  static const _privacy = 'https://ghossthub.com/privacy.php';

  @override
  Widget build(BuildContext context) {
    final link = AppText.caption.copyWith(
      color: AppColors.textDim,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.textDim.withValues(alpha: 0.5),
    );
    return Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: 'By signing in you agree to our '),
          TextSpan(
            text: 'Terms of Service',
            style: link,
            recognizer: TapGestureRecognizer()..onTap = () => _open(_terms),
          ),
          const TextSpan(text: ' and '),
          TextSpan(
            text: 'Privacy Policy',
            style: link,
            recognizer: TapGestureRecognizer()..onTap = () => _open(_privacy),
          ),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
      style: AppText.caption.copyWith(height: 1.5),
    );
  }

  void _open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}
