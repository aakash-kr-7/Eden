import random
import hashlib
import logging
import json

from personality.loader import list_archetypes, load_archetype
from personality.mutator import mutate_persona
from personality.voice_synthesizer import synthesize_voice
from core.llm import get_llm_core

logger = logging.getLogger(__name__)


def _get_seeded_rng(user_id: str) -> random.Random:
    """Creates a local deterministic random number generator seeded by user_id."""
    seed_int = int(hashlib.sha256(user_id.encode("utf-8")).hexdigest(), 16) % (2**32)
    return random.Random(seed_int)


async def infer_attachment_style(response_text: str) -> str:
    """Uses the LLM to classify user's open-text connection description into an attachment style."""
    system_prompt = (
        "You are an expert psychologist. Analyze the user's connection style response and "
        "classify it into one of the following attachment styles: secure, anxious, avoidant. "
        "Respond with a JSON object containing a single key: 'attachment_style'."
    )
    schema = {
        "type": "object",
        "properties": {
            "attachment_style": {
                "type": "string",
                "enum": ["secure", "anxious", "avoidant"]
            }
        },
        "required": ["attachment_style"]
    }
    messages = [{"role": "user", "content": f"User connection style response: \"{response_text}\""}]
    try:
        core = get_llm_core()
        result = await core.complete_structured(system_prompt, messages, schema, temperature=0.1)
        style = result.get("attachment_style", "secure")
        if style in ["secure", "anxious", "avoidant"]:
            return style
    except Exception as e:
        logger.error(f"Error inferring attachment style: {e}")
    return "secure"


def _map_user_onboarding(onboarding_data: dict) -> dict:
    """Legacy mapper fallback, kept for safety."""
    conn_style = onboarding_data.get("connection_style", "easy_to_talk_to")
    depth_pref = onboarding_data.get("depth_preference", "little_honesty")
    
    attachment_map = {
        "takes_their_time": "avoidant",
        "easy_to_talk_to": "secure",
        "says_whats_on_mind": "secure",
        "makes_things_fun": "anxious",
        "meaningful_conversations": "anxious",
    }
    user_attachment = attachment_map.get(conn_style, "secure")
    
    depth_map = {
        "let_it_happen": "surface",
        "little_honesty": "medium",
        "dont_mind_personal": "deep",
        "skip_small_talk": "deep",
    }
    user_depth = depth_map.get(depth_pref, "medium")
    
    intent_map = {
        "let_it_happen": "friendship",
        "little_honesty": "companionship",
        "dont_mind_personal": "romance",
        "skip_small_talk": "open",
    }
    user_intent = intent_map.get(depth_pref, "companionship")
    
    return {
        "attachment_style": user_attachment,
        "emotional_depth_preference": user_depth,
        "relationship_type_intent": user_intent,
    }


async def generate_partner(onboarding_data: dict, user_id: str) -> dict:
    """
    Determines and generates the user's permanent companion partner from onboarding answers.
    Guarantees absolute determinism per user_id (apart from LLM classification step).
    """
    logger.info("Starting partner generation for user %s", user_id)
    rng = _get_seeded_rng(user_id)

    # 1. Infer attachment style if not already resolved
    inferred_attachment = onboarding_data.get("attachment_style")
    if not inferred_attachment:
        connection_text = onboarding_data.get("connection_style", "")
        inferred_attachment = await infer_attachment_style(connection_text)

    depth_raw = onboarding_data.get("emotional_depth_preference", "")
    depth_to_pref = {
        "a lot — I go deep": "dont_mind_personal",
        "some things — when it feels right": "little_honesty",
        "not much — I'm more private": "let_it_happen"
    }
    mapped_depth_pref = depth_to_pref.get(depth_raw, "little_honesty")

    intent_raw = onboarding_data.get("relationship_type_intent", "")
    intent_map = {
        "someone to talk to": "friendship",
        "a real friendship": "friendship",
        "something that might become more": "romance",
        "I'm not sure yet": "open"
    }
    mapped_intent = intent_map.get(intent_raw, "friendship")

    # Construct mapped onboarding dictionary for mutator compatibilities
    mapped_onboarding = {
        **onboarding_data,
        "connection_style": {
            "secure": "easy_to_talk_to",
            "avoidant": "takes_their_time",
            "anxious": "meaningful_conversations"
        }.get(inferred_attachment, "easy_to_talk_to"),
        "depth_preference": mapped_depth_pref,
        "attachment_style": inferred_attachment,
        "emotional_depth_preference": depth_raw,
        "relationship_type_intent": intent_raw
    }

    # 2. Score each archetype based on compatibility weights
    user_profile = {
        "attachment_style": inferred_attachment,
        "emotional_depth_preference": {
            "a lot — I go deep": "deep",
            "some things — when it feels right": "medium",
            "not much — I'm more private": "surface"
        }.get(depth_raw, "medium"),
        "relationship_type_intent": mapped_intent,
    }

    scored_candidates = []
    for arch_dict in list_archetypes():
        arch_id = arch_dict["archetype_id"]
        arch = load_archetype(arch_id)
        weights = arch.get("compatibility_weights", {})

        score = 0.0
        score += weights.get("attachment_style", {}).get(user_profile["attachment_style"], 0.5)
        score += weights.get("emotional_depth_preference", {}).get(user_profile["emotional_depth_preference"], 0.5)
        score += weights.get("relationship_type_intent", {}).get(user_profile["relationship_type_intent"], 0.5)
        score /= 3.0

        noise = rng.uniform(-0.15, 0.15)
        final_score = score + noise

        scored_candidates.append({
            "archetype": arch,
            "score": final_score
        })

    # Select candidate
    scored_candidates.sort(key=lambda x: x["score"], reverse=True)
    selected_archetype = scored_candidates[0]["archetype"]
    logger.info("Selected archetype '%s' for user %s with score %.3f", 
                selected_archetype["archetype_id"], user_id, scored_candidates[0]["score"])

    # 3. Mutate archetype persona
    mutated_persona = mutate_persona(selected_archetype, mapped_onboarding, rng)

    # 4. Synthesize voice
    voice_style = synthesize_voice(mutated_persona, rng)

    # 5. Return complete partner structure
    partner_id = f"partner_{user_id}"
    return {
        "id": partner_id,
        "user_id": user_id,
        "name": mutated_persona["name"],
        "archetype_id": selected_archetype["archetype_id"],
        "persona_json": mutated_persona,
        "voice_style_json": voice_style,
    }


class PersonalityGenerator:
    """Generator class wrapper for companion personalities."""
    @classmethod
    async def generate(cls, onboarding_data: dict, user_id: str) -> dict:
        return await generate_partner(onboarding_data, user_id)
