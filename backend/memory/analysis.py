import logging
import json
import math
from collections import Counter
from memory.store import db, memory_store
from core.llm import get_llm_core

logger = logging.getLogger(__name__)

# Preserve existing emotional definitions and functions for compatibility
EMOTION_VALENCE = {
    "joy": 0.9,
    "excited": 0.8,
    "excitement": 0.8,
    "hopeful": 0.6,
    "pride": 0.7,
    "content": 0.45,
    "playful": 0.35,
    "calm": 0.3,
    "neutral": 0.0,
    "flat": -0.05,
    "numb": -0.35,
    "anxious": -0.6,
    "anxiety": -0.6,
    "sad": -0.75,
    "sadness": -0.75,
    "lonely": -0.7,
    "loneliness": -0.7,
    "angry": -0.7,
    "anger": -0.7,
    "grief": -0.95,
    "overwhelmed": -0.8,
    "stressed": -0.65,
}

DAY_NAMES = {
    0: "Mondays",
    1: "Tuesdays",
    2: "Wednesdays",
    3: "Thursdays",
    4: "Fridays",
    5: "Saturdays",
    6: "Sundays",
}

def emotion_to_valence(emotion: str | None) -> float:
    if not emotion:
        return 0.0
    return EMOTION_VALENCE.get(emotion.strip().lower(), 0.0)

def detect_behavioral_patterns(user_id: str, pair_id: str, companion_id: str) -> list[dict]:
    patterns: list[dict] = []
    patterns.extend(_detect_late_night_openness(pair_id))
    patterns.extend(_detect_recurring_emotional_day(pair_id))
    patterns.extend(_detect_recurring_triggers(pair_id))
    patterns.extend(_detect_volatility(user_id, pair_id))

    for pattern in patterns:
        db.upsert_behavioral_pattern(
            user_id=user_id,
            pair_id=pair_id,
            companion_id=companion_id,
            pattern_type=pattern["pattern_type"],
            description=pattern["description"],
            evidence_count=pattern["evidence_count"],
            confidence=pattern["confidence"],
            source=pattern.get("source", "detector"),
        )
    return patterns

def infer_themes(memories: list[dict], emotions: list[dict]) -> list[str]:
    counter: Counter[str] = Counter()
    for memory in memories:
        title = (memory.get("title") or "").strip()
        if title:
            counter.update(_top_words(title))
        emotion = (memory.get("emotion_tag") or "").strip()
        if emotion:
            counter[emotion] += 1

    for event in emotions:
        for key in ("trigger_entity", "trigger_topic", "emotion"):
            value = (event.get(key) or "").strip()
            if value:
                counter[value.lower()] += 1

    themes = [item for item, _ in counter.most_common(4)]
    return themes[:3]

def emotional_direction_from_events(emotions: list[dict]) -> str:
    if not emotions:
        return "stable"

    values = [float(event.get("valence", 0.0)) for event in reversed(emotions)]
    if len(values) < 4:
        return "stable"

    midpoint = len(values) // 2
    first_half = sum(values[:midpoint]) / max(1, len(values[:midpoint]))
    second_half = sum(values[midpoint:]) / max(1, len(values[midpoint:]))

    if max(values) - min(values) > 0.9:
        return "volatile"
    if second_half - first_half > 0.18:
        return "improving"
    if second_half - first_half < -0.18:
        return "declining"
    return "stable"

def _detect_late_night_openness(pair_id: str) -> list[dict]:
    rows = db.conn.execute(
        """
        SELECT hour_of_day, LENGTH(content) AS length
        FROM messages
        WHERE pair_id = ? AND role = 'user' AND hour_of_day IS NOT NULL
        """,
        (pair_id,),
    ).fetchall()

    if len(rows) < 6:
        return []

    overall_avg = sum(int(row["length"] or 0) for row in rows) / len(rows)
    night_rows = [
        row for row in rows
        if row["hour_of_day"] is not None and (row["hour_of_day"] >= 22 or row["hour_of_day"] <= 2)
    ]

    if len(night_rows) < 3:
        return []

    night_avg = sum(int(row["length"] or 0) for row in night_rows) / len(night_rows)
    if night_avg < overall_avg * 1.15:
        return []

    confidence = min(0.9, 0.45 + (len(night_rows) / max(1, len(rows))) * 0.6)
    return [{
        "pattern_type": "temporal",
        "description": "They tend to open up more in late-night conversations.",
        "evidence_count": len(night_rows),
        "confidence": round(confidence, 3),
    }]

