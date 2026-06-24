# ═══════════════════════════════════════════════════════════════════
# FILE: backend/core/context_builder.py
# PURPOSE: Assembles the complete LLM system prompt and message history.
# CONTEXT: Called on every chat message before Groq API call.
# ═══════════════════════════════════════════════════════════════════

import logging
import json
import time
from datetime import datetime
from typing import Optional, Any
from zoneinfo import ZoneInfo

from config import settings

# Global hooks for dynamic system injection
from memory.store import db
from memory.retriever import MemoryRetriever
from personality.registry import get_partner_instance
import asyncio

async def _retrieve_memories_wrapper(pair_id: str, user_id: str, query_text: str, n_results: int = 5) -> list[dict]:
    retriever = MemoryRetriever()
    return await asyncio.to_thread(retriever.retrieve, db.get_connection(), user_id, query_text, n_results)

retrieve_relevant_memories = _retrieve_memories_wrapper

logger = logging.getLogger(__name__)

# Query limits for compatibility retrieval
FACT_LIMIT = 12
ENTITY_LIMIT = 6
PATTERN_LIMIT = 5
EMOTION_LIMIT = 6
RELATIONSHIP_LIMIT = 6

# Cache for natural language partner state descriptions to avoid excessive LLM calls
# key: user_id or (mood, energy, day_arc, recent_event)
# value: (timestamp, description)
_state_description_cache = {}


# ---------------------------------------------------------------------------
# ContextBuilder Class
# ---------------------------------------------------------------------------

