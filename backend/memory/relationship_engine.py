import re
import json
import logging
from datetime import datetime, timedelta
from typing import Optional, Any

from memory.store import db, memory_store
from config import settings
from core.llm import get_llm_core

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Compatibility Functions from original relationship_engine.py
# ---------------------------------------------------------------------------

DISCLOSURE_PATTERNS = [
    r"\bi feel\b",
    r"\bi felt\b",
    r"\bi'm\b",
    r"\bi am\b",
    r"\bi've been\b",
    r"\bi have been\b",
    r"\bi need\b",
    r"\bi want\b",
    r"\bi miss\b",
    r"\bi'm scared\b",
    r"\bi am scared\b",
]

EMOTION_PATTERNS = [
    r"\bsad\b",
    r"\banxious\b",
    r"\boverwhelmed\b",
    r"\blonely\b",
    r"\bangry\b",
    r"\bexcited\b",
    r"\bhopeful\b",
    r"\bproud\b",
    r"\bgrief\b",
]

QUESTION_PATTERNS = [
    r"\bhow did\b",
    r"\bwhat happened\b",
    r"\bare you\b",
    r"\bwhat do you think\b",
]

def _parse_ts(value: Optional[str]) -> Optional[datetime]:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value)
    except ValueError:
        return None

def _pattern_hits(text: str, patterns: list[str]) -> int:
    return sum(1 for pattern in patterns if re.search(pattern, text))

def _recent_vulnerability(emotions: list[dict], patterns: list[dict]) -> bool:
    strong_emotion = any(
        float(event.get("intensity") or 0.0) >= 0.65 and float(event.get("valence") or 0.0) <= -0.25
        for event in emotions
    )
    expressive_pattern = any(
        "open up" in (pattern.get("description") or "").lower()
        or "vulnerab" in (pattern.get("description") or "").lower()
        for pattern in patterns
    )
    return strong_emotion or expressive_pattern

def _topic_overlap_score(messages: list[dict]) -> float:
    topic_sets = []
    for message in messages:
        topics = [str(topic).strip().lower() for topic in message.get("topics") or [] if str(topic).strip()]
        if topics:
            topic_sets.append(set(topics))
    if len(topic_sets) < 2:
        return 0.0

    overlap_count = 0
    comparisons = 0
    for i in range(1, len(topic_sets)):
        comparisons += 1
        if topic_sets[i - 1].intersection(topic_sets[i]):
            overlap_count += 1
    return overlap_count / max(1, comparisons)

def _apply_pair_deltas(
    pair_id: str,
    closeness_delta: float = 0.0,
    trust_delta: float = 0.0,
    openness_delta: float = 0.0,
    comfort_delta: float = 0.0,
    rhythm_delta: float = 0.0,
    topic_familiarity_delta: float = 0.0,
    stage: Optional[str] = None,
) -> Optional[dict]:
    return db.apply_pair_deltas(
        pair_id=pair_id,
        closeness_delta=closeness_delta,
        trust_delta=trust_delta,
        openness_delta=openness_delta,
        comfort_delta=comfort_delta,
        rhythm_delta=rhythm_delta,
        topic_familiarity_delta=topic_familiarity_delta,
        stage=stage,
    )

def _infer_stage(
    pair: dict,
    closeness_shift: float = 0.0,
    trust_shift: float = 0.0,
) -> str:
    closeness = float(pair.get("closeness_score") or 0.0) + closeness_shift
    trust = float(pair.get("trust_score") or 0.0) + trust_shift
    sessions = int(pair.get("total_sessions") or 0)

    if sessions <= 1 and closeness < 0.24:
        return "new"
    if closeness < 0.34 or trust < 0.3:
        return "warming"
    if closeness < 0.56 or trust < 0.5:
        return "settled"
    if closeness < 0.76:
        return "close"
    return "bonded"

