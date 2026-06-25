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
from engine.composition_strategies import get_strategy

logger = logging.getLogger(__name__)

class CompositionEngine:
    
    async def decompose(
        self,
        full_response: str,
        partner_mood: str,
        partner_energy: str,
        user_message_length: int,
        conversation_id: str = "",
        communication_rhythm: str = "measured",
        user_analysis: dict = None
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
        initial_bursts = []
        for s in raw_splits:
            cleaned = s.strip()
            if cleaned:
                cleaned = re.sub(r'^\|BREAK\||\|BREAK\|$', '', cleaned).strip()
                if cleaned:
                    initial_bursts.append(cleaned)
                    
        # Defensive fallback if we ended up with no chunks
        if not initial_bursts:
            initial_bursts = [full_response.strip()]

        # 3. Retrieve mood+energy strategy
        strategy = dict(get_strategy(partner_mood, partner_energy))
        
        # If user is vulnerable, add elaboration bursts by forcing short bursts
        if user_analysis and user_analysis.get("sentiment") == "vulnerable":
            strategy["prefer_short_bursts"] = True
            strategy["max_bursts"] = max(strategy.get("max_bursts", 3), 4)

        # 4. Apply strategy rules and split options
        # A. Split self-corrections first
        chunks_after_self_corr = []
        pattern = re.compile(r'\b(wait\b|actually\b|no\s+i\s+mean\b|but\s+actually\b)', re.IGNORECASE)
        for chunk in initial_bursts:
            match = pattern.search(chunk)
            if match and match.start() > 0:
                split_idx = match.start()
                left = chunk[:split_idx].strip()
                right = chunk[split_idx:].strip()
                if left and right:
                    left = re.sub(r'[\s.,\-]+$', '', left)
                    chunks_after_self_corr.append(left)
                    chunks_after_self_corr.append(right)
                    continue
            chunks_after_self_corr.append(chunk)

        # B. Split questions to ensure they get their own bursts (or end a burst)
        chunks_after_questions = []
        for chunk in chunks_after_self_corr:
            sub_chunks = re.split(r'(?<=\?)\s+', chunk)
            for sc in sub_chunks:
                sc = sc.strip()
                if sc:
                    chunks_after_questions.append(sc)

        # C. Recombine or re-split based on strategy
        final_chunks = []
        max_s = strategy.get("max_sentences_per_burst", 2)

        if partner_mood.lower().strip() == "reflective" and partner_energy.lower().strip() == "low":
            for chunk in chunks_after_questions:
                sentences = re.split(r'(?<=[.?!])\s+', chunk)
                if len(sentences) >= 4:
                    mid = len(sentences) // 2
                    left = " ".join(sentences[:mid]).strip()
                    right = " ".join(sentences[mid:]).strip()
                    final_chunks.extend([left, right])
                else:
                    final_chunks.append(chunk)
        elif strategy.get("prefer_short_bursts", False):
            # Split all chunks into individual sentences
            for chunk in chunks_after_questions:
                if partner_mood.lower().strip() == "quiet" and len(chunk.split()) > 8:
                    fragments = re.split(r'(?<=[,;])\s+', chunk)
                    for frag in fragments:
                        frag = frag.strip()
                        if frag:
                            final_chunks.append(frag)
                else:
                    sentences = re.split(r'(?<=[.?!])\s+', chunk)
                    for s in sentences:
                        s = s.strip()
                        if s:
                            final_chunks.append(s)
        else:
            # Split if chunk exceeds max_sentences_per_burst
            for chunk in chunks_after_questions:
                sentences = re.split(r'(?<=[.?!])\s+', chunk)
                if len(sentences) > max_s:
                    for i in range(0, len(sentences), max_s):
                        grouped = " ".join(sentences[i:i+max_s]).strip()
                        if grouped:
                            final_chunks.append(grouped)
                else:
                    final_chunks.append(chunk)

        # Recombine if we exceed max_bursts
        max_b = strategy.get("max_bursts", 3)
        def can_merge(left: str, right: str) -> bool:
            if left.endswith("?") or right.endswith("?"):
                return False
            if right.lower().startswith(("wait", "actually", "no ")):
                return False
            return True

        while len(final_chunks) > max_b:
            merged = False
            for i in range(len(final_chunks) - 1):
                if can_merge(final_chunks[i], final_chunks[i+1]):
                    final_chunks[i] = final_chunks[i] + " " + final_chunks[i+1]
                    final_chunks.pop(i+1)
                    merged = True
                    break
            if not merged:
                # Force merge the adjacent pair with the shortest combined length
                best_idx = 0
                min_len = len(final_chunks[0]) + len(final_chunks[1])
                for i in range(1, len(final_chunks) - 1):
                    combined_len = len(final_chunks[i]) + len(final_chunks[i+1])
                    if combined_len < min_len:
                        min_len = combined_len
                        best_idx = i
                final_chunks[best_idx] = final_chunks[best_idx] + " " + final_chunks[best_idx+1]
                final_chunks.pop(best_idx+1)

        # Final clean
        final_chunks = [c.strip() for c in final_chunks if c.strip()]
        if not final_chunks:
            final_chunks = [full_response.strip()]

        # Setup seeded randomness for consistency if conversation_id is provided
        if conversation_id:
            import hashlib
            seed_str = f"{conversation_id}_{partner_mood}_{partner_energy}_{user_message_length}"
            seed_val = int(hashlib.md5(seed_str.encode('utf-8')).hexdigest(), 16)
            local_rand = random.Random(seed_val)
        else:
            local_rand = random

        # 5. Build burst list with timing and classifications
        bursts = []
        for idx, chunk in enumerate(final_chunks):
            thought_type = self._classify_burst(chunk, idx)
            
            delay_before = self._calculate_delay_ms(
                is_first_burst=(idx == 0),
                thought_type=thought_type,
                strategy=strategy,
                user_msg_length=user_message_length,
                idx=idx,
                local_rand=local_rand,
                user_analysis=user_analysis,
                partner_mood=partner_mood
            )
            
            typing_time = self._calculate_typing_time_ms(
                burst_text=chunk,
                thought_type=thought_type,
                strategy=strategy,
                local_rand=local_rand
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
        reaction_words = {"oh", "yeah", "lol", "true", "haha", "hey", "yep", "nope", "ah", "cool", "okay", "ok", "wow", "omg"}
        words = [w.strip(".,!?\"'") for w in text_lower.split()]
        if len(words) <= 4 and any(w in reaction_words for w in words):
            return "reaction"
            
        # 4. Emotional check
        emotional_phrases = [
            "i just want you to know", "want you to know", "honestly", "really means a lot",
            "to be honest", "i'm not sure how to explain", "feelings", "vulnerable", "scared to say",
            "mean a lot", "glad we talked", "sorry", "miss you", "love", "trust you"
        ]
        emotional_words = [
            "feel", "love", "sad", "happy", "sorry", "miss", "glad", "hurt", "afraid", 
            "scared", "angry", "excited", "worry", "worried", "hope", "wish", "trust", 
            "scare", "fear", "hate", "excite", "lonely", "warm", "close"
        ]
        if any(phrase in text_lower for phrase in emotional_phrases) or any(word in text_lower.split() for word in emotional_words):
            return "emotional"
            
        # 5. Elaboration check (subsequent parts of thoughts)
        if index > 0:
            return "elaboration"
            
        return "statement"

    def _calculate_delay_ms(
        self,
        is_first_burst: bool,
        thought_type: str,
        strategy: dict,
        user_msg_length: int,
        idx: int,
        local_rand,
        user_analysis: dict = None,
        partner_mood: str = "content"
    ) -> int:
        if is_first_burst:
            # Determine base first burst delay using urgency category from user_analysis
            urgency = "normal"
            if user_analysis:
                urgency = user_analysis.get("urgency", "normal")
            else:
                if user_msg_length < 10:
                    urgency = "instant"
                elif user_msg_length <= 30:
                    urgency = "quick"
                elif user_msg_length <= 100:
                    urgency = "normal"
                else:
                    urgency = "thoughtful"

            if urgency == "instant":
                base_delay = local_rand.randint(100, 200)
            elif urgency == "quick":
                base_delay = local_rand.randint(500, 800)
            elif urgency == "normal":
                base_delay = local_rand.randint(1200, 1800)
            else:  # thoughtful
                base_delay = local_rand.randint(2500, 3500)
                
            # First burst adjustments
            if user_analysis:
                text = user_analysis.get("text", "").lower().strip()
                is_thoughtful_question = (
                    user_analysis.get("requires_thinking") and
                    user_analysis.get("is_question") and
                    user_analysis.get("length") == "long"
                )
                if is_thoughtful_question:
                    base_delay += 1000
                elif text == "hey":
                    base_delay -= 400
                
                if user_analysis.get("sentiment") == "vulnerable":
                    base_delay += 800
            
            user_adj = 0
            
        else:
            # Check classification-specific overrides first
            if thought_type == "self_correction":
                base_delay = local_rand.randint(1200, 1600)
            elif thought_type == "question":
                base_delay = local_rand.randint(1200, 1800)
                # Prioritize question in bursts: if user asked a question, respond slightly faster
                if user_analysis and user_analysis.get("is_question"):
                    base_delay = int(base_delay * 0.8)
            elif thought_type == "emotional":
                base_delay = local_rand.randint(2500, 3500)
            elif thought_type == "reaction":
                base_delay = local_rand.randint(400, 600)
            elif thought_type == "elaboration":
                base_delay = local_rand.randint(2000, 3000)
            else:
                # Default baseline based on strategy
                delays_spec = strategy.get("delays", [1000, 2000])
                if delays_spec == "randomized":
                    base_delay = local_rand.randint(800, 2500)
                elif isinstance(delays_spec, list):
                    list_idx = idx - 1
                    if list_idx < len(delays_spec):
                        base_delay = delays_spec[list_idx]
                    else:
                        base_delay = local_rand.choice(delays_spec)
                else:
                    # Range e.g. [2000, 4000]
                    base_delay = local_rand.randint(delays_spec[0], delays_spec[1])

            # Subsequent burst sentiment vulnerable check: longer delays
            if user_analysis and user_analysis.get("sentiment") == "vulnerable":
                base_delay += 1000

            # User message length effect adjustment (preserving from original)
            if user_msg_length < 20:
                user_adj = -200
            elif user_msg_length <= 50:
                user_adj = 0
            elif user_msg_length <= 150:
                user_adj = 300
            else:
                user_adj = 600

        delay = base_delay + user_adj
        
        # Apply user_tone affect mood multipliers
        multiplier = 1.0
        if user_analysis:
            user_tone = user_analysis.get("tone", "statement")
            mood_tone_multipliers = {
                ("playful", "casual"): 0.8,
                ("playful", "emotional"): 1.1,
                ("warm", "emotional"): 1.2,
                ("warm", "casual"): 0.9,
                ("reflective", "emotional"): 1.3,
                ("reflective", "question"): 1.1,
                ("reflective", "casual"): 1.0,
                ("quiet", "emotional"): 1.4,
                ("quiet", "casual"): 1.1,
                ("distracted", "casual"): 0.7,
                ("tired", "casual"): 1.2,
                ("tired", "emotional"): 1.5,
            }
            m_key = partner_mood.lower().strip()
            t_key = user_tone.lower().strip()
            multiplier = mood_tone_multipliers.get((m_key, t_key), 1.0)
            
        delay = int(delay * multiplier)

        # Add ±100ms randomness for natural variation
        random_adj = local_rand.randint(-100, 100)
        delay = int(delay + random_adj)
        
        min_clamp = 0 if is_first_burst else 150
        return max(min_clamp, delay)

    def _calculate_typing_time_ms(
        self,
        burst_text: str,
        thought_type: str,
        strategy: dict,
        local_rand
    ) -> int:
        if thought_type == "reaction":
            return local_rand.randint(200, 450)
            
        text_len = len(burst_text)
        
        if strategy.get("typing_time_range") == "inconsistent":
            base_time = local_rand.randint(150, 750)
        else:
            time_range = strategy.get("typing_time_range", (400, 600))
            min_t, max_t = time_range
            
            # Estimate character speeds based on strategy
            if min_t < 300:  # playful / tired
                char_speed = 8
            elif min_t > 600:  # reflective
                char_speed = 25
            else:
                char_speed = 15
                
            base_time = text_len * char_speed
            base_time = max(min_t, min(max_t, base_time))

        if thought_type == "emotional":
            base_time = int(base_time * 1.5)
            base_time = max(800, min(2000, base_time))
            
        return base_time

