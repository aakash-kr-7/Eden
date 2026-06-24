// FILE: models/partner.dart  
// PURPOSE: Partner data model — name, stage, current mood, energy.

enum RelationshipStage {
  newStage,
  familiar,
  close,
  intimate,
}

class Partner {
  final String id;
  final String name;
  final RelationshipStage relationshipStage;
  final int intimacyTier;
  final String? currentMood;
  final String? currentEnergy;
  final int daysTogether;
  final List<String> insideJokes;

  const Partner({
    required this.id,
    required this.name,
    required this.relationshipStage,
    required this.intimacyTier,
    this.currentMood,
    this.currentEnergy,
    required this.daysTogether,
    required this.insideJokes,
  });

  factory Partner.fromJson(Map<String, dynamic> json) {
    final stageStr = (json['relationship_stage'] ?? json['stage'] ?? 'new').toString().toLowerCase();
    RelationshipStage stage;
    if (stageStr == 'new') {
      stage = RelationshipStage.newStage;
    } else if (stageStr == 'warming' || stageStr == 'familiar' || stageStr == 'settled') {
      stage = RelationshipStage.familiar;
    } else if (stageStr == 'close') {
      stage = RelationshipStage.close;
    } else if (stageStr == 'intimate' || stageStr == 'bonded') {
      stage = RelationshipStage.intimate;
    } else {
      stage = RelationshipStage.newStage;
    }

    final rawJokes = json['inside_jokes'];
    List<String> jokes = [];
    if (rawJokes is List) {
      jokes = rawJokes.map((e) => e.toString()).toList();
    }

    return Partner(
      id: json['id']?.toString() ?? json['companion_id']?.toString() ?? '',
      name: json['name'] as String? ?? 'Partner',
      relationshipStage: stage,
      intimacyTier: json['intimacy_tier'] as int? ?? 1,
      currentMood: json['current_mood'] as String?,
      currentEnergy: json['current_energy'] as String?,
      daysTogether: json['days_together'] as int? ?? 0,
      insideJokes: jokes,
    );
  }

  Map<String, dynamic> toJson() {
    String stageStr;
    switch (relationshipStage) {
      case RelationshipStage.newStage:
        stageStr = 'new';
        break;
      case RelationshipStage.familiar:
        stageStr = 'familiar';
        break;
      case RelationshipStage.close:
        stageStr = 'close';
        break;
      case RelationshipStage.intimate:
        stageStr = 'intimate';
        break;
    }

    return {
      'id': id,
      'name': name,
      'relationship_stage': stageStr,
      'intimacy_tier': intimacyTier,
      'current_mood': currentMood,
      'current_energy': currentEnergy,
      'days_together': daysTogether,
      'inside_jokes': insideJokes,
    };
  }
}