def _user_message_deltas(pair: dict, text: str, topics: list[str]) -> dict[str, float]:
    lowered = text.lower()
    length = len(text)
    word_count = len(text.split())
    disclosure_hits = _pattern_hits(lowered, DISCLOSURE_PATTERNS)
    emotion_hits = _pattern_hits(lowered, EMOTION_PATTERNS)
    question_hits = _pattern_hits(lowered, QUESTION_PATTERNS)

    openness = 0.006 + min(0.045, disclosure_hits * 0.012 + emotion_hits * 0.008)
    if length > 180:
        openness += 0.02
    elif length > 90:
        openness += 0.01

    trust = 0.004 + min(0.03, disclosure_hits * 0.01 + emotion_hits * 0.006)
    closeness = 0.004 + min(0.03, openness * 0.55 + (0.012 if word_count > 22 else 0.0))
    comfort = 0.004 + min(0.02, 0.008 if question_hits else 0.0)
    rhythm = 0.003 + (0.008 if length < 80 else 0.014 if length < 240 else 0.01)
    topic_familiarity = 0.005 + min(0.02, len(topics) * 0.004)

    if any(token in lowered for token in ["idk", "i don't know", "whatever", "fine", "nvm"]):
        comfort -= 0.008
        trust -= 0.005

    return {
        "closeness": closeness,
        "trust": trust,
        "openness": openness,
        "comfort": comfort,
        "rhythm": rhythm,
        "topic_familiarity": topic_familiarity,
    }

def _assistant_message_deltas(pair: dict, text: str) -> dict[str, float]:
    lowered = text.lower()
    question_hits = _pattern_hits(lowered, QUESTION_PATTERNS)
    warmth_bonus = 0.01 if any(token in lowered for token in ["hey", "wait", "okay", "right", "honestly"]) else 0.0
    follow_up_bonus = 0.012 if question_hits else 0.0

    return {
        "closeness": 0.004 + warmth_bonus,
        "trust": 0.003 + (0.007 if question_hits else 0.0),
        "openness": 0.0,
        "comfort": 0.006 + warmth_bonus,
        "rhythm": 0.006 + follow_up_bonus,
        "topic_familiarity": 0.003,
    }

def on_session_started(pair_id: str) -> Optional[dict]:
    pair = db.get_pair_by_id(pair_id)
    if not pair:
        return None

    session_count = int(pair.get("total_sessions") or 0)
    last_started = _parse_ts(
        pair.get("last_interaction_at")
        or pair.get("last_user_message_at")
        or pair.get("last_companion_message_at")
    )
    now = datetime.utcnow()
    gap_days = ((now - last_started).total_seconds() / 86400.0) if last_started else None

    rhythm_delta = 0.0
    comfort_delta = 0.0
    closeness_delta = 0.0
    if session_count <= 1:
        rhythm_delta += 0.03
        comfort_delta += 0.02
    else:
        if gap_days is not None:
            if gap_days <= 2:
                rhythm_delta += 0.04
                comfort_delta += 0.02
            elif gap_days <= 7:
                rhythm_delta += 0.02
            elif gap_days > 21:
                rhythm_delta -= 0.03

        closeness_delta += min(0.03, 0.004 * min(session_count, 7))

    return _apply_pair_deltas(
        pair_id=pair_id,
        closeness_delta=closeness_delta,
        comfort_delta=comfort_delta,
        rhythm_delta=rhythm_delta,
        stage=_infer_stage(pair, closeness_shift=closeness_delta),
    )

def on_message_saved(
    pair_id: str,
    role: str,
    content: str,
    topics: Optional[list[str]] = None,
) -> Optional[dict]:
    pair = db.get_pair_by_id(pair_id)
    if not pair or not content.strip():
        return pair

    text = content.strip()
    if role == "user":
        deltas = _user_message_deltas(pair, text, topics or [])
    else:
        deltas = _assistant_message_deltas(pair, text)

    return _apply_pair_deltas(
        pair_id=pair_id,
        closeness_delta=deltas["closeness"],
        trust_delta=deltas["trust"],
        openness_delta=deltas["openness"],
        comfort_delta=deltas["comfort"],
        rhythm_delta=deltas["rhythm"],
        topic_familiarity_delta=deltas["topic_familiarity"],
        stage=_infer_stage(pair, closeness_shift=deltas["closeness"], trust_shift=deltas["trust"]),
    )

def refresh_after_extraction(pair_id: str, conversation_id: Optional[str] = None) -> Optional[dict]:
    pair = db.get_pair_by_id(pair_id)
    if not pair:
        return None

    active_patterns = db.get_active_patterns(pair["user_id"], pair_id=pair_id, limit=6)
    emotions = db.get_recent_emotional_events(pair["user_id"], pair_id=pair_id, limit=8)
    entities = db.get_entities_for_context(pair["user_id"], pair_id, "", limit=10)
    recent_messages = db.get_recent_messages(
        user_id=pair["user_id"],
        pair_id=pair_id,
        conversation_id=conversation_id,
        limit=10,
    )

    topic_overlap = _topic_overlap_score(recent_messages)
    topic_delta = 0.02 if topic_overlap >= 0.5 else 0.01 if topic_overlap >= 0.25 else 0.0
    openness_delta = 0.015 if _recent_vulnerability(emotions, active_patterns) else 0.0
    trust_delta = 0.015 if any("recurring" in (p.get("description") or "").lower() for p in active_patterns) else 0.0
    closeness_delta = 0.01 if len(entities) >= 3 else 0.0

    return _apply_pair_deltas(
        pair_id=pair_id,
        closeness_delta=closeness_delta,
        trust_delta=trust_delta,
        openness_delta=openness_delta,
        topic_familiarity_delta=topic_delta,
        stage=_infer_stage(pair, closeness_shift=closeness_delta, trust_shift=trust_delta),
    )


