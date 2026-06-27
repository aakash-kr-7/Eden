// FILE: screens/auth_screen.dart
// PURPOSE: Handles sign-in and sign-up without changing backend auth behavior.
// RESPONSIBILITIES: Present auth UI and forward user actions into existing auth services.
// NEVER: Contain backend contract changes or app bootstrap responsibilities.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../main.dart';
import '../services/auth_service.dart';
import '../theme/eden_colors.dart';
import '../theme/eden_typography.dart';
import '../theme/glass_theme.dart';
import '../components/glass.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entryCtrl;
  late final Animation<double> _entryFade;

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

    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _entryFade = CurvedAnimation(
      parent: _entryCtrl,
      curve: Curves.easeOut,
    );
    _entryCtrl.forward();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _errorTimer?.cancel();
    super.dispose();
  }

  void _startErrorTimer() {
    _errorTimer?.cancel();
    _errorTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _errorMessage = null;
        });
      }
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
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Something went wrong — try again';
          _errorIsWrongPassword = false;
        });
        _startErrorTimer();
      }
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
          if (mounted) {
            setState(() {
              _isLoading = false;
              if (signUpError.code == 'email-already-in-use') {
                _errorIsWrongPassword = true;
                _errorMessage = 'Incorrect password.';
              } else {
                _errorMessage = 'Something went wrong — try again';
                _errorIsWrongPassword = false;
                _startErrorTimer();
              }
            });
          }
        } catch (err) {
          if (mounted) {
            setState(() {
              _isLoading = false;
              _errorMessage = 'Something went wrong — try again';
              _errorIsWrongPassword = false;
              _startErrorTimer();
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Something went wrong — try again';
            _errorIsWrongPassword = false;
            _startErrorTimer();
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Something went wrong — try again';
          _errorIsWrongPassword = false;
          _startErrorTimer();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _entryFade,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: CustomScrollView(
            physics: const ClampingScrollPhysics(),
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28.0,
                    vertical: 32.0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Spacer(flex: 3),
                      FakeGlass(
                        shape: const LiquidOval(),
                        settings: GlassTheme.button,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Image.asset(
                            'assets/images/eden_logo.png',
                            width: 80,
                            height: 80,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24.0),
                      Text(
                        'Eden',
                        style: EdenTypography.displayXl.copyWith(
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              color: EdenColors.electricBlue
                                  .withValues(alpha: 0.6),
                              blurRadius: 20,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      Text(
                        'Begin.',
                        style: EdenTypography.bodyMd.copyWith(
                          color: Colors.white70,
                          letterSpacing: 0.5,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                      const SizedBox(height: 48.0),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        child: LiquidGlass.withOwnLayer(
                          shape: GlassTheme.shape,
                          settings: GlassTheme.prominent,
                          child: Padding(
                            padding: const EdgeInsets.all(28.0),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 250),
                              transitionBuilder:
                                  (Widget child, Animation<double> animation) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0.0, 0.03),
                                      end: Offset.zero,
                                    ).animate(
                                      CurvedAnimation(
                                        parent: animation,
                                        curve: Curves.easeOutCubic,
                                      ),
                                    ),
                                    child: child,
                                  ),
                                );
                              },
                              child: _showEmailForm
                                  ? _buildEmailForm()
                                  : _buildOAuthMenu(),
                            ),
                          ),
                        ),
                      ),
                      if (_errorMessage != null && !_errorIsWrongPassword) ...[
                        const SizedBox(height: 24.0),
                        Text(
                          _errorMessage!.toLowerCase(),
                          style: EdenTypography.bodySm.copyWith(
                            color: Colors.white60,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const Spacer(flex: 5),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOAuthMenu() {
    return Column(
      key: const ValueKey('oauth_menu'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _GlassAuthButton(
          glowColor: EdenColors.amberGlow,
          onTap: _handleGoogleSignIn,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/google_logo.png',
                width: 20.0,
                height: 20.0,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.g_mobiledata,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12.0),
              Text(
                'Continue with Google',
                style: EdenTypography.bodyLg.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12.0),
        _GlassAuthButton(
          glowColor: EdenColors.electricBlue,
          onTap: () {
            setState(() {
              _showEmailForm = true;
              _errorMessage = null;
              _errorIsWrongPassword = false;
            });
          },
          child: Text(
            'Use email instead',
            style: EdenTypography.bodyLg.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmailForm() {
    return Form(
      key: _formKey,
      child: Column(
        key: const ValueKey('email_form'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _GlassInput(
            child: TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              style: EdenTypography.bodyXl.copyWith(color: Colors.white),
              cursorColor: EdenColors.electricBlue,
              decoration: _buildInputDecoration(hintText: 'email'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'please enter your email';
                }
                return null;
              },
            ),
          ),
          const SizedBox(height: 16.0),
          _GlassInput(
            child: TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              autofillHints: const [AutofillHints.password],
              style: EdenTypography.bodyXl.copyWith(color: Colors.white),
              cursorColor: EdenColors.electricBlue,
              decoration: _buildInputDecoration(
                hintText: 'password',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: Colors.white60,
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'please enter your password';
                }
                if (value.length < 6) {
                  return 'password must be at least 6 characters';
                }
                return null;
              },
            ),
          ),
          if (_errorIsWrongPassword) ...[
            const SizedBox(height: 12.0),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  'incorrect password.',
                  style: EdenTypography.bodySm.copyWith(
                    color: Colors.white60,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 28.0),
          _GlassAuthButton(
            glowColor: EdenColors.orangeGlow,
            onTap: _handleEmailAuth,
            child: _isLoading
                ? const SizedBox(
                    width: 20.0,
                    height: 20.0,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.0,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    'Continue',
                    style: EdenTypography.bodyLg.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
          const SizedBox(height: 16.0),
          GestureDetector(
            onTap: _isLoading
                ? null
                : () {
                    setState(() {
                      _showEmailForm = false;
                      _errorMessage = null;
                      _errorIsWrongPassword = false;
                    });
                  },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                'cancel',
                style: EdenTypography.bodyMd.copyWith(
                  color: Colors.white60,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _buildInputDecoration({
    required String hintText,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: EdenTypography.bodyLg.copyWith(
        color: Colors.white.withValues(alpha: 0.4),
      ),
      floatingLabelBehavior: FloatingLabelBehavior.never,
      suffixIcon: suffixIcon,
      filled: false,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 20.0,
        vertical: 16.0,
      ),
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
      errorStyle: EdenTypography.bodySm.copyWith(
        color: Colors.white60,
      ),
    );
  }
}

class _GlassAuthButton extends StatelessWidget {
  const _GlassAuthButton({
    required this.glowColor,
    required this.onTap,
    required this.child,
  });

  final Color glowColor;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassGlow(
          glowColor: glowColor,
          glowRadius: 0.9,
          child: FakeGlass(
            shape: const LiquidRoundedSuperellipse(borderRadius: 20),
            settings: GlassTheme.button,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20.0,
                    vertical: 16.0,
                  ),
                  child: Center(child: child),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GlassInput extends StatelessWidget {
  const _GlassInput({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FakeGlass(
      shape: const LiquidRoundedSuperellipse(borderRadius: 16),
      settings: const LiquidGlassSettings(
        blur: 6,
        glassColor: Color(0x20FFFFFF),
      ),
      child: child,
    );
  }
}
