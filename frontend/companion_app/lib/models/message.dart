// ═══════════════════════════════════════════════════════════════════
// FILE: message.dart
// PURPOSE: Message model definition for chat messages.
// CONTEXT: Frontend data models.
// ═══════════════════════════════════════════════════════════════════

// FILE: models/message.dart
// PURPOSE: Chat message model — user or partner, with emotional metadata.

import 'package:isar/isar.dart';

part 'message.g.dart';

enum MessageRole { user, partner }

@collection
class Message {
  Id id;
  
  final String conversationId;
  
  @enumerated
  final MessageRole role;
  
  final String content;
  
  final DateTime sentAt;
  
  final String? emotionalSignal;

  Message({
    required this.id,
    this.conversationId = '',
    required this.role,
    required this.content,
    required this.sentAt,
    this.emotionalSignal,
  });

  bool get isUser => role == MessageRole.user;

  factory Message.fromJson(Map<String, dynamic> json) {
    final roleStr = json['role'] as String? ?? 'partner';
    final role = roleStr == 'user' ? MessageRole.user : MessageRole.partner;
    
    final rawId = json['id'];
    int parsedId = 0;
    if (rawId is int) {
      parsedId = rawId;
    } else if (rawId != null) {
      parsedId = int.tryParse(rawId.toString()) ?? 0;
    }
    
    final rawSentAt = json['sent_at'] ?? json['created_at'];
    final sentAt = rawSentAt != null 
        ? DateTime.parse(rawSentAt.toString()) 
        : DateTime.now();

    return Message(
      id: parsedId,
      conversationId: json['conversation_id'] as String? ?? '',
      role: role,
      content: json['content'] as String? ?? '',
      sentAt: sentAt,
      emotionalSignal: json['emotional_signal'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversation_id': conversationId,
      'role': role.name,
      'content': content,
      'sent_at': sentAt.toIso8601String(),
      'emotional_signal': emotionalSignal,
    };
  }
}