def _detect_recurring_emotional_day(pair_id: str) -> list[dict]:
    row = db.conn.execute(
        """
        SELECT day_of_week, COUNT(*) AS count, AVG(valence) AS avg_valence, AVG(intensity) AS avg_intensity
        FROM emotional_events
        WHERE pair_id = ?
        GROUP BY day_of_week
        HAVING COUNT(*) >= 3
        ORDER BY avg_valence ASC, avg_intensity DESC
        LIMIT 1
        """,
        (pair_id,),
    ).fetchone()

    if not row:
        return []
    if float(row["avg_valence"] or 0.0) > -0.2 or float(row["avg_intensity"] or 0.0) < 0.45:
        return []

    day_name = DAY_NAMES.get(int(row["day_of_week"]), "That day")
    confidence = min(0.88, 0.4 + (int(row["count"]) * 0.08))
    return [{
        "pattern_type": "emotional",
        "description": f"{day_name} tend to carry heavier emotions for them.",
        "evidence_count": int(row["count"]),
        "confidence": round(confidence, 3),
    }]

def _detect_recurring_triggers(pair_id: str) -> list[dict]:
    rows = db.conn.execute(
        """
        SELECT
            COALESCE(NULLIF(trigger_entity, ''), NULLIF(trigger_topic, '')) AS trigger_name,
            CASE
                WHEN trigger_entity IS NOT NULL AND TRIM(trigger_entity) <> '' THEN 'relational'
                ELSE 'topical'
            END AS trigger_type,
            COUNT(*) AS count,
            AVG(intensity) AS avg_intensity,
            AVG(valence) AS avg_valence
        FROM emotional_events
        WHERE pair_id = ?
          AND COALESCE(NULLIF(trigger_entity, ''), NULLIF(trigger_topic, '')) IS NOT NULL
        GROUP BY trigger_name, trigger_type
        HAVING COUNT(*) >= 3
        ORDER BY count DESC, avg_intensity DESC
        LIMIT 2
        """,
        (pair_id,),
    ).fetchall()

    patterns = []
    for row in rows:
        trigger_name = row["trigger_name"]
        avg_intensity = float(row["avg_intensity"] or 0.0)
        avg_valence = float(row["avg_valence"] or 0.0)
        if avg_intensity < 0.45:
            continue

        if row["trigger_type"] == "relational":
            description = f"{trigger_name} repeatedly carries emotional weight in their life."
            pattern_type = "relational"
        elif avg_valence <= -0.2:
            description = f"They keep circling back to {trigger_name} when they are under strain."
            pattern_type = "topical"
        else:
            description = f"{trigger_name} is a recurring theme they return to often."
            pattern_type = "topical"

        confidence = min(0.9, 0.42 + int(row["count"]) * 0.09 + avg_intensity * 0.15)
        patterns.append({
            "pattern_type": pattern_type,
            "description": description,
            "evidence_count": int(row["count"]),
            "confidence": round(confidence, 3),
        })
    return patterns

def _detect_volatility(user_id: str, pair_id: str) -> list[dict]:
    # Use store method or query directly
    events = db.get_recent_emotional_events(user_id=user_id, pair_id=pair_id, limit=8)
    if len(events) < 6:
        return []

    values = [float(event.get("valence", 0.0)) for event in events]
    mean_value = sum(values) / len(values)
    variance = sum((value - mean_value) ** 2 for value in values) / len(values)
    std_dev = math.sqrt(variance)
    avg_intensity = sum(float(event.get("intensity", 0.0)) for event in events) / len(events)

    if std_dev < 0.45 or avg_intensity < 0.45:
        return []

    return [{
        "pattern_type": "emotional",
        "description": "Their emotions have been swinging sharply lately instead of staying steady.",
        "evidence_count": len(events),
        "confidence": round(min(0.92, 0.45 + std_dev * 0.5 + avg_intensity * 0.15), 3),
    }]

def _top_words(text: str) -> list[str]:
    words = [
        word.strip(".,!?;:()[]{}\"'").lower()
        for word in text.split()
    ]
    filtered = [word for word in words if len(word) > 4]
    return filtered[:3]


