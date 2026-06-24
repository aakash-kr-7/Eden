# ═══════════════════════════════════════════════════════════════════
# FILE: api/onboarding.py
# PURPOSE: 9-step onboarding flow — collects user profile, generates partner.
# CONTEXT: Only runs once per user. Partner is permanent after completion.
# ═══════════════════════════════════════════════════════════════════

import logging
import json
from typing import Optional, Union, Any
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from auth.firebase import AuthenticatedIdentity, get_authenticated_identity
from config import settings
from personality.generator import PersonalityGenerator
from core.context_builder import build_context
from core.llm import get_llm_core, _clean_response
from memory.store import db, MemoryStore
from personality.registry import get_partner_instance, resolve_or_assign_primary_pair
from engine.life_simulator import LifeSimulator

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/onboarding")

memory_store = MemoryStore()

# ---------------------------------------------------------------------------
# Question Configuration
# ---------------------------------------------------------------------------
ONBOARDING_STEPS = [
    {
        "step": 0,
        "question": "What should I call you?",
        "type": "open_text",
        "options": None,
        "optional": False,
        "key": "preferred_name"
    },
    {
        "step": 1,
        "question": "What brought you here today?",
        "type": "open_text",
        "options": None,
        "optional": False,
        "key": "opening_feel"
    },
    {
        "step": 2,
        "question": "When you really connect with someone — what does it feel like?",
        "type": "open_text",
        "options": None,
        "optional": False,
        "key": "connection_style"
    },
    {
        "step": 3,
        "question": "How do you prefer to talk?",
        "type": "multiple_choice",
        "options": ["Long deep conversations", "Quick check-ins", "Somewhere in between"],
        "optional": False,
        "key": "communication_pace"
    },
    {
        "step": 4,
        "question": "How much do you usually open up to people you're close to?",
        "type": "multiple_choice",
        "options": ["A lot — I go deep", "Some things, when it feels right", "Not much — I'm more private"],
        "optional": False,
        "key": "emotional_depth_preference"
    },
    {
        "step": 5,
        "question": "What kind of humor actually gets you?",
        "type": "multiple_choice",
        "options": ["Dry and deadpan", "Warm and silly", "Dark and honest", "I'm not really a humor person"],
        "optional": False,
        "key": "humor_style"
    },
    {
        "step": 6,
        "question": "What are you hoping to find here?",
        "type": "multiple_choice",
        "options": ["Someone to talk to", "A real friendship", "Something that might become more", "I'm not sure yet"],
        "optional": False,
        "key": "relationship_type_intent"
    },
    {
        "step": 7,
        "question": "Tell me one thing about yourself you don't usually lead with.",
        "type": "open_text",
        "options": None,
        "optional": False,
        "key": "something_real"
    },
    {
        "step": 8,
        "question": "Is there anything you'd want someone to know before getting to know you?",
        "type": "open_text",
        "options": None,
        "optional": True,
        "key": "one_last_thing"
    }
]


class RespondRequest(BaseModel):
    step: int
    response: Union[str, list, Any]


