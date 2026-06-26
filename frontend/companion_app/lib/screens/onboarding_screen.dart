import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import '../providers/onboarding_provider.dart';
import '../theme/eden_colors.dart';
import '../theme/eden_typography.dart';
import '../theme/glass_theme.dart';

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
      duration: const Duration(milliseconds: 200),
    );
    _inController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
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

    HapticFeedback.mediumImpact();

    setState(() {
      _isAnimatingOut = true;
    });
    await _outController.forward(from: 0.0);

    try {
      await notifier.respond(stepToSubmit, answer);

      final stateAfter = ref.read(onboardingProvider);

      _outController.reset();

      if (stateAfter.isComplete) {
        if (stateAfter.firstMessage != null) {
          _triggerRevealTimeline(stateAfter.firstMessage!);
        }
      } else {
        await Future.delayed(const Duration(milliseconds: 50));

        _textController.clear();
        _selectedOption = null;

        setState(() {
          _isAnimatingOut = false;
        });
        await _inController.forward(from: 0.0);
      }
    } catch (e) {
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
              ? _buildPartnerReveal(
                  state.partnerName ?? 'Companion',
                  state.firstMessage ?? '',
                )
              : Stack(
                  key: const ValueKey('onboarding_content'),
                  children: [
                    if (state.errorMessage != null)
                      Positioned(
                        top: MediaQuery.of(context).padding.top + 16,
                        left: 24,
                        right: 24,
                        child: _buildErrorPanel(state.errorMessage!),
                      ),
                    SafeArea(
                      child: state.isLoading
                          ? _GlassLoadingState(
                              text: state.currentStep >= 8 ||
                                      state.question == null
                                  ? 'meeting them...'
                                  : 'gathering presence...',
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
    final q = state.question;
    if (q == null) return const SizedBox.shrink();

    final outCurve = CurvedAnimation(
      parent: _outController,
      curve: Curves.easeIn,
    );
    final inCurve = CurvedAnimation(
      parent: _inController,
      curve: Curves.easeOut,
    );

    final double opacity =
        _isAnimatingOut ? 1.0 - outCurve.value : inCurve.value;
    final double translateY =
        _isAnimatingOut ? outCurve.value * -8.0 : (1.0 - inCurve.value) * 8.0;

    return Center(
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          24.0,
          32.0,
          24.0,
          32.0 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0.0, translateY),
            child: LiquidGlass.withOwnLayer(
              shape: GlassTheme.shape,
              settings: GlassTheme.prominent,
              child: Padding(
                padding: const EdgeInsets.all(28.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _StepIllustration(step: state.currentStep),
                    const SizedBox(height: 24.0),
                    _ProgressDots(
                      currentStep: state.currentStep,
                      totalSteps: _totalSteps,
                    ),
                    const SizedBox(height: 28.0),
                    Text(
                      q.question,
                      style: EdenTypography.displayMd.copyWith(
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            color:
                                EdenColors.electricBlue.withValues(alpha: 0.35),
                            blurRadius: 16,
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12.0),
                    Text(
                      'Step ${(state.currentStep + 1).clamp(1, _totalSteps)} of $_totalSteps',
                      style: EdenTypography.bodyMd.copyWith(
                        color: Colors.white70,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32.0),
                    q.type == 'open_text'
                        ? _buildGlassTextField()
                        : _buildOptions(q.options),
                    const SizedBox(height: 32.0),
                    AnimatedOpacity(
                      opacity: _isValid ? 1.0 : 0.45,
                      duration: const Duration(milliseconds: 200),
                      child: IgnorePointer(
                        ignoring: !_isValid,
                        child: _GlassOnboardingButton(
                          text: state.currentStep >= _totalSteps - 1
                              ? 'Get Started'
                              : 'Next',
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
      ),
    );
  }

  Widget _buildGlassTextField() {
    return FakeGlass(
      shape: const LiquidRoundedSuperellipse(borderRadius: 18),
      settings: const LiquidGlassSettings(
        blur: 8,
        glassColor: Color(0x20FFFFFF),
      ),
      child: TextField(
        controller: _textController,
        style: EdenTypography.bodyXl.copyWith(color: Colors.white),
        textAlign: TextAlign.center,
        cursorColor: EdenColors.electricBlue,
        textCapitalization: TextCapitalization.sentences,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) {
          if (_isValid) {
            _handleNext();
          }
        },
        decoration: InputDecoration(
          hintText: 'type here',
          hintStyle: EdenTypography.bodyLg.copyWith(
            color: Colors.white.withValues(alpha: 0.4),
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18.0,
            vertical: 16.0,
          ),
        ),
      ),
    );
  }

  Widget _buildOptions(List<String> options) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: options.map((option) {
        final isSelected = _selectedOption == option;

        return Padding(
          padding: const EdgeInsets.only(bottom: 10.0),
          child: _GlassOption(
            text: option,
            isSelected: isSelected,
            onTap: () {
              setState(() {
                _selectedOption = option;
              });
            },
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPartnerReveal(String partnerName, String firstMessage) {
    return SafeArea(
      key: const ValueKey('partner_reveal'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
        child: Center(
          child: LiquidGlass.withOwnLayer(
            shape: GlassTheme.shape,
            settings: GlassTheme.prominent,
            child: Padding(
              padding: const EdgeInsets.all(30.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _RevealIllustration(),
                  const SizedBox(height: 28.0),
                  Text(
                    partnerName,
                    style: EdenTypography.displayLg.copyWith(
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color:
                              EdenColors.electricBlue.withValues(alpha: 0.35),
                          blurRadius: 18,
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 22.0),
                  Text(
                    _displayedMessage,
                    style: EdenTypography.bodyXl.copyWith(
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32.0),
                  AnimatedOpacity(
                    opacity: _messageTypewriterFinished ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: IgnorePointer(
                      ignoring: !_messageTypewriterFinished,
                      child: _GlassOnboardingButton(
                        text: 'Get Started',
                        width: 220.0,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          context.go('/chat');
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
    );
  }

  Widget _buildErrorPanel(String error) {
    return FakeGlass(
      shape: const LiquidRoundedSuperellipse(borderRadius: 16),
      settings: const LiquidGlassSettings(
        blur: 8,
        glassColor: Color(0x28FFFFFF),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(
          error.replaceAll('ApiException:', '').trim(),
          style: EdenTypography.bodyMd.copyWith(
            color: Colors.white70,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _StepIllustration extends StatelessWidget {
  const _StepIllustration({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    final icons = [
      Icons.auto_awesome_rounded,
      Icons.favorite_border_rounded,
      Icons.psychology_alt_rounded,
      Icons.forum_outlined,
      Icons.nights_stay_outlined,
      Icons.lightbulb_outline_rounded,
      Icons.spa_outlined,
      Icons.graphic_eq_rounded,
      Icons.blur_on_rounded,
    ];
    final icon = icons[step.clamp(0, icons.length - 1)];

    return FakeGlass(
      shape: const LiquidOval(),
      settings: GlassTheme.button,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Icon(
          icon,
          color: Colors.white.withValues(alpha: 0.9),
          size: 44.0,
        ),
      ),
    );
  }
}

class _RevealIllustration extends StatelessWidget {
  const _RevealIllustration();

  @override
  Widget build(BuildContext context) {
    return FakeGlass(
      shape: const LiquidOval(),
      settings: GlassTheme.button,
      child: Padding(
        padding: const EdgeInsets.all(22.0),
        child: Icon(
          Icons.favorite_rounded,
          color: Colors.white.withValues(alpha: 0.9),
          size: 46.0,
        ),
      ),
    );
  }
}

class _ProgressDots extends StatelessWidget {
  const _ProgressDots({
    required this.currentStep,
    required this.totalSteps,
  });

  final int currentStep;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(totalSteps, (index) {
        final isActive = index == currentStep.clamp(0, totalSteps - 1);

        return AnimatedOpacity(
          opacity: isActive ? 1.0 : 0.35,
          duration: const Duration(milliseconds: 220),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: FakeGlass(
              shape: const LiquidOval(),
              settings: GlassTheme.button,
              child: SizedBox(
                width: isActive ? 10.0 : 8.0,
                height: isActive ? 10.0 : 8.0,
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _GlassOption extends StatelessWidget {
  const _GlassOption({
    required this.text,
    required this.isSelected,
    required this.onTap,
  });

  final String text;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FakeGlass(
      shape: const LiquidRoundedSuperellipse(borderRadius: 18),
      settings: isSelected
          ? GlassTheme.button
          : const LiquidGlassSettings(
              blur: 8,
              glassColor: Color(0x18FFFFFF),
            ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Text(
              text,
              style: EdenTypography.bodyLg.copyWith(
                color: Colors.white,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassOnboardingButton extends StatelessWidget {
  const _GlassOnboardingButton({
    required this.text,
    required this.onTap,
    this.width,
  });

  final String text;
  final VoidCallback onTap;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return GlassGlow(
      glowColor: EdenColors.amberGlow,
      glowRadius: 0.9,
      child: FakeGlass(
        shape: const LiquidRoundedSuperellipse(borderRadius: 20),
        settings: GlassTheme.button,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            width: width ?? double.infinity,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 22.0,
                vertical: 16.0,
              ),
              child: Text(
                text,
                style: EdenTypography.bodyLg.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassLoadingState extends StatefulWidget {
  const _GlassLoadingState({required this.text});

  final String text;

  @override
  State<_GlassLoadingState> createState() => _GlassLoadingStateState();
}

class _GlassLoadingStateState extends State<_GlassLoadingState>
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
        child: LiquidGlass.withOwnLayer(
          shape: GlassTheme.shape,
          settings: GlassTheme.card,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
            child: Text(
              widget.text,
              style: EdenTypography.displayMd.copyWith(
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
