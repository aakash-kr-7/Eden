# ═══════════════════════════════════════════════════════════════════
# FILE: engine/composition_engine.py
# PURPOSE: Decomposes partner's thought into human-like message bursts.
# CONTEXT: Called before streaming. Turns monologue into conversation.
# ═══════════════════════════════════════════════════════════════════

import random
import logging
import re
from typing import List, Dict

from core.llm import get_llm_core
from config import settings

logger = logging.getLogger(__name__)

class CompositionEngine:
    
    async def decompose(
        self,
        full_response: str,
        partner_mood: str,
        partner_energy: str,
        user_message_length: int,
        conversation_id: str = "",
        communication_rhythm: str = "measured"
    ) -> List[Dict]:
        """
        Takes the full LLM response and decomposes it into realistic message bursts.
        
        Returns list of dicts:
        [
            {
                "burst": "First message text",
                "delay_before_ms": 0,  // First burst sends immediately
                "typing_time_ms": 400,  // How long to show typing indicator
                "thought_type": "question|statement|reaction|elaboration"
            },
            ...
        ]
        """
        if not full_response or not full_response.strip():
            return []

        # 1. Use llama-3.1-8b-instant to identify break points
        system_prompt = (
            "Identify natural break points in this text where a person "
            "would naturally pause and send a new message. Mark with |BREAK|.\n"
            "Consider: questions, topic shifts, self-corrections, clause boundaries.\n"
            "Return ONLY the text with |BREAK| markers, nothing else."
        )
        
        try:
            llm = get_llm_core()
            # groq fast model is typically settings.GROQ_FAST_MODEL ("llama-3.1-8b-instant")
            model_name = getattr(settings, "GROQ_FAST_MODEL", "llama-3.1-8b-instant")
            
            logger.info(f"CompositionEngine request: Decomposing response of length {len(full_response)} using {model_name}")
            
            llm_result = await llm.complete(
                system_prompt=system_prompt,
                messages=[{"role": "user", "content": full_response}],
                model=model_name,
                temperature=0.3
            )
            
            raw_splits = llm_result.split("|BREAK|")
        except Exception as e:
            logger.error(f"CompositionEngine break analysis failed: {e}. Falling back to sentence splitting.")
            # Fallback split: sentences ending in ., ?, or !
            raw_splits = re.split(r'(?<=[.?!])\s+', full_response)

        # 2. Process and clean splits
        chunks = []
        for s in raw_splits:
            cleaned = s.strip()
            if cleaned:
                chunks.append(cleaned)
                
        # Defensive fallback if we ended up with no chunks
        if not chunks:
            chunks = [full_response.strip()]
            
        # Refine chunks: ensure 1-3 sentences max per chunk, and semantic cohesion
        # (Since the LLM was prompted to identify breaks, chunks are usually semantic)
        
        # 3. Build burst list with timing and classifications
        bursts = []
        for idx, chunk in enumerate(chunks):
            thought_type = self._classify_burst(chunk, idx)
            
            delay_before = self._calculate_delay_ms(
                is_first_burst=(idx == 0),
                thought_type=thought_type,
                mood=partner_mood,
                energy=partner_energy,
                user_msg_length=user_message_length,
                conversation_id=conversation_id,
                idx=idx
            )
            
            typing_time = self._calculate_typing_time_ms(
                burst_text=chunk,
                communication_rhythm=communication_rhythm
            )
            
            bursts.append({
                "burst": chunk,
                "delay_before_ms": delay_before,
                "typing_time_ms": typing_time,
                "thought_type": thought_type
            })
            
        logger.info(f"CompositionEngine output: Created {len(bursts)} bursts.")
        return bursts
        
    def _classify_burst(self, text: str, index: int) -> str:
        text_clean = text.strip()
        text_lower = text_clean.lower()
        
        # 1. Self correction check
        self_correction_words = ["wait", "actually", "no,", "no ", "i mean", "no i meant"]
        if any(word in text_lower for word in self_correction_words):
            return "self_correction"
            
        # 2. Question check
        if text_clean.endswith("?"):
            return "question"
            
        # 3. Reaction check
        # reaction: short, immediate (oh, yeah, lol, true, etc.)
        reaction_words = {"oh", "yeah", "lol", "true", "haha", "hey", "yep", "nope", "ah", "cool", "okay", "ok", "wow"}
        # Strip common punctuation for reaction check
        words = [w.strip(".,!?\"'") for w in text_lower.split()]
        if len(words) <= 4 and any(w in reaction_words for w in words):
            return "reaction"
            
        # 4. Emotional check
        emotional_words = [
            "feel", "love", "sad", "happy", "sorry", "miss", "glad", "hurt", "afraid", 
            "scared", "angry", "excited", "worry", "worried", "hope", "wish", "trust", 
            "scare", "fear", "hate", "excite", "lonely", "warm", "close"
        ]
        if any(word in text_lower for word in emotional_words):
            return "emotional"
            
        # 5. Elaboration check (subsequent parts of thoughts)
        if index > 0:
            return "elaboration"
            
        return "statement"

    def _calculate_delay_ms(
        self,
        is_first_burst: bool,
        thought_type: str,
        mood: str,
        energy: str,
        user_msg_length: int,
        conversation_id: str = "",
        idx: int = 0
    ) -> int:
        """
        Calculates the delay in milliseconds before this burst is sent.
        First burst = 0 (sent immediately)
        """
        if is_first_burst:
            return 0
            
        # Setup seeded randomness for consistency if conversation_id is provided
        if conversation_id:
            import hashlib
            seed_str = f"{conversation_id}_{idx}_{thought_type}_{mood}_{energy}_{user_msg_length}"
            seed_val = int(hashlib.md5(seed_str.encode('utf-8')).hexdigest(), 16)
            local_rand = random.Random(seed_val)
        else:
            local_rand = random

        # Mood effects
        mood_lower = mood.lower()
        if "playful" in mood_lower:
            mood_mult = 0.6
        elif "warm" in mood_lower:
            mood_mult = 0.7
        elif "content" in mood_lower:
            mood_mult = 0.9
        elif "reflective" in mood_lower:
            mood_mult = 1.2
        elif "quiet" in mood_lower:
            mood_mult = 1.5
        elif "tired" in mood_lower:
            mood_mult = 1.8
        elif "distracted" in mood_lower:
            mood_mult = local_rand.uniform(0.8, 1.4)
        else:
            mood_mult = 1.0

        # Energy effects
        energy_lower = energy.lower()
        if "high" in energy_lower:
            energy_mult = 0.9
        elif "low" in energy_lower:
            energy_mult = 1.3
        else:
            energy_mult = 1.0

        # Thought type effects
        baselines = {
            "reaction": 600,
            "question": 1200,
            "elaboration": 2400,
            "self_correction": 1800,
            "statement": 1500,
            "emotional": 1600
        }
        baseline = baselines.get(thought_type.lower(), 1500)

        # User message length effect
        if user_msg_length < 20:
            user_adj = -400
        elif user_msg_length <= 50:
            user_adj = 0
        elif user_msg_length <= 150:
            user_adj = 500
        else:
            user_adj = 1000

        # Final formula
        delay = baseline * mood_mult * energy_mult + user_adj
        
        # Add ±200ms randomness
        random_adj = local_rand.randint(-200, 200)
        delay = int(delay + random_adj)
        
        return max(0, delay)

    def _calculate_typing_time_ms(
        self,
        burst_text: str,
        communication_rhythm: str
    ) -> int:
        """
        How long the typing indicator shows before the message appears.
        """
        rhythm_lower = communication_rhythm.lower()
        if "rapid-fire" in rhythm_lower or "rapid_fire" in rhythm_lower:
            ms_per_char = 25
        elif "sparse" in rhythm_lower:
            ms_per_char = 80
        else:
            ms_per_char = 50  # baseline: measured

        char_count = len(burst_text)
        typing_time = char_count * ms_per_char
        
        return max(150, min(2000, typing_time))
