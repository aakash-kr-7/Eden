import random
import hashlib
import logging

from personality.loader import list_archetypes, load_archetype
from personality.mutator import mutate_persona
from personality.voice_synthesizer import synthesize_voice

logger = logging.getLogger(__name__)


def _get_seeded_rng(user_id: str) -> random.Random:
    """Creates a local deterministic random number generator seeded by user_id."""
    seed_int = int(hashlib.sha256(user_id.encode("utf-8")).hexdigest(), 16) % (2**32)
    return random.Random(seed_int)


def _map_user_onboarding(onboarding_data: dict) -> dict:
    """
    Maps onboarding questions q2-q5 to compatibility metrics:
    - attachment_style
    - emotional_depth_preference
    - relationship_type_intent
    """
    conn_style = onboarding_data.get("connection_style", "easy_to_talk_to")
    depth_pref = onboarding_data.get("depth_preference", "little_honesty")

    # Map q2 -> attachment_style
    attachment_map = {
        "takes_their_time": "avoidant",
        "easy_to_talk_to": "secure",
        "says_whats_on_mind": "secure",
        "makes_things_fun": "anxious",
        "meaningful_conversations": "anxious",
    }
    user_attachment = attachment_map.get(conn_style, "secure")

    # Map q4 -> emotional_depth_preference
    depth_map = {
        "let_it_happen": "surface",
        "little_honesty": "medium",
        "dont_mind_personal": "deep",
        "skip_small_talk": "deep",
    }
    user_depth = depth_map.get(depth_pref, "medium")

    # Map q4 -> relationship_type_intent
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


def generate_partner(onboarding_data: dict, user_id: str) -> dict:
    """
    Determines and generates the user's permanent companion partner from onboarding answers.
    Guarantees absolute determinism per user_id.
    """
    logger.info("Starting partner generation for user %s", user_id)
    rng = _get_seeded_rng(user_id)

    # 1. Map onboarding responses to user profile metrics
    user_profile = _map_user_onboarding(onboarding_data)

    # 2. Score each archetype from the seed files
    archetype_ids = list_archetypes()
    scored_candidates = []

    for arch_dict in list_archetypes():
        arch_id = arch_dict["archetype_id"]
        arch = load_archetype(arch_id)
        weights = arch.get("compatibility_weights", {})

        # Calculate base compatibility score (0.0 - 1.0)
        score = 0.0
        score += weights.get("attachment_style", {}).get(user_profile["attachment_style"], 0.5)
        score += weights.get("emotional_depth_preference", {}).get(user_profile["emotional_depth_preference"], 0.5)
        score += weights.get("relationship_type_intent", {}).get(user_profile["relationship_type_intent"], 0.5)
        score /= 3.0

        # Add controlled noise (+- 0.15) to break determinism matches across users
        noise = rng.uniform(-0.15, 0.15)
        final_score = score + noise

        scored_candidates.append({
            "archetype": arch,
            "score": final_score
        })

    # Select the highest-scoring candidate (stable sort to ensure determinism for ties)
    scored_candidates.sort(key=lambda x: x["score"], reverse=True)
    selected_archetype = scored_candidates[0]["archetype"]
    logger.info("Selected archetype '%s' for user %s with score %.3f", 
                selected_archetype["archetype_id"], user_id, scored_candidates[0]["score"])

    # 3. Pass archetype + user profile to mutator
    mutated_persona = mutate_persona(selected_archetype, onboarding_data, rng)

    # 4. Pass mutated result to voice synthesizer
    voice_style = synthesize_voice(mutated_persona, rng)

    # 5. Return the complete partner structure
    partner_id = f"partner_{user_id}"
    return {
        "id": partner_id,
        "user_id": user_id,
        "name": mutated_persona["name"],
        "archetype_id": selected_archetype["archetype_id"],
        "persona_json": mutated_persona,
        "voice_style_json": voice_style,
    }