@router.get("/status")
async def get_onboarding_status(
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    """Checks completion state, current step index, and partner readiness."""
    user_id = identity.uid
    user = db.get_user(user_id) if db else None
    if not user:
        return {
            "complete": False,
            "current_step": 0,
            "partner_ready": False
        }

    partner = db.get_partner(user_id) if db else None
    partner_ready = partner is not None

    complete = bool(user.get("onboarding_completed", 0) or user.get("onboarding_complete", 0))

    session = db.get_onboarding_session(user_id) if db else None
    current_step = session["current_step"] if session else (8 if complete else 0)

    return {
        "complete": complete,
        "current_step": current_step,
        "partner_ready": partner_ready
    }


@router.post("/start")
async def start_onboarding(
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    """Initializes onboarding session and returns first question."""
    user_id = identity.uid
    if db:
        db.get_or_create_user(user_id)
        session = db.get_onboarding_session(user_id)
        if not session:
            db.create_onboarding_session(user_id)
            session = db.get_onboarding_session(user_id)
    else:
        session = None

    step = session["current_step"] if session else 0
    if step >= len(ONBOARDING_STEPS):
        step = len(ONBOARDING_STEPS) - 1

    step_info = ONBOARDING_STEPS[step]
    return {
        "step": step,
        "question": step_info["question"],
        "type": step_info["type"],
        "options": step_info["options"],
        "optional": step_info["optional"]
    }


@router.post("/respond")
async def respond_onboarding(
    payload: RespondRequest,
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    """Validates user responses, updates onboarding progress state."""
    user_id = identity.uid
    session = db.get_onboarding_session(user_id) if db else None
    if not session:
        raise HTTPException(status_code=400, detail="Onboarding session not started. Call /start first.")

    current_step = session["current_step"]
    if payload.step != current_step:
        raise HTTPException(status_code=400, detail=f"Step mismatch. Expected step {current_step}, got {payload.step}.")

    if current_step >= len(ONBOARDING_STEPS):
        raise HTTPException(status_code=400, detail="Onboarding questions already completed. Call /complete.")

    step_info = ONBOARDING_STEPS[current_step]
    key = step_info["key"]

    response_val = payload.response
    if isinstance(response_val, str):
        response_val = response_val.strip()

    # Validate multiple choice response
    if step_info["type"] == "multiple_choice":
        if isinstance(response_val, list):
            for choice in response_val:
                if choice not in step_info["options"]:
                    raise HTTPException(
                        status_code=400,
                        detail=f"Invalid response choice. Options are: {', '.join(step_info['options'])}"
                    )
        else:
            if response_val not in step_info["options"]:
                raise HTTPException(
                    status_code=400,
                    detail=f"Invalid response choice. Options are: {', '.join(step_info['options'])}"
                )

    # Validate open response (Step 0 to 7 must have non-empty text; step 8 is optional)
    if not step_info["optional"] and step_info["type"] == "open_text":
        if not response_val:
            raise HTTPException(status_code=400, detail="Response cannot be empty.")

    responses = session["responses"]
    if not isinstance(responses, dict):
        responses = {}
    responses[key] = response_val

    next_step = current_step + 1
    if db:
        db.update_onboarding_session(user_id, next_step, responses)

    # Return next question or completion signal
    if next_step >= len(ONBOARDING_STEPS):
        return {
            "next_step": next_step,
            "question": None,
            "is_complete": True
        }

    next_step_info = ONBOARDING_STEPS[next_step]
    return {
        "next_step": next_step,
        "question": {
            "step": next_step_info["step"],
            "question": next_step_info["question"],
            "type": next_step_info["type"],
            "options": next_step_info["options"],
            "optional": next_step_info["optional"]
        },
        "is_complete": False
    }


@router.post("/complete")
async def complete_onboarding(
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    """Validates completion of onboarding, triggers partner generation & returns first message."""
    user_id = identity.uid
    session = db.get_onboarding_session(user_id) if db else None
    if not session:
        raise HTTPException(status_code=400, detail="Onboarding session not started.")

    if session["current_step"] < len(ONBOARDING_STEPS):
        raise HTTPException(
            status_code=400,
            detail=f"Onboarding not complete. Currently at step {session['current_step']} of {len(ONBOARDING_STEPS)}."
        )

    onboarding_data = session["responses"]
    preferred_name = onboarding_data.get("preferred_name")
    something_real = onboarding_data.get("something_real")
    one_last_thing = onboarding_data.get("one_last_thing")

    # Validate that steps 0 to 7 are present
    for step_cfg in ONBOARDING_STEPS:
        if not step_cfg["optional"] and not onboarding_data.get(step_cfg["key"]):
            raise HTTPException(
                status_code=400,
                detail=f"Missing response for required question: {step_cfg['question']}"
            )

    try:
        # 1. Run partner generation
        partner_data = await PersonalityGenerator.generate(onboarding_data, user_id)

        # 2. Save signals, partner details and mark onboarding complete in DB
        if db:
            with db.transaction():
                db.get_or_create_user(user_id)
                
                # Save onboarding signals and mark complete in users table
                db.save_onboarding_signals(
                    user_id=user_id,
                    preferred_name=preferred_name,
                    signals=onboarding_data,
                    onboarding_completed=1
                )

                # Save partner record (also updates relationship pair & registers life state)
                db.save_partner(
                    user_id=user_id,
                    partner_id=partner_data["id"],
                    name=partner_data["name"],
                    archetype_id=partner_data["archetype_id"],
                    persona_json=partner_data["persona_json"],
                    voice_style_json=partner_data["voice_style_json"],
                )

                # Resolve relationship pair
                pair = resolve_or_assign_primary_pair(user_id)
                
                # Apply proactive cadence cadence (gentle/balanced/frequent)
                cadence_map = {
                    "Long deep conversations": "gentle",
                    "Quick check-ins": "frequent",
                    "Somewhere in between": "balanced"
                }
                cadence = cadence_map.get(onboarding_data.get("communication_pace", ""), "balanced")
                db.update_pair_proactive_settings(pair["id"], proactive_cadence=cadence)

        # 3. Initialize life state with defaults
        simulator = LifeSimulator()
        await simulator.initialize(db, user_id)

        # 4. Create 2 pinned memories from step 7 and step 8 answers
        with db.get_connection() as conn:
            if something_real:
                memory_store.add(
                    db=conn,
                    user_id=user_id,
                    memory_text=something_real,
                    memory_type="onboarding",
                    salience_score=0.9,
                    emotional_valence="neutral",
                    source_conversation_id="",
                    is_pinned=True
                )
            if one_last_thing:
                memory_store.add(
                    db=conn,
                    user_id=user_id,
                    memory_text=one_last_thing,
                    memory_type="onboarding",
                    salience_score=0.9,
                    emotional_valence="neutral",
                    source_conversation_id="",
                    is_pinned=True
                )

        # 5. Create conversation and generate first partner message using full ContextBuilder pipeline
        partner_id = partner_data["id"]
        partner_name = partner_data["name"]
        pair_id = pair["id"]
        conversation_id = db.create_conversation(user_id=user_id, pair_id=pair_id, partner_id=partner_id)

        system_prompt, messages = await build_context(
            user_id=user_id,
            pair_id=pair_id,
            current_message="",
            conversation_id=conversation_id,
            partner_id=partner_id
        )

        # Append a greeting trigger message if messages is empty
        if not messages:
            messages = [{"role": "user", "content": "Write your very first text message to greet the user."}]

        llm = get_llm_core()
        first_message_raw = await llm.complete(
            system_prompt=system_prompt,
            messages=messages,
            model=settings.GROQ_CHAT_MODEL,
            temperature=0.7
        )
        first_message = _clean_response(first_message_raw)

        # Save opening message to DB
        db.save_message(
            conversation_id=conversation_id,
            user_id=user_id,
            pair_id=pair_id,
            partner_id=partner_id,
            role="partner",
            content=first_message
        )

        # Clean up temporary onboarding session
        if db:
            db.delete_onboarding_session(user_id)

        return {
            "partner_name": partner_name,
            "first_message": first_message,
            "conversation_id": conversation_id
        }

    except Exception as e:
        logger.exception("Failed to complete onboarding for user %s", user_id)
        raise HTTPException(status_code=500, detail=f"Onboarding completion failed: {str(e)}")
