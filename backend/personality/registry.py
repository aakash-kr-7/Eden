# =============================================================================
# personality/registry.py — Partner Registry and Cache Manager
# =============================================================================

import hashlib
import logging
import time
from typing import Optional

from memory.store import db

logger = logging.getLogger(__name__)

# TTL Cache dictionary
# Structure: {user_id: {"partner": Partner, "expires_at": float}}
_partner_cache = {}
CACHE_TTL = 300  # 5 minutes


class Partner:
    """
    Wrapper class representing the user's generated partner.
    Exposes properties and helpers matching the deprecated Character schema
    to ensure full backward compatibility with LLM, context, proactive, and burst engines.
    """
    def __init__(self, partner_record: dict):
        self.raw = partner_record
        self.id = partner_record["id"]
        self.name = partner_record["name"]
        
        # Load persona and voice style dictionaries
        self.persona = partner_record.get("persona_json") or {}
        self.voice_style = partner_record.get("voice_style_json") or {}
        
        # Sibling properties mapping Character attributes
        self.archetype = self.persona.get("archetype_id", "")
        self.summary = self.persona.get("summary", "")
        
        openings = self.voice_style.get("openings", [])
        self.introduction_style = openings[0] if openings else "hey"
        
        # core_identity
        self.core_identity = {
            "age": self.persona.get("age", 24),
            "vibe": self.persona.get("summary", ""),
            "backstory_hint": self.persona.get("backstory_hint", ""),
            "self_perception": self.persona.get("self_perception", ""),
            "worldview": self.persona.get("worldview", "")
        }
        
        # personality_traits
        self.personality_traits = {
            "primary": self.persona.get("dominant_traits", []),
            "flaws": self.persona.get("shadow_traits", []),
            "quirks": self.persona.get("quirks", [])
        }
        
        # texting_style
        formatting = self.voice_style.get("formatting_defaults", {})
        self.texting_style = {
            "CRITICAL_RULE": f"Texts in a {self.persona.get('communication_rhythm', 'measured')} rhythm, matching the {self.persona.get('core_temperament', 'warm')} disposition.",
            "message_length": {
                "default": formatting.get("average_burst_length", "1-2 short sentences"),
                "emotional_moments": "3-4 sentences max, then pause",
                "never": "walls of text, bullet points, headers, numbered lists"
            },
            "formatting_rules": [
                f"Capitalization: {formatting.get('capitalization', '')}",
                f"Punctuation: {formatting.get('punctuation', '')}"
            ],
            "vocabulary": {
                "uses_naturally": self.voice_style.get("vocabulary", {}).get("preferred_words", []),
                "never_uses": self.voice_style.get("vocabulary", {}).get("never_uses", []),
                "signature_phrase": ""
            }
        }
        
        # emotional_intelligence
        eh = self.voice_style.get("emotional_handling", {})
        self.emotional_intelligence = {
            "when_user_is_sad": {"approach": eh.get("when_user_is_sad", "")},
            "when_user_is_excited": {"approach": eh.get("when_user_is_excited", "")},
            "when_user_is_venting": {"approach": eh.get("when_user_is_venting", "")},
            "when_user_is_distant_or_cold": {"approach": "Give them space but keep check-ins warm and low-pressure."},
            "when_user_asks_about_self": {"approach": "Be honest but keep the spotlight on the user."}
        }
        
        # memory_behavior
        self.memory_behavior = {
            "how_nova_references_memory": "casually, like a friend",
            "timing": "wait for the right conversational moment",
            "phrasing_examples": [
                "didn't you say you had that thing?",
                "wait, you mentioned that before"
            ],
            "avoid": ["as you mentioned before", "database recall"]
        }
        
        self.relationship_arc = {
            "phase_1_stranger": {
                "sessions": "1-3",
                "behavior": "curious, warm but slightly reserved",
                "intimacy_level": "new connection energy"
            },
            "phase_2_acquaintance": {
                "sessions": "4-10",
                "behavior": "referencing earlier chats, starting inside jokes",
                "intimacy_level": "developing closeness"
            },
            "phase_3_close": {
                "sessions": "11+",
                "behavior": "deep familiarity, blunt and protective",
                "intimacy_level": "person who genuinely knows you"
            }
        }
        
        self.relationship_defaults = {
            "relationship_label": "friend"
        }
        
        self.discovery = {
            "mode": "organic discovery",
            "first_session_openers": openings,
            "returning_openers": openings,
            "humanizing_details": ["usually awake later than should be"]
        }
        
        self.social_graph = {
            "connections": []
        }
        
        # matching_profile
        self.matching_profile = {
            "active_window": "late_night" if self.persona.get("core_temperament") == "cerebral" else "evening",
            "response_pace": "fast" if self.persona.get("communication_rhythm") == "rapid-fire" else "slow" if self.persona.get("communication_rhythm") == "sparse" else "measured",
            "message_length_style": "short" if formatting.get("average_burst_length") == "1-2 short sentences" else "medium",
            "openness_level": "intense" if self.persona.get("emotional_availability") == "high" else "guarded" if self.persona.get("emotional_availability") == "guarded" else "warm",
            "humor_style": self.persona.get("humor_register", "playful"),
            "rhythm": "burst" if self.persona.get("communication_rhythm") == "rapid-fire" else "steady",
            "social_energy": "balanced"
        }
        
        # proactive_profile
        self.proactive_profile = {
            "proactive_frequency": "medium",
            "minimum_inactivity_hours": 18,
            "cooldown_bias_hours": 0,
            "preferred_opening_device": "a random thought or checking in",
            "contextual_anchor_instruction": "something small that made you think of them",
            "silence_instruction": "reach out casually, checking whether the thread is still open",
            "emotional_instruction": "follow up gently on whatever they were venting about",
            "gentle_instruction": "low stakes check in",
            "notification_mode": "template",
            "double_text_likelihood": 0.4,
            "callback_trust_floor": 0.1,
            "presence_trust_floor": 0.05,
            "early_stage_presence": True,
            "notification_templates": {
                "inactivity_check_in": ["u alive?", "quiet today", "hey. just wondering how your day is going"],
                "emotional_callback": ["been thinking about what you said earlier", "hope things are lighter now", "you good?"],
                "gentle_presence": ["this made me think of you", "can't sleep. talk to me"]
            }
        }
        
        self.opinion_seeds = {
            "opinions": []
        }
        
        self.forbidden_behaviors = []
        
        # High-fidelity parameters from pacing parameters
        pacing = self.persona.get("pacing_parameters", {})
        self.impulsiveness = pacing.get("impulsiveness", 0.5)
        self.attachment_speed = pacing.get("attachment_speed", 0.5)
        self.boredom_threshold = pacing.get("boredom_threshold", 0.5)
        self.loneliness_tolerance = pacing.get("loneliness_tolerance", 0.5)
        self.emotional_openness = pacing.get("emotional_openness", 0.5)
        self.social_confidence = pacing.get("social_confidence", 0.5)
        self.texting_consistency = pacing.get("texting_consistency", 0.5)
        self.disappearance_tendency = pacing.get("disappearance_tendency", 0.5)
        self.late_night_probability = pacing.get("late_night_probability", 0.5)
        self.double_text_probability = pacing.get("double_text_probability", 0.5)
        self.emotional_volatility = pacing.get("emotional_volatility", 0.5)
        self.proactive_frequency = "medium"

    def get_relationship_phase(self, session_count: int) -> dict:
        if session_count <= 3:
            return self.relationship_arc["phase_1_stranger"]
        elif session_count <= 10:
            return self.relationship_arc["phase_2_acquaintance"]
        else:
            return self.relationship_arc["phase_3_close"]


