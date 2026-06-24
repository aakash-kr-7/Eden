# ═══════════════════════════════════════════════════════════════════
# FILE: api/notifications.py
# PURPOSE: FCM token registration and notification preference management.
# CONTEXT: Called by Flutter on startup and when FCM token refreshes.
# ═══════════════════════════════════════════════════════════════════

import logging
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from auth.firebase import AuthenticatedIdentity, get_authenticated_identity
from memory.store import db

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/notifications")

# ── API Models ───────────────────────────────────────────────────────────────

class RegisterTokenRequest(BaseModel):
    fcm_token: str

class NotificationPreferencesRequest(BaseModel):
    proactive: bool
    emotional_followup: bool
    anniversaries: bool
    absence_check: bool

# ── API Endpoints ─────────────────────────────────────────────────────────────

@router.post("/register")
async def register_token(
    body: RegisterTokenRequest,
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    user = db.get_user(identity.uid)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    db.update_user_fcm_token(identity.uid, body.fcm_token)
    logger.info("FCM token registered for user %s", identity.uid)
    return {"status": "success", "message": "Token registered successfully"}


@router.post("/unregister")
async def unregister_token(
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    user = db.get_user(identity.uid)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    db.update_user_fcm_token(identity.uid, None)
    logger.info("FCM token cleared for user %s", identity.uid)
    return {"status": "success", "message": "Token unregistered successfully"}


@router.patch("/preferences")
async def update_preferences(
    body: NotificationPreferencesRequest,
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    user = db.get_user(identity.uid)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    prefs_dict = body.model_dump()
    db.update_user_notification_preferences(identity.uid, prefs_dict)
    logger.info("Notification preferences updated for user %s", identity.uid)
    return {"status": "success", "preferences": prefs_dict}


@router.get("/preferences")
async def get_preferences(
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    user = db.get_user(identity.uid)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    prefs = db.get_user_notification_preferences(identity.uid)
    if prefs is None:
        # Default fallback preferences
        prefs = {
            "proactive": True,
            "emotional_followup": True,
            "anniversaries": True,
            "absence_check": True
        }
    return prefs
