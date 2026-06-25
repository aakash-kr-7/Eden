// ═══════════════════════════════════════════════════════════════════
// FILE: screens/onboarding_screen.dart
// PURPOSE: 9-step conversational onboarding that generates the user's partner.
// CONTEXT: Runs once per user. After completion, partner exists forever.
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../theme/eden_colors.dart';
import '../theme/eden_typography.dart';
import '../theme/eden_animations.dart';
import '../providers/onboarding_provider.dart';
import '../widgets/pill_option.dart';
import '../widgets/eden_button.dart';

// NOTE: google_fonts import removed — GoogleFonts.plusJakartaSans() in _buildErrorPanel
// replaced with EdenTypography.bodyMd (Plus Jakarta Sans via the design system).

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with TickerProviderStateMixin {
  final _textController = TextEditingController();
  String? _selectedOption;
  bool _isAnimatingOut = false;

  // Transition controllers
  late final AnimationController _outController;
  late final AnimationController _inController;

  // Partner reveal state
  String _displayedMessage = '';
  bool _messageTypewriterFinished = false;
  Timer? _typewriterTimer;

  @override
  void initState() {
    super.initState();
    _outController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _inController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    // Initially, show the first question immediately
    _inController.value = 1.0;

    WidgetsBinding.instance.addPostFrameCallback((_) => _initOnboarding());
  }

  @override
  void dispose() {
    _textController.dispose();
    _outController.dispose();
    _inController.dispose();
    _typewriterTimer?.cancel();
    super.dispose();
  }

  Future<void> _initOnboarding() async {
    final notifier = ref.read(onboardingProvider.notifier);
    await notifier.start();

    final state = ref.read(onboardingProvider);
    if (state.isComplete && state.firstMessage != null) {
      _triggerRevealTimeline(state.firstMessage!);
    }
  }

  bool get _isValid {
    final state = ref.read(onboardingProvider);
    final q = state.question;
    if (q == null) return false;

    if (q.type == 'open_text') {
      final text = _textController.text.trim();
      if (q.optional) {
        return true;
      }
      return text.length >= 2;
    } else {
      return _selectedOption != null;
    }
  }

  dynamic _getCurrentAnswer() {
    final state = ref.read(onboardingProvider);
    final q = state.question;
    if (q == null) return null;

    if (q.type == 'open_text') {
      return _textController.text.trim();
    } else {
      return _selectedOption;
    }
  }

  Future<void> _handleNext() async {
    if (!_isValid || _isAnimatingOut) return;

    final answer = _getCurrentAnswer();
    final stateBefore = ref.read(onboardingProvider);
    final stepToSubmit = stateBefore.currentStep;
    final notifier = ref.read(onboardingProvider.notifier);

    // Haptic feedback on next action
    HapticFeedback.mediumImpact();

    // 1. OUT animation: opacity 1 -> 0, slide 0 -> -8
    setState(() {
      _isAnimatingOut = true;
    });
    await _outController.forward(from: 0.0);

    try {
      // 2. Submit response to provider/API and wait for processing
      await notifier.respond(stepToSubmit, answer);

      // Check if we are complete
      final stateAfter = ref.read(onboardingProvider);

      _outController.reset();

      if (stateAfter.isComplete) {
        if (stateAfter.firstMessage != null) {
          _triggerRevealTimeline(stateAfter.firstMessage!);
        }
      } else {
        // 3. Gap of 50ms
        await Future.delayed(const Duration(milliseconds: 50));

        // Reset inputs for the next step
        _textController.clear();
        _selectedOption = null;

        // 4. IN animation: opacity 0 -> 1, slide 8 -> 0
        setState(() {
          _isAnimatingOut = false;
        });
        await _inController.forward(from: 0.0);
      }
    } catch (e) {
      // On error, restore visibility of the current question
      if (mounted) {
        _outController.reset();
        setState(() {
          _isAnimatingOut = false;
        });
        _inController.value = 1.0;
      }
    }
  }

  void _triggerRevealTimeline(String message) {
    _typewriterTimer?.cancel();
    setState(() {
      _displayedMessage = '';
      _messageTypewriterFinished = false;
    });

    // After 800ms, start letter-by-letter typewriter
    _typewriterTimer = Timer(const Duration(milliseconds: 800), () {
      int charIndex = 0;
      _typewriterTimer =
          Timer.periodic(const Duration(milliseconds: 25), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        if (charIndex < message.length) {
          setState(() {
            _displayedMessage += message[charIndex];
          });
          charIndex++;
        } else {
          timer.cancel();
          setState(() {
            _messageTypewriterFinished = true;
          });
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingProvider);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: true,
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: state.isComplete
              ? Container(
                  key: const ValueKey('void_bg'),
                  color: EdenColors.edenVoid,
                  child: _buildPartnerReveal(state.partnerName ?? 'Companion',
                      state.firstMessage ?? ''),
                )
              : Container(
                  key: const ValueKey('onboarding_content'),
                  color: EdenColors.edenDepth,
                  child: Stack(
                    children: [
                      // Atmospheric background with three breathing orbs
                      const Positioned.fill(child: AtmosphericBackground()),

                      // Error message if any
                      if (state.errorMessage != null)
                        Positioned(
                          top: MediaQuery.of(context).padding.top + 16,
                          left: 24,
                          right: 24,
                          child: _buildErrorPanel(state.errorMessage!),
                        ),

                      // Loading state or conversational questions
                      SafeArea(
                        child: state.isLoading
                            ? (state.currentStep >= 8 || state.question == null
                                ? const PulsingLoadingState(
                                    text: 'meeting them...')
                                : const PulsingLoadingState(
                                    text: 'gathering presence...'))
                            : _buildQuestionFlow(state),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildQuestionFlow(OnboardingState state) {
    final q = state.question;
    if (q == null) return const SizedBox.shrink();

    final double opacity = _isAnimatingOut
        ? (1.0 -
            CurvedAnimation(parent: _outController, curve: Curves.easeIn).value)
        : CurvedAnimation(parent: _inController, curve: Curves.easeOut).value;

    final double translateY = _isAnimatingOut
        ? CurvedAnimation(parent: _outController, curve: Curves.easeIn).value *
            -8.0
        : (1.0 -
                CurvedAnimation(parent: _inController, curve: Curves.easeOut)
                    .value) *
            8.0;

    return Stack(
      children: [
        // Centered Content (Question + Input/Options)
        Positioned(
          top: MediaQuery.of(context).size.height * 0.35,
          left: 24,
          right: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom > 0 ? 0 : null,
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0.0, translateY),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Question text — displayMd (Cormorant Garamond 28sp), centered
                    Container(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Text(
                        q.question,
                        style: EdenTypography.displayMd.copyWith(
                          color: EdenColors.textPrimary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 48),

                    // Input / choices container
                    Container(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: q.type == 'open_text'
                          ? TextField(
                              controller: _textController,
                              style: EdenTypography.bodyXl
                                  .copyWith(color: EdenColors.textPrimary),
                              textAlign: TextAlign.center,
                              cursorColor: EdenColors.edenIris,
                              textCapitalization: TextCapitalization.sentences,
                              onChanged: (_) => setState(() {}),
                              onSubmitted: (_) {
                                if (_isValid) {
                                  _handleNext();
                                }
                              },
                              decoration: const InputDecoration(
                                border: UnderlineInputBorder(
                                  borderSide: BorderSide(
                                      color: EdenColors.edenRim, width: 1.0),
                                ),
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(
                                      color: EdenColors.edenRim, width: 1.0),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(
                                      color: EdenColors.edenIris, width: 1.0),
                                ),
                                contentPadding:
                                    EdgeInsets.symmetric(vertical: 8),
                              ),
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: q.options.map((option) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10.0),
                                  child: PillOption(
                                    text: option,
                                    isSelected: _selectedOption == option,
                                    onTap: () {
                                      setState(() {
                                        _selectedOption = option;
                                      });
                                    },
                                  ),
                                );
                              }).toList(),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Bottom navigation next arrow (only visible after valid answer)
        Positioned(
          bottom: MediaQuery.of(context).padding.bottom + 24,
          right: 24,
          child: AnimatedOpacity(
            opacity: _isValid ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: AnimatedScale(
              scale: _isValid ? 1.0 : 0.8,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_isValid,
                child: GestureDetector(
                  onTap: _handleNext,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: EdenColors.edenIris,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: EdenColors.edenIrisGlow,
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.white,
                      size: 24,
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

  Widget _buildPartnerReveal(String partnerName, String firstMessage) {
    return SafeArea(
      child: Stack(
        children: [
          // Top Center: Partner Name
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 80.0),
              child: FadeSlideIn(
                duration: const Duration(milliseconds: 500),
                offsetY: 12.0,
                curve: Curves.decelerate,
                child: Text(
                  partnerName,
                  style: EdenTypography.displayLg.copyWith(
                    color: EdenColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),

          // Center: Typewritten First Message
          Align(
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(
                  _displayedMessage,
                  style: EdenTypography.bodyXl.copyWith(
                    color: EdenColors.textPartner,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),

          // Bottom Center: Continue (fades in when typewriter completes)
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 48.0),
              child: AnimatedOpacity(
                opacity: _messageTypewriterFinished ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: IgnorePointer(
                  ignoring: !_messageTypewriterFinished,
                  child: EdenSecondaryButton(
                    text: 'continue',
                    width: 200,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      context.go('/chat');
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorPanel(String error) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: EdenColors.semanticError.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: EdenColors.semanticError.withValues(alpha: 0.2)),
      ),
      // FIXED: was GoogleFonts.plusJakartaSans() — not using direct google_fonts calls.
      // EdenTypography.bodyMd is already Plus Jakarta Sans at 14sp per the design system.
      child: Text(
        error.replaceAll('ApiException:', '').trim(),
        style: EdenTypography.bodyMd.copyWith(
          color: EdenColors.semanticError.withValues(alpha: 0.9),
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ─── Pulsing Loading State Helper ───────────────────────────────────
class PulsingLoadingState extends StatefulWidget {
  final String text;
  const PulsingLoadingState({super.key, required this.text});

  @override
  State<PulsingLoadingState> createState() => _PulsingLoadingStateState();
}

class _PulsingLoadingStateState extends State<PulsingLoadingState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.02).animate(
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
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Text(
          widget.text,
          style: EdenTypography.displayMd.copyWith(
            color: EdenColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

// ─── Atmospheric Background Helper ──────────────────────────────────
// FIXED: replaced presenceBlue, warmViolet, humanWarmth — none exist in the Eden
// design system. Mapped to nearest spec equivalents:
//   presenceBlue → edenIris  (primary accent, represents presence/memory/thoughtfulness)
//   warmViolet   → edenIris  (violet is iris — same emotional territory)
//   humanWarmth  → edenBlush (blush = warmth, affection, intimacy per spec)
class AtmosphericBackground extends StatefulWidget {
  const AtmosphericBackground({super.key});

  @override
  State<AtmosphericBackground> createState() => _AtmosphericBackgroundState();
}

class _AtmosphericBackgroundState extends State<AtmosphericBackground>
    with SingleTickerProviderStateMixin {
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
        return Stack(
          children: [
            // Solid base background
            Container(color: EdenColors.edenDepth),

            // Orb 1: Top-Left — edenIris (presence, memory, thoughtfulness)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(-0.8, -0.7 + (pulse * 0.15)),
                    radius: 1.2,
                    colors: [
                      EdenColors.edenIris
                          .withValues(alpha: 0.04 + (pulse * 0.02)),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // Orb 2: Bottom-Right — edenIris (warm violet, same emotional territory)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0.8, 0.7 - (pulse * 0.15)),
                    radius: 1.3,
                    colors: [
                      EdenColors.edenIris
                          .withValues(alpha: 0.03 + ((1.0 - pulse) * 0.02)),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // Orb 3: Bottom-Center — edenBlush (human warmth, intimacy)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0.0, 0.9 + (pulse * 0.1)),
                    radius: 1.0,
                    colors: [
                      EdenColors.edenBlush
                          .withValues(alpha: 0.02 + (pulse * 0.015)),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
