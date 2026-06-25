// ═══════════════════════════════════════════════════════════════════
// FILE: chat_provider.dart
// PURPOSE: Riverpod provider managing chat streaming and message list.
// CONTEXT: Frontend state providers.
// ═══════════════════════════════════════════════════════════════════

// FILE: providers/chat_provider.dart
// PURPOSE: Chat state — messages, streaming status, typing indicator.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart';
import '../models/models.dart';
import '../services/local_cache_service.dart';

final localCacheServiceProvider = Provider<LocalCacheService>((ref) => LocalCacheService());

final isTypingProvider = StateProvider<bool>((ref) => false);
final streamingTextProvider = StateProvider<String>((ref) => '');

class MessagesNotifier extends StateNotifier<List<Message>> {
  final Ref _ref;

  MessagesNotifier(this._ref) : super(const []);

  void setMessages(List<Message> messages) {
    state = messages;
  }

  Future<void> loadFromCache() async {
    try {
      final localCache = _ref.read(localCacheServiceProvider);
      final cached = await localCache.getRecentMessages();
      if (cached.isNotEmpty) {
        state = cached;
      }
    } catch (e) {
      debugPrint('Error loading from cache: $e');
    }
  }

  Future<void> loadFromBackend({int? limit}) async {
    try {
      final apiService = _ref.read(apiServiceProvider);
      final messages = await apiService.getMessages(null, limit: limit ?? 50);
      state = messages;

      final localCache = _ref.read(localCacheServiceProvider);
      await localCache.saveMessages(messages);
    } catch (e) {
      debugPrint('Error loading from backend: $e');
    }
  }

  Future<void> addMessage(Message message) async {
    state = [message, ...state];
    final localCache = _ref.read(localCacheServiceProvider);
    await localCache.saveMessages([message]);
  }

  Future<void> sendMessage(String? conversationId, String text) async {
    // 1. Optimistically add user message to list & cache
    final userMessageId = DateTime.now().millisecondsSinceEpoch;
    final userMessage = Message(
      id: userMessageId,
      conversationId: conversationId ?? '',
      role: MessageRole.user,
      content: text,
      sentAt: DateTime.now(),
    );
    await addMessage(userMessage);

    // 2. Set isTyping = true
    _ref.read(isTypingProvider.notifier).state = true;
    _ref.read(streamingTextProvider.notifier).state = '';

    StreamSubscription<String>? subscription;
    try {
      final apiService = _ref.read(apiServiceProvider);
      
      // 3. Open SSE stream from api_service
      final stream = apiService.sendMessage(conversationId, text);

      final completer = Completer<void>();
      subscription = stream.listen(
        (data) {
          try {
            final jsonMap = jsonDecode(data) as Map<String, dynamic>;
            final type = jsonMap['type'] as String?;
            if (type == 'token') {
              // 4. For each token: append to streamingTextProvider
              final tokenText = jsonMap['text'] as String? ?? '';
              _ref.read(streamingTextProvider.notifier).state += tokenText;
            } else if (type == 'done') {
              // 5. On 'done': create Message object, add to list, save to cache
              final fullText = jsonMap['full_text'] as String? ?? '';
              final partnerMessageId = DateTime.now().millisecondsSinceEpoch + 1;
              final partnerMessage = Message(
                id: partnerMessageId,
                conversationId: jsonMap['conversation_id']?.toString() ?? conversationId ?? '',
                role: MessageRole.partner,
                content: fullText,
                sentAt: DateTime.now(),
                emotionalSignal: jsonMap['emotional_signal'] as String?,
              );
              
              // Add to state and save to cache
              addMessage(partnerMessage);
              
              // Clear streaming state
              _ref.read(streamingTextProvider.notifier).state = '';
              completer.complete();
            }
          } catch (e) {
            debugPrint('Error parsing stream chunk: $e');
          }
        },
        onError: (err) {
          debugPrint('Error in SSE stream: $err');
          if (!completer.isCompleted) completer.completeError(err);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
      );

      await completer.future;
    } catch (e) {
      debugPrint('Error in sendMessage: $e');
    } finally {
      await subscription?.cancel();
      // 6. Set isTyping = false
      _ref.read(isTypingProvider.notifier).state = false;
    }
  }
}

final messagesProvider = StateNotifierProvider<MessagesNotifier, List<Message>>((ref) {
  return MessagesNotifier(ref);
});
