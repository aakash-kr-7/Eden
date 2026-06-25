// ═══════════════════════════════════════════════════════════════════
// FILE: models.dart
// PURPOSE: Aggregated exports for Eden data models.
// CONTEXT: Frontend data models.
// ═══════════════════════════════════════════════════════════════════

export 'message.dart';
export 'partner.dart';
export 'session.dart';
export 'memory.dart';
export 'onboarding.dart';

// --- ChatBurst Model (For typing & delay animation support) ---
class ChatBurst {
  final String text;
  final int preBurstDelayMs;
  final int typingDurationMs;
  final String pauseIntensity;
  final bool isFollowUp;

  const ChatBurst({
    required this.text,
    required this.preBurstDelayMs,
    required this.typingDurationMs,
    required this.pauseIntensity,
    required this.isFollowUp,
  });

  factory ChatBurst.fromJson(Map<String, dynamic> json) {
    return ChatBurst(
      text: json['text'] as String? ?? '',
      preBurstDelayMs: json['pre_burst_delay_ms'] as int? ?? 800,
      typingDurationMs: json['typing_duration_ms'] as int? ?? 1200,
      pauseIntensity: json['pause_intensity'] as String? ?? 'medium',
      isFollowUp: json['is_follow_up'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'pre_burst_delay_ms': preBurstDelayMs,
      'typing_duration_ms': typingDurationMs,
      'pause_intensity': pauseIntensity,
      'is_follow_up': isFollowUp,
    };
  }
}

// --- MessageResponse Model (API sendMessage response) ---
class MessageResponse {
  final String reply;
  final List<ChatBurst> bursts;
  final String conversationId;
  final int memoryCount;
  final String pairId;
  final String companionId;
  final String companionName;

  const MessageResponse({
    required this.reply,
    required this.bursts,
    required this.conversationId,
    required this.memoryCount,
    required this.pairId,
    required this.companionId,
    required this.companionName,
  });

  factory MessageResponse.fromJson(Map<String, dynamic> json) {
    final burstsData = json['bursts'] as List<dynamic>? ?? const [];
    final bursts = burstsData.map((e) => ChatBurst.fromJson(e as Map<String, dynamic>)).toList();
    return MessageResponse(
      reply: json['reply'] as String? ?? '',
      bursts: bursts,
      conversationId: json['conversation_id'] as String? ?? '',
      memoryCount: json['memory_count'] as int? ?? 0,
      pairId: json['pair_id'] as String? ?? '',
      companionId: json['companion_id'] as String? ?? '',
      companionName: json['companion_name'] as String? ?? '',
    );
  }
}

// --- Legacy RelationshipSummary Model if referenced in widgets ---
class RelationshipSummary {
  final String stage;
  final int daysTogether;
  final int totalConversations;
  final int totalMemories;
  final double closenessScore;
  final double trustScore;

  const RelationshipSummary({
    required this.stage,
    required this.daysTogether,
    required this.totalConversations,
    required this.totalMemories,
    required this.closenessScore,
    required this.trustScore,
  });

  factory RelationshipSummary.fromJson(Map<String, dynamic> json) {
    return RelationshipSummary(
      stage: json['stage'] as String? ?? 'new',
      daysTogether: json['days_together'] as int? ?? 0,
      totalConversations: json['total_conversations'] as int? ?? 0,
      totalMemories: json['total_memories'] as int? ?? 0,
      closenessScore: (json['closeness_score'] as num?)?.toDouble() ?? 0.0,
      trustScore: (json['trust_score'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