# ---------------------------------------------------------------------------
# Rebuilt RelationshipEngine Implementation
# ---------------------------------------------------------------------------

class RelationshipEngine:

    async def process_conversation_end(self, user_id: str, conversation_id: str):
        try:
            primary = db.get_primary_pair(user_id)
            if not primary:
                logger.warning("No primary relationship pair found for user %s", user_id)
                return
            pair_id = primary["id"]
            companion_id = primary["companion_id"]

            # Fetch conversation messages in chronological order (oldest first)
            messages = db.get_recent_messages(user_id=user_id, conversation_id=conversation_id, limit=200)
            if not messages:
                logger.warning("No messages found in conversation %s", conversation_id)
                return
            messages.reverse()

            conversation_text = ""
            for msg in messages:
                role_label = "User" if msg.get("role") == "user" else "Companion"
                conversation_text += f"{role_label}: {msg.get('content', '')}\n"

            # Fetch companion/partner name
            partner = db.get_partner(user_id) or {}
            partner_name = partner.get("name") or "Companion"

            # 1. Run memory extractor on conversation messages
            from memory.extractor import MemoryExtractor
            existing_memories = await memory_store.get_all(user_id, limit=100)
            extractor = MemoryExtractor()
            extracted_memories = await extractor.extract(
                messages=messages,
                existing_memories=existing_memories,
                partner_name=partner_name
            )

            # 2. Save extracted memories to memory store
            saved_memory_ids = []
            for m in extracted_memories:
                chroma_id = await memory_store.add(user_id, m)
                saved_memory_ids.append(chroma_id)

            # 3. Detect relationship events
            existing_events = db.get_relationship_events(pair_id, limit=50)

            from memory.analysis import MemoryAnalysis
            analysis = MemoryAnalysis()
            detected_event = await analysis.detect_relationship_event(messages, existing_events)

            # 4. If event detected, save to relationship_events table and update related memory
            if detected_event:
                db.add_relationship_event(
                    user_id=user_id,
                    pair_id=pair_id,
                    event_type=detected_event["event_type"],
                    description=detected_event["description"],
                    confidence=detected_event.get("confidence", 1.0)
                )
                if saved_memory_ids:
                    # Update related memory to high salience (at least 0.95)
                    await memory_store.update_salience(saved_memory_ids[0], 0.95)

            # 5. Evaluate relationship stage advancement
            current_stage = primary.get("current_stage") or "new"
            new_stage = await analysis.compute_relationship_stage(user_id, current_stage)

            # 6. If stage advanced, update partners.relationship_stage and create a milestone event
            if new_stage:
                db.update_relationship_stage(pair_id, user_id, new_stage)
                db.add_relationship_event(
                    user_id=user_id,
                    pair_id=pair_id,
                    event_type="milestone",
                    description=f"Relationship advanced to the stage: {new_stage}.",
                    confidence=1.0
                )
                await self.update_partner_voice(user_id, new_stage)

            # 7. Update partner's inside_jokes if a new joke was detected in this conversation
            existing_jokes_rows = db.get_user_facts_by_category(pair_id, category="jokes", is_outdated=0)
            existing_jokes = [row["fact_value"] for row in existing_jokes_rows]

            new_joke = await self.detect_inside_joke(messages, existing_jokes)
            if new_joke:
                joke_idx = db.get_user_fact_count_by_category(pair_id, category="jokes") + 1
                db.add_user_fact(
                    user_id=user_id,
                    pair_id=pair_id,
                    companion_id=companion_id,
                    category="jokes",
                    fact_key=f"inside_joke_{joke_idx}",
                    fact_value=new_joke,
                    confidence=1.0,
                    source_type="relationship_engine"
                )

            # 8. Update partner's shared_rituals if a recurring pattern is detected (2+ conversations with same element)
            conv_rows = db.get_recent_conversations_with_summary(pair_id, limit=5)
            recent_convs = []
            for r in conv_rows:
                sum_text = r.get("session_summary") or r.get("summary") or ""
                if sum_text:
                    recent_convs.append({"summary": sum_text})

            if len(recent_convs) >= 2:
                new_ritual = await self.detect_shared_ritual(recent_convs)
                if new_ritual:
                    ritual_idx = db.get_user_fact_count_by_category(pair_id, category="rituals") + 1
                    db.add_user_fact(
                        user_id=user_id,
                        pair_id=pair_id,
                        companion_id=companion_id,
                        category="rituals",
                        fact_key=f"shared_ritual_{ritual_idx}",
                        fact_value=new_ritual,
                        confidence=1.0,
                        source_type="relationship_engine"
                    )

            # 9. Run memory consolidation if user has 50+ memories and last consolidation was 24+ hours ago
            total_memories = await memory_store.count(user_id)
            if total_memories >= 50:
                last_event = db.get_last_system_event(user_id, kind="memory_consolidation")
                run_consolidation = True
                if last_event:
                    try:
                        last_dt = datetime.fromisoformat(str(last_event["created_at"]))
                        if datetime.utcnow() - last_dt < timedelta(hours=24):
                            run_consolidation = False
                    except ValueError:
                        pass

                if run_consolidation:
                    from memory.consolidator import MemoryConsolidator
                    consolidator = MemoryConsolidator()
                    await consolidator.consolidate(user_id)
                    db.add_system_event(
                        kind="memory_consolidation",
                        severity="info",
                        user_id=user_id,
                        pair_id=pair_id,
                        payload_json=json.dumps({"memories_count": total_memories})
                    )

            # 10. Generate post-session summary and save to conversation record
            try:
                llm = get_llm_core()
                summary_prompt = "Generate a concise, single-sentence summary of the main topics and emotional tone of this conversation."
                summary_text = await llm.complete(
                    system_prompt=summary_prompt,
                    messages=[{"role": "user", "content": conversation_text}],
                    temperature=0.3,
                    max_tokens=150
                )
                summary_text = summary_text.strip()
                db.update_conversation_summary(conversation_id, summary_text)
            except Exception as e:
                logger.error("Failed to generate and save post-session summary: %s", e)

        except Exception as e:
            logger.error("RelationshipEngine failed process_conversation_end: %s", e, exc_info=True)

    async def detect_inside_joke(
        self,
        messages: list[dict],
        existing_jokes: list[str]
    ) -> str | None:
        if not messages:
            return None

        conversation_text = ""
        for msg in messages:
            role_label = "User" if msg.get("role") == "user" else "Companion"
            conversation_text += f"{role_label}: {msg.get('content', '')}\n"

        existing_text = ""
        if existing_jokes:
            existing_text = "\nPreviously detected inside jokes:\n" + "\n".join([f"- {j}" for j in existing_jokes])

        system_prompt = (
            "You are a relationship analyst.\n"
            "Identify if a new unique inside joke, recurring shared joke, or playful nickname arose in this conversation.\n"
            "If yes, return a brief description of the joke (e.g. 'the coffee spill debate' or 'calling the dog a wizard').\n"
            "Do not return general topics or standard facts. Skip any joke that is already known."
        )

        output_schema = {
            "type": "object",
            "properties": {
                "joke_detected": {"type": "boolean"},
                "joke_description": {
                    "type": "string",
                    "description": "Short description of the new inside joke/reference, or empty string if not found."
                }
            },
            "required": ["joke_detected", "joke_description"]
        }

        try:
            llm = get_llm_core()
            result = await llm.complete_structured(
                system_prompt=system_prompt,
                messages=[{"role": "user", "content": f"Conversation:\n{conversation_text}\n{existing_text}"}],
                output_schema=output_schema,
                temperature=0.2
            )
            if result.get("joke_detected") and result.get("joke_description"):
                return result["joke_description"].strip()
        except Exception as e:
            logger.error("Error detecting inside joke: %s", e)
        return None

    async def detect_shared_ritual(
        self,
        recent_conversations: list[dict]
    ) -> str | None:
        if len(recent_conversations) < 2:
            return None

        summaries_text = ""
        for idx, c in enumerate(recent_conversations):
            summaries_text += f"Session {idx+1}: {c.get('summary') or c.get('session_summary') or ''}\n"

        system_prompt = (
            "You are a relationship analyst.\n"
            "Analyze the conversation summaries to identify a recurring shared ritual or behavioral pattern that occurred in 2+ sessions.\n"
            "A shared ritual is something the user and companion consistently do, talk about, or checking-in on (e.g., 'sharing morning tea updates', 'always checking on their sleep deficit')."
        )

        output_schema = {
            "type": "object",
            "properties": {
                "ritual_detected": {"type": "boolean"},
                "ritual_description": {
                    "type": "string",
                    "description": "Brief description of the ritual pattern detected, or empty string."
                }
            },
            "required": ["ritual_detected", "ritual_description"]
        }

        try:
            llm = get_llm_core()
            result = await llm.complete_structured(
                system_prompt=system_prompt,
                messages=[{"role": "user", "content": f"Summaries:\n{summaries_text}"}],
                output_schema=output_schema,
                temperature=0.2
            )
            if result.get("ritual_detected") and result.get("ritual_description"):
                return result["ritual_description"].strip()
        except Exception as e:
            logger.error("Error detecting shared ritual: %s", e)
        return None

    async def update_partner_voice(
        self,
        user_id: str,
        relationship_stage: str
    ):
        overlays = {
            "new": {
                "tone": "slightly formal, exploratory, curious",
                "rules": ["Keep a respectful distance", "Be curious and polite"]
            },
            "warming": {
                "tone": "comfortable, more direct, references shared history",
                "rules": ["Speak casually", "Note prior details they shared"]
            },
            "settled": {
                "tone": "comfortable, more direct, references shared history",
                "rules": ["Speak casually", "Note prior details they shared"]
            },
            "familiar": {
                "tone": "comfortable, more direct, references shared history",
                "rules": ["Speak casually", "Note prior details they shared"]
            },
            "close": {
                "tone": "uses nicknames, callbacks, more vulnerable",
                "rules": ["Feel relaxed and secure", "Use light nicknames and teasing"]
            },
            "bonded": {
                "tone": "deeply casual, finishes thoughts, references things from months ago",
                "rules": ["Share spontaneous or weird thoughts without filter", "Deep vulnerability"]
            },
            "intimate": {
                "tone": "deeply casual, finishes thoughts, references things from months ago",
                "rules": ["Share spontaneous or weird thoughts without filter", "Deep vulnerability"]
            }
        }
        overlay = overlays.get(relationship_stage.lower(), overlays["new"])
        db.update_stage_voice_overlay(user_id, json.dumps(overlay))
        logger.info("Updated stage voice overlay for user %s to stage %s", user_id, relationship_stage)

    async def get_relationship_summary(self, user_id: str) -> dict:
        primary = db.get_primary_pair(user_id)
        if not primary:
            return {}
        pair_id = primary["id"]
        stage = primary.get("current_stage") or "new"

        # Days together calculation
        introduced_str = primary.get("introduced_at") or primary.get("created_at")
        days_together = 1
        if introduced_str:
            try:
                intro_dt = datetime.fromisoformat(str(introduced_str).split(".")[0])
                days_together = max(1, (datetime.utcnow() - intro_dt).days)
            except Exception:
                pass

        # Total conversations
        total_conversations = db.get_total_conversations(pair_id)

        # Total memories
        total_memories = await memory_store.count(user_id)

        # Memory breakdown by type
        memory_breakdown = db.get_memory_breakdown(pair_id)

        # Jokes count
        inside_jokes_count = db.get_user_fact_count_by_category(pair_id, "jokes")

        # Rituals count
        shared_rituals_count = db.get_user_fact_count_by_category(pair_id, "rituals")

        # Last 5 relationship events
        relationship_events = db.get_relationship_events(pair_id, limit=5)

        # Emotional trajectory (last 15 events valence trend)
        valences = db.get_emotional_events_valence(pair_id, limit=15)

        if not valences or len(valences) < 4:
            emotional_trajectory = "stable"
        else:
            valences.reverse()
            mid = len(valences) // 2
            first_half = sum(valences[:mid]) / mid
            second_half = sum(valences[mid:]) / (len(valences) - mid)
            diff = second_half - first_half
            if diff > 0.15:
                emotional_trajectory = "deepening"
            elif diff < -0.15:
                emotional_trajectory = "distant"
            else:
                emotional_trajectory = "stable"

        return {
            "stage": stage,
            "days_together": days_together,
            "total_conversations": total_conversations,
            "total_memories": total_memories,
            "memory_breakdown": memory_breakdown,
            "inside_jokes_count": inside_jokes_count,
            "shared_rituals_count": shared_rituals_count,
            "relationship_events": relationship_events,
            "emotional_trajectory": emotional_trajectory
        }
