// ═══════════════════════════════════════════════════════════════════
// FILE: models/message_v2.dart
// PURPOSE: Message model updated with burst metadata.
// RESPONSIBILITIES: Represent chat message data and local serialization metadata.
// NEVER: Contain widget rendering, route logic, or API transport code.
// CONTEXT: Replaces message.dart to track burst composition.
// ═══════════════════════════════════════════════════════════════════

import 'package:isar/isar.dart';

part 'message_v2.g.dart';

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

  // New fields for burst composition support
  final String? thoughtType;
  final bool isPartOfBurst;
  final int? burstIndex;
  final int? burstTotal;

  Message({
    required this.id,
    this.conversationId = '',
    required this.role,
    required this.content,
    required this.sentAt,
    this.emotionalSignal,
    this.thoughtType,
    this.isPartOfBurst = false,
    this.burstIndex,
    this.burstTotal,
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
      thoughtType: json['thought_type'] as String?,
      isPartOfBurst: json['is_part_of_burst'] as bool? ?? false,
      burstIndex: json['burst_index'] as int?,
      burstTotal: json['burst_total'] as int?,
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
      'thought_type': thoughtType,
      'is_part_of_burst': isPartOfBurst,
      'burst_index': burstIndex,
      'burst_total': burstTotal,
    };
  }
}
