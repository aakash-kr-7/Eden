# ═══════════════════════════════════════════════════════════════════
# FILE: api/chat.py
# PURPOSE: Primary chat API — send messages, stream responses, manage sessions.
# CONTEXT: The core loop of Eden. Called on every user message.
# ═══════════════════════════════════════════════════════════════════

import logging
import json
import asyncio
from typing import Optional
from datetime import datetime, timezone

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from sse_starlette.sse import EventSourceResponse

from auth.firebase import AuthenticatedIdentity, get_authenticated_identity
from config import settings
from core.concurrency import concurrency
from core.context_builder import build_context
from core.llm import get_llm_core
from core.session_loader import SessionLoader
from memory.store import db
from memory.embedder import Embedder
from personality.registry import get_partner_instance, resolve_or_assign_primary_pair
from engine.burst_engine import BurstEngine

logger = logging.getLogger(__name__)

# Set the router prefix so it mounts cleanly
router = APIRouter(prefix="/chat")

class MessageRequest(BaseModel):
    message: str = Field(..., min_length=1, max_length=2000)
    conversation_id: Optional[str] = None

async def run_relationship_event_detection(user_id: str, pair_id: str, partner_id: str):
    """
    Background task to run behavioral pattern detection.
    """
    pass

async def extract_and_save_task(user_id: str, pair_id: str, conversation_id: str):
    """
    Background task to trigger memory extraction checks.
    """
    from memory.consolidator import MemoryConsolidator
    try:
        conv = db.get_conversation(conversation_id)
        msg_count = conv.get("message_count", 0) if conv else 0
        
        trigger_n = getattr(settings, "MEMORY_EXTRACTION_EVERY_N_TURNS", 5)
        if msg_count > 0 and msg_count % trigger_n == 0:
            logger.info(f"Triggering background memory extraction for user {user_id}, conversation {conversation_id}")
            consolidator = MemoryConsolidator()
            with db.get_connection() as conn:
                await consolidator.process_conversation(conn, conversation_id, user_id)
    except Exception as e:
        logger.error(f"Error in background memory extraction check: {e}", exc_info=True)

@router.post("/message")
async def send_message(
    request: MessageRequest,
    background_tasks: BackgroundTasks,
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    # 1. Verify onboarding complete (403 if not)
    user = db.get_user(identity.uid)
    if not user or not (user.get("onboarding_completed") or user.get("onboarding_complete")):
        return JSONResponse(status_code=403, content={"error": "onboarding_required"})

    # Resolve pair
    pair = resolve_or_assign_primary_pair(identity.uid)
    if not pair:
        raise HTTPException(status_code=500, detail="Failed to resolve pair")

    # Use asyncio lock keyed by user_id to prevent concurrency race conditions
    async with concurrency.acquire(identity.uid):
        conversation_id = request.conversation_id
        if not conversation_id:
            # Start new conversation
            conversation_id = db.create_conversation(
                user_id=identity.uid,
                pair_id=pair["id"],
                partner_id=pair["partner_id"]
            )
        else:
            conversation = db.get_conversation(conversation_id)
            if not conversation or conversation["user_id"] != identity.uid or conversation["pair_id"] != pair["id"]:
                raise HTTPException(status_code=404, detail="Conversation not found")

        # 2. Save user message to messages table
        db.save_message(
            conversation_id=conversation_id,
            user_id=identity.uid,
            pair_id=pair["id"],
            partner_id=pair["partner_id"],
            role="user",
            content=request.message
        )

        # 3. Embed user message (Embedder.embed_for_search)
        embedding_vec = Embedder.embed_for_search(request.message)

        # 4. Retrieve relevant memories (Retrieved inside build_context via wrappers)
        # 5. Load partner from DB (Loaded inside build_context)
        # 6. Load life_state from DB (Loaded inside build_context)
        # 7. Build system prompt (ContextBuilder.build_system_prompt)
        # 8. Build message history (ContextBuilder.build_message_history, last 10 msgs)
        try:
            system_prompt, messages = await build_context(
                user_id=identity.uid,
                pair_id=pair["id"],
                current_message=request.message,
                conversation_id=conversation_id,
                partner_id=pair["partner_id"]
            )
        except Exception as exc:
            logger.error("Context building failed for pair %s: %s", pair["id"], exc)
            raise HTTPException(status_code=500, detail="Failed to build context")

        # 9. Check BurstEngine.should_burst()
        life_state = db.get_life_state(pair["id"])
        mood = life_state.get("partner_mood", "content") if life_state else "content"

        # 10. Return SSE stream via stream_partner_response
        async def generator():
            full_text = ""
            try:
                llm = get_llm_core()
                async for chunk in llm.stream(system_prompt=system_prompt, messages=messages):
                    full_text += chunk
                    yield {"data": json.dumps({"type": "token", "text": chunk})}

                # On "done" event server-side: save partner message to DB
                # Update conversation.last_message_at and message_count
                db.save_message(
                    conversation_id=conversation_id,
                    user_id=identity.uid,
                    pair_id=pair["id"],
                    partner_id=pair["partner_id"],
                    role="partner",
                    content=full_text
                )

                # Check if it should burst
                burst_engine = BurstEngine()
                bursts = []
                delays = []
                if burst_engine.should_burst(full_text, mood):
                    bursts = await burst_engine.split_response(full_text)
                    delays = burst_engine.get_burst_delays(bursts)

                payload = {
                    "type": "done",
                    "full_text": full_text
                }
                if bursts and len(bursts) > 1:
                    payload["bursts"] = bursts
                    payload["delays"] = delays

                yield {"data": json.dumps(payload)}

                # Trigger background tasks (fire-and-forget)
                background_tasks.add_task(
                    extract_and_save_task,
                    user_id=identity.uid,
                    pair_id=pair["id"],
                    conversation_id=conversation_id
                )
                background_tasks.add_task(
                    run_relationship_event_detection,
                    user_id=identity.uid,
                    pair_id=pair["id"],
                    partner_id=pair["partner_id"]
                )
            except Exception as e:
                logger.error(f"Error in chat stream generator: {e}", exc_info=True)
                yield {"data": json.dumps({"type": "error", "message": str(e)})}

        return EventSourceResponse(generator())

@router.get("/session")
async def get_session(
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    # Validate user exists and completed onboarding
    user = db.get_user(identity.uid)
    if not user or not (user.get("onboarding_completed") or user.get("onboarding_complete")):
        return JSONResponse(status_code=403, content={"error": "onboarding_required"})

    loader = SessionLoader()
    async with concurrency.acquire(identity.uid):
        with db.get_connection() as conn:
            payload = await loader.load(conn, identity.uid)
    return payload

@router.post("/session/end")
async def end_session(
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    # Updates users.last_active_at
    db.update_last_active(identity.uid)
    return {"status": "success"}

@router.get("/messages")
async def get_chat_messages(
    before_id: Optional[int] = Query(default=None),
    limit: int = Query(default=20, ge=1, le=50),
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    # Validate user exists and completed onboarding
    user = db.get_user(identity.uid)
    if not user or not (user.get("onboarding_completed") or user.get("onboarding_complete")):
        return JSONResponse(status_code=403, content={"error": "onboarding_required"})

    # Find the active conversation for this user
    conversation_id = db.get_current_conversation(identity.uid)
    if not conversation_id:
        primary = db.get_primary_pair(identity.uid)
        if primary:
            conversation_id = db.create_conversation(identity.uid, primary["id"], primary["partner_id"])
        else:
            return []

    messages = db.get_paginated_messages(conversation_id, limit=limit, before_id=before_id)
    return messages