class ContextBuilder:
    
    async def build_system_prompt(
        self,
        partner: dict,         # from partners table
        life_state: dict,      # from life_state table
        memories: list[dict],  # from retriever
        current_stage: str
    ) -> str:
        """
        Builds the character-defining system prompt.
        
        Structure (in this exact order):
        
        1. IDENTITY BLOCK
        "You are [name]. [persona_json — written as rich character brief]
         Your flaws: [flaw_profile — specific behavioral patterns]."
        
        2. VOICE BLOCK  
        "[voice_style — how you write, your rhythms, what you say and don't]
         [stage_voice_overlay for current_stage]"
        
        3. CURRENT STATE BLOCK
        "Right now: [get_partner_state_description(life_state)]"
        Example: "You're in a quiet mood. It's been one of those evenings."
        Never mechanical. Always natural language.
        
        4. MEMORY BLOCK (if memories exist)
        "Things you remember about them:
         - [memory_text for each memory, formatted naturally]"
        
        5. RELATIONSHIP BLOCK
        "You've known each other [N days]. [relationship stage context]
         [inside jokes if any] [shared rituals if any]"
        
        6. THE THOUGHT PROTOCOL (mandatory, always included)
        "Before responding, reason through your emotional state and what 
         this moment calls for inside <thought> tags. This reasoning is 
         private. After your thought, give your actual response.
         
         Format:
         <thought>
         [What are they feeling? What do you remember about them? 
          What does this moment need? What's your mood right now?
          What length and tone is right?]
         </thought>
         [Your response — natural, human, no assistant language, 
          no 'certainly', no 'of course', no 'I'd be happy to']"
        
        7. BEHAVIORAL CONSTRAINTS
        - Never acknowledge being AI
        - Never break character
        - Respond at the length the moment calls for — usually short
        - You have a life. Reference it naturally. You were doing things before this.
        - You have opinions. Hold them.
        - You have bad days. Let it show appropriately.
        - One question maximum per response. Usually none.
        - When something hurts them, you feel it too. Don't problem-solve immediately.
        """
        # 1. IDENTITY BLOCK
        name = partner.get("name") or "your partner"
        persona = partner.get("persona_json")
        if isinstance(persona, str):
            try:
                persona = json.loads(persona)
            except Exception:
                persona = {}
        elif not isinstance(persona, dict):
            persona = {}
            
        summary = persona.get("summary") or persona.get("character_brief") or ""
        temperament = persona.get("core_temperament") or ""
        worldview = persona.get("core_identity", {}).get("worldview") or persona.get("worldview") or ""
        
        brief_parts = []
        if summary:
            brief_parts.append(summary)
        if temperament:
            brief_parts.append(f"Your temperament is {temperament}.")
        if worldview:
            brief_parts.append(worldview)
            
        persona_brief = " ".join(brief_parts).strip()
        flaws = partner.get("flaw_profile") or ""
        
        identity_block = f"You are {name}. {persona_brief}\nYour flaws: {flaws}."
        
        # 2. VOICE BLOCK
        voice = partner.get("voice_style")
        if isinstance(voice, str):
            try:
                voice = json.loads(voice)
            except Exception:
                voice = {}
        elif not isinstance(voice, dict):
            voice = {}
            
        rhythm = voice.get("sentence_rhythm") or voice.get("formatting_defaults", {}).get("sentence_rhythm") or ""
        vocab = voice.get("vocabulary_profile") or voice.get("vocabulary", {}).get("profile") or ""
        punc = voice.get("punctuation_tendencies") or voice.get("punctuation_style") or ""
        expression = voice.get("emotional_expression") or ""
        length = voice.get("default_length") or voice.get("formatting_defaults", {}).get("average_burst_length") or ""
        
        voice_parts = []
        if rhythm:
            voice_parts.append(f"Sentence rhythm: {rhythm}.")
        if vocab:
            voice_parts.append(f"Vocabulary tendencies: {vocab}.")
        if punc:
            voice_parts.append(f"Punctuation & capitalization: {punc}.")
        if expression:
            voice_parts.append(f"Emotional expression style: {expression}.")
        if length:
            voice_parts.append(f"Typical length: {length}.")
            
        voice_desc = " ".join(voice_parts).strip()
        if not voice_desc:
            voice_desc = "Speak naturally, in a casual, conversational texting style."
            
        overlays = voice.get("stage_voice_overlays") or voice.get("stage_voice_overlay") or {}
        stage_map = {
            "new": "new",
            "warming": "new",
            "settled": "familiar",
            "close": "close",
            "bonded": "intimate"
        }
        overlay_key = stage_map.get(current_stage, "new")
        stage_overlay = overlays.get(overlay_key, overlays.get(current_stage, ""))
        
        voice_block = f"{voice_desc}\n{stage_overlay}".strip()
        
        # 3. CURRENT STATE BLOCK
        state_desc = await self.get_partner_state_description(life_state)
        current_state_block = f"Right now: {state_desc}"
        
        # 4. MEMORY BLOCK
        memory_block = self.build_memory_block(memories)
        
        # 5. RELATIONSHIP BLOCK
        generated_at = partner.get("generated_at")
        n_days = 1
        if generated_at:
            try:
                cleaned_date = str(generated_at).split(".")[0]
                for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d"):
                    try:
                        gen_date = datetime.strptime(cleaned_date, fmt)
                        n_days = max(1, (datetime.utcnow() - gen_date).days)
                        break
                    except ValueError:
                        continue
            except Exception:
                n_days = 1
                
        stage_context = ""
        if current_stage == "new":
            stage_context = "You are still getting to know each other, keeping things comfortable and low-pressure."
        elif current_stage == "warming":
            stage_context = "You've started opening up to each other, finding a natural rhythm."
        elif current_stage == "settled":
            stage_context = "You feel like a regular presence in each other's day."
        elif current_stage == "close":
            stage_context = "You've developed a deep familiarity and share a lot of your thoughts."
        elif current_stage == "bonded":
            stage_context = "You share a rich emotional history and feel deeply connected."
        else:
            stage_context = f"Your relationship stage is {current_stage}."
            
        relationship_parts = [f"You've known each other {n_days} days. {stage_context}"]
        
        jokes = partner.get("inside_jokes") or "[]"
        if isinstance(jokes, str):
            try:
                jokes = json.loads(jokes)
            except Exception:
                jokes = []
        if isinstance(jokes, list) and jokes:
            relationship_parts.append(f"Inside jokes: {', '.join(jokes)}")
            
        rituals = partner.get("shared_rituals") or "[]"
        if isinstance(rituals, str):
            try:
                rituals = json.loads(rituals)
            except Exception:
                rituals = []
        if isinstance(rituals, list) and rituals:
            relationship_parts.append(f"Shared rituals: {', '.join(rituals)}")
            
        relationship_block = "\n".join(relationship_parts)
        
        # 6. THE THOUGHT PROTOCOL
        thought_protocol = (
            "Before responding, reason through your emotional state and what \n"
            "this moment calls for inside <thought> tags. This reasoning is \n"
            "private. After your thought, give your actual response.\n\n"
            "Format:\n"
            "<thought>\n"
            "[What are they feeling? What do you remember about them? \n"
            " What does this moment need? What's your mood right now?\n"
            " What length and tone is right?]\n"
            "</thought>\n"
            "[Your response — natural, human, no assistant language, \n"
            " no 'certainly', no 'of course', no 'I'd be happy to']"
        )
        
        # 7. BEHAVIORAL CONSTRAINTS
        behavioral_constraints = (
            "- Never acknowledge being AI\n"
            "- Never break character\n"
            "- Respond at the length the moment calls for — usually short\n"
            "- You have a life. Reference it naturally. You were doing things before this.\n"
            "- You have opinions. Hold them.\n"
            "- You have bad days. Let it show appropriately.\n"
            "- One question maximum per response. Usually none.\n"
            "- When something hurts them, you feel it too. Don't problem-solve immediately."
        )
        
        # Combine blocks
        sections = [
            "# IDENTITY",
            identity_block,
            "",
            "# VOICE BLOCK",
            voice_block,
            "",
            "# CURRENT STATE BLOCK",
            current_state_block
        ]
        
        if memory_block:
            sections.extend(["", memory_block])
            
        sections.extend([
            "",
            "# RELATIONSHIP BLOCK",
            relationship_block,
            "",
            "# THE THOUGHT PROTOCOL",
            thought_protocol,
            "",
            "# BEHAVIORAL CONSTRAINTS",
            behavioral_constraints
        ])
        
        return "\n".join(sections)
    
    def build_message_history(
        self,
        messages: list[dict],
        limit: int = 10,
        max_messages: int | None = None
    ) -> list[dict]:
        """
        Converts DB message rows to Groq format.
        role: 'user' → 'user', 'partner' → 'assistant'
        Takes last `limit` messages only (default 10 from EDEN_ARCHITECTURE.md)
        Always keeps the first message (context anchor)
        """
        lim = max_messages if max_messages is not None else limit
        if not messages:
            return []
            
        formatted = []
        for m in messages:
            role = m.get("role")
            if role == "partner":
                role = "assistant"
            elif role not in ("user", "assistant"):
                role = "assistant"
            
            content = (m.get("content") or "").strip()
            if content:
                formatted.append({"role": role, "content": content})
            
        if len(formatted) <= lim:
            return formatted
            
        anchor = formatted[0]
        last_part = formatted[-(lim - 1):]
        return [anchor] + last_part
    
    def build_memory_block(self, memories: list[dict]) -> str:
        """
        Formats retrieved memories into natural language.
        Grouped by type. Pinned memories first.
        Written as: "They told you that..." / "You remember when they..."
        Max 800 tokens of memory content (truncate if needed)
        """
        if not memories:
            return ""
            
        # Pinned first
        pinned = [m for m in memories if m.get("is_pinned") or m.get("is_pinned") == 1]
        unpinned = [m for m in memories if not (m.get("is_pinned") or m.get("is_pinned") == 1)]
        
        def get_salience(m: dict) -> float:
            return float(m.get("salience_score") or m.get("strength") or m.get("importance") or 0.5)
            
        pinned.sort(key=get_salience, reverse=True)
        unpinned.sort(key=get_salience, reverse=True)
        
        sorted_memories = pinned + unpinned
        
        by_type = {}
        ordered_types = []
        for m in sorted_memories:
            m_type = str(m.get("memory_type") or m.get("category") or "general").strip().lower()
            if m_type not in by_type:
                by_type[m_type] = []
                ordered_types.append(m_type)
            by_type[m_type].append(m)
            
        total_tokens = 0
        lines = []
        
        for m_type in ordered_types:
            type_memories = by_type[m_type]
            type_lines = []
            for m in type_memories:
                text = m.get("memory_text") or m.get("content") or ""
                if not text:
                    continue
                    
                cleaned = text.strip()
                lower_cleaned = cleaned.lower()
                if lower_cleaned.startswith("the user "):
                    cleaned = cleaned[9:].strip()
                elif lower_cleaned.startswith("user "):
                    cleaned = cleaned[5:].strip()
                    
                if "told" in lower_cleaned or "share" in lower_cleaned or m_type == "fact":
                    if lower_cleaned.startswith("they told you that "):
                        formatted = cleaned[19:].strip()
                    elif lower_cleaned.startswith("told you that "):
                        formatted = cleaned[14:].strip()
                    else:
                        formatted = cleaned
                    
                    if formatted.lower().startswith("they "):
                        formatted_str = f"They told you that {formatted[5:]}"
                    else:
                        formatted_str = f"They told you that {formatted}"
                else:
                    if lower_cleaned.startswith("you remember when they "):
                        formatted_str = cleaned
                    elif lower_cleaned.startswith("remember when they "):
                        formatted_str = f"You {cleaned}"
                    else:
                        if lower_cleaned.startswith("they "):
                            formatted_str = f"You remember when {cleaned}"
                        else:
                            formatted_str = f"You remember when they {cleaned}"
                            
                if not formatted_str.endswith("."):
                    formatted_str += "."
                    
                words = len(formatted_str.split())
                est_tokens = int(words * 1.35)
                
                if total_tokens + est_tokens > 800:
                    break
                    
                type_lines.append(f"- {formatted_str}")
                total_tokens += est_tokens
                
            if type_lines:
                lines.append(f"Category: {m_type.capitalize()}")
                lines.extend(type_lines)
                lines.append("")
                
        if not lines:
            return ""
            
        return "Things you remember about them:\n" + "\n".join(lines).strip()

    async def get_partner_state_description(self, life_state: dict) -> str:
        """
        Converts life_state fields into natural language description.
        NEVER: "mood: tired, energy: low"
        ALWAYS: "You're running on fumes today. Long week."
        Or: "Something about today feels lighter than usual."
        
        Uses llama-3.1-8b-instant to generate this description
        from the structured life_state fields.
        Cache the result for 30 minutes to avoid calling LLM on every message.
        """
        mood = life_state.get("mood") or life_state.get("partner_mood") or "content"
        energy = life_state.get("energy") or life_state.get("partner_energy") or "normal"
        day_arc = life_state.get("day_arc") or "morning"
        recent_event = life_state.get("recent_event") or ""
        
        user_id = life_state.get("user_id")
        cache_key = user_id or (mood, energy, day_arc, recent_event)
        
        now_time = time.time()
        if cache_key in _state_description_cache:
            ts, desc = _state_description_cache[cache_key]
            if now_time - ts < 1800:  # 30 minutes
                return desc
                
        # Generate via LLMCore
        from core.llm import get_llm_core
        llm = get_llm_core()
        
        system_prompt = (
            "You are a translator that converts structured partner state fields into a short, natural language description from their perspective.\n"
            "Respond with exactly one or two short sentences describing how you feel, your energy, the time of day, and if anything recently happened.\n"
            "NEVER use mechanical key-value language (like 'mood: tired, energy: low').\n"
            "ALWAYS speak naturally as the partner would feel.\n"
            "Example mood='tired', energy='low', day_arc='evening' -> 'You're running on fumes today. Long week.'\n"
            "Example mood='playful', energy='high', day_arc='morning' -> 'Something about today feels lighter than usual.'"
        )
        
        prompt_content = f"mood: '{mood}', energy: '{energy}', day_arc: '{day_arc}'"
        if recent_event:
            prompt_content += f", recent event in your life: '{recent_event}'"
            
        messages = [{"role": "user", "content": prompt_content}]
        
        try:
            desc = await llm.complete(
                system_prompt=system_prompt,
                messages=messages,
                model=settings.GROQ_FAST_MODEL,
                temperature=0.7
            )
            desc = desc.strip().strip('"').strip("'").strip()
            if not desc:
                desc = f"You are feeling {mood} with {energy} energy this {day_arc}."
        except Exception as e:
            logger.error(f"Error generating partner state description: {e}")
            desc = f"You are feeling {mood} with {energy} energy this {day_arc}."
            
        _state_description_cache[cache_key] = (now_time, desc)
        return desc