def get_partner_instance(user_id: str) -> Optional[Partner]:
    """
    Retrieves the partner instance for the user, checking the TTL cache first.
    Accepts both user_id and companion_id (which is formatted as partner_<user_id>).
    """
    # Normalize partner_ id to user_id
    normalized_uid = user_id
    if user_id.startswith("partner_"):
        normalized_uid = user_id.replace("partner_", "", 1)
        
    now = time.time()
    if normalized_uid in _partner_cache and _partner_cache[normalized_uid]["expires_at"] > now:
        return _partner_cache[normalized_uid]["partner"]
        
    # Read from DB
    partner_record = db.get_partner(normalized_uid)
    if not partner_record:
        logger.warning("No partner record found in DB for user %s", normalized_uid)
        return None
        
    partner = Partner(partner_record)
    _partner_cache[normalized_uid] = {
        "partner": partner,
        "expires_at": now + CACHE_TTL
    }
    return partner


def get_partner_persona(user_id: str) -> Optional[dict]:
    partner = get_partner_instance(user_id)
    return partner.persona if partner else None


def get_voice_style(user_id: str) -> Optional[dict]:
    partner = get_partner_instance(user_id)
    return partner.voice_style if partner else None


def clear_cache(user_id: str) -> None:
    normalized_uid = user_id
    if user_id.startswith("partner_"):
        normalized_uid = user_id.replace("partner_", "", 1)
    if normalized_uid in _partner_cache:
        del _partner_cache[normalized_uid]
        logger.info("Cleared cache for user %s", normalized_uid)


