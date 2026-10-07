import 'package:appwrite/appwrite.dart';
import 'package:flutter/material.dart';

import 'appwrite_client.dart';
import 'premium.dart';
import 'theme.dart';
import 'validation.dart';

class SignUp extends StatefulWidget {
  const SignUp({
    super.key,
    required this.onSignedUp,
    required this.onGoToSignIn,
  });

  final VoidCallback onSignedUp;
  final VoidCallback onGoToSignIn;

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
      final account = Account(client);
      final cleanEmail = email.text.trim();
      await account.create(
        userId: ID.unique(),
        email: cleanEmail,
        password: password.text,
        name: name.text.trim().isEmpty ? null : name.text.trim(),
      );
      await account.createEmailPasswordSession(
        email: cleanEmail,
        password: password.text,
      );
      widget.onSignedUp();
    } on AppwriteException catch (e) {
      if (mounted) {
        setState(() {
          error =
              friendlyAuthError(e.message ?? '', fallback: 'Sign up failed');
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = 'Sign up failed');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _errorBox() {
    return AnimatedSize(
      duration: kMotionBase,
      curve: kPremiumCurve,
      alignment: Alignment.topCenter,
      child: error.isEmpty
          ? const SizedBox(width: double.infinity)
          : AnimatedOpacity(
              duration: kMotionFast,
              curve: kPremiumCurve,
              opacity: 1,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 16),
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: AppColors.red.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: AppColors.red.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        size: 18, color: AppColors.red),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        error,
                        style: const TextStyle(
                            color: AppColors.red, fontSize: 13.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  /// Inline validation message under a field (animated reveal).
  Widget _fieldError(String? message) {
    return AnimatedSize(
      duration: kMotionBase,
      curve: kPremiumCurve,
      alignment: Alignment.topCenter,
      child: message == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 8, left: 4),
              child: Row(
                children: [
                  const Icon(Icons.error_outline,
                      size: 14, color: AppColors.red),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      message,
                      style:
                          const TextStyle(color: AppColors.red, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  /// Under-password assist: rule hint normally, error while invalid.
  Widget _passAssist() {
    return AnimatedSize(
      duration: kMotionBase,
      curve: kPremiumCurve,
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 8, left: 4),
        child: passErr == null
            ? Text(
                'Minimum 8 characters',
                style: TextStyle(
                  color: AppColors.textDim.withValues(alpha: 0.75),
                  fontSize: 11.5,
                ),
              )
            : Row(
                children: [
                  const Icon(Icons.error_outline,
                      size: 14, color: AppColors.red),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      passErr!,
                      style: const TextStyle(
                          color: AppColors.red, fontSize: 12),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const MeshBackground(),
        Positioned.fill(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 56, 24, 40),
            children: [
              const Center(child: LogoBadge(size: 76, fontSize: 38)),
              const SizedBox(height: 30),
              const Center(
                child: ScrollReveal(
                  child: Eyebrow(text: 'New member'),
                ),
              ),
              const SizedBox(height: 18),
              const ScrollReveal(
                delay: Duration(milliseconds: 120),
                child: Center(
                  child: GradientText(
                    'Create account',
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const ScrollReveal(
                delay: Duration(milliseconds: 200),
                child: Center(
                  child: Text(
                    'Join and start claiming license keys',
                    style: TextStyle(color: AppColors.textDim, fontSize: 14.5),
                  ),
                ),
              ),
              const SizedBox(height: 44),
              ScrollReveal(
                delay: const Duration(milliseconds: 260),
                child: DoubleBezel(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: name,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.name],
                        onSubmitted: (_) =>
                            FocusScope.of(context).nextFocus(),
                        decoration: const InputDecoration(
                          hintText: 'Name (optional)',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.email],
                        onChanged: (_) {
                          if (emailErr != null || error.isNotEmpty) {
                            setState(() {
                              emailErr = null;
                              error = '';
                            });
                          }
                        },
                        onSubmitted: (_) =>
                            FocusScope.of(context).nextFocus(),
                        decoration: InputDecoration(
                          hintText: 'Email',
                          prefixIcon: Icon(
                            Icons.mail_outline,
                            color: emailErr == null
                                ? AppColors.textDim
                                : AppColors.red,
                          ),
                          enabledBorder: emailErr == null
                              ? null
                              : OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(
                                    color:
                                        AppColors.red.withValues(alpha: 0.55),
                                  ),
                                ),
                          focusedBorder: emailErr == null
                              ? null
                              : OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: const BorderSide(
                                      color: AppColors.red, width: 1.6),
                                ),
                        ),
                      ),
                      _fieldError(emailErr),
                      const SizedBox(height: 14),
                      TextField(
                        controller: password,
                        obscureText: obscure,
                        textInputAction: TextInputAction.done,
                        keyboardType: TextInputType.visiblePassword,
                        autofillHints: const [AutofillHints.password],
                        onChanged: (_) {
                          if (passErr != null || error.isNotEmpty) {
                            setState(() {
                              passErr = null;
                              error = '';
                            });
                          }
                        },
                        onSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          hintText: 'Password',
                          prefixIcon: Icon(
                            Icons.lock_outline,
                            color: passErr == null
                                ? AppColors.textDim
                                : AppColors.red,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(obscure
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined),
                            onPressed: () =>
                                setState(() => obscure = !obscure),
                          ),
                          enabledBorder: passErr == null
                              ? null
                              : OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(
                                    color:
                                        AppColors.red.withValues(alpha: 0.55),
                                  ),
                                ),
                          focusedBorder: passErr == null
                              ? null
                              : OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: const BorderSide(
                                      color: AppColors.red, width: 1.6),
                                ),
                        ),
                      ),
                      _passAssist(),
                      _errorBox(),
                      const SizedBox(height: 24),
                      IslandButton(
                        label: 'Create account',
                        busy: busy,
                        onPressed: _submit,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              const ScrollReveal(
                delay: Duration(milliseconds: 340),
                child: Center(
                  child: Text(
                    'KEYS DELIVERED INSTANTLY',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.4,
                      color: AppColors.textDim,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 30),
              ScrollReveal(
                delay: const Duration(milliseconds: 400),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Already have an account? ',
                        style:
                            TextStyle(color: AppColors.textDim, fontSize: 14),
                      ),
                      TextButton(
                        onPressed: widget.onGoToSignIn,
                        child: const Text('Sign in'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
