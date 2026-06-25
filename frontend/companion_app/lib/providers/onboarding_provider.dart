// ═══════════════════════════════════════════════════════════════════
// FILE: onboarding_provider.dart
// PURPOSE: Riverpod provider managing onboarding step state and submission.
// CONTEXT: Frontend state providers.
// ═══════════════════════════════════════════════════════════════════

// FILE: providers/onboarding_provider.dart
// PURPOSE: Onboarding flow state — current step, responses, partner generation.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart';
import '../models/models.dart';

class OnboardingState {
  final int currentStep;
  final OnboardingQuestion? question;
  final Map<int, dynamic> responses;
  final bool isLoading;
  final bool isComplete;
  final String? partnerName;
  final String? firstMessage;
  final String? errorMessage;

  const OnboardingState({
    this.currentStep = 0,
    this.question,
    this.responses = const {},
    this.isLoading = false,
    this.isComplete = false,
    this.partnerName,
    this.firstMessage,
    this.errorMessage,
  });

  OnboardingState copyWith({
    int? currentStep,
    OnboardingQuestion? question,
    Map<int, dynamic>? responses,
    bool? isLoading,
    bool? isComplete,
    String? partnerName,
    String? firstMessage,
    String? errorMessage,
  }) {
    return OnboardingState(
      currentStep: currentStep ?? this.currentStep,
      question: question ?? this.question,
      responses: responses ?? this.responses,
      isLoading: isLoading ?? this.isLoading,
      isComplete: isComplete ?? this.isComplete,
      partnerName: partnerName ?? this.partnerName,
      firstMessage: firstMessage ?? this.firstMessage,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class OnboardingNotifier extends StateNotifier<OnboardingState> {
  final Ref _ref;

  OnboardingNotifier(this._ref) : super(const OnboardingState());

  Future<void> start() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final apiService = _ref.read(apiServiceProvider);
      
      final status = await apiService.onboardingStatus();
      final isComplete = status['complete'] as bool? ?? false;
      
      if (isComplete) {
        await complete();
      } else {
        final question = await apiService.onboardingStart();
        state = state.copyWith(
          currentStep: question.step,
          question: question,
          isLoading: false,
        );
      }
    } catch (e) {
      debugPrint('Error starting onboarding: $e');
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> respond(int step, dynamic response) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    final updatedResponses = Map<int, dynamic>.from(state.responses)..[step] = response;

    try {
      final apiService = _ref.read(apiServiceProvider);
      final result = await apiService.onboardingRespond(step, response);
      
      if (result.isComplete) {
        state = state.copyWith(
          responses: updatedResponses,
          currentStep: step + 1,
          isLoading: false,
        );
        await complete();
      } else {
        state = state.copyWith(
          responses: updatedResponses,
          currentStep: result.question?.step ?? (step + 1),
          question: result.question,
          isLoading: false,
        );
      }
    } catch (e) {
      debugPrint('Error submitting onboarding response: $e');
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      rethrow;
    }
  }

  Future<void> complete() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final apiService = _ref.read(apiServiceProvider);
      final completeResult = await apiService.onboardingComplete();
      
      state = state.copyWith(
        partnerName: completeResult.partnerName,
        firstMessage: completeResult.firstMessage,
        isComplete: true,
        isLoading: false,
      );
    } catch (e) {
      debugPrint('Error completing onboarding: $e');
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      rethrow;
    }
  }
}

final onboardingProvider = StateNotifierProvider<OnboardingNotifier, OnboardingState>((ref) {
  return OnboardingNotifier(ref);
});
