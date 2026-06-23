import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../theme/eden_theme.dart';
import '../models/models.dart';
import '../main.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> with SingleTickerProviderStateMixin {
  int? _currentStep;
  String? _questionText;
  String? _questionType; // 'open' or 'multiple_choice'
  List<String> _options = [];
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  // Animation controller for transition between questions
  late final AnimationController _animController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnimation = CurvedAnimation(parent: _animController, curve: Curves.easeInOut);
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));

    WidgetsBinding.instance.addPostFrameCallback((_) => _initOnboarding());
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _initOnboarding() async {
    try {
      final apiService = ref.read(apiServiceProvider);
      // Start/Retrieve current onboarding state
      final result = await apiService.startOnboarding();
      _displayStep(result);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load onboarding. Please try again.';
      });
    }
  }

  void _displayStep(OnboardingStepResult result) {
    if (result.isComplete) {
      _finishOnboarding();
      return;
    }

    setState(() {
      _currentStep = int.tryParse(result.nextStep ?? '0') ?? 0;
      _questionText = result.question ?? '';
      _questionType = result.type ?? 'open';
      _options = result.options ?? [];
      _textController.clear();
      _isLoading = false;
      _isSubmitting = false;
      _errorMessage = null;
    });

    _animController.forward(from: 0.0);
  }

  Future<void> _submitAnswer(dynamic answer) async {
    if (_isSubmitting) return;
    HapticFeedback.lightImpact();

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final apiService = ref.read(apiServiceProvider);
      final step = _currentStep ?? 0;
      final result = await apiService.completeOnboardingStep(step, answer);

      if (result.isComplete) {
        _finishOnboarding();
      } else {
        await _animController.reverse();
        _displayStep(result);
      }
    } catch (e) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = e.toString().replaceAll('ApiException(400):', '').trim();
      });
    }
  }

  Future<void> _finishOnboarding() async {
    setState(() {
      _isLoading = true;
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final apiService = ref.read(apiServiceProvider);
      // Complete onboarding and generate partner
      await apiService.completeOnboarding();
      if (mounted) {
        context.go('/chat');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isSubmitting = false;
        _errorMessage = 'Partner creation failed. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EdenTheme.bgPrimary,
      body: Stack(
        children: [
          // Ambient Breathing Background Orbs
          Positioned.fill(child: _buildBackgroundOrbs()),
          
          SafeArea(
            child: _isLoading
                ? _buildLoadingState()
                : FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: Center(
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildQuestionCard(),
                              if (_errorMessage != null) ...[
                                const SizedBox(height: 16),
                                _buildErrorPanel(),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundOrbs() {
    return const _AmbientBackground();
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              valueColor: AlwaysStoppedAnimation(EdenTheme.accentPrimary),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _isSubmitting ? 'generating companion…' : 'gathering presence…',
            style: EdenTheme.bodySmall.copyWith(color: EdenTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: EdenTheme.bgSurface.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: EdenTheme.textPrimary.withValues(alpha: 0.08),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.all(28.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Eyebrow step label (clean, airy)
              Text(
                'QUESTION ${(_currentStep ?? 0) + 1} OF 9',
                style: EdenTheme.labelSmall.copyWith(color: EdenTheme.accentSecondary),
              ),
              const SizedBox(height: 12),
              // Question text in Garamond
              Text(
                _questionText ?? '',
                style: EdenTheme.displaySmall,
              ),
              const SizedBox(height: 32),
              
              if (_questionType == 'open')
                _buildOpenInput()
              else
                _buildMultipleChoiceOptions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOpenInput() {
    final bool isEmpty = _textController.text.trim().isEmpty;
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: EdenTheme.bgPrimary.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: EdenTheme.textSecondary.withValues(alpha: 0.15)),
          ),
          child: TextField(
            controller: _textController,
            style: EdenTheme.bodyMedium,
            cursorColor: EdenTheme.accentPrimary,
            textCapitalization: TextCapitalization.sentences,
            maxLines: 3,
            minLines: 1,
            decoration: InputDecoration(
              hintText: 'Type your answer here...',
              hintStyle: EdenTheme.bodyMedium.copyWith(color: EdenTheme.textTertiary),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              border: InputBorder.none,
            ),
            onChanged: (text) => setState(() {}),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: (isEmpty || _isSubmitting)
                ? null
                : () => _submitAnswer(_textController.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: EdenTheme.accentPrimary,
              foregroundColor: EdenTheme.bgPrimary,
              disabledBackgroundColor: EdenTheme.accentPrimary.withValues(alpha: 0.3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      valueColor: AlwaysStoppedAnimation(EdenTheme.bgPrimary),
                    ),
                  )
                : Text(
                    'Continue',
                    style: EdenTheme.bodyMedium.copyWith(fontWeight: FontWeight.w600, color: EdenTheme.bgPrimary),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildMultipleChoiceOptions() {
    return Column(
      children: _options.map((opt) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: SizedBox(
            width: double.infinity,
            height: 54,
            child: OutlinedButton(
              onPressed: _isSubmitting ? null : () => _submitAnswer(opt),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: EdenTheme.textSecondary.withValues(alpha: 0.2)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                backgroundColor: EdenTheme.bgPrimary.withValues(alpha: 0.3),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  opt,
                  style: EdenTheme.bodyMedium.copyWith(
                    color: EdenTheme.textPrimary.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildErrorPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EdenTheme.destructive.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EdenTheme.destructive.withValues(alpha: 0.25)),
      ),
      child: Text(
        _errorMessage!,
        style: EdenTheme.bodySmall.copyWith(color: EdenTheme.destructive),
      ),
    );
  }
}

// --- breathing ambient backgrounds helper ---
class _AmbientBackground extends StatefulWidget {
  const _AmbientBackground();

  @override
  State<_AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<_AmbientBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final double pulse = _controller.value;
        return Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-0.6, -0.5 + (pulse * 0.1)),
              radius: 1.2,
              colors: [
                EdenTheme.accentPrimary.withValues(alpha: 0.04 + (pulse * 0.02)),
                Colors.transparent,
              ],
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.6, 0.5 - (pulse * 0.1)),
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
    );
  }
}
