// ═══════════════════════════════════════════════════════════════════
// FILE: providers/chat_provider_v3.dart
// PURPOSE: Chat state management with burst composition and typing status support.
// RESPONSIBILITIES: Own chat-related frontend state and delegate persistence/network work to services.
// NEVER: Contain widget composition, route registration, or backend contract changes.
// CONTEXT: Replaces chat_provider_v2.dart.
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart';
import '../models/models.dart';
import '../services/local_cache_service.dart';

final localCacheServiceProvider =
    Provider<LocalCacheService>((ref) => LocalCacheService());

final isTypingProvider = StateProvider<bool>((ref) => false);
final streamingTextProvider = StateProvider<String>((ref) => '');

// V2 burst composition streaming states
final isComposingProvider = StateProvider<bool>((ref) => false);
final currentBurstIndexProvider = StateProvider<int>((ref) => 0);
final typingDurationProvider = StateProvider<int?>((ref) => null);
final streamingBurstsProvider =
    StateProvider<List<StreamingBurst>>((ref) => const []);

// V3 user typing and read markers states
final lastSeenMessageIdProvider = StateProvider<int>((ref) => 0);
final isUserTypingProvider = StateProvider<bool>((ref) => false);

class StreamingBurst {
  final String id;
  final String text;
  final String thoughtType;
  final String state; // 'typing' | 'showing'
  final DateTime typingStartedAt;

  const StreamingBurst({
    required this.id,
    required this.text,
    required this.thoughtType,
    required this.state,
    required this.typingStartedAt,
  });

  StreamingBurst copyWith({
    String? id,
    String? text,
    String? thoughtType,
    String? state,
    DateTime? typingStartedAt,
  }) {
    return StreamingBurst(
      id: id ?? this.id,
      text: text ?? this.text,
      thoughtType: thoughtType ?? this.thoughtType,
      state: state ?? this.state,
      typingStartedAt: typingStartedAt ?? this.typingStartedAt,
    );
  }
}

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
    // 1. Optimistically add user message to list
    final userMessageId = DateTime.now().millisecondsSinceEpoch;
    final userMessage = Message(
      id: userMessageId,
      conversationId: conversationId ?? '',
      role: MessageRole.user,
      content: text,
      sentAt: DateTime.now(),
    );
    await addMessage(userMessage);

    // 2. Set states
    _ref.read(isTypingProvider.notifier).state = true;
    _ref.read(isComposingProvider.notifier).state = true;
    _ref.read(streamingTextProvider.notifier).state = '';
    _ref.read(currentBurstIndexProvider.notifier).state = 0;
    _ref.read(typingDurationProvider.notifier).state = null;
    _ref.read(streamingBurstsProvider.notifier).state = const [];

    StreamSubscription<String>? subscription;
    final List<String> accumulatedBursts = [];
    int burstIndex = 0;

    try {
      final apiService = _ref.read(apiServiceProvider);

      // 3. Open SSE stream
      final stream = apiService.sendMessage(conversationId, text);

      final completer = Completer<void>();
      subscription = stream.listen(
        (data) {
          try {
            final jsonMap = jsonDecode(data) as Map<String, dynamic>;
            final type = jsonMap['type'] as String?;

            if (type == 'typing_start') {
              // "typing_start": show typing indicator
              _ref.read(isTypingProvider.notifier).state = true;

              final newBurst = StreamingBurst(
                id: 'typing_$burstIndex',
                text: '',
                thoughtType: 'statement',
                state: 'typing',
                typingStartedAt: DateTime.now(),
              );
              _ref
                  .read(streamingBurstsProvider.notifier)
                  .update((state) => [...state, newBurst]);
            } else if (type == 'burst') {
              // "burst": hide typing, add message burst to list
              _ref.read(isTypingProvider.notifier).state = false;

              final burstText = jsonMap['text'] as String? ?? '';
              final thoughtType =
                  jsonMap['thought_type'] as String? ?? 'statement';
              final typingMs = jsonMap['typing_ms'] as int? ?? 600;

              accumulatedBursts.add(burstText);

              final partnerMessageId =
                  DateTime.now().millisecondsSinceEpoch + burstIndex;
              final partnerMessage = Message(
                id: partnerMessageId,
                conversationId: jsonMap['conversation_id']?.toString() ??
                    conversationId ??
                    '',
                role: MessageRole.partner,
                content: burstText,
                sentAt: DateTime.now(),
                thoughtType: thoughtType,
                isPartOfBurst: true,
                burstIndex: burstIndex,
                burstTotal: null, // set in done
              );

              _ref.read(streamingBurstsProvider.notifier).update((state) {
                return state.map((b) {
                  if (b.id == 'typing_$burstIndex') {
                    return b.copyWith(
                        text: burstText,
                        thoughtType: thoughtType,
                        state: 'showing');
                  }
                  return b;
                }).toList();
              });

              addMessage(partnerMessage);

              _ref.read(currentBurstIndexProvider.notifier).state =
                  burstIndex + 1;
              _ref.read(typingDurationProvider.notifier).state = typingMs;

              burstIndex++;
            } else if (type == 'done') {
              // "done": mark stream complete, save to DB
              final burstCount = jsonMap['burst_count'] as int? ?? burstIndex;

              // Update burstTotal in list
              state = state.map((msg) {
                if (msg.role == MessageRole.partner &&
                    msg.isPartOfBurst &&
                    msg.burstTotal == null) {
                  return Message(
                    id: msg.id,
                    conversationId: msg.conversationId,
                    role: msg.role,
                    content: msg.content,
                    sentAt: msg.sentAt,
                    emotionalSignal: msg.emotionalSignal,
                    thoughtType: msg.thoughtType,
                    isPartOfBurst: msg.isPartOfBurst,
                    burstIndex: msg.burstIndex,
                    burstTotal: burstCount,
                  );
                }
                return msg;
              }).toList();

              final localCache = _ref.read(localCacheServiceProvider);
              localCache.saveMessages(state.take(burstCount + 1).toList());

              completer.complete();
            } else if (type == 'error') {
              final errMsg =
                  jsonMap['message'] as String? ?? 'Error streaming response';
              if (!completer.isCompleted) {
                completer.completeError(Exception(errMsg));
              }
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
      rethrow;
    } finally {
      await subscription?.cancel();
      _ref.read(isTypingProvider.notifier).state = false;
      _ref.read(isComposingProvider.notifier).state = false;
    }
  }
}

final messagesProvider =
    StateNotifierProvider<MessagesNotifier, List<Message>>((ref) {
  return MessagesNotifier(ref);
});