# New MemoryAnalysis Rebuild implementation
class MemoryAnalysis:
    async def detect_relationship_event(
        self,
        messages: list[dict],
        existing_events: list[dict]
    ) -> dict | None:
        if not messages:
            return None

        # Format conversation text
        conversation_text = ""
        for msg in messages:
            role_label = "User" if msg.get("role") == "user" else "Companion"
            content = msg.get("content") or ""
            conversation_text += f"{role_label}: {content}\n"

        existing_text = ""
        if existing_events:
            existing_text = "\nPreviously detected relationship events:\n"
            for e in existing_events:
                existing_text += f"- [{e.get('event_type')}] {e.get('description')}\n"

        system_prompt = (
            "You are a relationship analysis engine.\n"
            "Analyze the conversation to detect if it contains a significant relationship event or milestone between the user and the companion.\n"
            "Only return an event if your confidence is high (>= 0.8). False positives are worse than misses.\n"
            "Event types:\n"
            "- milestone: a major shift or breakthrough in the relationship\n"
            "- rupture: a conflict, misunderstanding, or distance\n"
            "- repair: resolving a conflict, apologizing, rebuilding trust\n"
            "- deepening: a moment of vulnerability, sharing secrets, or getting significantly closer\n"
            "- first_of_type: first time they talked about family, shared a joke, etc.\n"
            "- anniversary: marking a time milestone"
        )

        output_schema = {
            "type": "object",
            "properties": {
                "event_detected": {
                    "type": "boolean"
                },
                "event_type": {
                    "type": "string",
                    "enum": ["milestone", "rupture", "repair", "deepening", "first_of_type", "anniversary"]
                },
                "description": {
                    "type": "string",
                    "description": "Short, objective, natural description of the event from an observer's perspective."
                },
                "confidence": {
                    "type": "number",
                    "description": "Confidence score from 0.0 to 1.0."
                },
                "trigger_reason": {
                    "type": "string",
                    "description": "The exact reason or text snippet that triggered this detection."
                }
            },
            "required": ["event_detected", "event_type", "description", "confidence", "trigger_reason"]
        }

        try:
            llm = get_llm_core()
            result = await llm.complete_structured(
                system_prompt=system_prompt,
                messages=[{"role": "user", "content": f"Conversation:\n{conversation_text}\n{existing_text}"}],
                output_schema=output_schema,
                temperature=0.2
            )
            
            if result.get("event_detected") and result.get("confidence", 0.0) >= 0.8:
                return {
                    "event_type": result.get("event_type"),
                    "description": result.get("description"),
                    "confidence": result.get("confidence"),
                }
        except Exception as e:
            logger.error("Failed to detect relationship event: %s", e)
        
        return None

    async def compute_relationship_stage(
        self,
        user_id: str,
        current_stage: str
    ) -> str | None:
        try:
            primary = db.get_primary_pair(user_id)
            if not primary:
                return None
            pair_id = primary["id"]

            # Query conversations count
            conv_row = db.conn.execute(
                "SELECT COUNT(*) as count FROM conversations WHERE pair_id = ?",
                (pair_id,)
            ).fetchone()
            conv_count = conv_row["count"] if conv_row else 0

            # Query memories count
            mem_count = await memory_store.count(user_id)

            # Query deepening events count
            deep_row = db.conn.execute(
                "SELECT COUNT(*) as count FROM relationship_events WHERE pair_id = ? AND event_type = 'deepening'",
                (pair_id,)
            ).fetchone()
            deepening_count = deep_row["count"] if deep_row else 0

            # Query repair events count
            repair_row = db.conn.execute(
                "SELECT COUNT(*) as count FROM relationship_events WHERE pair_id = ? AND event_type = 'repair'",
                (pair_id,)
            ).fetchone()
            repair_count = repair_row["count"] if repair_row else 0

            # Stages and transition logic:
            # new → familiar: 10+ conversations, 20+ memories
            # familiar → close: 30+ conversations, 50+ memories, at least 1 deepening event
            # close → intimate: 70+ conversations, 100+ memories, at least 3 deepening events, at least 1 repair event
            stage = current_stage.lower()

            if stage == "new":
                if conv_count >= 10 and mem_count >= 20:
                    return "familiar"
            elif stage == "familiar":
                if conv_count >= 30 and mem_count >= 50 and deepening_count >= 1:
                    return "close"
            elif stage == "close":
                if conv_count >= 70 and mem_count >= 100 and deepening_count >= 3 and repair_count >= 1:
                    return "intimate"

            return None
        except Exception as e:
            logger.error("Failed to compute relationship stage: %s", e, exc_info=True)
            return None
