import 'package:flutter/material.dart';

import 'api/api_exception.dart';
import 'auth_ui.dart';
import 'services/worker_backend.dart';
import 'theme.dart';
import 'validation.dart';

class SignIn extends StatefulWidget {
  const SignIn({
    super.key,
    required this.onSignedIn,
    required this.onGoToSignUp,
    this.onBack,
  });

  final VoidCallback onSignedIn;
  final VoidCallback onGoToSignUp;

  /// Returns to the signed-out landing page. Null pops when this route was
  /// pushed; either way the screen is never a dead end.
  final VoidCallback? onBack;

  @override
  State<SignIn> createState() => _SignInState();
}

class _SignInState extends State<SignIn> {
  final email = TextEditingController();
  final password = TextEditingController();
  String error = '';
  String? emailErr;
  String? passErr;
  bool busy = false;
  bool obscure = true;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
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
              ? 'Maling email o password.'
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
      children: [
        const AuthHeader(
          title: 'Sign in',
          subtitle: 'Pick up where your coins left off.',
        ),
        const SizedBox(height: AppSpace.xl + 4),
        AuthPanel(
          children: [
            const AuthFieldLabel('Email'),
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              autofillHints: const [AutofillHints.email],
              onChanged: (_) => _clearErrors(),
              onSubmitted: (_) => FocusScope.of(context).nextFocus(),
              decoration: authDecoration(
                hint: 'you@example.com',
                icon: Icons.alternate_email_rounded,
                errorText: emailErr,
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            const AuthFieldLabel('Password'),
            TextField(
              controller: password,
              obscureText: obscure,
              textInputAction: TextInputAction.done,
              keyboardType: TextInputType.visiblePassword,
              autofillHints: const [AutofillHints.password],
              onChanged: (_) => _clearErrors(),
              onSubmitted: (_) => _submit(),
              decoration: authDecoration(
                hint: 'Your password',
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
          ],
        ),
        AuthErrorBox(message: error),
        const SizedBox(height: AppSpace.xl),
        AuthSubmit(label: 'Sign in', busy: busy, onPressed: _submit),
        const SizedBox(height: AppSpace.md),
        Center(
          child: TextButton(
            onPressed: widget.onGoToSignUp,
            child: const Text('Create an account'),
          ),
        ),
      ],
    );
  }
}
