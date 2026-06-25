# ═══════════════════════════════════════════════════════════════════
# FILE: core/streaming_v2.py
# PURPOSE: Streams decomposed bursts with realistic delays and typing indicators.
# CONTEXT: Replaces core/streaming.py. Used by chat API.
# ═══════════════════════════════════════════════════════════════════

from sse_starlette.sse import EventSourceResponse
import asyncio
import json
import logging

from core.llm import LLMCore
from engine.composition_engine import CompositionEngine
from config import settings

logger = logging.getLogger(__name__)

async def stream_partner_response_v2(
    llm: LLMCore,
    composition_engine: CompositionEngine,
    system_prompt: str,
    messages: list[dict],
    partner_mood: str,
    partner_energy: str,
    user_message_length: int,
    communication_rhythm: str = "measured",
    conversation_id: str = "",
    on_done = None
) -> EventSourceResponse:
    """
    Streams partner response as realistic message bursts.
    
    SSE event types:
    - {"type": "typing_start"} — show typing indicator, store timestamp
    - {"type": "burst", "text": "message text", "typing_ms": 600} — message arrives after typing_ms delay
    - {"type": "done", "all_bursts": [...]} — all complete, save to DB
    - {"type": "error", "message": "..."} — stream failed
    """
    
    async def generator():
        try:
            # Generate full response (non-streaming for this implementation)
            # Using the chat temperature defined in settings
            full_response = await llm.complete(
                system_prompt=system_prompt,
                messages=messages,
                model=None,
                temperature=settings.LLM_TEMPERATURE
            )
            
            # Decompose into bursts
            bursts = await composition_engine.decompose(
                full_response=full_response,
                partner_mood=partner_mood,
                partner_energy=partner_energy,
                user_message_length=user_message_length,
                conversation_id=conversation_id,
                communication_rhythm=communication_rhythm
            )
            
            all_burst_texts = []
            
            for idx, burst in enumerate(bursts):
                burst_text = burst["burst"]
                delay_ms = burst["delay_before_ms"]
                typing_ms = burst["typing_time_ms"]
                thought_type = burst.get("thought_type", "statement")
                
                # Emit typing indicator start
                yield {"data": json.dumps({"type": "typing_start"})}
                
                # Wait for delay + typing time
                total_wait_ms = delay_ms + typing_ms
                logger.info(
                    f"Burst {idx+1}/{len(bursts)}: wait={total_wait_ms}ms (delay={delay_ms}ms, typing={typing_ms}ms), "
                    f"type='{thought_type}', text='{burst_text:.30s}...'"
                )
                await asyncio.sleep(total_wait_ms / 1000.0)
                
                # Emit the actual message burst
                yield {"data": json.dumps({
                    "type": "burst",
                    "text": burst_text,
                    "thought_type": thought_type,
                    "typing_ms": typing_ms
                })}
                
                all_burst_texts.append(burst_text)
            
            full_message_text = " ".join(all_burst_texts)
            
            # Run the callback on completion of the stream
            if on_done:
                try:
                    if asyncio.iscoroutinefunction(on_done):
                        await on_done(full_message_text)
                    else:
                        on_done(full_message_text)
                except Exception as cb_err:
                    logger.error(f"Error in stream_partner_response_v2 on_done callback: {cb_err}", exc_info=True)
            
            # Emit done with complete concatenated text
            yield {"data": json.dumps({
                "type": "done",
                "full_text": full_message_text,
                "burst_count": len(bursts)
            })}
            
        except Exception as e:
            logger.error(f"Error in stream_partner_response_v2 stream generator: {e}", exc_info=True)
            yield {"data": json.dumps({
                "type": "error",
                "message": str(e)
            })}
            
    return EventSourceResponse(generator())
