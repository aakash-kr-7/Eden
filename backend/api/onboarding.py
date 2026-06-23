import logging
import json
from typing import Optional, Union, Any
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from auth.firebase import AuthenticatedIdentity, get_authenticated_identity
from personality.generator import PersonalityGenerator
from core.context_builder import build_context
from core.llm import get_llm_core, _clean_response

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/onboarding")

db = None
memory_store = None
get_partner_instance = None
resolve_or_assign_primary_pair = None
clear_cache = None
plan_burst_response = None
on_message_saved = None
on_session_started = None


# ---------------------------------------------------------------------------
# Structured Steps Config
# ---------------------------------------------------------------------------
ONBOARDING_STEPS = {
    0: {
        "key": "preferred_name",
        "question": "What should I call you?",
        "type": "open",
        "options": []
    },
    1: {
        "key": "opening_feel",
        "question": "What made you come here today?",
        "type": "open",
        "options": []
    },
    2: {
        "key": "connection_style",
        "question": "When you really connect with someone — what does that feel like for you?",
        "type": "open",
        "options": []
    },
    3: {
        "key": "communication_pace",
        "question": "Do you tend to have long deep conversations or quick check-ins? Or something in between?",
        "type": "multiple_choice",
        "options": ["long and deep", "quick and light", "it depends"]
    },
    4: {
        "key": "emotional_depth_preference",
        "question": "How much do you usually share with people you're close to?",
        "type": "multiple_choice",
        "options": ["a lot — I go deep", "some things — when it feels right", "not much — I'm more private"]
    },
    5: {
        "key": "humor_style",
        "question": "What kind of humor lands for you?",
        "type": "multiple_choice",
        "options": ["dry and deadpan", "warm and silly", "dark and honest", "I'm not really a humor person"]
    },
    6: {
        "key": "relationship_type_intent",
        "question": "What kind of connection are you hoping for here?",
        "type": "multiple_choice",
        "options": ["someone to talk to", "a real friendship", "something that might become more", "I'm not sure yet"]
    },
    7: {
        "key": "something_real",
        "question": "Tell me one thing about yourself that you don't usually lead with.",
        "type": "open",
        "options": []
    },
    8: {
        "key": "one_last_thing",
        "question": "Is there anything you'd want someone to know before getting to know you?",
        "type": "open",
        "options": []
    }
}


class RespondRequest(BaseModel):
    step: int
    response: Union[str, dict, Any]


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
            "current_step": None,
            "partner_ready": False
        }

    # Fetch partner state
    partner = db.get_partner(user_id) if db else None
    partner_ready = partner is not None

    complete = bool(user.get("onboarding_completed", 0))

    # Fetch current session step
    session = db.get_onboarding_session(user_id) if db else None
    current_step = session["current_step"] if session else None

    return {
        "complete": complete,
        "current_step": current_step,
        "partner_ready": partner_ready
    }


@router.post("/start")
async def start_onboarding(
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    """Initializes onboarding session, idempotent."""
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
    # If the user somehow completed all questions but hasn't run complete, limit step to 8
    if step >= len(ONBOARDING_STEPS):
        step = len(ONBOARDING_STEPS) - 1

    step_info = ONBOARDING_STEPS[step]
    return {
        "step": step,
        "question": step_info["question"],
        "type": step_info["type"],
        "options": step_info["options"]
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

    if current_step not in ONBOARDING_STEPS:
        raise HTTPException(status_code=400, detail="Onboarding questions already completed. Call /complete.")

    step_info = ONBOARDING_STEPS[current_step]
    key = step_info["key"]

    # Extract response string
    if isinstance(payload.response, dict):
        response_str = payload.response.get("value") or payload.response.get("text") or str(payload.response)
    else:
        response_str = str(payload.response).strip()

    # Validate multiple choice response
    if step_info["type"] == "multiple_choice":
        if response_str not in step_info["options"]:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid response choice. Options are: {', '.join(step_info['options'])}"
            )

    # Validate open response (Step 0 to 7 must have non-empty text; step 8 is optional)
    if step_info["type"] == "open" and current_step != 8:
        if not response_str:
            raise HTTPException(status_code=400, detail="Response cannot be empty.")

    # Save to responses JSON blob
    responses = session["responses"]
    responses[key] = response_str

    next_step = current_step + 1
    if db:
        db.update_onboarding_session(user_id, next_step, responses)

    # Return next question or completion signal
    if next_step >= len(ONBOARDING_STEPS):
        return {
            "step": next_step,
            "complete": True,
            "question": None,
            "type": None,
            "options": None
        }

    next_step_info = ONBOARDING_STEPS[next_step]
    return {
        "step": next_step,
        "complete": False,
        "question": next_step_info["question"],
        "type": next_step_info["type"],
        "options": next_step_info["options"]
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

    try:
        # 1. Run partner generation (calls PersonalityGenerator)
        partner_data = await PersonalityGenerator.generate(onboarding_data, user_id)

        # 2. Database update transaction
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

                # Save partner record
                db.save_partner(
                    user_id=user_id,
                    partner_id=partner_data["id"],
                    name=partner_data["name"],
                    archetype_id=partner_data["archetype_id"],
                    persona_json=partner_data["persona_json"],
                    voice_style_json=partner_data["voice_style_json"],
                )

                # Clear cache to reflect new partner registration
                if clear_cache:
                    clear_cache(user_id)

                # Resolve relationship pair
                pair = resolve_or_assign_primary_pair(user_id) if resolve_or_assign_primary_pair else {"id": "dummy", "partner_id": partner_data["id"]}

                # Apply communication pace cadence
                cadence_map = {
                    "long and deep": "gentle",
                    "quick and light": "frequent",
                    "it depends": "balanced"
                }
                cadence = cadence_map.get(onboarding_data.get("communication_pace", ""), "balanced")
                db.update_pair_proactive_settings(pair["id"], proactive_cadence=cadence)

        # 3. Store onboarding facts as pinned memories (Stubs)
        pass

        # 4. Generate first message using full context pipeline (Stubs)
        organic_opening_line = "hey. you actually showed up."
        partner_name = partner_data["name"]

        # Clean up temporary onboarding session
        if db:
            db.delete_onboarding_session(user_id)

        return {
            "partner_name": partner_name,
            "first_message": organic_opening_line
        }

    except Exception as e:
        logger.exception("Failed to complete onboarding for user %s", user_id)
        raise HTTPException(status_code=500, detail=f"Onboarding completion failed: {str(e)}")
