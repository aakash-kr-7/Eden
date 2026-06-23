import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/eden_theme.dart';
import '../main.dart';
import '../widgets/question_card.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _currentStep = 0;
  final Map<int, dynamic> _responses = {};
  bool _isLoading = true;
  bool _isComplete = false;
  String? _partnerName;
  String? _firstMessage;
  String? _errorMessage;

  // Typewriter state
  String _displayedText = '';
  int _charIndex = 0;
  Timer? _typewriterTimer;
  bool _typewriterFinished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initOnboarding());
  }

  @override
  void dispose() {
    _typewriterTimer?.cancel();
    super.dispose();
  }

  Future<void> _initOnboarding() async {
    try {
      final apiService = ref.read(apiServiceProvider);
      final status = await apiService.checkOnboardingStatus();
      
      if (status.isComplete) {
        // If already completed onboarding, trigger full-screen intro directly
        setState(() {
          _isLoading = true;
        });
        final completeResult = await apiService.completeOnboarding();
        setState(() {
          _partnerName = completeResult.companionName;
          _firstMessage = completeResult.openingLine;
          _isComplete = true;
          _isLoading = false;
        });
        if (_firstMessage != null) {
          _startTypewriter(_firstMessage!);
        }
      } else {
        // Retrieve current onboarding step from backend
        final result = await apiService.startOnboarding();
        setState(() {
          _currentStep = int.tryParse(result.nextStep ?? '0') ?? 0;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load onboarding. Please try again.';
      });
    }
  }

  Future<void> _submitAnswer(dynamic response) async {
    setState(() {
      _errorMessage = null;
    });

    // 200ms brief pause to let selection animation feel solid
    await Future.delayed(const Duration(milliseconds: 200));

    // Keep response in local state
    _responses[_currentStep] = response;

    try {
      final apiService = ref.read(apiServiceProvider);
      
      if (_currentStep < onboardingQuestions.length - 1) {
        // Submit current step answer to API
        final result = await apiService.completeOnboardingStep(_currentStep, response);
        
        // Go to next question, cross-fade is handled by AnimatedSwitcher
        final nextStep = int.tryParse(result.nextStep ?? '') ?? (_currentStep + 1);
        setState(() {
          _currentStep = nextStep;
        });
      } else {
        // Final step: show loading and complete onboarding
        setState(() {
          _isLoading = true;
        });
        
        // Call respond endpoint for step 8
        await apiService.completeOnboardingStep(_currentStep, response);
        
        // Call final completion endpoint
        final completeResult = await apiService.completeOnboarding();

        setState(() {
          _partnerName = completeResult.companionName;
          _firstMessage = completeResult.openingLine;
          _isComplete = true;
          _isLoading = false;
        });

        // Trigger typewriter
        if (_firstMessage != null) {
          _startTypewriter(_firstMessage!);
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('ApiException(400):', '').trim();
      });
      // Rethrow to let QuestionCard reset its submit button state
      rethrow;
    }
  }

  void _startTypewriter(String message) {
    setState(() {
      _displayedText = '';
      _charIndex = 0;
      _typewriterFinished = false;
    });
    _typewriterTimer?.cancel();
    _typewriterTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      if (_charIndex < message.length) {
        setState(() {
          _displayedText += message[_charIndex];
          _charIndex++;
        });
      } else {
        timer.cancel();
        setState(() {
          _typewriterFinished = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0F),
        body: Stack(
          children: [
            // Ambient breathing background
            Positioned.fill(child: const _AmbientBackground()),
            
            SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    switchInCurve: Curves.easeInOut,
                    switchOutCurve: Curves.easeInOut,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: child,
                      );
                    },
                    child: _isComplete
                        ? _buildFirstImpressionMoment()
                        : (_isLoading
                            ? const PulsingLoadingState()
                            : SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    QuestionCard(
                                      key: ValueKey<int>(_currentStep),
                                      config: onboardingQuestions[_currentStep],
                                      onAnswer: _submitAnswer,
                                    ),
                                    if (_errorMessage != null) ...[
                                      const SizedBox(height: 24),
                                      _buildErrorPanel(),
                                    ],
                                  ],
                                ),
                              )),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFirstImpressionMoment() {
    return Column(
      key: const ValueKey('first_impression'),
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Partner name at the top
        Text(
          _partnerName ?? 'Companion',
          style: GoogleFonts.cormorantGaramond(
            fontSize: 28,
            fontWeight: FontWeight.w300,
            color: EdenTheme.accentSecondary,
            letterSpacing: -0.2,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 48),
        
        // Typewriter first message
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 120),
          child: Text(
            _displayedText,
            style: GoogleFonts.cormorantGaramond(
              fontSize: 24,
              fontWeight: FontWeight.w300,
              color: EdenTheme.textPrimary,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 64),
        
        // Fading continue button
        AnimatedOpacity(
          opacity: _typewriterFinished ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 600),
          child: IgnorePointer(
            ignoring: !_typewriterFinished,
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                context.go('/chat');
              },
              borderRadius: BorderRadius.circular(20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                    decoration: BoxDecoration(
                      color: EdenTheme.bgSurface.withValues(alpha: 0.60),
                      border: Border.all(color: EdenTheme.textPrimary.withValues(alpha: 0.07), width: 0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'continue',
                      style: GoogleFonts.jost(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        color: EdenTheme.textPrimary.withValues(alpha: 0.78),
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: EdenTheme.destructive.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EdenTheme.destructive.withValues(alpha: 0.2)),
      ),
      child: Text(
        _errorMessage!,
        style: GoogleFonts.plusJakartaSans(
          color: EdenTheme.destructive.withValues(alpha: 0.9),
          fontSize: 14,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// --- Question Configuration ---
const List<QuestionConfig> onboardingQuestions = [
  QuestionConfig(
    step: 0,
    question: "What should I call you?",
    type: QuestionType.openText,
  ),
  QuestionConfig(
    step: 1,
    question: "What made you come here today?",
    type: QuestionType.openText,
  ),
  QuestionConfig(
    step: 2,
    question: "When you really connect with someone — what does that feel like for you?",
    type: QuestionType.openText,
  ),
  QuestionConfig(
    step: 3,
    question: "Do you tend to have long deep conversations or quick check-ins? Or something in between?",
    type: QuestionType.multipleChoice,
    options: ["long and deep", "quick and light", "it depends"],
  ),
  QuestionConfig(
    step: 4,
    question: "How much do you usually share with people you're close to?",
    type: QuestionType.multipleChoice,
    options: ["a lot — I go deep", "some things — when it feels right", "not much — I'm more private"],
  ),
  QuestionConfig(
    step: 5,
    question: "What kind of humor lands for you?",
    type: QuestionType.multipleChoice,
    options: ["dry and deadpan", "warm and silly", "dark and honest", "I'm not really a humor person"],
  ),
  QuestionConfig(
    step: 6,
    question: "What kind of connection are you hoping for here?",
    type: QuestionType.multipleChoice,
    options: ["someone to talk to", "a real friendship", "something that might become more", "I'm not sure yet"],
  ),
  QuestionConfig(
    step: 7,
    question: "Tell me one thing about yourself that you don't usually lead with.",
    type: QuestionType.openText,
  ),
  QuestionConfig(
    step: 8,
    question: "Is there anything you'd want someone to know before getting to know you?",
    type: QuestionType.openText,
    optional: true,
  ),
];

// --- Pulsing Loading State Helper ---
class PulsingLoadingState extends StatefulWidget {
  const PulsingLoadingState({super.key});

  @override
  State<PulsingLoadingState> createState() => _PulsingLoadingStateState();
}

class _PulsingLoadingStateState extends State<PulsingLoadingState> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FadeTransition(
        opacity: _animation,
        child: Text(
          'meeting them...',
          style: GoogleFonts.cormorantGaramond(
            fontSize: 24,
            fontWeight: FontWeight.w300,
            color: EdenTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}

// --- Breathing Ambient Background Helper ---
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
