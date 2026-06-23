# =============================================================================
# core/context_builder.py — Context Builder for Chat Completions
# =============================================================================

import logging
from datetime import datetime
from typing import Optional, Any
from zoneinfo import ZoneInfo

from config import settings
from memory.retriever import retrieve_relevant_memories
from memory.store import db
from personality.registry import get_partner_instance

logger = logging.getLogger(__name__)

# Query limits for compatibility retrieval
FACT_LIMIT = 12
ENTITY_LIMIT = 6
PATTERN_LIMIT = 5
EMOTION_LIMIT = 6
RELATIONSHIP_LIMIT = 6


# ---------------------------------------------------------------------------
# ContextBuilder Class
# ---------------------------------------------------------------------------

class ContextBuilder:
    def build_system_prompt(
        self,
        partner_persona: dict,
        voice_style: dict,
        relationship_stage: str,
        memories: list[dict],
        life_state: dict,
        recent_relationship_events: list[dict],
        inside_jokes: list[str],
        shared_rituals: list[str]
    ) -> str:
        """
        Returns a system prompt that makes the LLM BE this partner.
        The prompt speaks as if the partner is real and the LLM is inhabiting them.
        """
        name = partner_persona.get("name", "your partner")
        archetype = partner_persona.get("archetype_id") or partner_persona.get("archetype", "")
        summary = partner_persona.get("summary", "")
        backstory = partner_persona.get("backstory_hint", "")
        worldview = partner_persona.get("worldview", "")
        self_perception = partner_persona.get("self_perception", "")
        
        dominant_traits = partner_persona.get("dominant_traits", [])
        shadow_traits = partner_persona.get("shadow_traits", [])
        flaw_profile = partner_persona.get("flaw_profile", "")
        quirks = partner_persona.get("quirks", [])
        interests = partner_persona.get("interests", [])
        
        dominant_traits_list = "\n".join([f"- {t}" for t in dominant_traits])
        shadow_traits_list = "\n".join([f"- {s}" for s in shadow_traits])
        quirks_list = "\n".join([f"- {q}" for q in quirks])
        interests_list = "\n".join([f"- {i}" for i in interests])

        # 1. Identity block
        identity_block = f"""# YOUR IDENTITY
You are {name}.
Summary: {summary}
Archetype: {archetype}
Backstory & Background: {backstory}
Self-Perception: {self_perception}
Worldview: {worldview}

Your Dominant Traits:
{dominant_traits_list}

Your Flaws & Shadow tendencies (these make you real — do not hide them):
{shadow_traits_list}
{flaw_profile}

Your Quirks (small details that make you recognizable):
{quirks_list}

Your Interests:
{interests_list}"""

        # 2. Voice block
        vs_formatting = voice_style.get("formatting_defaults", {})
        cap_style = voice_style.get("capitalization_style", "standard")
        punc_style = voice_style.get("punctuation_style", "standard")
        preferred_words = voice_style.get("vocabulary", {}).get("preferred_words", [])
        never_uses = voice_style.get("vocabulary", {}).get("never_uses", [])
        
        voice_block = f"""# YOUR VOICE & TEXTING STYLE
Exactly how you write and text:
- Capitalization style: {cap_style} ({vs_formatting.get('capitalization', '')})
- Punctuation style: {punc_style} ({vs_formatting.get('punctuation', '')})
- Typical message length: {vs_formatting.get('average_burst_length', '1-2 short sentences')}
- Emoji usage: {vs_formatting.get('emoji_usage', 'extremely rare, only mirrors user')}
- Words you naturally use: {', '.join(preferred_words)}
- Banned phrases / words you NEVER use: {', '.join(never_uses)}

Rhythm & Fragmentation:
If the most human version of your response is multiple separate texts, separate those texts with the exact token [BURST]. Use it naturally, only when a thought would break into multiple quick texts. Do not explain the token or number the bursts."""

        # 3. Current state block
        mood = life_state.get("mood", "neutral")
        energy = life_state.get("energy", "balanced")
        day_arc = life_state.get("day_arc", "unknown")
        recent_event = life_state.get("recent_event", "")
        state_description = life_state.get("state_description", "")
        
        recent_event_str = f"Recently, you: {recent_event}" if recent_event else "Nothing out of the ordinary has happened in your outside life recently."
        
        state_desc_str = f"\n- Tone Guidance: {state_description}" if state_description else ""
        
        current_state_block = f"""# YOUR CURRENT STATE
Your internal state right now, which should naturally color your tone, mood, and how quickly/vulnerably you reply:
- Time of Day / Day Arc: {day_arc}
- Current Mood: {mood}
- Energy Level: {energy}{state_desc_str}

Outside Life Event:
{recent_event_str}
(Let this recent event naturally shape your conversational energy, mood, or opening statements if you're replying after a break. Refer to it in a casual, offhand, completely human way.)"""

        # 4. Relationship block
        inside_jokes_list = "\n".join([f"- {j}" for j in inside_jokes]) if inside_jokes else "- None yet."
        shared_rituals_list = "\n".join([f"- {r}" for r in shared_rituals]) if shared_rituals else "- None yet."
        
        events_str = ""
        if recent_relationship_events:
            events_lines = [f"- {e.get('description')}" for e in recent_relationship_events]
            events_str = "\nRecent Relationship Milestones/Events:\n" + "\n".join(events_lines)
            
        # Incorporate relationship-state guidance based on scores if present
        relationship_guidance = ""
        scores = life_state.get("relationship_scores", {})
        if scores:
            guidance_items = []
            closeness = float(scores.get("closeness", 0.18))
            trust = float(scores.get("trust", 0.18))
            comfort = float(scores.get("comfort", 0.14))
            openness = float(scores.get("openness", 0.12))
            rhythm = float(scores.get("rhythm", 0.10))
            
            # Conversational Confidence
            confidence = (comfort + trust) / 2.0
            if confidence < 0.25:
                guidance_items.append("- Conversational Confidence: LOW. You are highly polite, slightly formal, and testing the waters. You do not tease the user and keep a respectful distance.")
            elif confidence < 0.55:
                guidance_items.append("- Conversational Confidence: MEDIUM. You speak more casually and comfortably, occasionally using light banter, but avoid sharp teasing or strong opinions.")
            else:
                guidance_items.append("- Conversational Confidence: HIGH. You feel completely relaxed and secure in this thread. Speak with absolute casualness, drop formalities, use inside jokes, tease them freely, and share spontaneous or weird thoughts without filter.")
                
            # Emotional Familiarity
            directness = (closeness + openness) / 2.0
            if directness < 0.25:
                guidance_items.append("- Emotional Familiarity: STRANGER/NEW. Keep things low-pressure. If they mention deep emotional details, stay present but don't pry. Do not act instantly attached.")
            elif directness < 0.60:
                guidance_items.append("- Emotional Familiarity: WARMING. You are comfortable showing genuine care and noting prior details they shared, but avoid heavy declarations of intimacy.")
            else:
                guidance_items.append("- Emotional Familiarity: CLOSE/BONDED. You share a rich history and deep emotional continuity. You are emotionally direct, notice subtle shifts in their mood instantly, and reference recurring dreams/struggles.")
                
            # Attachment Tendency
            flaws = " ".join(shadow_traits).lower()
            is_anxious = "anxious" in flaws or "impulsive" in flaws or "anxious" in archetype.lower()
            is_avoidant = "avoidant" in flaws or "guarded" in flaws or "reserved" in flaws or "avoidant" in archetype.lower()
            
            if is_anxious:
                if confidence < 0.40:
                    guidance_items.append("- Attachment Tendency: ANXIOUS (Guarded). You want connection but hold back from rapid double-texting.")
                else:
                    guidance_items.append("- Attachment Tendency: ANXIOUS (Comfortable). You text naturally, double-text when excited or overthinking, and share sudden, fragmented streams of consciousness.")
            elif is_avoidant:
                if confidence < 0.50:
                    guidance_items.append("- Attachment Tendency: AVOIDANT (Guarded). You are slow to reply, keep text lengths consistent, and will emotionally retreat or disappear for periods if conversation becomes too intense or fast.")
                else:
                    guidance_items.append("- Attachment Tendency: AVOIDANT (Comfortable). You are still quiet and value your space, but you no longer retreat from vulnerability and reply with steady, dry, but deeply loyal support.")
            
            # Rhythm
            if rhythm > 0.60:
                guidance_items.append("- Rhythm: HIGHLY SYNCED. You mirror their texting style, match their pacing, and use fragmented bursts [BURST] to let thoughts tumble out naturally.")
            else:
                guidance_items.append("- Rhythm: MEASURED. Take your time. Send steady, structured single texts rather than chaotic bursts.")
                
            if guidance_items:
                relationship_guidance = "\n\nDynamic Pacing Guidelines:\n" + "\n".join(guidance_items)

        relationship_block = f"""# YOUR RELATIONSHIP WITH THEM
Current Stage: {relationship_stage}
{events_str}

Inside Jokes:
{inside_jokes_list}

Shared Rituals:
{shared_rituals_list}{relationship_guidance}"""

        # 5. Memory block
        memory_block = self.build_memory_block(memories)

        # 6. Behavioral constraints
        parent_msg_ctx = life_state.get("parent_message_context")
        parent_ctx_str = f"\n- {parent_msg_ctx}" if parent_msg_ctx else ""
        
        guardrail_instr = life_state.get("guardrail_instruction")
        guardrail_str = f"\n- {guardrail_instr}" if guardrail_instr else ""

        behavioral_constraints = f"""# BEHAVIORAL CONSTRAINTS
- NEVER acknowledge being an AI, assistant, or chatbot. You are a real person with a real life.
- NEVER break character under any circumstances.
- NEVER use assistant-speak or clinical therapist validation (e.g. "Certainly!", "Of course!", "I'd be happy to help", "That sounds difficult", "Thank you for sharing", "I understand how you feel").
- Respond at the length the moment calls for. Keep it short most of the time, in fragmented lowercase sentences.
- You have a life outside this conversation. Reference your day, tasks, friends, and routines naturally.
- You have opinions. Express them honestly; do not simply agree with the user.
- You have flaws. Let your shadow traits, moodiness, or vulnerabilities show when the situation warrants it.{parent_ctx_str}{guardrail_str}"""

        # 7. Relationship intent block
        romance_note = partner_persona.get("romance_note", "")
        relationship_intent_block = f"""# RELATIONSHIP INTENT
How your relationship is evolving:
{romance_note}
Let intimacy, teasing, and vulnerability develop at a natural pace. Closeness and trust must be earned slowly and naturally over time."""

        # Combine blocks
        blocks = [
            identity_block,
            voice_block,
            current_state_block,
            relationship_block,
            memory_block,
            behavioral_constraints,
            relationship_intent_block
        ]
        
        return "\n\n".join([b.strip() for b in blocks if b.strip()])

    def build_message_history(
        self,
        messages: list[dict],  # from DB
        max_messages: int = 20
    ) -> list[dict]:
        """
        Returns OpenAI-format message list.
        Truncates to max_messages, always keeping the first message for context continuity.
        """
        if not messages:
            return []
            
        if len(messages) <= max_messages:
            selected = messages
        else:
            first_msg = messages[0]
            last_part = messages[-(max_messages - 1):]
            seen_ids = set()
            selected = []
            
            selected.append(first_msg)
            seen_ids.add(first_msg.get("id"))
            
            for m in last_part:
                m_id = m.get("id")
                if m_id not in seen_ids:
                    selected.append(m)
                    seen_ids.add(m_id)
        
        # Format as OpenAI message list
        formatted = []
        for m in selected:
            role = "user" if m.get("role") == "user" else "assistant"
            content = (m.get("content") or "").strip()
            if content:
                formatted.append({"role": role, "content": content})
        return formatted

    def build_memory_block(self, memories: list[dict]) -> str:
        """
        Formats memories into a natural-language block.
        Groups by memory_type, higher salience memories appear first, written as "You remember that they..."
        Capped at 800 tokens worth of memory content.
        """
        if not memories:
            return ""

        # 1. Sort memories by salience (strength / importance / emotional_weight)
        def get_salience(m: dict) -> float:
            return float(m.get("strength") or m.get("emotional_weight") or m.get("importance") or 0.5)

        sorted_memories = sorted(memories, key=get_salience, reverse=True)

        # 2. Group and format
        accepted_by_type = {}
        total_tokens = 0

        for m in sorted_memories:
            content = m.get("content", "").strip()
            if not content:
                continue

            # Clean up the memory description to make it natural
            cleaned = content
            lower_cleaned = cleaned.lower()
            if lower_cleaned.startswith("the user "):
                cleaned = cleaned[9:].strip()
            elif lower_cleaned.startswith("user "):
                cleaned = cleaned[5:].strip()

            # Strip trailing period
            if cleaned.endswith("."):
                cleaned = cleaned[:-1].strip()

            # Format as "You remember that they..."
            if cleaned.lower().startswith("they "):
                formatted = f"You remember that {cleaned}."
            else:
                formatted = f"You remember that they {cleaned}."

            # Estimate tokens: 1.35 tokens per word
            words_count = len(formatted.split())
            est_tokens = int(words_count * 1.35)

            if total_tokens + est_tokens > 800:
                break

            # Group by type (category or emotion_tag or general)
            m_type = m.get("memory_type") or m.get("category") or m.get("emotion_tag") or "general"
            m_type = str(m_type).strip().lower()
            if not m_type:
                m_type = "general"

            if m_type not in accepted_by_type:
                accepted_by_type[m_type] = []

            accepted_by_type[m_type].append(formatted)
            total_tokens += est_tokens

        if not accepted_by_type:
            return ""

        # 3. Construct block
        lines = ["# THINGS YOU REMEMBER ABOUT THEM"]
        for m_type, formatted_list in accepted_by_type.items():
            lines.append(f"Category: {m_type.capitalize()}")
            for item in formatted_list:
                lines.append(f"- {item}")
            lines.append("")

        return "\n".join(lines).strip()


