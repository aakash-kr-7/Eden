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
import '../widgets/eden_logo.dart';
import '../widgets/atmospheric_background.dart';
import '../widgets/glass_card.dart';

// NOTE: google_fonts import removed — Jost is not part of the Eden design system.
// All text uses EdenTypography (Cormorant Garamond for display, Plus Jakarta Sans for UI).

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
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
  void dispose() {
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
      await ref
          .read(authServiceProvider)
          .signInWithEmailPassword(email, password);
      if (mounted) {
        context.go('/');
      }
    } on AuthException catch (e) {
      // Under email enumeration protection, Firebase returns 'invalid-credential' for new users too.
      if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        try {
          // 2. Attempt Sign Up (New user flow)
          await ref
              .read(authServiceProvider)
              .signUpWithEmailPassword(email, password);
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
      body: AtmosphericBackground(
        child: SafeArea(
          child: CustomScrollView(
            physics: const ClampingScrollPhysics(),
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28.0, vertical: 32.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Spacer(flex: 3),

                      // Custom painted logo (breathes on Auth screen)
                      const EdenLogo(size: 80.0),
                      const SizedBox(height: 24.0),

                      // Wordmark — Cormorant Garamond, display-xl (emotional anchor)
                      Text(
                        'Eden',
                        style: EdenTypography.displayXl.copyWith(
                          color: EdenColors.textPrimary,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 8.0),

                      // Tagline — Plus Jakarta Sans via EdenTypography.bodyMd (UI layer, not emotional)
                      // FIXED: was GoogleFonts.jost — Jost is not in the Eden design system
                      Text(
                        'Begin.',
                        style: EdenTypography.bodyMd.copyWith(
                          color: EdenColors.textSecondary,
                          letterSpacing: 2.5,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                      const SizedBox(height: 48.0),

                      // Auth options card with glassmorphism + custom animated size transition
                      AnimatedSize(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        child: GlassCard(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24.0, vertical: 28.0),
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
                                  ).animate(CurvedAnimation(
                                      parent: animation,
                                      curve: Curves.easeOutCubic)),
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

                      // Soft, lowercase general error message below the card
                      // FIXED: was GoogleFonts.jost — now EdenTypography.bodySm (Plus Jakarta Sans)
                      if (_errorMessage != null && !_errorIsWrongPassword) ...[
                        const SizedBox(height: 24.0),
                        Text(
                          _errorMessage!.toLowerCase(),
                          style: EdenTypography.bodySm.copyWith(
                            color: EdenColors.textSecondary,
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
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Email Field
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            style:
                EdenTypography.bodyXl.copyWith(color: EdenColors.textPrimary),
            cursorColor: EdenColors.edenIris,
            decoration: _buildInputDecoration(hintText: 'email'),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'please enter your email';
              }
              return null;
            },
          ),
          const SizedBox(height: 16.0),
          // Password Field
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            autofillHints: const [AutofillHints.password],
            style:
                EdenTypography.bodyXl.copyWith(color: EdenColors.textPrimary),
            cursorColor: EdenColors.edenIris,
            decoration: _buildInputDecoration(
              hintText: 'password',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
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
                return 'please enter your password';
              }
              if (value.length < 6) {
                return 'password must be at least 6 characters';
              }
              return null;
            },
          ),
          // Inline Wrong Password Error — soft, lowercase, left-aligned
          // FIXED: was GoogleFonts.jost — now EdenTypography.bodySm (Plus Jakarta Sans)
          if (_errorIsWrongPassword) ...[
            const SizedBox(height: 12.0),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  'incorrect password.',
                  style: EdenTypography.bodySm.copyWith(
                    color: EdenColors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 28.0),
          // Submit Button
          EdenPrimaryButton(
            text: 'Continue',
            onTap: _handleEmailAuth,
            isLoading: _isLoading,
            width: double.infinity,
          ),
          const SizedBox(height: 16.0),
          // Cancel — minimal, lowercase, text-only tap target
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
                // FIXED: was GoogleFonts.jost — now EdenTypography.bodyMd (Plus Jakarta Sans)
                style: EdenTypography.bodyMd.copyWith(
                  color: EdenColors.textSecondary,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _buildInputDecoration(
      {required String hintText, Widget? suffixIcon}) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: EdenTypography.bodyLg.copyWith(color: EdenColors.textTertiary),
      floatingLabelBehavior: FloatingLabelBehavior.never,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: EdenColors.edenElevated,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: EdenColors.edenIrisDim, width: 1.0),
        borderRadius: BorderRadius.circular(28.0),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: EdenColors.edenRim, width: 1.0),
        borderRadius: BorderRadius.circular(28.0),
      ),
      errorBorder: OutlineInputBorder(
        borderSide:
            const BorderSide(color: EdenColors.semanticError, width: 1.0),
        borderRadius: BorderRadius.circular(28.0),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderSide:
            const BorderSide(color: EdenColors.semanticError, width: 1.0),
        borderRadius: BorderRadius.circular(28.0),
      ),
    );
  }
}
