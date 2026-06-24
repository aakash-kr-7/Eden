// ═══════════════════════════════════════════════════════════════════
// FILE: screens/auth_screen.dart
// PURPOSE: Sign in / sign up. No distinction between the two — just "Begin."
// CONTEXT: Shown when user is not authenticated. Routes to onboarding or chat.
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../theme/eden_colors.dart';
import '../theme/eden_typography.dart';
import '../main.dart';
import '../services/auth_service.dart';
import '../widgets/eden_button.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> with SingleTickerProviderStateMixin {
  bool _showEmailForm = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _errorIsWrongPassword = false;
  String? _errorMessage;
  Timer? _errorTimer;

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  late final AnimationController _bgController;

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _bgController.dispose();
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
        context.go('/');
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
      // 1. Attempt Sign In
      await ref.read(authServiceProvider).signInWithEmailPassword(email, password);
      if (mounted) {
        context.go('/');
      }
    } on AuthException catch (e) {
      // Under email enumeration protection, Firebase returns 'invalid-credential' for new users too.
      if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        try {
          // 2. Attempt Sign Up (New user flow)
          await ref.read(authServiceProvider).signUpWithEmailPassword(email, password);
          if (mounted) {
            context.go('/');
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
    return Scaffold(
      backgroundColor: EdenColors.edenVoid,
      body: Stack(
        children: [
          // Three breathing atmospheric orbs
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _bgController,
              builder: (context, child) {
                final pulse = _bgController.value;
                return Stack(
                  children: [
                    // Top-Left (Presence Blue)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: Alignment(-0.8, -0.8 + (pulse * 0.1)),
                            radius: 1.2,
                            colors: [
                              EdenColors.presenceBlue.withValues(alpha: 0.04 + (pulse * 0.015)),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Bottom-Right (Warm Violet)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: Alignment(0.8, 0.8 - (pulse * 0.1)),
                            radius: 1.2,
                            colors: [
                              EdenColors.warmViolet.withValues(alpha: 0.03 + ((1 - pulse) * 0.015)),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Bottom-Center (Human Warmth)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: Alignment(0.0, 1.0 - (pulse * 0.05)),
                            radius: 1.0,
                            colors: [
                              EdenColors.humanWarmth.withValues(alpha: 0.02 + (pulse * 0.01)),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          
          SafeArea(
            child: CustomScrollView(
              physics: const ClampingScrollPhysics(),
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 32.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Spacer(flex: 4),
                        // Wordmark (optical center 40% from top bias)
                        Text(
                          'Eden',
                          style: EdenTypography.displayXl.copyWith(
                            color: EdenColors.textPrimary,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 48.0),
                        Text(
                          'Begin.',
                          style: EdenTypography.displayMd.copyWith(
                            color: EdenColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 64.0),

                        // Auth options / form with entrance animation
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          transitionBuilder: (Widget child, Animation<double> animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0.0, 0.04),
                                  end: Offset.zero,
                                ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                                child: child,
                              ),
                            );
                          },
                          child: _showEmailForm ? _buildEmailForm() : _buildOAuthMenu(),
                        ),

                        // General Errors (auto-dismissed, placed below buttons)
                        if (_errorMessage != null && !_errorIsWrongPassword) ...[
                          const SizedBox(height: 24.0),
                          Text(
                            'Something went wrong — try again',
                            style: EdenTypography.bodySm.copyWith(
                              color: EdenColors.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const Spacer(flex: 6),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOAuthMenu() {
    return Column(
      key: const ValueKey('oauth_menu'),
      children: [
        // Google Button
        EdenSecondaryButton(
          onTap: _handleGoogleSignIn,
          width: double.infinity,
          icon: Image.asset(
            'assets/images/google_logo.png',
            width: 20.0,
            height: 20.0,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.g_mobiledata,
              color: Colors.white,
              size: 20,
            ),
          ),
          text: 'Continue with Google',
        ),
        const SizedBox(height: 12.0),
        // Email Toggle Button
        EdenSecondaryButton(
          onTap: () {
            setState(() {
              _showEmailForm = true;
              _errorMessage = null;
              _errorIsWrongPassword = false;
            });
          },
          width: double.infinity,
          text: 'Use email instead',
        ),
      ],
    );
  }

  Widget _buildEmailForm() {
    return Form(
      key: _formKey,
      child: Column(
        key: const ValueKey('email_form'),
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Email Field
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            style: EdenTypography.bodyXl.copyWith(color: EdenColors.textPrimary),
            cursorColor: EdenColors.edenIris,
            decoration: _buildInputDecoration(),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your email';
              }
              return null;
            },
          ),
          const SizedBox(height: 16.0),
          // Password Field
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            style: EdenTypography.bodyXl.copyWith(color: EdenColors.textPrimary),
            cursorColor: EdenColors.edenIris,
            decoration: _buildInputDecoration(
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: EdenColors.textSecondary,
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
                return 'Please enter your password';
              }
              if (value.length < 6) {
                return 'Password must be at least 6 characters';
              }
              return null;
            },
          ),
          // Inline Wrong Password Error
          if (_errorIsWrongPassword) ...[
            const SizedBox(height: 8.0),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  'Incorrect password.',
                  style: EdenTypography.bodySm.copyWith(
                    color: EdenColors.textTertiary,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 32.0),
          // Submit Button
          EdenPrimaryButton(
            text: 'Continue',
            onTap: _handleEmailAuth,
            isLoading: _isLoading,
            width: double.infinity,
          ),
          const SizedBox(height: 16.0),
          // Cancel Button
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
            child: Text(
              'Cancel',
              style: EdenTypography.bodyMd.copyWith(
                color: EdenColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _buildInputDecoration({Widget? suffixIcon}) {
    return InputDecoration(
      hintText: null,
      labelText: null,
      floatingLabelBehavior: FloatingLabelBehavior.never,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: EdenColors.edenElevated,
    );
  }
}
