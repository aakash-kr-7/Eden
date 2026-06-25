// ═══════════════════════════════════════════════════════════════════
// FILE: services/api_service.dart
// PURPOSE: All HTTP communication with Eden backend. Auth token injected automatically.
// CONTEXT: Used by all Riverpod providers to fetch data from FastAPI.
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/models.dart';
import 'auth_service.dart';

String _defaultBaseUrl() {
  if (kIsWeb) {
    return 'http://localhost:8001';
  }

  if (defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:8001';
  }

  return 'http://localhost:8001';
}

const String kBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: '',
);

class ApiService {
  final AuthService _authService;
  final Dio _dio;

  ApiService(this._authService, {String? baseUrl})
      : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl ?? (kBaseUrl.isNotEmpty ? kBaseUrl : _defaultBaseUrl()),
          ),
        ) {
    // 1. Interceptor: Auto-inject Firebase ID token
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          try {
            final token = await _authService.getCurrentIdToken();
            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          } catch (e) {
            debugPrint('Error injecting Auth Token: $e');
          }
          return handler.next(options);
        },
      ),
    );

    // 2. Interceptor: Retry 3x on 5xx with exponential backoff
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (DioException error, handler) async {
          final response = error.response;
          final requestOptions = error.requestOptions;

          int retryCount = requestOptions.extra['retry_count'] as int? ?? 0;
          if (response != null &&
              response.statusCode != null &&
              response.statusCode! >= 500 &&
              response.statusCode! < 600 &&
              retryCount < 3) {
            retryCount++;
            requestOptions.extra['retry_count'] = retryCount;

            final backoffMs = 1000 * (1 << retryCount); // 2s, 4s, 8s
            await Future.delayed(Duration(milliseconds: backoffMs));

            try {
              final res = await _dio.fetch(requestOptions);
              return handler.resolve(res);
            } on DioException catch (retryError) {
              return handler.next(retryError);
            }
          }
          return handler.next(error);
        },
      ),
    );
  }

  // --- API Methods ---

  Future<Session> loadSession() async {
    try {
      final response = await _dio.get('/api/chat/session');
      if (response.data == null) {
        throw const ApiException('Session payload was empty', 204);
      }
      return Session.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException(
        e.message ?? 'Failed to load session',
        e.response?.statusCode ?? 500,
      );
    }
  }

  Stream<String> sendMessage(String? conversationId, String message) async* {
    try {
      final response = await _dio.post<ResponseBody>(
        '/api/chat/message',
        data: {
          'message': message,
          if (conversationId != null) 'conversation_id': conversationId,
        },
        options: Options(responseType: ResponseType.stream),
      );

      final stream = response.data!.stream
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in stream) {
        if (line.startsWith('data: ')) {
          final dataStr = line.substring(6).trim();
          if (dataStr.isNotEmpty) {
            yield dataStr;
          }
        }
      }
    } on DioException catch (e) {
      throw ApiException(
        e.message ?? 'Failed to send message',
        e.response?.statusCode ?? 500,
      );
    }
  }

  Future<List<Message>> getMessages(String? conversationId, {int? beforeId, int? limit}) async {
    try {
      final response = await _dio.get(
        '/api/chat/messages',
        queryParameters: {
          if (beforeId != null) 'before_id': beforeId,
          if (limit != null) 'limit': limit,
        },
      );
      final list = response.data as List<dynamic>? ?? const [];
      return list.map((e) => Message.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiException(
        e.message ?? 'Failed to get messages',
        e.response?.statusCode ?? 500,
      );
    }
  }

  Future<RelationshipSummary> getRelationshipSummary() async {
    try {
      final response = await _dio.get('/api/profile/relationship');
      return RelationshipSummary.fromJson(response.data as Map<String, dynamic>? ?? const {});
    } on DioException catch (e) {
      throw ApiException(
        e.message ?? 'Failed to get relationship summary',
        e.response?.statusCode ?? 500,
      );
    }
  }

  Future<List<Memory>> getMemories({String? type, String? sort, int? page}) async {
    try {
      final response = await _dio.get(
        '/api/profile/memories',
        queryParameters: {
          if (type != null) 'type': type,
          if (sort != null) 'sort': sort,
          if (page != null) 'page': page,
        },
      );
      final rawData = response.data as Map<String, dynamic>? ?? const {};
      final list = rawData['memories'] as List<dynamic>? ?? const [];
      return list.map((e) => Memory.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiException(
        e.message ?? 'Failed to get memories',
        e.response?.statusCode ?? 500,
      );
    }
  }

  Future<void> pinMemory(int id) async {
    try {
      await _dio.post('/api/profile/memories/$id/pin');
    } on DioException catch (e) {
      throw ApiException(
        e.message ?? 'Failed to pin memory',
        e.response?.statusCode ?? 500,
      );
    }
  }

  Future<void> deleteMemory(int id) async {
    try {
      await _dio.delete('/api/profile/memories/$id');
    } on DioException catch (e) {
      throw ApiException(
        e.message ?? 'Failed to delete memory',
        e.response?.statusCode ?? 500,
      );
    }
  }

  Future<List<ProactiveMessage>> getPendingProactive() async {
    try {
      final response = await _dio.get('/api/proactive/pending');
      final list = response.data as List<dynamic>? ?? const [];
      return list.map((e) => ProactiveMessage.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiException(
        e.message ?? 'Failed to get pending proactive messages',
        e.response?.statusCode ?? 500,
      );
    }
  }

  Future<void> acknowledgeProactive(String id) async {
    try {
      await _dio.post('/api/proactive/acknowledge/$id');
    } on DioException catch (e) {
      throw ApiException(
        e.message ?? 'Failed to acknowledge proactive message',
        e.response?.statusCode ?? 500,
      );
    }
  }

  Future<Map<String, dynamic>> onboardingStatus() async {
    try {
      final response = await _dio.get('/api/onboarding/status');
      return response.data as Map<String, dynamic>? ?? const {};
    } on DioException catch (e) {
      throw ApiException(
        e.message ?? 'Failed to check onboarding status',
        e.response?.statusCode ?? 500,
      );
    }
  }

  Future<OnboardingQuestion> onboardingStart() async {
    try {
      final response = await _dio.post('/api/onboarding/start');
      return OnboardingQuestion.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException(
        e.message ?? 'Failed to start onboarding',
        e.response?.statusCode ?? 500,
      );
    }
  }

  Future<OnboardingStepResult> onboardingRespond(int step, dynamic response) async {
    try {
      final res = await _dio.post(
        '/api/onboarding/respond',
        data: {
          'step': step,
          'response': response,
        },
      );
      return OnboardingStepResult.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException(
        e.message ?? 'Failed to submit onboarding response',
        e.response?.statusCode ?? 500,
      );
    }
  }

  Future<OnboardingCompleteResult> onboardingComplete() async {
    try {
      final response = await _dio.post('/api/onboarding/complete');
      return OnboardingCompleteResult.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException(
        e.message ?? 'Failed to complete onboarding',
        e.response?.statusCode ?? 500,
      );
    }
  }

  Future<void> registerFcmToken(String token, String platform) async {
    try {
      await _dio.post(
        '/api/notifications/register',
        data: {
          'fcm_token': token,
        },
      );
    } on DioException catch (e) {
      throw ApiException(
        e.message ?? 'Failed to register FCM token',
        e.response?.statusCode ?? 500,
      );
    }
  }

  // --- Backwards Compatibility / Legacy Screen Methods ---

  Future<OnboardingStepResult> checkOnboardingStatus() async {
    final response = await _dio.get('/api/onboarding/status');
    final data = response.data as Map<String, dynamic>;
    return OnboardingStepResult(
      nextStep: data['current_step']?.toString(),
      question: null,
      isComplete: data['complete'] == true || data['complete'] == 1,
    );
  }

  Future<OnboardingStepResult> startOnboarding() async {
    final response = await _dio.post('/api/onboarding/start');
    final data = response.data as Map<String, dynamic>;
    return OnboardingStepResult(
      nextStep: data['step']?.toString(),
      question: OnboardingQuestion.fromJson(data),
      isComplete: false,
    );
  }

  Future<OnboardingStepResult> completeOnboardingStep(int step, dynamic response) async {
    final res = await _dio.post(
      '/api/onboarding/respond',
      data: {
        'step': step,
        'response': response,
      },
    );
    final data = res.data as Map<String, dynamic>;
    
    final rawQuestion = data['question'];
    OnboardingQuestion? nextQuestion;
    if (rawQuestion is Map<String, dynamic>) {
      nextQuestion = OnboardingQuestion.fromJson(rawQuestion);
    } else if (data['step'] != null) {
      nextQuestion = OnboardingQuestion.fromJson(data);
    }

    return OnboardingStepResult(
      nextStep: data['next_step']?.toString() ?? data['step']?.toString(),
      question: nextQuestion,
      isComplete: data['is_complete'] == true || data['is_complete'] == 1 || data['complete'] == true,
    );
  }

  Future<OnboardingCompleteResult> completeOnboarding() async {
    return onboardingComplete();
  }

  Future<Map<String, dynamic>> getProfile() async {
    try {
      final response = await _dio.get('/api/profile/me');
      return response.data as Map<String, dynamic>? ?? const {};
    } on DioException catch (e) {
      throw ApiException(
        e.message ?? 'Failed to get profile',
        e.response?.statusCode ?? 500,
      );
    }
  }

  Future<void> updateProfile({
    Map<String, dynamic>? data,
    String? displayName,
    String? communicationPace,
    bool? allowProactive,
    bool? allowPush,
  }) async {
    final Map<String, dynamic> body = {};
    if (data != null) {
      body.addAll(data);
    }
    if (displayName != null) body['display_name'] = displayName;
    if (communicationPace != null) body['communication_pace'] = communicationPace;
    if (allowProactive != null) body['allow_proactive_messages'] = allowProactive;
    if (allowPush != null) body['allow_push_notifications'] = allowPush;

    try {
      await _dio.patch('/api/profile/me', data: body);
    } on DioException catch (e) {
      throw ApiException(
        e.message ?? 'Failed to update profile',
        e.response?.statusCode ?? 500,
      );
    }
  }

  Future<void> deleteAllMemories() async {
    try {
      await _dio.delete('/api/profile/memories');
    } on DioException catch (e) {
      throw ApiException(
        e.message ?? 'Failed to delete all memories',
        e.response?.statusCode ?? 500,
      );
    }
  }

  Future<void> deleteAccount() async {
    try {
      await _dio.delete('/api/profile/me');
    } on DioException catch (e) {
      throw ApiException(
        e.message ?? 'Failed to delete account',
        e.response?.statusCode ?? 500,
      );
    }
  }

  Future<Map<String, dynamic>> exportData(String userId) async {
    try {
      final response = await _dio.get('/api/ops/export/$userId');
      return response.data as Map<String, dynamic>? ?? const {};
    } on DioException catch (e) {
      throw ApiException(
        e.message ?? 'Failed to export data',
        e.response?.statusCode ?? 500,
      );
    }
  }

  Future<Map<String, dynamic>> getNotificationPreferences() async {
    try {
      final response = await _dio.get('/api/notifications/preferences');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException(
        e.message ?? 'Failed to get notification preferences',
        e.response?.statusCode ?? 500,
      );
    }
  }

  Future<void> updateNotificationPreferences({
    required bool proactive,
    required bool emotionalFollowup,
    required bool anniversaries,
    required bool absenceCheck,
  }) async {
    try {
      await _dio.patch(
        '/api/notifications/preferences',
        data: {
          'proactive': proactive,
          'emotional_followup': emotionalFollowup,
          'anniversaries': anniversaries,
          'absence_check': absenceCheck,
        },
      );
    } on DioException catch (e) {
      throw ApiException(
        e.message ?? 'Failed to update notification preferences',
        e.response?.statusCode ?? 500,
      );
    }
  }

  Future<void> markRead(String conversationId, int lastMessageId) async {
    try {
      await _dio.post(
        '/api/chat/mark_read',
        data: {
          'conversation_id': conversationId,
          'last_message_id': lastMessageId,
        },
      );
    } on DioException catch (e) {
      throw ApiException(
        e.message ?? 'Failed to mark messages as read',
        e.response?.statusCode ?? 500,
      );
    }
  }

  Future<void> updateTypingStatus(String conversationId, bool isTyping) async {
    try {
      await _dio.post(
        '/api/chat/typing_status',
        data: {
          'conversation_id': conversationId,
          'is_typing': isTyping,
        },
      );
    } on DioException catch (e) {
      throw ApiException(
        e.message ?? 'Failed to update typing status',
        e.response?.statusCode ?? 500,
      );
    }
  }

  // Legacy/Session support aliases
  Future<Session> startSession() async {
    return loadSession();
  }

  Future<List<dynamic>> getConversations() async {
    try {
      final response = await _dio.get('/api/chat/messages');
      final list = response.data as List<dynamic>? ?? const [];
      if (list.isNotEmpty) {
        final convId = list.first['conversation_id'];
        return [
          {'id': convId}
        ];
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }
}

class ApiException implements Exception {
  final String message;
  final int statusCode;

  const ApiException(this.message, this.statusCode);

  @override
  String toString() => 'ApiException($statusCode): $message';
}
