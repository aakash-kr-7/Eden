// FILE: screens/auth_screen.dart
// PURPOSE: Present a refined authentication entry without changing the underlying auth behavior.
// RESPONSIBILITIES: Render auth UI and forward all sign-in and sign-up actions into existing services.
// NEVER: Modify authentication contracts, backend calls, or app bootstrap flow.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../main.dart';
import '../services/auth_service.dart';
import '../theme/nocturne.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entryController;
  late final Animation<double> _fade;
  late final Animation<double> _lift;

  bool _showEmailForm = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _errorIsWrongPassword = false;
  String? _errorMessage;
  Timer? _errorTimer;

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: Nocturne.durationSlow,
    );
    _fade = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutCubic,
    );
    _lift = Tween<double>(begin: 24, end: 0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: Curves.easeOut,
      ),
    );
    _entryController.forward();
  }

  @override
  void dispose() {
    _entryController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _errorTimer?.cancel();
    super.dispose();
  }

  void _startErrorTimer() {
    _errorTimer?.cancel();
    _errorTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() {
        _errorMessage = null;
      });
    });
  }

  Future<void> _handleGoogleSignIn() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _errorIsWrongPassword = false;
    });

    try {
      await ref.read(authServiceProvider).signInWithGoogle();
      if (mounted) {
        context.go(AppRoute.boot);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Try again.';
        _errorIsWrongPassword = false;
      });
      _startErrorTimer();
    }
  }

  Future<void> _handleEmailAuth() async {
    if (_isLoading) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _errorIsWrongPassword = false;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    try {
      await ref
          .read(authServiceProvider)
          .signInWithEmailPassword(email, password);
      if (mounted) {
        context.go(AppRoute.boot);
      }
    } on AuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        try {
          await ref
              .read(authServiceProvider)
              .signUpWithEmailPassword(email, password);
          if (mounted) {
            context.go(AppRoute.boot);
          }
        } on AuthException catch (signUpError) {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            if (signUpError.code == 'email-already-in-use') {
              _errorIsWrongPassword = true;
              _errorMessage = 'Incorrect password.';
            } else {
              _errorMessage = 'Try again.';
              _errorIsWrongPassword = false;
              _startErrorTimer();
            }
          });
        } catch (_) {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _errorMessage = 'Try again.';
            _errorIsWrongPassword = false;
            _startErrorTimer();
          });
        }
      } else {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _errorMessage = 'Try again.';
          _errorIsWrongPassword = false;
          _startErrorTimer();
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Try again.';
        _errorIsWrongPassword = false;
        _startErrorTimer();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _entryController,
          builder: (context, child) {
            return Opacity(
              opacity: _fade.value,
              child: Transform.translate(
                offset: Offset(0, _lift.value),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Nocturne.space8,
                    Nocturne.space8,
                    Nocturne.space8,
                    Nocturne.space8,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Spacer(),
                          _buildHero(),
                          const SizedBox(height: Nocturne.space9),
                          AnimatedSwitcher(
                            duration: Nocturne.durationStandard,
                            switchInCurve: Curves.easeOut,
                            switchOutCurve: Curves.easeIn,
                            transitionBuilder: (child, animation) {
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, 0.03),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              );
                            },
                            child: _showEmailForm
                                ? _buildEmailForm()
                                : _buildAuthChoices(),
                          ),
                          if (_errorMessage != null &&
                              !_errorIsWrongPassword) ...[
                            const SizedBox(height: Nocturne.space5),
                            Text(
                              _errorMessage!,
                              style: Nocturne.bodySm.copyWith(
                                color: Nocturne.textSecondary,
                              ),
                            ),
                          ],
                          const Spacer(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHero() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Nocturne.borderSubtle),
            gradient: RadialGradient(
              colors: [
                Nocturne.accentWarm.withValues(alpha: 0.18),
                Colors.transparent,
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(Nocturne.space5),
            child: Image.asset(
              'assets/images/eden_logo.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(height: Nocturne.space8),
        Text(
          'Eden',
          style: Nocturne.displayXl.copyWith(fontSize: 56),
        ),
        const SizedBox(height: Nocturne.space3),
        Text(
          'Begin quietly.',
          style: Nocturne.bodyLg.copyWith(color: Nocturne.textSecondary),
        ),
      ],
    );
  }

  Widget _buildAuthChoices() {
    return Column(
      key: const ValueKey('auth_choices'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PrimaryAuthButton(
          label: 'Continue with Google',
          isLoading: _isLoading,
          onTap: _handleGoogleSignIn,
          leading: Image.asset(
            'assets/images/google_logo.png',
            width: 18,
            height: 18,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.g_mobiledata_rounded,
              size: 22,
              color: Nocturne.black,
            ),
          ),
        ),
        const SizedBox(height: Nocturne.space4),
        _SecondaryAuthButton(
          label: 'Use email',
          onTap: () {
            setState(() {
              _showEmailForm = true;
              _errorMessage = null;
              _errorIsWrongPassword = false;
            });
          },
        ),
      ],
    );
  }

  Widget _buildEmailForm() {
    return Form(
      key: _formKey,
      child: Column(
        key: const ValueKey('email_form'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Use email',
            style: Nocturne.displayMd,
          ),
          const SizedBox(height: Nocturne.space2),
          Text(
            'Sign in or create your place.',
            style: Nocturne.bodySm.copyWith(color: Nocturne.textSecondary),
          ),
          const SizedBox(height: Nocturne.space7),
          _AuthField(
            child: TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              style: Nocturne.bodyLg,
              cursorColor: Nocturne.accentCool,
              decoration: _inputDecoration('Email'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Enter your email';
                }
                return null;
              },
            ),
          ),
          const SizedBox(height: Nocturne.space4),
          _AuthField(
            child: TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              autofillHints: const [AutofillHints.password],
              style: Nocturne.bodyLg,
              cursorColor: Nocturne.accentCool,
              decoration: _inputDecoration(
                'Password',
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: Nocturne.textTertiary,
                    size: Nocturne.iconLg,
                  ),
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Enter your password';
                }
                if (value.length < 6) {
                  return 'Use at least 6 characters';
                }
                return null;
              },
            ),
          ),
          if (_errorIsWrongPassword) ...[
            const SizedBox(height: Nocturne.space3),
            Text(
              'Incorrect password.',
              style: Nocturne.bodySm.copyWith(color: Nocturne.textSecondary),
            ),
          ],
          const SizedBox(height: Nocturne.space7),
          _PrimaryAuthButton(
            label: 'Continue',
            isLoading: _isLoading,
            onTap: _handleEmailAuth,
          ),
          const SizedBox(height: Nocturne.space4),
          _SecondaryAuthButton(
            label: 'Back',
            onTap: _isLoading
                ? null
                : () {
                    setState(() {
                      _showEmailForm = false;
                      _errorMessage = null;
                      _errorIsWrongPassword = false;
                    });
                  },
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hintText, {Widget? suffixIcon}) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: Nocturne.bodyLg.copyWith(color: Nocturne.textTertiary),
      suffixIcon: suffixIcon,
      filled: false,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Nocturne.space6,
        vertical: Nocturne.space5,
      ),
      errorStyle: Nocturne.bodySm.copyWith(color: Nocturne.textSecondary),
    );
  }
}