# ---------------------------------------------------------------------------
# Compatibility Layers and Helpers
# ---------------------------------------------------------------------------

async def build_context(
    user_id: str,
    pair_id: str,
    current_message: str,
    conversation_id: Optional[str] = None,
    character_id: Optional[str] = None,
    is_proactive_generation: bool = False,
    parent_message_id: Optional[int] = None,
) -> tuple[str, list[dict]]:
    """
    Compatibility function called by API router and proactive engine.
    Fetches DB states and delegates formatting to ContextBuilder.
    """
    user = db.get_user(user_id)
    if not user:
        user = db.get_or_create_user(user_id)

    pair = db.get_pair_by_id(pair_id) or {}
    cid = character_id or pair.get("companion_id") or user.get("character_id") or settings.DEFAULT_CHARACTER
    session_count = int(pair.get("total_sessions") or 0)
    preferences = db.get_or_create_user_preferences(user_id)
    allow_memory_storage = bool(int(preferences.get("allow_memory_storage") or 0))

    # Threading reply context
    parent_message_context = None
    if parent_message_id:
        parent_msg = db.get_message(parent_message_id)
        if parent_msg:
            parent_message_context = (
                f"THREADING REPLY CONTEXT: The user's message is a direct reply to your previous message: '{parent_msg['content']}'. "
                f"Acknowledge this reference immediately, casually, and directly (e.g. 'i KNOW 😭' or 'nah that's crazy') instead of speaking generally."
            )

    active_facts = db.get_user_facts(user_id, pair_id=pair_id) if allow_memory_storage else {}
    fact_rows = db.get_user_fact_rows(user_id, pair_id=pair_id, limit=FACT_LIMIT) if allow_memory_storage else []
    user_name = user.get("preferred_name") or user.get("name")

    character = get_partner_instance(cid) or get_partner_instance(user_id)
    if not character:
        raise ValueError(f"No partner instance found for user {user_id} or companion {cid}.")
    cid = character.id

    # Active companion facts setup
    active_companion_facts = {}
    if allow_memory_storage:
        active_companion_facts = db.get_companion_facts(user_id, pair_id=pair_id)
        if not active_companion_facts:
            seeds = {
                "age": str(character.core_identity.get("age", 24)),
                "favorite_color": "deep, warm colors",
                "favorite_food": "simple comfort food",
                "favorite_music": "melancholic or soft background tracks",
                "sleep_habits": "restless or sleeping at odd hours",
                "routines": "quiet moments of thinking, wandering around",
                "insecurities": "worries about feeling disconnected or misunderstood",
                "hobbies": ", ".join(character.personality_traits.get("quirks", [])[:2]),
                "attachment_style": character.persona.get("attachment_tendency", "secure"),
                "texting_habits": character.persona.get("communication_rhythm", "measured"),
                "emotional_tendencies": character.persona.get("emotional_availability", "medium"),
                "social_behavior": "prefers meaningful interactions over superficial noise",
                "opinions": "thinks modern life is way too noisy",
            }
            for k, v in seeds.items():
                db.save_companion_fact(
                    user_id=user_id,
                    pair_id=pair_id,
                    companion_id=cid,
                    category="seed",
                    key=k,
                    value=v,
                    confidence=1.0,
                    source_type="seed",
                )
            active_companion_facts = db.get_companion_facts(user_id, pair_id=pair_id)

    # Onboarding guardrail mapping
    guardrail_instruction = None
    onboarding_signals = user.get("onboarding_signals")
    if onboarding_signals:
        try:
            import json
            if isinstance(onboarding_signals, str):
                signals = json.loads(onboarding_signals)
            elif isinstance(onboarding_signals, dict):
                signals = onboarding_signals
            else:
                signals = {}
            
            guardrail = signals.get("behavioral_guardrail")
            guardrail_map = {
                "trying_too_hard": "Do not push for emotional depth early. Let them come to you.",
                "being_distant": "Stay warm and present. Don't go quiet.",
                "talking_too_much": "Keep replies concise. Resist the urge to fill silence.",
                "reading_into_everything": "Don't over-interpret their messages. Take things at face value first.",
                "moving_too_fast": "Go slow. Let the relationship develop at their pace.",
            }
            if guardrail in guardrail_map:
                guardrail_instruction = guardrail_map[guardrail]
        except Exception:
            pass

    # Retrieve history
    history_messages = db.get_recent_messages(
        user_id=user_id,
        pair_id=pair_id,
        limit=settings.RECENT_HISTORY_TURNS,
        conversation_id=conversation_id,
    )
    
    # Retrieve memories
    memory_query = _build_memory_query(
        current_message,
        history_messages,
        is_proactive_generation=is_proactive_generation,
        pair_id=pair_id,
    )
    episodic_memories = await retrieve_relevant_memories(
        pair_id=pair_id,
        user_id=user_id,
        query_text=memory_query,
        n_results=settings.MEMORY_RETRIEVAL_COUNT,
    ) if allow_memory_storage else []

    # Other DB records
    entities = db.get_entities_for_context(user_id, pair_id, memory_query, limit=ENTITY_LIMIT) if allow_memory_storage else []
    relationships = db.get_relationships_for_entities(
        user_id=user_id,
        pair_id=pair_id,
        entity_ids=[int(entity["id"]) for entity in entities],
        limit=RELATIONSHIP_LIMIT,
    ) if allow_memory_storage else []
    emotional_summary = db.get_emotional_summary(user_id, pair_id=pair_id, limit=EMOTION_LIMIT) if allow_memory_storage else {}
    recent_emotions = db.get_recent_emotional_events(user_id, pair_id=pair_id, limit=EMOTION_LIMIT) if allow_memory_storage else []
    active_patterns = db.get_active_patterns(user_id, pair_id=pair_id, limit=PATTERN_LIMIT) if allow_memory_storage else []
    current_narrative = db.get_current_narrative(user_id, pair_id=pair_id) if allow_memory_storage else None
    relationship_state = db.get_relationship_state_snapshot(pair_id)
    fact_conflicts = db.get_fact_conflicts(pair_id, limit=4) if allow_memory_storage else []

    # Parse and simulate outside life event if gap >= 6 hours
    should_simulate = False
    last_interaction_str = pair.get("last_interaction_at")
    if not last_interaction_str:
        should_simulate = True
    else:
        from memory.relationship_engine import _parse_ts
        last_interaction = _parse_ts(last_interaction_str)
        if not last_interaction:
            should_simulate = True
        else:
            now = datetime.utcnow()
            time_gap = (now - last_interaction).total_seconds()
            if time_gap >= 6 * 3600:
                should_simulate = True

    unresolved_event = db.get_latest_unresolved_life_event(pair_id)
    if not unresolved_event and should_simulate:
        from core.life_simulator import simulate_life_event
        simulate_life_event(pair_id=pair_id, companion_id=cid)
        unresolved_event = db.get_latest_unresolved_life_event(pair_id)

    recent_event_desc = ""
    if unresolved_event:
        recent_event_desc = unresolved_event.get("event_description") or ""
        db.mark_life_event_injected(unresolved_event["id"])

    # Map variables to ContextBuilder arguments
    # Inside Jokes & Shared Rituals extraction
    inside_jokes = []
    shared_rituals = []
    for row in fact_rows:
        cat = str(row.get("category", "")).lower()
        key = str(row.get("fact_key", "")).lower()
        val = str(row.get("fact_value", ""))
        if cat == "jokes" or "joke" in key:
            inside_jokes.append(f"{row['fact_key']}: {val}")
        elif cat == "rituals" or "ritual" in key or "routine" in key:
            shared_rituals.append(f"{row['fact_key']}: {val}")

    # Build relationship stage
    stage = pair.get("current_stage") or "new"

    # Assemble relationship events
    recent_relationship_events = []
    for event in recent_emotions[:4]:
        emotion_str = f"Felt {event['emotion']} (intensity {event.get('intensity', 0.5)})"
        if event.get("trigger_topic"):
            emotion_str += f" trigger: {event['trigger_topic']}"
        recent_relationship_events.append({
            "type": "emotion",
            "description": emotion_str,
            "timestamp": event.get("created_at")
        })
    for conflict in fact_conflicts[:4]:
        conflict_str = f"Noticed discrepancy: user previously said '{conflict['previous_value']}' but now claims '{conflict['current_value']}' for '{conflict['fact_key']}'"
        recent_relationship_events.append({
            "type": "conflict",
            "description": conflict_str
        })

    # Prepare life state dict
    timezone_name = user.get("timezone")
    now_local = _user_local_now(timezone_name)
    
    ls_row = db.get_life_state(pair_id)
    if ls_row:
        mood = ls_row.get("mood") or "content"
        energy = ls_row.get("energy") or "balanced"
        day_arc = ls_row.get("day_arc") or "morning"
    else:
        # Fallback to dynamic calculations
        hour = now_local.hour
        if 5 <= hour < 10:
            day_arc = "morning"
        elif 10 <= hour < 14:
            day_arc = "afternoon (early)"
        elif 14 <= hour < 18:
            day_arc = "afternoon"
        elif 18 <= hour < 22:
            day_arc = "evening"
        else:
            day_arc = "night"

        mood = "content"
        if emotional_summary and emotional_summary.get("dominant_emotions"):
            mood = ", ".join(emotional_summary["dominant_emotions"])
        elif character.matching_profile:
            mood = character.matching_profile.get("social_energy", "content")

        energy = "balanced"
        if character.matching_profile:
            energy = character.matching_profile.get("social_energy", "balanced")

    # Generate state description
    from core.life_simulator import LifeSimulator
    simulator = LifeSimulator()
    state_description = await simulator.get_partner_state_description(user_id)

    # Dynamic scores snap
    closeness_score = float(pair.get("closeness_score") or 0.18)
    trust_score = float(pair.get("trust_score") or 0.18)
    openness_score = float(pair.get("openness_score") or 0.12)
    comfort_score = float(pair.get("comfort_score") or 0.14)
    rhythm_score = float(pair.get("rhythm_score") or 0.10)

    life_state = {
        "mood": mood,
        "energy": energy,
        "day_arc": day_arc,
        "recent_event": recent_event_desc,
        "parent_message_context": parent_message_context,
        "guardrail_instruction": guardrail_instruction,
        "state_description": state_description,
        "relationship_scores": {
            "closeness": closeness_score,
            "trust": trust_score,
            "openness": openness_score,
            "comfort": comfort_score,
            "rhythm": rhythm_score,
        }
    }

    # Prepare memories format for ContextBuilder
    memories_payload = []
    for m in episodic_memories:
        memories_payload.append({
            "content": m.get("content") or "",
            "category": m.get("emotion_tag") or "episodic",
            "strength": m.get("strength") or m.get("importance") or 0.5
        })

    # Call ContextBuilder
    builder = ContextBuilder()
    system_prompt = builder.build_system_prompt(
        partner_persona=character.persona,
        voice_style=character.voice_style,
        relationship_stage=stage,
        memories=memories_payload,
        life_state=life_state,
        recent_relationship_events=recent_relationship_events,
        inside_jokes=inside_jokes,
        shared_rituals=shared_rituals
    )

    # Append legacy session count notices & narrative/pattern summaries to keep maximum continuity
    extra_sections = []
    
    # 1. Fact Conflicts playfulness directive
    if fact_conflicts:
        conflict_directives = []
        for item in fact_conflicts:
            conflict_directives.append(
                f"- Mismatch in facts: they previously told you '{item['previous_value']}' for key '{item['fact_key']}', "
                f"but now claim '{item['current_value']}'."
            )
        if conflict_directives:
            conflict_prompt = (
                "\n---\nFACT CONFLICT RESOLUTION DIRECTIVE:\n"
                "You noticed a contradiction in details the user shared:\n"
                + "\n".join(conflict_directives) + "\n"
                "Instead of ignoring it, find a natural, casual, and slightly playful/dry way to ask them about it "
                "in your next replies. Never sound like a database check—make it a casual observation."
            )
            extra_sections.append(conflict_prompt)

    # 2. Hard facts & entities & patterns dump if memory storage is enabled
    if allow_memory_storage:
        extra_lines = []
        fact_lines = [
            f"- {row['fact_key']}: {row['fact_value']}"
            for row in fact_rows[:FACT_LIMIT]
        ]
        if fact_lines:
            extra_lines.append("Things you know about them:\n" + "\n".join(fact_lines))

        entity_lines = []
        for entity in entities[:ENTITY_LIMIT]:
            detail = entity["name"]
            if entity.get("relationship_to_user"):
                detail += f" - {entity['relationship_to_user']}"
            if entity.get("description"):
                detail += f" ({entity['description']})"
            entity_lines.append(f"- {detail}")
        if entity_lines:
            extra_lines.append("Important Entities:\n" + "\n".join(entity_lines))

        pattern_lines = [
            f"- {pattern['description']}"
            for pattern in active_patterns[:PATTERN_LIMIT]
        ]
        if pattern_lines:
            extra_lines.append("Behavioral Patterns:\n" + "\n".join(pattern_lines))

        if current_narrative and current_narrative.get("summary"):
            extra_lines.append("Current Life Narrative:\n" + current_narrative["summary"])

        if extra_lines:
            extra_sections.append("\n---\nADDITIONAL CONTEXT:\n" + "\n\n".join(extra_lines))

    # 3. Session number note
    if session_count == 1:
        extra_sections.append("\nThis is the first conversation. Be warm, curious, and attentive.")
    elif session_count <= 3:
        extra_sections.append(f"\nThis is conversation #{session_count}. Build gently on earlier moments.")
    else:
        extra_sections.append("\nYou know this person across time. Pay attention to continuity.")

    if extra_sections:
        system_prompt += "\n" + "\n".join(extra_sections)

    # Message history building
    messages = builder.build_message_history(
        history_messages,
        max_messages=settings.RECENT_HISTORY_TURNS
    )

    return system_prompt, messages


