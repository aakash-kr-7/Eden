import re
import random
import logging
import asyncio
from dataclasses import dataclass
from typing import Optional

from personality.registry import Partner
from config import settings

logger = logging.getLogger(__name__)

EXPLICIT_BURST_TOKEN = "[BURST]"

@dataclass(frozen=True)
class BurstSegment:
    text: str
    pre_burst_delay_ms: int
    typing_duration_ms: int
    pause_intensity: str
    is_follow_up: bool = False


@dataclass(frozen=True)
class BurstPlan:
    combined_text: str
    bursts: list[BurstSegment]


class BurstEngine:
    async def should_burst(self, response: str, mood: str) -> bool:
        """
        Returns True if this response should be split into multiple messages.
        Criteria:
        - Response is long enough to split naturally (250+ chars)
        - Partner's current mood is playful, warm, or content (not quiet or tired)
        - 40% base probability, increased by mood
        """
        if len(response) < 250:
            return False

        mood_normalized = mood.lower().strip()
        if "quiet" in mood_normalized or "tired" in mood_normalized or "reflective" in mood_normalized:
            return False

        allowed_moods = ["playful", "warm", "content", "distracted"]
        has_allowed_mood = any(m in mood_normalized for m in allowed_moods)
        if not has_allowed_mood:
            return False

        # Base probability 40%
        prob = 0.40
        if "playful" in mood_normalized:
            prob += 0.35
        elif "warm" in mood_normalized:
            prob += 0.25
        elif "content" in mood_normalized:
            prob += 0.10
        elif "distracted" in mood_normalized:
            prob += 0.15

        return random.random() < min(1.0, prob)

    async def split_response(self, response: str) -> list[str]:
        """
        Splits a response into 2-4 natural burst messages.
        NOT by character count — by semantic/emotional units.
        Uses LLM to split: "Split this message into 2-4 natural text bursts a person would send"
        Returns list of strings.
        """
        response = response.strip()
        if not response:
            return []

        # Do not try splitting extremely short messages
        if len(response) < 50:
            return [response]

        from core.llm import get_llm_core
        llm = get_llm_core()

        system_prompt = (
            "You are an expert at parsing chat messages. Your task is to split the provided text message into 2 to 4 natural text bursts "
            "that a person would send sequentially in a messaging app.\n"
            "Each burst must represent a semantic or emotional unit (a complete thought, clause, or sentence).\n"
            "CRITICAL: Do not alter, edit, summarize, or rephrase any words. Every word from the original message must be preserved exactly, in order. "
            "Do not add any new words or punctuation."
        )

        output_schema = {
            "type": "object",
            "properties": {
                "bursts": {
                    "type": "array",
                    "items": {
                        "type": "string"
                    },
                    "minItems": 2,
                    "maxItems": 4
                }
            },
            "required": ["bursts"]
        }

        try:
            result = await llm.complete_structured(
                system_prompt=system_prompt,
                messages=[{"role": "user", "content": f"Message to split:\n{response}"}],
                output_schema=output_schema,
                temperature=0.2
            )
            bursts = result.get("bursts", [])
            bursts = [b.strip() for b in bursts if b.strip()]

            # Validation: Verify that the bursts combined contain the exact same characters when normalized
            original_normalized = "".join(c.lower() for c in response if c.isalnum())
            bursts_normalized = "".join(c.lower() for b in bursts for c in b if c.isalnum())

            if bursts and original_normalized == bursts_normalized:
                return bursts
            else:
                logger.warning("LLM split validation failed (character mismatch). Falling back to heuristic split.")
        except Exception as e:
            logger.error("LLM split_response failed: %s. Falling back to heuristic split.", e)

        # Heuristic split fallbacks
        # Try sentence splitting
        sentences = re.split(r"(?<=[.!?…])\s+", response)
        sentences = [s.strip() for s in sentences if s.strip()]
        if len(sentences) >= 2:
            num_bursts = min(4, len(sentences))
            bursts = []
            chunk_size = max(1, len(sentences) // num_bursts)
            for i in range(num_bursts):
                if i == num_bursts - 1:
                    burst_text = " ".join(sentences[i * chunk_size:])
                else:
                    burst_text = " ".join(sentences[i * chunk_size:(i + 1) * chunk_size])
                if burst_text:
                    bursts.append(burst_text)
            return bursts

        # Try connector splitting
        parts = re.split(r"\s+(?=(?:but|and|so|because|also|wait|okay|ok|plus)\b)", response, maxsplit=2, flags=re.IGNORECASE)
        cleaned = [p.strip() for p in parts if p.strip()]
        if len(cleaned) >= 2:
            return cleaned

        return [response]

    async def get_burst_delays(self, bursts: list[str]) -> list[float]:
        """
        Returns delay in seconds before each burst.
        First burst: 0 (immediate)
        Subsequent bursts: 3-12 seconds, scaled by burst length.
        """
        if not bursts:
            return []
        
        delays = [0.0]
        for b in bursts[1:]:
            # Scale by length: 3.0 seconds base, adding 0.05 seconds per character, capped at 12.0 seconds
            delay = 3.0 + min(9.0, len(b) * 0.05)
            delays.append(round(delay, 2))
        
        return delays


async def plan_burst_response(
    raw_text: str,
    character: Partner,
    user_message: Optional[str] = None,
    is_opening: bool = False,
    relationship_state: Optional[dict] = None,
) -> BurstPlan:
    """
    Compatibility wrapper returning a BurstPlan with BurstSegments and delay details.
    Uses BurstEngine under the hood.
    """
    text = (raw_text or "").replace("\r\n", "\n").strip()
    # Normalize explicit burst token variants
    text = re.sub(r"\s*\[burst\]\s*", f" {EXPLICIT_BURST_TOKEN} ", text, flags=re.IGNORECASE)
    
    # 1. First check if explicit token exists in LLM reply
    if EXPLICIT_BURST_TOKEN in text:
        bursts = [p.strip() for p in text.split(EXPLICIT_BURST_TOKEN) if p.strip()]
    else:
        # Determine current mood of the companion to check if they should burst
        mood = "warm"
        if relationship_state and "id" in relationship_state:
            from memory.store import db
            ls = db.get_life_state(relationship_state["id"])
            if ls:
                mood = ls.get("mood") or "warm"
                
        engine = BurstEngine()
        should = await engine.should_burst(text, mood)
        
        if should:
            bursts = await engine.split_response(text)
        else:
            bursts = [text]

    # Calculate delays using BurstEngine
    engine = BurstEngine()
    delays = await engine.get_burst_delays(bursts)

    # Construct BurstSegments
    segments = []
    for idx, b in enumerate(bursts):
        delay_sec = delays[idx]
        pre_delay_ms = int(delay_sec * 1000)
        
        # Simulate typing time based on length
        # Base typing: 400ms + 8ms per character, capped at 2500ms
        typing_ms = 400 + min(2100, len(b) * 8)
        
        segments.append(
            BurstSegment(
                text=b,
                pre_burst_delay_ms=pre_delay_ms,
                typing_duration_ms=typing_ms,
                pause_intensity="medium" if pre_delay_ms > 4000 else "brief",
                is_follow_up=(idx > 0)
            )
        )

    return BurstPlan(
        combined_text="\n".join(bursts),
        bursts=segments
    )
