import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/models.dart';
import 'auth_service.dart';

class ApiConfig {
  static const String _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  static String get baseUrl {
    final raw = _baseUrl.trim();
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return raw;
    }
    return 'http://$raw';
  }
}

class ApiService {
  final AuthService _authService;
  final String _baseUrl;

  ApiService(this._authService, {String? baseUrl}) 
      : _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  // --- Exponential Backoff Retry for 5xx Server Errors ---
  Future<http.Response> _requestWithRetry(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
    final token = await _authService.getIdToken();
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    int attempt = 0;
    while (true) {
      try {
        http.Response response;
        if (method == 'POST') {
          response = await http.post(uri, headers: headers, body: body != null ? jsonEncode(body) : null);
        } else if (method == 'GET') {
          response = await http.get(uri, headers: headers);
        } else if (method == 'PATCH') {
          response = await http.patch(uri, headers: headers, body: body != null ? jsonEncode(body) : null);
        } else if (method == 'DELETE') {
          response = await http.delete(uri, headers: headers);
        } else {
          throw UnsupportedError('Unsupported HTTP method $method');
        }

        if (response.statusCode >= 500 && response.statusCode < 600) {
          if (attempt < 3) {
            attempt++;
            final backoffMs = 1000 * (1 << attempt);
            await Future.delayed(Duration(milliseconds: backoffMs));
            continue;
          }
        }
        return response;
      } catch (e) {
        if (attempt < 3) {
          attempt++;
          final backoffMs = 1000 * (1 << attempt);
          await Future.delayed(Duration(milliseconds: backoffMs));
          continue;
        }
        rethrow;
      }
    }
  }

  // --- API Methods ---