class _PrimaryAuthButton extends StatelessWidget {
  const _PrimaryAuthButton({
    required this.label,
    required this.onTap,
    this.isLoading = false,
    this.leading,
  });

  final String label;
  final VoidCallback? onTap;
  final bool isLoading;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(Nocturne.radiusLg),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: Nocturne.space6,
          vertical: Nocturne.space5,
        ),
        decoration: BoxDecoration(
          color: Nocturne.textPrimary,
          borderRadius: BorderRadius.circular(Nocturne.radiusLg),
          boxShadow: Nocturne.elevationLow,
        ),
        child: Center(
          child: isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Nocturne.black),
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (leading != null) ...[
                      leading!,
                      const SizedBox(width: Nocturne.space3),
                    ],
                    Text(
                      label,
                      style: Nocturne.button.copyWith(color: Nocturne.black),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _SecondaryAuthButton extends StatelessWidget {
  const _SecondaryAuthButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Nocturne.radiusLg),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: Nocturne.space6,
          vertical: Nocturne.space5,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF0C0D10),
          borderRadius: BorderRadius.circular(Nocturne.radiusLg),
          border: Border.all(color: Nocturne.borderSubtle),
        ),
        child: Center(
          child: Text(
            label,
            style: Nocturne.button.copyWith(color: Nocturne.textSecondary),
          ),
        ),
      ),
    );
  }
}

class _AuthField extends StatelessWidget {
  const _AuthField({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0C0D10),
        borderRadius: BorderRadius.circular(Nocturne.radiusLg),
        border: Border.all(color: Nocturne.borderSubtle),
      ),
      child: child,
    );
  }
}