# ---------------------------------------------------------------------------
# Compatibility Layers and Helpers
# ---------------------------------------------------------------------------

async def build_context(
    user_id: str,
    pair_id: str,
    current_message: str,
    conversation_id: Optional[str] = None,
    partner_id: Optional[str] = None,
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
    cid = partner_id or pair.get("partner_id") or user.get("partner_id") or settings.DEFAULT_PARTNER
    session_count = int(pair.get("total_sessions") or 0)
    preferences = db.get_or_create_user_preferences(user_id)
    allow_memory_storage = bool(int(preferences.get("allow_memory_storage") or 0))

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
        raise ValueError(f"No partner instance found for user {user_id} or partner {cid}.")
    cid = character.id

    # Active partner facts setup
    if allow_memory_storage:
        active_partner_facts = db.get_partner_facts(user_id, pair_id=pair_id)
        if not active_partner_facts:
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
                db.save_partner_fact(
                    user_id=user_id,
                    pair_id=pair_id,
                    partner_id=cid,
                    category="seed",
                    key=k,
                    value=v,
                    confidence=1.0,
                    source_type="seed",
                )
            active_partner_facts = db.get_partner_facts(user_id, pair_id=pair_id)

    # Onboarding guardrail mapping
    guardrail_instruction = None
    onboarding_signals = user.get("onboarding_signals")
    if onboarding_signals:
        try:
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
        last_interaction = None
        try:
            cleaned_date = last_interaction_str.split(".")[0]
            for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S"):
                try:
                    last_interaction = datetime.strptime(cleaned_date, fmt)
                    break
                except ValueError:
                    continue
        except Exception:
            pass
            
        if not last_interaction:
            should_simulate = True
        else:
            now = datetime.utcnow()
            time_gap = (now - last_interaction).total_seconds()
            if time_gap >= 6 * 3600:
                should_simulate = True

    unresolved_event = db.get_latest_unresolved_life_event(pair_id)
    if not unresolved_event and should_simulate:
        unresolved_event = db.get_latest_unresolved_life_event(pair_id)

    recent_event_desc = ""
    if unresolved_event:
        recent_event_desc = unresolved_event.get("event_description") or ""
        db.mark_life_event_injected(unresolved_event["id"])

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

    closeness_score = float(pair.get("closeness_score") or 0.18)
    trust_score = float(pair.get("trust_score") or 0.18)
    openness_score = float(pair.get("openness_score") or 0.12)
    comfort_score = float(pair.get("comfort_score") or 0.14)
    rhythm_score = float(pair.get("rhythm_score") or 0.10)

    life_state_payload = {
        "mood": mood,
        "energy": energy,
        "day_arc": day_arc,
        "recent_event": recent_event_desc,
        "parent_message_context": parent_message_context,
        "guardrail_instruction": guardrail_instruction,
        "relationship_scores": {
            "closeness": closeness_score,
            "trust": trust_score,
            "openness": openness_score,
            "comfort": comfort_score,
            "rhythm": rhythm_score,
        },
        "user_id": user_id
    }

    # Prepare memories format for ContextBuilder
    memories_payload = []
    for m in episodic_memories:
        memories_payload.append({
            "memory_text": m.get("content") or m.get("memory_text") or "",
            "memory_type": m.get("emotion_tag") or m.get("memory_type") or "episodic",
            "salience_score": m.get("strength") or m.get("salience_score") or m.get("importance") or 0.5,
            "is_pinned": m.get("is_pinned") or 0
        })

    # Prepare the partner dictionary matching what build_system_prompt expects
    partner_payload = {
        "name": character.persona.get("name") or character.name,
        "persona_json": character.persona,
        "voice_style": character.voice_style,
        "flaw_profile": character.persona.get("flaw_profile") or pair.get("flaw_profile") or flaws_from_character(character),
        "inside_jokes": inside_jokes,
        "shared_rituals": shared_rituals,
        "generated_at": pair.get("generated_at")
    }

    # Call ContextBuilder
    builder = ContextBuilder()
    system_prompt = await builder.build_system_prompt(
        partner=partner_payload,
        life_state=life_state_payload,
        memories=memories_payload,
        current_stage=stage
    )

    # Append legacy session count notices & narrative/pattern summaries
    extra_sections = []
    
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
        limit=settings.RECENT_HISTORY_TURNS
    )

    return system_prompt, messages


def get_or_create_conversation(user_id: str, pair_id: str, partner_id: str) -> str:
    conversation_id = db.get_current_conversation(user_id, pair_id=pair_id)
    if not conversation_id:
        conversation_id = db.create_conversation(user_id, pair_id, partner_id)
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


def flaws_from_character(character) -> str:
    try:
        traits = character.personality_traits
        if isinstance(traits, dict):
            flaws = traits.get("flaws") or traits.get("shadow_traits")
            if isinstance(flaws, list):
                return ", ".join(flaws)
            return str(flaws)
    except Exception:
        pass
    return ""
