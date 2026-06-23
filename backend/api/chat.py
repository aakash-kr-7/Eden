import logging
import asyncio
from typing import Optional

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from auth.firebase import AuthenticatedIdentity, get_authenticated_identity
from config import settings
from core.concurrency import concurrency
from core.context_builder import build_context
from core.llm import get_llm_core, _clean_response
from core.session_loader import SessionLoader

logger = logging.getLogger(__name__)

# Set the router prefix so it mounts cleanly
router = APIRouter(prefix="/chat")

# Stub database / memory / registry modules deleted
db = None
extract_and_save = None
on_message_saved = None
on_session_started = None
get_partner_instance = None
resolve_or_assign_primary_pair = None


class MessageRequest(BaseModel):
    message: str = Field(..., min_length=1, max_length=2000)
    conversation_id: Optional[str] = None


class ChatRequest(BaseModel):
    user_id: Optional[str] = None
    message: str = Field(..., min_length=1, max_length=2000)
    conversation_id: Optional[str] = None
    partner_id: Optional[str] = None
    client_sent_at: Optional[str] = None
    draft_duration_ms: Optional[int] = None
    reply_latency_ms: Optional[int] = None
    parent_message_id: Optional[int] = None


async def run_relationship_event_detection(user_id: str, pair_id: str, partner_id: str):
    """
    Background task to run behavioral pattern detection.
    """
    pass


async def extract_and_save_task(user_id: str, pair_id: str, partner_id: str, conversation_id: str):
    """
    Background task to trigger memory extraction checks.
    """
    pass


@router.post("/message")
async def send_message(
    request: MessageRequest,
    background_tasks: BackgroundTasks,
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    # Validate user exists and completed onboarding
    user = db.get_user(identity.uid) if db else None
    if not user or not user.get("onboarding_completed"):
        return JSONResponse(status_code=403, content={"error": "onboarding_required"})

    # Resolve pair
    pair = resolve_or_assign_primary_pair(identity.uid) if resolve_or_assign_primary_pair else None
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
            if on_session_started:
                on_session_started(pair["id"])
        else:
            conversation = db.get_conversation(conversation_id)
            if not conversation or conversation["user_id"] != identity.uid or conversation["pair_id"] != pair["id"]:
                raise HTTPException(status_code=404, detail="Conversation not found")

        # Save user message to DB
        db.save_message(
            conversation_id=conversation_id,
            user_id=identity.uid,
            pair_id=pair["id"],
            partner_id=pair["partner_id"],
            role="user",
            content=request.message
        )
        if on_message_saved:
            on_message_saved(pair["id"], "user", request.message)

        # Build context
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

        # Call LLMCore complete
        try:
            llm_core = get_llm_core()
            raw_reply = await llm_core.complete(system_prompt=system_prompt, messages=messages)
            reply = _clean_response(raw_reply) or "..."
        except Exception as exc:
            logger.error("LLM completion failed for pair %s: %s", pair["id"], exc)
            raise HTTPException(status_code=503, detail="Your partner is offline")

        # Save partner reply to DB
        db.save_message(
            conversation_id=conversation_id,
            user_id=identity.uid,
            pair_id=pair["id"],
            partner_id=pair["partner_id"],
            role="assistant",
            content=reply
        )
        if on_message_saved:
            on_message_saved(pair["id"], "assistant", reply)

        # Trigger background tasks (fire-and-forget)
        background_tasks.add_task(
            extract_and_save_task,
            user_id=identity.uid,
            pair_id=pair["id"],
            partner_id=pair["partner_id"],
            conversation_id=conversation_id
        )
        background_tasks.add_task(
            run_relationship_event_detection,
            user_id=identity.uid,
            pair_id=pair["id"],
            partner_id=pair["partner_id"]
        )

        # Load partner mood
        partner_inst = get_partner_instance(identity.uid) if get_partner_instance else None
        emotional_summary = db.get_emotional_summary(identity.uid, pair_id=pair["id"], limit=6) if db else {}
        if emotional_summary and emotional_summary.get("dominant_emotions"):
            partner_mood = ", ".join(emotional_summary["dominant_emotions"])
        elif partner_inst and partner_inst.matching_profile:
            partner_mood = partner_inst.matching_profile.get("social_energy", "neutral")
        else:
            partner_mood = "neutral"

        return {
            "response": reply,
            "conversation_id": conversation_id,
            "partner_mood": partner_mood
        }


@router.get("/conversations")
async def get_conversations(
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    # Validate user exists and completed onboarding
    user = db.get_user(identity.uid) if db else None
    if not user or not user.get("onboarding_completed"):
        return JSONResponse(status_code=403, content={"error": "onboarding_required"})

    conversations = db.get_user_conversations(identity.uid)
    return conversations


@router.get("/conversations/{conversation_id}/messages")
async def get_messages(
    conversation_id: str,
    before_id: Optional[int] = Query(default=None),
    limit: int = Query(default=50, ge=1, le=100),
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    # Validate user exists and completed onboarding
    user = db.get_user(identity.uid) if db else None
    if not user or not user.get("onboarding_completed"):
        return JSONResponse(status_code=403, content={"error": "onboarding_required"})

    conversation = db.get_conversation(conversation_id)
    if not conversation:
        raise HTTPException(status_code=404, detail="Conversation not found")
    if conversation["user_id"] != identity.uid:
        raise HTTPException(status_code=403, detail="Not authorized to access this conversation")

    messages = db.get_paginated_messages(conversation_id, limit=limit, before_id=before_id)
    return messages


@router.delete("/conversations/{conversation_id}")
async def delete_conversation(
    conversation_id: str,
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    # Validate user exists and completed onboarding
    user = db.get_user(identity.uid) if db else None
    if not user or not user.get("onboarding_completed"):
        return JSONResponse(status_code=403, content={"error": "onboarding_required"})

    conversation = db.get_conversation(conversation_id)
    if not conversation:
        raise HTTPException(status_code=404, detail="Conversation not found")
    if conversation["user_id"] != identity.uid:
        raise HTTPException(status_code=403, detail="Not authorized to delete this conversation")

    db.soft_delete_conversation(conversation_id)
    return {"success": True, "deleted": True}


@router.post("/session/start")
async def start_session(
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    # Validate user exists and completed onboarding
    user = db.get_user(identity.uid) if db else None
    if not user or not user.get("onboarding_completed"):
        return JSONResponse(status_code=403, content={"error": "onboarding_required"})

    loader = SessionLoader()
    async with concurrency.acquire(identity.uid):
        payload = await loader.load_session(identity.uid)
        await loader.update_last_active(identity.uid)
    return payload
