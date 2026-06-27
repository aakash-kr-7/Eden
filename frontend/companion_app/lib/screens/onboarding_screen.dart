// FILE: screens/onboarding_screen.dart
// PURPOSE: Guide first-launch onboarding with a calm, one-concept-at-a-time experience.
// RESPONSIBILITIES: Render onboarding questions and relay answers to the existing onboarding provider.
// NEVER: Change onboarding contracts, provider behavior, or chat handoff logic.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../main.dart';
import '../providers/onboarding_provider.dart';
import '../theme/nocturne.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with TickerProviderStateMixin {
  static const int _totalSteps = 9;

  final _textController = TextEditingController();
  String? _selectedOption;
  bool _isAnimatingOut = false;

  late final AnimationController _outController;
  late final AnimationController _inController;

  String _displayedMessage = '';
  bool _messageTypewriterFinished = false;
  Timer? _typewriterTimer;

  @override
  void initState() {
    super.initState();
    _outController = AnimationController(
      vsync: this,
      duration: Nocturne.durationFast,
    );
    _inController = AnimationController(
      vsync: this,
      duration: Nocturne.durationStandard,
    );
    _inController.value = 1;

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
    final question = state.question;
    if (question == null) return false;

    if (question.type == 'open_text') {
      final text = _textController.text.trim();
      if (question.optional) return true;
      return text.length >= 2;
    }

    return _selectedOption != null;
  }

  dynamic _getCurrentAnswer() {
    final state = ref.read(onboardingProvider);
    final question = state.question;
    if (question == null) return null;

    if (question.type == 'open_text') {
      return _textController.text.trim();
    }
    return _selectedOption;
  }

  Future<void> _handleNext() async {
    if (!_isValid || _isAnimatingOut) return;

    final answer = _getCurrentAnswer();
    final stateBefore = ref.read(onboardingProvider);
    final stepToSubmit = stateBefore.currentStep;
    final notifier = ref.read(onboardingProvider.notifier);

    HapticFeedback.mediumImpact();

    setState(() {
      _isAnimatingOut = true;
    });
    await _outController.forward(from: 0);

    try {
      await notifier.respond(stepToSubmit, answer);
      final stateAfter = ref.read(onboardingProvider);

      _outController.reset();

      if (stateAfter.isComplete) {
        if (stateAfter.firstMessage != null) {
          _triggerRevealTimeline(stateAfter.firstMessage!);
        }
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        _textController.clear();
        _selectedOption = null;

        setState(() {
          _isAnimatingOut = false;
        });
        await _inController.forward(from: 0);
      }
    } catch (_) {
      if (!mounted) return;
      _outController.reset();
      setState(() {
        _isAnimatingOut = false;
      });
      _inController.value = 1;
    }
  }

  void _triggerRevealTimeline(String message) {
    _typewriterTimer?.cancel();
    setState(() {
      _displayedMessage = '';
      _messageTypewriterFinished = false;
    });

    _typewriterTimer = Timer(const Duration(milliseconds: 600), () {
      var charIndex = 0;
      _typewriterTimer =
          Timer.periodic(const Duration(milliseconds: 22), (timer) {
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
          duration: Nocturne.durationStandard,
          child: state.isComplete
              ? _buildPartnerReveal(
                  state.partnerName ?? 'Companion',
                  state.firstMessage ?? '',
                )
              : Stack(
                  key: const ValueKey('onboarding_content'),
                  children: [
                    const _OnboardingBackdrop(),
                    if (state.errorMessage != null)
                      Positioned(
                        top: MediaQuery.of(context).padding.top +
                            Nocturne.space6,
                        left: Nocturne.space8,
                        right: Nocturne.space8,
                        child: _buildErrorPanel(state.errorMessage!),
                      ),
                    SafeArea(
                      child: state.isLoading
                          ? _LoadingState(
                              text: state.currentStep >= 8 ||
                                      state.question == null
                                  ? 'Meeting them...'
                                  : 'Gathering the shape...',
                            )
                          : _buildQuestionFlow(state),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildQuestionFlow(OnboardingState state) {
    final question = state.question;
    if (question == null) return const SizedBox.shrink();

    final outCurve = CurvedAnimation(
      parent: _outController,
      curve: Curves.easeInCubic,
    );
    final inCurve = CurvedAnimation(
      parent: _inController,
      curve: Curves.easeOut,
    );

    final opacity = _isAnimatingOut ? 1 - outCurve.value : inCurve.value;
    final translateY =
        _isAnimatingOut ? outCurve.value * -10 : (1 - inCurve.value) * 12;

    return Center(
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          Nocturne.space8,
          Nocturne.space8,
          Nocturne.space8,
          Nocturne.space8 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Opacity(
          opacity: opacity.clamp(0, 1),
          child: Transform.translate(
            offset: Offset(0, translateY),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ProgressHeader(
                    currentStep: state.currentStep,
                    totalSteps: _totalSteps,
                  ),
                  const SizedBox(height: Nocturne.space9),
                  _StepMark(step: state.currentStep),
                  const SizedBox(height: Nocturne.space8),
                  Text(
                    question.question,
                    style: Nocturne.displayLg.copyWith(fontSize: 40),
                  ),
                  const SizedBox(height: Nocturne.space4),
                  Text(
                    question.optional ? 'Optional' : 'One answer is enough.',
                    style: Nocturne.bodySm.copyWith(
                      color: Nocturne.textSecondary,
                    ),
                  ),
                  const SizedBox(height: Nocturne.space9),
                  question.type == 'open_text'
                      ? _buildTextField()
                      : _buildOptions(question.options),
                  const SizedBox(height: Nocturne.space9),
                  AnimatedOpacity(
                    opacity: _isValid ? 1 : 0.35,
                    duration: Nocturne.durationFast,
                    child: IgnorePointer(
                      ignoring: !_isValid,
                      child: _OnboardingPrimaryButton(
                        label: state.currentStep >= _totalSteps - 1
                            ? 'Finish'
                            : 'Continue',
                        onTap: _handleNext,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0C0D10),
        borderRadius: BorderRadius.circular(Nocturne.radiusXl),
        border: Border.all(color: Nocturne.borderSubtle),
      ),
      child: TextField(
        controller: _textController,
        style: Nocturne.bodyXl,
        cursorColor: Nocturne.accentCool,
        textCapitalization: TextCapitalization.sentences,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) {
          if (_isValid) {
            _handleNext();
          }
        },
        decoration: InputDecoration(
          hintText: 'Type here',
          hintStyle: Nocturne.bodyLg.copyWith(color: Nocturne.textTertiary),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: Nocturne.space6,
            vertical: Nocturne.space6,
          ),
        ),
      ),
    );
  }

  Widget _buildOptions(List<String> options) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: options.map((option) {
        final isSelected = _selectedOption == option;

        return Padding(
          padding: const EdgeInsets.only(bottom: Nocturne.space4),
          child: InkWell(
            onTap: () {
              setState(() {
                _selectedOption = option;
              });
            },
            borderRadius: BorderRadius.circular(Nocturne.radiusLg),
            child: AnimatedContainer(
              duration: Nocturne.durationFast,
              curve: Curves.easeOut,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: Nocturne.space6,
                vertical: Nocturne.space5,
              ),
              decoration: BoxDecoration(
                color:
                    isSelected ? Nocturne.textPrimary : const Color(0xFF0C0D10),
                borderRadius: BorderRadius.circular(Nocturne.radiusLg),
                border: Border.all(
                  color:
                      isSelected ? Colors.transparent : Nocturne.borderSubtle,
                ),
              ),
              child: Text(
                option,
                style: Nocturne.bodyLg.copyWith(
                  color: isSelected ? Nocturne.black : Nocturne.textPrimary,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPartnerReveal(String partnerName, String firstMessage) {
    return Stack(
      key: const ValueKey('partner_reveal'),
      children: [
        const _OnboardingBackdrop(),
        SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(Nocturne.space8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      partnerName,
                      style: Nocturne.displayXl.copyWith(fontSize: 64),
                    ),
                    const SizedBox(height: Nocturne.space7),
                    Text(
                      _displayedMessage,
                      style: Nocturne.bodyXl.copyWith(height: 1.65),
                    ),
                    const SizedBox(height: Nocturne.space9),
                    AnimatedOpacity(
                      opacity: _messageTypewriterFinished ? 1 : 0,
                      duration: Nocturne.durationStandard,
                      child: IgnorePointer(
                        ignoring: !_messageTypewriterFinished,
                        child: _OnboardingPrimaryButton(
                          label: 'Enter',
                          width: 180,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            context.go(AppRoute.chat);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorPanel(String error) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Nocturne.space5,
        vertical: Nocturne.space4,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF111317),
        borderRadius: BorderRadius.circular(Nocturne.radiusLg),
        border: Border.all(color: Nocturne.borderSubtle),
      ),
      child: Text(
        error.replaceAll('ApiException:', '').trim(),
        style: Nocturne.bodySm.copyWith(color: Nocturne.textSecondary),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _OnboardingBackdrop extends StatelessWidget {
  const _OnboardingBackdrop();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          const ColoredBox(color: Colors.black),
          Positioned(
            top: -80,
            right: -20,
            child: IgnorePointer(
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Nocturne.accentWarm.withValues(alpha: 0.09),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: -80,
            bottom: 80,
            child: IgnorePointer(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Nocturne.accentCool.withValues(alpha: 0.07),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({
    required this.currentStep,
    required this.totalSteps,
  });

  final int currentStep;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    final current = (currentStep + 1).clamp(1, totalSteps);
    final progress = current / totalSteps;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$current of $totalSteps',
          style: Nocturne.label.copyWith(color: Nocturne.textTertiary),
        ),
        const SizedBox(height: Nocturne.space3),
        ClipRRect(
          borderRadius: BorderRadius.circular(Nocturne.radiusPill),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 3,
            backgroundColor: Colors.white.withValues(alpha: 0.06),
            valueColor:
                const AlwaysStoppedAnimation<Color>(Nocturne.textPrimary),
          ),
        ),
      ],
    );
  }
}

class _StepMark extends StatelessWidget {
  const _StepMark({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    const marks = [
      'Presence',
      'Tone',
      'Closeness',
      'Conversation',
      'Night',
      'Curiosity',
      'Care',
      'Rhythm',
      'Arrival',
    ];

    return Text(
      marks[step.clamp(0, marks.length - 1)].toUpperCase(),
      style: Nocturne.label.copyWith(
        color: Nocturne.accentWarm,
        letterSpacing: 0.9,
      ),
    );
  }
}

class _OnboardingPrimaryButton extends StatelessWidget {
  const _OnboardingPrimaryButton({
    required this.label,
    required this.onTap,
    this.width,
  });

  final String label;
  final VoidCallback onTap;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Nocturne.radiusLg),
      child: Container(
        width: width ?? double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: Nocturne.space6,
          vertical: Nocturne.space5,
        ),
        decoration: BoxDecoration(
          color: Nocturne.textPrimary,
          borderRadius: BorderRadius.circular(Nocturne.radiusLg),
          boxShadow: Nocturne.elevationLow,
        ),
        child: Text(
          label,
          style: Nocturne.button.copyWith(color: Nocturne.black),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _LoadingState extends StatefulWidget {
  const _LoadingState({required this.text});

  final String text;

  @override
  State<_LoadingState> createState() => _LoadingStateState();
}

class _LoadingStateState extends State<_LoadingState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Nocturne.durationAmbient,
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.45, end: 1).animate(
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
    return Stack(
      children: [
        const _OnboardingBackdrop(),
        Center(
          child: FadeTransition(
            opacity: _opacity,
            child: Text(
              widget.text,
              style: Nocturne.displayMd,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}
