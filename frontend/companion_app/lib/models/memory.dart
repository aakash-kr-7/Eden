// FILE: models/memory.dart
// PURPOSE: Episodic memory model for the memory vault.

enum MemoryType {
  general,
  emotional,
  behavioral,
  fact,
  entity,
  onboarding,
}

class Memory {
  final int id;
  final String memoryText;
  final MemoryType memoryType;
  final double salienceScore;
  final String? emotionalValence;
  final bool isPinned;
  final int recallCount;
  final List<String> tags;
  final DateTime createdAt;

  // Backwards compatibility fields/getters
  String get content => memoryText;
  double get salience => salienceScore;
  bool get isPhysical => false;

  const Memory({
    required this.id,
    String? memoryText,
    String? content,
    required this.memoryType,
    double? salienceScore,
    double? salience,
    this.emotionalValence,
    this.isPinned = false,
    this.recallCount = 0,
    required this.tags,
    required this.createdAt,
    bool? isPhysical,
  })  : memoryText = memoryText ?? content ?? '',
        salienceScore = salienceScore ?? salience ?? 0.5;

  factory Memory.fromJson(Map<String, dynamic> json) {
    final typeStr = (json['memory_type'] ?? 'general').toString().toLowerCase();
    MemoryType type;
    switch (typeStr) {
      case 'general':
        type = MemoryType.general;
        break;
      case 'emotional':
        type = MemoryType.emotional;
        break;
      case 'behavioral':
        type = MemoryType.behavioral;
        break;
      case 'fact':
        type = MemoryType.fact;
        break;
      case 'entity':
        type = MemoryType.entity;
        break;
      case 'onboarding':
        type = MemoryType.onboarding;
        break;
      default:
        type = MemoryType.general;
    }

    final rawId = json['id'];
    int parsedId = 0;
    if (rawId is int) {
      parsedId = rawId;
    } else if (rawId != null) {
      parsedId = int.tryParse(rawId.toString()) ?? 0;
    }

    final rawTags = json['tags'];
    List<String> parsedTags = [];
    if (rawTags is List) {
      parsedTags = rawTags.map((e) => e.toString()).toList();
    }

    final rawCreatedAt = json['created_at'];
    final createdAt = rawCreatedAt != null 
        ? DateTime.parse(rawCreatedAt.toString()) 
        : DateTime.now();

    final isPinnedIntOrBool = json['is_pinned'];
    final isPinned = isPinnedIntOrBool == 1 || isPinnedIntOrBool == true;

    return Memory(
      id: parsedId,
      memoryText: json['memory_text'] as String? ?? json['content'] as String? ?? '',
      memoryType: type,
      salienceScore: (json['salience_score'] as num?)?.toDouble() ?? (json['salience'] as num?)?.toDouble() ?? 0.5,
      emotionalValence: json['emotional_valence'] as String?,
      isPinned: isPinned,
      recallCount: json['recall_count'] as int? ?? 0,
      tags: parsedTags,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'memory_text': memoryText,
      'memory_type': memoryType.name,
      'salience_score': salienceScore,
      'emotional_valence': emotionalValence,
      'is_pinned': isPinned ? 1 : 0,
      'recall_count': recallCount,
      'tags': tags,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
