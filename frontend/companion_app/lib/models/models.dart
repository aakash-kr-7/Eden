import 'dart:convert';
import 'package:flutter/foundation.dart';

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

// --- Message Model ---
class Message {
  final String id;
  final String role; // 'user' or 'assistant'
  final String content;
  final DateTime sentAt;
  final String? emotionalSignal;

  const Message({
    required this.id,
    required this.role,
    required this.content,
    required this.sentAt,
    this.emotionalSignal,
  });

  bool get isUser => role == 'user';

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id']?.toString() ?? UniqueKey().toString(),
      role: json['role'] as String? ?? 'assistant',
      content: json['content'] as String? ?? '',
      sentAt: json['sent_at'] != null 
          ? DateTime.parse(json['sent_at'] as String) 
          : (json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : DateTime.now()),
      emotionalSignal: json['emotional_signal'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role,
      'content': content,
      'sent_at': sentAt.toIso8601String(),
      'emotional_signal': emotionalSignal,
    };
  }
}

// --- Partner Model ---
class Partner {
  final String name;
  final String relationshipStage;
  final String? currentMood;
  final String? currentEnergy;

  const Partner({
    required this.name,
    required this.relationshipStage,
    this.currentMood,
    this.currentEnergy,
  });

  factory Partner.fromJson(Map<String, dynamic> json) {
    return Partner(
      name: json['name'] as String? ?? 'Companion',
      relationshipStage: json['relationship_stage'] as String? ?? 'new',
      currentMood: json['current_mood'] as String?,
      currentEnergy: json['current_energy'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'relationship_stage': relationshipStage,
      'current_mood': currentMood,
      'current_energy': currentEnergy,
    };
  }
}

// --- SessionData Model ---
class SessionData {
  final Partner partner;
  final String? lastSummary;
  final int unreadProactive;
  final int memoriesCount;
  final int daysTogether;
  final DateTime? lastSeen;

  const SessionData({
    required this.partner,
    this.lastSummary,
    required this.unreadProactive,
    required this.memoriesCount,
    required this.daysTogether,
    this.lastSeen,
  });

  factory SessionData.fromJson(Map<String, dynamic> json) {
    return SessionData(
      partner: Partner.fromJson(json['partner'] as Map<String, dynamic>? ?? const {}),
      lastSummary: json['last_summary'] as String?,
      unreadProactive: json['unread_proactive'] as int? ?? 0,
      memoriesCount: json['memories_count'] as int? ?? 0,
      daysTogether: json['days_together'] as int? ?? 0,
      lastSeen: json['last_seen'] != null ? DateTime.parse(json['last_seen'] as String) : null,
    );
  }
}

// --- Memory Model ---
class Memory {
  final String id;
  final String content;
  final String memoryType;
  final double salience;
  final double emotionalValence;
  final List<String> tags;
  final bool isPhysical;
  final DateTime createdAt;

  const Memory({
    required this.id,
    required this.content,
    required this.memoryType,
    required this.salience,
    required this.emotionalValence,
    required this.tags,
    required this.isPhysical,
    required this.createdAt,
  });

  factory Memory.fromJson(Map<String, dynamic> json) {
    var rawTags = json['tags'];
    List<String> parsedTags = [];
    if (rawTags is List) {
      parsedTags = rawTags.map((e) => e.toString()).toList();
    } else if (rawTags is String) {
      try {
        final decoded = jsonDecode(rawTags);
        if (decoded is List) {
          parsedTags = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }

    return Memory(
      id: json['id']?.toString() ?? json['chroma_id']?.toString() ?? '',
      content: json['content'] as String? ?? '',
      memoryType: json['memory_type'] as String? ?? 'general',
      salience: (json['salience'] as num?)?.toDouble() ?? 0.0,
      emotionalValence: (json['emotional_valence'] as num?)?.toDouble() ?? 0.0,
      tags: parsedTags,
      isPhysical: json['is_physical'] == 1 || json['is_physical'] == true,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'] as String) 
          : DateTime.now(),
    );
  }
}

// --- RelationshipSummary Model ---
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

// --- ProactiveMessage Model ---
class ProactiveMessage {
  final String id;
  final String message;
  final String triggerType;
  final DateTime sentAt;

  const ProactiveMessage({
    required this.id,
    required this.message,
    required this.triggerType,
    required this.sentAt,
  });

  factory ProactiveMessage.fromJson(Map<String, dynamic> json) {
    return ProactiveMessage(
      id: json['id'] as String? ?? '',
      message: json['message'] as String? ?? '',
      triggerType: json['trigger_type'] as String? ?? 'general',
      sentAt: json['sent_at'] != null ? DateTime.parse(json['sent_at'] as String) : DateTime.now(),
    );
  }
}

// --- OnboardingStepResult Model ---
class OnboardingStepResult {
  final String? nextStep;
  final String? question;
  final bool isComplete;
  final String? type;
  final List<String>? options;

  const OnboardingStepResult({
    this.nextStep,
    this.question,
    required this.isComplete,
    this.type,
    this.options,
  });

  factory OnboardingStepResult.fromJson(Map<String, dynamic> json) {
    return OnboardingStepResult(
      nextStep: json['next_step']?.toString() ?? json['step']?.toString(),
      question: json['question'] as String?,
      isComplete: json['is_complete'] as bool? ?? json['complete'] as bool? ?? false,
      type: json['type'] as String?,
      options: (json['options'] as List<dynamic>?)?.map((e) => e.toString()).toList(),
    );
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

// --- OnboardingCompleteResult Model ---
class OnboardingCompleteResult {
  final String companionId;
  final String companionName;
  final String companionSummary;
  final List<String> humanizingDetails;
  final String conversationalVibe;
  final String openingLine;
  final String pairId;

  const OnboardingCompleteResult({
    required this.companionId,
    required this.companionName,
    required this.companionSummary,
    required this.humanizingDetails,
    required this.conversationalVibe,
    required this.openingLine,
    required this.pairId,
  });

  factory OnboardingCompleteResult.fromJson(Map<String, dynamic> json) {
    return OnboardingCompleteResult(
      companionId: json['companion_id'] as String? ?? '',
      companionName: json['companion_name'] as String? ?? '',
      companionSummary: json['companion_summary'] as String? ?? '',
      humanizingDetails: (json['humanizing_details'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      conversationalVibe: json['conversational_vibe'] as String? ?? '',
      openingLine: json['opening_line'] as String? ?? '',
      pairId: json['pair_id'] as String? ?? '',
    );
  }
}
