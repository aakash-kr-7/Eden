// FILE: models/onboarding.dart
// PURPOSE: Onboarding step data and complete result model.

class OnboardingQuestion {
  final int step;
  final String question;
  final String type;
  final List<String> options;
  final bool optional;

  const OnboardingQuestion({
    required this.step,
    required this.question,
    required this.type,
    required this.options,
    required this.optional,
  });

  factory OnboardingQuestion.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'];
    List<String> options = [];
    if (rawOptions is List) {
      options = rawOptions.map((e) => e.toString()).toList();
    }
    return OnboardingQuestion(
      step: json['step'] as int? ?? 0,
      question: json['question'] as String? ?? '',
      type: json['type'] as String? ?? 'open_text',
      options: options,
      optional: json['optional'] == true || json['optional'] == 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'step': step,
      'question': question,
      'type': type,
      'options': options,
      'optional': optional,
    };
  }
}

class OnboardingStepResult {
  final String? nextStep;
  final OnboardingQuestion? question;
  final bool isComplete;

  const OnboardingStepResult({
    this.nextStep,
    this.question,
    required this.isComplete,
  });

  factory OnboardingStepResult.fromJson(Map<String, dynamic> json) {
    final rawQuestion = json['question'];
    OnboardingQuestion? question;
    if (rawQuestion is Map<String, dynamic>) {
      question = OnboardingQuestion.fromJson(rawQuestion);
    }
    return OnboardingStepResult(
      nextStep: json['next_step']?.toString() ?? json['step']?.toString(),
      question: question,
      isComplete: json['is_complete'] == true || json['is_complete'] == 1 || json['complete'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'next_step': nextStep,
      'question': question?.toJson(),
      'is_complete': isComplete,
    };
  }
}

class OnboardingCompleteResult {
  final String partnerName;
  final String firstMessage;
  final String conversationId;

  const OnboardingCompleteResult({
    required this.partnerName,
    required this.firstMessage,
    required this.conversationId,
  });

  factory OnboardingCompleteResult.fromJson(Map<String, dynamic> json) {
    return OnboardingCompleteResult(
      partnerName: json['partner_name'] as String? ?? json['companion_name'] as String? ?? '',
      firstMessage: json['first_message'] as String? ?? json['opening_line'] as String? ?? '',
      conversationId: json['conversation_id'] as String? ?? '',
    );
  }

  String get companionName => partnerName;
  String get openingLine => firstMessage;

  Map<String, dynamic> toJson() {
    return {
      'partner_name': partnerName,
      'first_message': firstMessage,
      'conversation_id': conversationId,
    };
  }
}