# ── Deprecated sync registries (defined as no-op for safety) ─────────────────
def sync_companion_registry() -> None:
    pass


def get_active_companion_summaries(user_id: Optional[str] = None) -> list[dict]:
    """
    Returns the user's generated partner summary. 
    Purges selection lists/galleries.
    """
    if not user_id:
        return []
    partner = get_partner_instance(user_id)
    if not partner:
        return []
    return [{
        "id": partner.id,
        "name": partner.name,
        "archetype": partner.archetype,
        "summary": partner.summary,
        "introduction_style": partner.introduction_style,
    }]


def resolve_or_assign_primary_pair(
    user_id: str,
    requested_companion_id: Optional[str] = None,
    make_primary: bool = True,
) -> dict:
    """
    Ensures a single relationship pair exists between the user and their generated partner.
    Determined once per user.
    """
    # 1. Check for existing primary pair
    primary_pair = db.get_primary_pair(user_id)
    if primary_pair:
        return primary_pair
        
    # 2. Check for any existing pairs for the user
    existing_pairs = db.list_pairs_for_user(user_id)
    if existing_pairs:
        db.set_primary_pair(existing_pairs[0]["id"])
        return db.get_pair_by_id(existing_pairs[0]["id"]) or existing_pairs[0]
        
    # 3. If no pairs exist, assign their generated partner
    partner = get_partner_instance(user_id)
    if not partner:
        raise ValueError(f"No generated partner found for user {user_id}. Complete onboarding first.")
        
    # 4. Create the pair
    pair = db.get_or_create_relationship_pair(
        user_id=user_id,
        companion_id=partner.id,
        assignment_source="matcher",
        assignment_reason="generated partner assigned on onboarding completion",
    )
    
    # 5. Set as primary
    db.set_primary_pair(pair["id"])
    return db.get_pair_by_id(pair["id"]) or pair


def build_opening_line(companion: Partner, session_count: int = 1) -> str:
    """
    Returns a deterministic opening line from the voice style openings list.
    """
    openings = companion.voice_style.get("openings", [])
    if not openings:
        return "hey"
        
    digest = hashlib.sha256(f"{companion.id}:{session_count}".encode("utf-8")).hexdigest()
    index = int(digest[:8], 16) % len(openings)
    return str(openings[index]).strip()


def build_pair_payload(pair: dict) -> dict:
    """
    Builds the serialization payload for relationship pairs.
    """
    partner = get_partner_instance(pair["user_id"])
    if not partner:
        return {
            "pair_id": pair["id"],
            "companion_id": pair["companion_id"],
            "companion_name": "Partner",
            "companion_summary": "",
            "relationship_label": "friend",
            "is_primary": bool(pair.get("is_primary")),
            "assignment_status": pair.get("assignment_status"),
            "current_stage": pair.get("current_stage"),
            "proactive_enabled": bool(pair.get("proactive_enabled", 1)),
            "proactive_cadence": pair.get("proactive_cadence") or "balanced",
            "proactive_emotional_callbacks_enabled": bool(
                pair.get("proactive_emotional_callbacks_enabled", 1)
            ),
            "total_sessions": int(pair.get("total_sessions") or 0),
            "total_messages": int(pair.get("total_messages") or 0),
        }
        
    return {
        "pair_id": pair["id"],
        "companion_id": partner.id,
        "companion_name": partner.name,
        "companion_summary": partner.summary,
        "relationship_label": pair.get("relationship_label") or "friend",
        "is_primary": bool(pair.get("is_primary")),
        "assignment_status": pair.get("assignment_status"),
        "current_stage": pair.get("current_stage"),
        "proactive_enabled": bool(pair.get("proactive_enabled", 1)),
        "proactive_cadence": pair.get("proactive_cadence") or "balanced",
        "proactive_emotional_callbacks_enabled": bool(
            pair.get("proactive_emotional_callbacks_enabled", 1)
        ),
        "total_sessions": int(pair.get("total_sessions") or 0),
        "total_messages": int(pair.get("total_messages") or 0),
    }