  Future<SessionData> startSession() async {
    final response = await _requestWithRetry('POST', '/api/chat/session/start');
    if (response.statusCode != 200) {
      throw ApiException('Failed to start session: ${response.body}', response.statusCode);
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return SessionData.fromJson(data);
  }

  Future<List<dynamic>> getConversations() async {
    final response = await _requestWithRetry('GET', '/api/chat/conversations');
    if (response.statusCode != 200) {
      throw ApiException('Failed to get conversations: ${response.body}', response.statusCode);
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  Future<MessageResponse> sendMessage(String? conversationId, String message) async {
    final response = await _requestWithRetry(
      'POST', 
      '/api/chat/message', 
      body: {
        'message': message,
        if (conversationId != null) 'conversation_id': conversationId,
      },
    );
    if (response.statusCode != 200) {
      throw ApiException('Failed to send message: ${response.body}', response.statusCode);
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    
    // Convert backend {"response": ..., "conversation_id": ..., "partner_mood": ...}
    // into the required MessageResponse model structure.
    final reply = data['response'] as String? ?? '';
    return MessageResponse(
      reply: reply,
      bursts: [
        ChatBurst(
          text: reply,
          preBurstDelayMs: 600,
          typingDurationMs: (reply.length * 20).clamp(800, 2500),
          pauseIntensity: 'medium',
          isFollowUp: false,
        )
      ],
      conversationId: data['conversation_id'] as String? ?? '',
      memoryCount: 0,
      pairId: '',
      companionId: '',
      companionName: '',
    );
  }

  Future<List<Message>> getMessages(String conversationId, {String? beforeId, int? limit}) async {
    final Map<String, String> queryParams = {};
    if (beforeId != null) queryParams['before_id'] = beforeId;
    if (limit != null) queryParams['limit'] = limit.toString();

    final queryString = queryParams.isNotEmpty 
        ? '?${Uri(queryParameters: queryParams).query}' 
        : '';
        
    final response = await _requestWithRetry(
      'GET', 
      '/api/chat/conversations/$conversationId/messages$queryString',
    );
    if (response.statusCode != 200) {
      throw ApiException('Failed to get messages: ${response.body}', response.statusCode);
    }
    final data = jsonDecode(response.body) as List<dynamic>;
    return data.map((e) => Message.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<RelationshipSummary> getRelationshipSummary() async {
    final response = await _requestWithRetry('GET', '/api/profile/relationship');
    if (response.statusCode != 200) {
      throw ApiException('Failed to get relationship summary: ${response.body}', response.statusCode);
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return RelationshipSummary.fromJson(data);
  }

  Future<List<Memory>> getMemories({String? type, String? sort}) async {
    final Map<String, String> queryParams = {};
    if (type != null) queryParams['type'] = type;
    if (sort != null) queryParams['sort'] = sort;

    final queryString = queryParams.isNotEmpty 
        ? '?${Uri(queryParameters: queryParams).query}' 
        : '';

    final response = await _requestWithRetry('GET', '/api/profile/memories$queryString');
    if (response.statusCode != 200) {
      throw ApiException('Failed to get memories: ${response.body}', response.statusCode);
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final memoriesList = data['memories'] as List<dynamic>? ?? [];
    return memoriesList.map((e) => Memory.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> pinMemory(String memoryId) async {
    final response = await _requestWithRetry('POST', '/api/profile/memories/$memoryId/pin');
    if (response.statusCode != 200) {
      throw ApiException('Failed to pin memory: ${response.body}', response.statusCode);
    }
  }

  Future<void> deleteMemory(String memoryId) async {
    final response = await _requestWithRetry('DELETE', '/api/profile/memories/$memoryId');
    if (response.statusCode != 200) {
      throw ApiException('Failed to delete memory: ${response.body}', response.statusCode);
    }
  }

  Future<List<ProactiveMessage>> getPendingProactive() async {
    final response = await _requestWithRetry('GET', '/api/proactive/pending');
    if (response.statusCode != 200) {
      throw ApiException('Failed to get pending proactive messages: ${response.body}', response.statusCode);
    }
    final data = jsonDecode(response.body) as List<dynamic>;
    return data.map((e) => ProactiveMessage.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> acknowledgeProactive(String messageId) async {
    final response = await _requestWithRetry('POST', '/api/proactive/acknowledge/$messageId');
    if (response.statusCode != 200) {
      throw ApiException('Failed to acknowledge message: ${response.body}', response.statusCode);
    }
  }

  Future<OnboardingStepResult> startOnboarding() async {
    final response = await _requestWithRetry('POST', '/api/onboarding/start');
    if (response.statusCode != 200) {
      throw ApiException('Failed to start onboarding: ${response.body}', response.statusCode);
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return OnboardingStepResult(
      nextStep: data['step']?.toString(),
      question: data['question'] as String?,
      isComplete: false,
    );
  }

  Future<OnboardingStepResult> checkOnboardingStatus() async {
    final response = await _requestWithRetry('GET', '/api/onboarding/status');
    if (response.statusCode != 200) {
      throw ApiException('Failed to check onboarding status: ${response.body}', response.statusCode);
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return OnboardingStepResult(
      isComplete: data['complete'] as bool? ?? false,
      nextStep: data['current_step']?.toString(),
    );
  }

  Future<OnboardingStepResult> completeOnboardingStep(int step, dynamic response) async {
    final res = await _requestWithRetry(
      'POST', 
      '/api/onboarding/respond', 
      body: {
        'step': step,
        'response': response,
      },
    );
    if (res.statusCode != 200) {
      throw ApiException('Failed to complete onboarding step: ${res.body}', res.statusCode);
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return OnboardingStepResult(
      nextStep: data['step']?.toString(),
      question: data['question'] as String?,
      isComplete: data['complete'] as bool? ?? false,
    );
  }

  Future<OnboardingCompleteResult> completeOnboarding() async {
    // 1. Mark onboarding complete in backend
    final res = await _requestWithRetry('POST', '/api/onboarding/complete');
    if (res.statusCode != 200) {
      throw ApiException('Failed to complete onboarding: ${res.body}', res.statusCode);
    }
    final resData = jsonDecode(res.body) as Map<String, dynamic>;
    final firstMessage = resData['first_message'] as String? ?? 'hey. you actually showed up.';

    // 2. Fetch primary pair / active session info to populate OnboardingCompleteResult
    try {
      final sessionResponse = await _requestWithRetry('POST', '/api/chat/session/start');
      if (sessionResponse.statusCode == 200) {
        final sessionData = jsonDecode(sessionResponse.body) as Map<String, dynamic>;
        // Use loaded session details to return a complete onboarding result
        return OnboardingCompleteResult(
          companionId: sessionData['companion_id']?.toString() ?? '',
          companionName: sessionData['companion_name']?.toString() ?? resData['partner_name']?.toString() ?? '',
          companionSummary: sessionData['companion_summary']?.toString() ?? '',
          humanizingDetails: (sessionData['humanizing_details'] as List<dynamic>? ?? const [])
              .map((e) => e.toString())
              .toList(),
          conversationalVibe: sessionData['conversational_vibe']?.toString() ?? '',
          openingLine: firstMessage,
          pairId: sessionData['pair_id']?.toString() ?? '',
        );
      }
    } catch (e) {
      debugPrint('Failed to load session details during onboarding completion: $e');
    }

    // Fallback if session loader fails
    return OnboardingCompleteResult(
      companionId: 'companion',
      companionName: resData['partner_name']?.toString() ?? 'Companion',
      companionSummary: '',
      humanizingDetails: const [],
      conversationalVibe: '',
      openingLine: firstMessage,
      pairId: '',
    );
  }
  
  Future<void> registerDeviceToken({
    required String platform,
    required String pushToken,
  }) async {
    final response = await _requestWithRetry(
      'POST', 
      '/api/me/device-token', 
      body: {
        'platform': platform,
        'push_token': pushToken,
      },
    );
    if (response.statusCode != 200) {
      throw ApiException('Failed to register device token: ${response.body}', response.statusCode);
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
