import 'package:flutter/material.dart';

import 'api/api_exception.dart';
import 'auth_ui.dart';
import 'services/worker_backend.dart';
import 'theme.dart';
import 'validation.dart';

class SignUp extends StatefulWidget {
  const SignUp({
    super.key,
    required this.onSignedUp,
    required this.onGoToSignIn,
    this.onBack,
  });

  final VoidCallback onSignedUp;
  final VoidCallback onGoToSignIn;

  /// Returns to the signed-out landing page. Null pops when this route was
  /// pushed; either way the screen is never a dead end.
  final VoidCallback? onBack;

  @override
  State<SignUp> createState() => _SignUpState();
}

class _SignUpState extends State<SignUp> {
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  String error = '';
  String? emailErr;
  String? passErr;
  bool busy = false;
  bool obscure = true;

  @override
  void dispose() {
    name.dispose();
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
      final cleanEmail = email.text.trim();
      await Backend.signUp(cleanEmail, password.text, name: name.text.trim());
      widget.onSignedUp();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          error = switch (e.code) {
            'email_taken' => 'May account na ang email na ito.',
            'invalid_email' => 'Hindi valid ang email.',
            'weak_password' => 'Masyadong maikli ang password.',
            _ => e.userMessage,
          };
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = 'Sign up failed');
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
          title: 'Create account',
          subtitle: 'Watch an ad, get coins. Spend them on keys.',
        ),
        const SizedBox(height: AppSpace.xxl),
        const AuthFieldLabel('Name (optional)'),
        TextField(
          controller: name,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.name],
          onSubmitted: (_) => FocusScope.of(context).nextFocus(),
          decoration: authDecoration(
            hint: 'Your display name',
            icon: Icons.person_outline_rounded,
          ),
        ),
        const SizedBox(height: AppSpace.lg),
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
            helperText: 'Minimum 8 characters',
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
        const SizedBox(height: AppSpace.xl),
        AuthSubmit(label: 'Create account', busy: busy, onPressed: _submit),
        const SizedBox(height: AppSpace.md),
        Center(
          child: TextButton(
            onPressed: widget.onGoToSignIn,
            child: const Text('I already have an account'),
          ),
        ),
      ],
    );
  }
}
