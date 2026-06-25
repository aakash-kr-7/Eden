# ═══════════════════════════════════════════════════════════════════
# FILE: api/chat_v2.py
# PURPOSE: Updated chat API using composition engine instead of burst engine.
# CONTEXT: Replaces POST /api/chat/message with human texting support.
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

from engine.composition_engine import CompositionEngine
from core.streaming_v2 import stream_partner_response_v2

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

        # Get partner instance to extract communication rhythm
        partner_instance = get_partner_instance(pair["partner_id"])
        communication_rhythm = "measured"
        if partner_instance and partner_instance.persona:
            communication_rhythm = partner_instance.persona.get("communication_rhythm", "measured")

        # Load life state to extract mood and energy
        life_state = db.get_life_state(pair["id"])
        partner_mood = "content"
        partner_energy = "normal"
        if life_state:
            partner_mood = life_state.get("partner_mood") or "content"
            partner_energy = life_state.get("partner_energy") or "normal"

        user_message_length = len(request.message)
        
        llm = get_llm_core()
        composition_engine = CompositionEngine()

        # Define the callback on completion of the stream
        async def on_done(full_text: str):
            # Save partner response to DB
            db.save_message(
                conversation_id=conversation_id,
                user_id=identity.uid,
                pair_id=pair["id"],
                partner_id=pair["partner_id"],
                role="partner",
                content=full_text
            )

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

        # 8. Return SSE stream via stream_partner_response_v2
        return await stream_partner_response_v2(
            llm=llm,
            composition_engine=composition_engine,
            system_prompt=system_prompt,
            messages=messages,
            partner_mood=partner_mood,
            partner_energy=partner_energy,
            user_message_length=user_message_length,
            communication_rhythm=communication_rhythm,
            conversation_id=conversation_id,
            on_done=on_done
        )

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