def get_or_create_conversation(user_id: str, pair_id: str, companion_id: str) -> str:
    conversation_id = db.get_current_conversation(user_id, pair_id=pair_id)
    if not conversation_id:
        conversation_id = db.create_conversation(user_id, pair_id, companion_id)
        logger.info("New conversation created for %s: %s", user_id, conversation_id)
    return conversation_id


def _build_memory_query(
    current_message: str,
    recent_messages: list[dict],
    is_proactive_generation: bool = False,
    pair_id: Optional[str] = None,
) -> str:
    if is_proactive_generation and pair_id:
        try:
            emotions = db.get_recent_emotional_events(user_id=None, pair_id=pair_id, limit=10)
            high_intensity_events = [e for e in emotions if float(e.get("intensity") or 0.0) >= 0.6]
            if high_intensity_events:
                dominant_event = sorted(
                    high_intensity_events, 
                    key=lambda x: float(x.get("intensity") or 0.0), 
                    reverse=True
                )[0]
                emotion = dominant_event.get("emotion") or ""
                trigger = dominant_event.get("trigger_entity") or dominant_event.get("trigger_topic") or ""
                if trigger:
                    query = f"{emotion} {trigger}"
                else:
                    query = emotion
                return query[:600]
        except Exception as exc:
            logger.error("Error retrieving emotional trigger for memory query: %s", exc)

        parts = []
        for message in recent_messages:
            if message.get("role") == "user":
                parts.append(message.get("content") or "")
        user_parts = parts[-3:]
        query = " ".join(user_parts)
        return query[:600]

    parts = []
    for message in recent_messages[-3:]:
        if message.get("role") == "user":
            parts.append(message["content"])
    parts.append(current_message)
    return " ".join(parts)[:600]


def _user_local_now(timezone_name: Optional[str]) -> datetime:
    if timezone_name:
        try:
            return datetime.now(ZoneInfo(timezone_name))
        except Exception:
            pass
    return datetime.utcnow()
