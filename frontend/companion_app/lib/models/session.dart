// FILE: models/session.dart
// PURPOSE: Session bootstrap payload returned on app open.

import 'message.dart';
import 'partner.dart';

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
    final rawSentAt = json['sent_at'] ?? json['delivered_at'] ?? json['scheduled_for'] ?? json['created_at'];
    final sentAt = rawSentAt != null 
        ? DateTime.parse(rawSentAt.toString()) 
        : DateTime.now();

    return ProactiveMessage(
      id: json['id']?.toString() ?? '',
      message: json['message'] as String? ?? json['message_text'] as String? ?? '',
      triggerType: json['trigger_type'] as String? ?? json['reason'] as String? ?? 'general',
      sentAt: sentAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'message': message,
      'trigger_type': triggerType,
      'sent_at': sentAt.toIso8601String(),
    };
  }
}

class Session {
  final Partner partner;
  final String conversationId;
  final List<Message> recentMessages;
  final List<ProactiveMessage> unreadProactive;
  final int memoryCount;
  final int daysTogether;
  final DateTime? lastSeen;

  const Session({
    required this.partner,
    required this.conversationId,
    required this.recentMessages,
    required this.unreadProactive,
    required this.memoryCount,
    required this.daysTogether,
    this.lastSeen,
  });

  factory Session.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['recent_messages'];
    List<Message> messages = [];
    if (rawMessages is List) {
      messages = rawMessages.map((e) => Message.fromJson(e as Map<String, dynamic>)).toList();
    }

    final rawProactive = json['unread_proactive'];
    List<ProactiveMessage> proactive = [];
    if (rawProactive is List) {
      proactive = rawProactive.map((e) => ProactiveMessage.fromJson(e as Map<String, dynamic>)).toList();
    }

    final rawLastSeen = json['last_seen'];
    final lastSeen = rawLastSeen != null 
        ? DateTime.parse(rawLastSeen.toString()) 
        : null;

    return Session(
      partner: Partner.fromJson(json['partner'] as Map<String, dynamic>? ?? const {}),
      conversationId: json['conversation_id'] as String? ?? '',
      recentMessages: messages,
      unreadProactive: proactive,
      memoryCount: json['memory_count'] as int? ?? json['memories_count'] as int? ?? 0,
      daysTogether: json['days_together'] as int? ?? 0,
      lastSeen: lastSeen,
    );
  }

  List<ProactiveMessage> get pendingProactive => unreadProactive;

  Map<String, dynamic> toJson() {
    return {
      'partner': partner.toJson(),
      'conversation_id': conversationId,
      'recent_messages': recentMessages.map((e) => e.toJson()).toList(),
      'unread_proactive': unreadProactive.map((e) => e.toJson()).toList(),
      'memory_count': memoryCount,
      'days_together': daysTogether,
      'last_seen': lastSeen?.toIso8601String(),
    };
  }
}

typedef SessionData = Session;