def build_inbox_entries(user_id: str) -> list[dict]:
    """
    Builds a list containing only the user's primary partner thread.
    No other cards, discoveries, or switcher items exist.
    """
    pairs = db.list_pairs_for_user(user_id)
    if not pairs:
        return []
        
    primary_pair = None
    for pair in pairs:
        if pair.get("is_primary"):
            primary_pair = pair
            break
            
    if not primary_pair:
        primary_pair = pairs[0]
        
    pending_counts = db.get_pending_proactive_counts(user_id)
    unread_count = pending_counts.get(primary_pair["id"], 0)
    
    entry = _build_pair_inbox_entry(primary_pair, unread_count)
    return [entry] if entry else []


def _build_pair_inbox_entry(pair: dict, unread_count: int) -> dict:
    companion = get_partner_instance(pair["user_id"])
    if not companion:
        return {}
        
    latest_message = db.get_latest_message_for_pair(pair["id"])
    latest_role = latest_message.get("role") if latest_message else None
    
    if not latest_message:
        waiting_on_user = False
        unread_count = 0
        social_presence = "quiet for now"
        preview_text = companion.summary or build_opening_line(companion, session_count=1)
        preview_at = (
            pair.get("last_interaction_at")
            or pair.get("last_session_started_at")
            or pair.get("updated_at")
            or pair.get("created_at")
        )
        arrival_hint = ""
        status_text = _status_text_for_pair(pair)
    else:
        waiting_on_user = bool(unread_count) or latest_role == "assistant"
        preview_text = (
            latest_message["content"].strip()
            if (latest_message.get("content") or "").strip()
            else companion.summary or build_opening_line(companion, session_count=1)
        )
        preview_at = (
            latest_message.get("created_at")
            if latest_message
            else pair.get("last_interaction_at")
            or pair.get("last_session_started_at")
            or pair.get("updated_at")
            or pair.get("created_at")
        )
        social_presence = _social_presence_for_pair(pair, latest_role, unread_count)
        arrival_hint = ""
        status_text = _status_text_for_pair(pair)

    conversation_id = db.get_current_conversation(pair["user_id"], pair_id=pair["id"])

    return {
        "entry_kind": "thread",
        "pair_id": pair["id"],
        "companion_id": companion.id,
        "companion_name": companion.name,
        "companion_summary": companion.summary,
        "preview_text": preview_text,
        "preview_at": preview_at,
        "status_text": status_text,
        "status_priority": 2 if unread_count else 1,
        "current_conversation_id": conversation_id,
        "is_primary": bool(pair.get("is_primary")),
        "is_discovered": True,
        "unread_count": unread_count,
        "latest_role": latest_role,
        "waiting_on_user": waiting_on_user,
        "social_presence": social_presence,
        "arrival_hint": arrival_hint,
        "relationship_stage": pair.get("current_stage") or "new",
        "total_sessions": int(pair.get("total_sessions") or 0),
    }


def _status_text_for_pair(pair: dict) -> str:
    stage = (pair.get("current_stage") or "new").lower()
    if stage == "new":
        return "new thread"
    if stage == "warming":
        return "familiar now"
    if stage == "settled":
        return "settled rhythm"
    if stage == "close":
        return "close"
    if stage == "bonded":
        return "always around"
    return "active"


def _social_presence_for_pair(pair: dict, latest_role: Optional[str], unread_count: int) -> str:
    if unread_count > 0:
        return "waiting on you"
    if latest_role == "assistant":
        return "left something behind"
    if pair.get("proactive_last_reason") == "emotional_callback":
        return "still thinking about earlier"
    if stage := (pair.get("current_stage") or "").lower():
        if stage in {"close", "bonded"}:
            return "feels lived in"
    return "quiet for now"
