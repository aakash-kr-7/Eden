import logging
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from auth.firebase import AuthenticatedIdentity, get_authenticated_identity
from memory.store import db
from personality.registry import build_opening_line, get_partner_instance, resolve_or_assign_primary_pair, clear_cache
from personality.generator import generate_partner
from core.burst_engine import plan_burst_response
from memory.relationship_engine import on_message_saved, on_session_started

logger = logging.getLogger(__name__)

router = APIRouter()

class OnboardingCompleteRequest(BaseModel):
    preferred_name: str
    connection_style: str
    presence_frequency: str
    depth_preference: str
    behavioral_guardrail: str


@router.get("/onboarding/status")
async def get_onboarding_status(
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    try:
        user = db.get_user(identity.uid)
        if not user:
            return {"onboarding_completed": False}
        return {"onboarding_completed": bool(user.get("onboarding_completed", 0))}
    except Exception as e:
        logger.exception("Failed to get onboarding status for user %s", identity.uid)
        raise HTTPException(status_code=500, detail=f"Failed to get status: {str(e)}")


@router.post("/onboarding/complete")
async def complete_onboarding(
    payload: OnboardingCompleteRequest,
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    user_id = identity.uid
    logger.info("Completing onboarding for user: %s", user_id)
    try:
        with db.transaction():
            # 1. Ensure user row exists
            db.get_or_create_user(user_id)
            
            # 2. Save onboarding signals + preferred name
            signals = {
                "connection_style": payload.connection_style,
                "presence_frequency": payload.presence_frequency,
                "depth_preference": payload.depth_preference,
                "behavioral_guardrail": payload.behavioral_guardrail,
            }
            db.save_onboarding_signals(user_id, payload.preferred_name, signals, onboarding_completed=1)
            
            # 3. Generate deeply personalized partner
            partner_data = generate_partner(signals, user_id)
            
            # 4. Save partner in database (which dynamically registers them as a companion to preserve FK constraints)
            db.save_partner(
                user_id=user_id,
                partner_id=partner_data["id"],
                name=partner_data["name"],
                archetype_id=partner_data["archetype_id"],
                persona_json=partner_data["persona_json"],
                voice_style_json=partner_data["voice_style_json"],
            )
            
            # Clear registry cache for user to force load new partner
            clear_cache(user_id)
            
            # 5. Resolve and assign primary relationship pair
            pair = resolve_or_assign_primary_pair(user_id)
            
            # 6. Apply cadence to pair
            cadence_map = {
                "every_now_and_then": "gentle",
                "when_it_matters": "gentle",
                "fairly_often": "balanced",
                "always_around": "frequent",
            }
            cadence = cadence_map.get(payload.presence_frequency, "balanced")
            db.update_pair_proactive_settings(pair["id"], proactive_cadence=cadence)
            
            # Get loaded partner instance from registry
            partner_instance = get_partner_instance(user_id)
            if not partner_instance:
                raise ValueError("Generated partner instance could not be loaded from registry.")
                
            # 7. Create active conversation, generate opener and save burst response
            conversation_id = db.create_conversation(
                user_id=user_id,
                pair_id=pair["id"],
                companion_id=partner_instance.id,
            )
            on_session_started(pair["id"])
            
            # Reload updated pair to pass to plan_burst_response
            pair_updated = db.get_pair_by_id(pair["id"]) or pair
            
            opening_line = build_opening_line(partner_instance, session_count=1)
            opening_plan = plan_burst_response(
                raw_text=opening_line,
                character=partner_instance,
                is_opening=True,
                relationship_state=pair_updated,
            )
            for burst in opening_plan.bursts:
                db.save_message(
                    conversation_id=conversation_id,
                    user_id=user_id,
                    pair_id=pair["id"],
                    companion_id=partner_instance.id,
                    role="assistant",
                    content=burst.text,
                )
                on_message_saved(pair["id"], "assistant", burst.text)
            
        return {
            "status": "success",
            "success": True,
            "companion_id": partner_instance.id,
            "companion_name": partner_instance.name,
            "companion_summary": partner_instance.summary,
            "humanizing_details": partner_instance.personality_traits["quirks"],
            "conversational_vibe": partner_instance.archetype,
            "opening_line": opening_plan.combined_text,
            "pair_id": pair["id"],
        }
    except Exception as e:
        logger.exception("Failed to complete onboarding for user %s", user_id)
        try:
            db.log_system_event(
                "onboarding_rollback",
                "error",
                user_id=user_id,
                payload={
                    "error": str(e),
                    "action": "rollback",
                    "preferred_name": payload.preferred_name,
                    "connection_style": payload.connection_style,
                }
            )
        except Exception as log_err:
            logger.error("Failed to log onboarding rollback to system_events: %s", log_err)
        raise HTTPException(status_code=500, detail=f"Failed to complete onboarding: {str(e)}")
