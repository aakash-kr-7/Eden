# ═══════════════════════════════════════════════════════════════════
# FILE: backend/core/streaming.py
# PURPOSE: SSE streaming helpers for sending Groq response to Flutter.
# CONTEXT: Used by chat API to stream partner responses token by token.
# ═══════════════════════════════════════════════════════════════════

from sse_starlette.sse import EventSourceResponse
import json
import logging
import asyncio
from core.llm import LLMCore

logger = logging.getLogger(__name__)

async def stream_partner_response(
    llm: LLMCore,
    system_prompt: str,
    messages: list[dict],
    on_done = None
) -> EventSourceResponse:
    """
    Returns an SSE EventSourceResponse that streams partner response.
    
    SSE event format:
    - data: {"type": "token", "text": "chunk"}
    - data: {"type": "done", "full_text": "complete response"}
    - data: {"type": "error", "message": "error description"}
    
    On stream completion:
    - Emit "done" event with full accumulated text
    - Save partner response to DB (handled via on_done callback)
    """
    async def generator():
        full_text = ""
        try:
            async for chunk in llm.stream(system_prompt, messages):
                full_text += chunk
                yield {"data": json.dumps({"type": "token", "text": chunk})}
                
            if on_done:
                try:
                    if asyncio.iscoroutinefunction(on_done):
                        await on_done(full_text)
                    else:
                        on_done(full_text)
                except Exception as e:
                    logger.error(f"Error in on_done callback of stream_partner_response: {e}", exc_info=True)
                    
            yield {"data": json.dumps({"type": "done", "full_text": full_text})}
        except Exception as e:
            logger.error(f"Error in stream_partner_response generator: {e}", exc_info=True)
            yield {"data": json.dumps({"type": "error", "message": str(e)})}
            
    return EventSourceResponse(generator())
