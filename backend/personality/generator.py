# ═══════════════════════════════════════════════════════════════════
# FILE: backend/personality/generator.py
# PURPOSE: Selects and generates a unique partner for a user on onboarding.
# CONTEXT: Called once per user. Partner is permanent after generation.
# ═══════════════════════════════════════════════════════════════════

import random
import hashlib
import logging
import json
from pathlib import Path

from personality.mutator import Mutator
from personality.voice_synthesizer import VoiceSynthesizer

logger = logging.getLogger(__name__)


class PersonalityGenerator:
    def generate_partner(
        self,
        user_id: str,
        onboarding_data: dict
    ) -> dict:
        """
        1. Load all 12 archetypes
        2. Score each against user profile using compatibility_weights
        3. Add ±0.15 noise (seeded with user_id for reproducibility)
        4. Select highest-scoring archetype
        5. Call Mutator.mutate(archetype, onboarding_data)
        6. Call VoiceSynthesizer.synthesize(mutated_persona, onboarding_data)
        7. Return complete partner dict ready for DB insertion
        """
        logger.info(f"Generating partner for user {user_id}...")
        rng = self._get_seeded_rng(user_id)
        
        # 1. Load all 12 archetypes
        archetypes = self._load_all_archetypes()
        
        # Determine the user profile values for matching
        inferred_attachment = onboarding_data.get("attachment_style")
        if not inferred_attachment:
            # Fallback mapper for attachment style based on connection style
            conn_style = onboarding_data.get("connection_style", "easy_to_talk_to")
            attachment_map = {
                "takes_their_time": "avoidant",
                "easy_to_talk_to": "secure",
                "says_whats_on_mind": "secure",
                "makes_things_fun": "anxious",
                "meaningful_conversations": "anxious",
            }
            inferred_attachment = attachment_map.get(conn_style, "secure")
            
        depth_raw = onboarding_data.get("depth_preference") or onboarding_data.get("emotional_depth_preference", "")
        depth_map = {
            "a lot — I go deep": "deep",
            "dont_mind_personal": "deep",
            "skip_small_talk": "deep",
            "some things — when it feels right": "medium",
            "little_honesty": "medium",
            "not much — I'm more private": "surface",
            "let_it_happen": "surface",
        }
        user_depth = depth_map.get(depth_raw, "medium")
        
        intent_raw = onboarding_data.get("relationship_type_intent", "")
        intent_map = {
            "someone to talk to": "friendship",
            "a real friendship": "friendship",
            "something that might become more": "romance",
            "I'm not sure yet": "open",
            "friendship": "friendship",
            "companionship": "companionship",
            "romance": "romance",
            "open": "open"
        }
        user_intent = intent_map.get(intent_raw, "companionship")
        
        # Normalizing onboarding_data to make sure all expected fields exist
        normalized_onboarding = {
            **onboarding_data,
            "attachment_style": inferred_attachment,
            "depth_preference": depth_raw,
            "relationship_type_intent": intent_raw
        }
        
        # 2. Score each against user profile using compatibility_weights
        scored_candidates = []
        for arch in archetypes:
            weights = arch.get("compatibility_weights", {})
            
            # Match attachment_style
            attachment_w = weights.get("attachment_style", {}).get(inferred_attachment, 0.5)
            # Match depth preference
            depth_w = weights.get("emotional_depth_preference", {}).get(user_depth, 0.5)
            # Match intent
            intent_w = weights.get("relationship_type_intent", {}).get(user_intent, 0.5)
            
            base_score = (attachment_w + depth_w + intent_w) / 3.0
            
            # 3. Add ±0.15 noise (seeded with user_id for reproducibility)
            noise = rng.uniform(-0.15, 0.15)
            final_score = base_score + noise
            
            scored_candidates.append((final_score, arch))
            
        # 4. Select highest-scoring archetype
        scored_candidates.sort(key=lambda x: x[0], reverse=True)
        best_score, selected_archetype = scored_candidates[0]
        logger.info(f"Selected archetype: {selected_archetype['archetype_id']} with score {best_score:.4f}")
        
        # 5. Call Mutator.mutate(archetype, onboarding_data, user_id)
        mutator = Mutator()
        mutated_persona = mutator.mutate(selected_archetype, normalized_onboarding, user_id)
        
        # 6. Call VoiceSynthesizer.synthesize(mutated_persona, archetype)
        synthesizer = VoiceSynthesizer()
        voice_style = synthesizer.synthesize(mutated_persona, selected_archetype)
        
        # 7. Return complete partner dict ready for DB insertion
        partner_id = f"partner_{user_id}"
        return {
            "id": partner_id,
            "user_id": user_id,
            "name": mutated_persona["name"],
            "archetype_id": selected_archetype["archetype_id"],
            "persona_json": mutated_persona,
            "voice_style_json": voice_style,
        }

    @classmethod
    async def generate(cls, onboarding_data: dict, user_id: str) -> dict:
        """Class method for backward compatibility in API onboarding.py"""
        generator = cls()
        return generator.generate_partner(user_id, onboarding_data)

    def _get_seeded_rng(self, user_id: str) -> random.Random:
        seed_int = int(hashlib.sha256(user_id.encode("utf-8")).hexdigest(), 16) % (2**32)
        return random.Random(seed_int)

    def _load_all_archetypes(self) -> list[dict]:
        archetypes_dir = Path(__file__).parent.resolve() / "archetypes"
        results = []
        for p in archetypes_dir.glob("*.json"):
            if not p.stem.startswith("_"):
                with open(p, "r", encoding="utf-8") as f:
                    try:
                        results.append(json.load(f))
                    except Exception as e:
                        logger.error(f"Error loading archetype {p}: {e}")
        return results
