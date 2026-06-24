# ═══════════════════════════════════════════════════════════════════
# FILE: burst_engine.py
# PURPOSE: Splits long partner responses into natural multi-message bursts.
# CONTEXT: Called by chat API before streaming. Adds human texting realism.
# ═══════════════════════════════════════════════════════════════════

import random
import logging

logger = logging.getLogger(__name__)

class BurstEngine:
    
    def should_burst(self, response: str, mood: str) -> bool:
        """
        Returns True if response should split into multiple messages.
        Criteria:
        - Response is 200+ characters
        - Mood is NOT tired, quiet, or distracted
        - 40% base probability
        - Probability increases if mood is playful or warm
        """
        if len(response) < 200:
            return False
            
        mood_lower = mood.lower()
        if any(m in mood_lower for m in ("tired", "quiet", "distracted")):
            return False
            
        prob = 0.40
        if "playful" in mood_lower:
            prob += 0.20
        if "warm" in mood_lower:
            prob += 0.15
            
        roll = random.random()
        decision = roll < prob
        logger.info(f"Burst decision: length={len(response)}, mood='{mood}', probability={prob:.2f}, roll={roll:.2f} -> should_burst={decision}")
        return decision
    
    async def split_response(self, response: str) -> list[str]:
        """
        Uses llama-3.1-8b-instant to split response into 2-4 natural bursts.
        Each burst must be a complete thought.
        Splitting prompt: "Split this into 2-4 natural text messages a real person
        would send. Each must be a complete thought. Return JSON array of strings."
        On failure: return [response] (unsplit)
        """
        system_prompt = (
            "Split this into 2-4 natural text messages a real person would send in quick succession.\n"
            "Each must be a complete thought.\n"
            "Return a JSON object with a single key 'bursts' containing a list of strings."
        )
        try:
            from core.llm import get_llm_core
            from config import settings
            llm = get_llm_core()
            result = await llm.complete_json(
                system_prompt=system_prompt,
                messages=[{"role": "user", "content": response}],
                model=settings.GROQ_FAST_MODEL
            )
            if isinstance(result, dict) and "bursts" in result and isinstance(result["bursts"], list):
                bursts = [str(b).strip() for b in result["bursts"] if b]
                if bursts:
                    logger.info(f"BurstEngine split response into {len(bursts)} bursts successfully.")
                    return bursts
            logger.warning("BurstEngine completion did not return expected JSON format. Falling back to unsplit.")
            return [response]
        except Exception as e:
            logger.error(f"Failed to split response in BurstEngine: {e}")
            return [response]
    
    def get_burst_delays(self, bursts: list[str]) -> list[float]:
        """
        Returns delay in seconds before each burst.
        First burst: 0 seconds (sent with stream)
        Subsequent: 3-12 seconds based on length
        Longer burst text → slightly longer delay (typing simulation)
        """
        delays = [0.0]
        if len(bursts) <= 1:
            return delays
            
        for burst in bursts[1:]:
            # base delay is 3.0 seconds, plus 0.05 seconds per character
            delay = 3.0 + (len(burst) * 0.05)
            # clamp delay between 3.0 and 12.0 seconds
            delay = min(12.0, max(3.0, delay))
            delays.append(round(delay, 2))
        return delays
