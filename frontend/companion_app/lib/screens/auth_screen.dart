import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/eden_theme.dart';
import '../main.dart';
import '../services/auth_service.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> with SingleTickerProviderStateMixin {
  bool _showEmailForm = false;
  bool _isLoading = false;
  String? _errorMessage;

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
    super.dispose();
  }

  Future<void> _handleGoogleSignIn() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = await ref.read(authServiceProvider).signInWithGoogle();
      if (user != null && mounted) {
        context.go('/');
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _handleEmailAuth() async {
    if (_isLoading) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
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
      // If sign in fails, it could be a wrong password or a new user account.
      // Under Firebase security rules, both might throw 'invalid-credential' or 'user-not-found'.
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
                _errorMessage = 'Incorrect password.';
              } else {
                _errorMessage = signUpError.message;
              }
            });
          }
        } catch (err) {
          if (mounted) {
            setState(() {
              _isLoading = false;
              _errorMessage = err.toString();
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = e.message;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Stack(
        children: [
          // Breathing ambient background
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _bgController,
              builder: (context, child) {
                final pulse = _bgController.value;
                return Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(-0.5, -0.6 + (pulse * 0.15)),
                      radius: 1.3,
                      colors: [
                        EdenTheme.accentPrimary.withValues(alpha: 0.05 + (pulse * 0.02)),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(0.5, 0.6 - (pulse * 0.15)),
                        radius: 1.4,
                        colors: [
                          EdenTheme.accentSecondary.withValues(alpha: 0.03 + ((1 - pulse) * 0.02)),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Wordmark
                    Text(
                      'Eden',
                      style: GoogleFonts.cormorantGaramond(
                        fontSize: 48,
                        fontWeight: FontWeight.w300,
                        color: EdenTheme.textPrimary,
                        letterSpacing: 2.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Begin.',
                      style: GoogleFonts.cormorantGaramond(
                        fontSize: 20,
                        fontWeight: FontWeight.w300,
                        fontStyle: FontStyle.italic,
                        color: EdenTheme.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 64),

                    // Inline Error Panel
                    if (_errorMessage != null) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: Text(
                          _errorMessage!,
                          style: GoogleFonts.plusJakartaSans(
                            color: EdenTheme.destructive,
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],

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
                  ],
                ),
              ),
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
        _buildGlassButton(
          onTap: _handleGoogleSignIn,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/images/google_logo.png', width: 18, height: 18, errorBuilder: (_, __, ___) => const Icon(Icons.g_mobiledata, color: Colors.white)),
              const SizedBox(width: 12),
              Text(
                'Continue with Google',
                style: GoogleFonts.jost(
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  color: EdenTheme.textPrimary.withValues(alpha: 0.9),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Email Toggle Button
        _buildGlassButton(
          onTap: () {
            setState(() {
              _showEmailForm = true;
              _errorMessage = null;
            });
          },
          child: Center(
            child: Text(
              'Use email',
              style: GoogleFonts.jost(
                fontSize: 15,
                fontWeight: FontWeight.w400,
                color: EdenTheme.textPrimary.withValues(alpha: 0.9),
                letterSpacing: 0.5,
              ),
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
        children: [
          // Email Field
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            style: GoogleFonts.plusJakartaSans(color: EdenTheme.textPrimary, fontSize: 15),
            cursorColor: EdenTheme.accentPrimary,
            decoration: _buildInputDecoration('Email address'),
            validator: (value) {
              if (value == null || value.trim().isEmpty) return 'Please enter your email';
              return null;
            },
          ),
          const SizedBox(height: 16),
          // Password Field
          TextFormField(
            controller: _passwordController,
            obscureText: true,
            style: GoogleFonts.plusJakartaSans(color: EdenTheme.textPrimary, fontSize: 15),
            cursorColor: EdenTheme.accentPrimary,
            decoration: _buildInputDecoration('Password'),
            validator: (value) {
              if (value == null || value.trim().isEmpty) return 'Please enter your password';
              if (value.length < 6) return 'Password must be at least 6 characters';
              return null;
            },
          ),
          const SizedBox(height: 32),
          // Actions
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: _isLoading ? null : () {
                    setState(() {
                      _showEmailForm = false;
                      _errorMessage = null;
                    });
                  },
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.jost(
                      fontSize: 15,
                      color: EdenTheme.textSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _buildGlassButton(
                  onTap: _handleEmailAuth,
                  child: Center(
                    child: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              valueColor: AlwaysStoppedAnimation(EdenTheme.accentPrimary),
                            ),
                          )
                        : Text(
                            'Continue',
                            style: GoogleFonts.jost(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: EdenTheme.textPrimary,
                              letterSpacing: 0.5,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _buildInputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.plusJakartaSans(color: EdenTheme.textTertiary, fontSize: 15),
      filled: true,
      fillColor: EdenTheme.bgSurface.withValues(alpha: 0.4),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      errorStyle: GoogleFonts.plusJakartaSans(color: EdenTheme.destructive.withValues(alpha: 0.8), fontSize: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: EdenTheme.textTertiary.withValues(alpha: 0.1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: EdenTheme.accentPrimary, width: 0.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: EdenTheme.destructive.withValues(alpha: 0.3), width: 0.8),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: EdenTheme.destructive.withValues(alpha: 0.5), width: 0.8),
      ),
    );
  }

  Widget _buildGlassButton({required VoidCallback? onTap, required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: EdenTheme.bgSurface.withValues(alpha: 0.50),
              border: Border.all(color: EdenTheme.textPrimary.withValues(alpha: 0.06), width: 0.6),
              borderRadius: BorderRadius.circular(16),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
