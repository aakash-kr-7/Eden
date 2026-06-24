# ═══════════════════════════════════════════════════════════════════
# FILE: api/proactive.py
# PURPOSE: Partner's proactive messages — sent while user was away.
# CONTEXT: Called by Flutter on session start to load "while you were away" messages.
# ═══════════════════════════════════════════════════════════════════

import logging
from fastapi import APIRouter, Depends, HTTPException
from auth.firebase import AuthenticatedIdentity, get_authenticated_identity
from memory.store import db

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/proactive")


@router.get("/pending")
async def get_pending_proactive(
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    """
    Returns all unsent/unacknowledged proactive messages for this user.
    These are messages the companion sent while the user was away.
    """
    user_id = identity.uid
    user = db.get_user(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    rows = db.get_pending_proactive_events(user_id)
    events = []
    for r in rows:
        sent_at = r["delivered_at"] or r["scheduled_for"] or r["created_at"]
        events.append({
            "id": r["id"],
            "message": r["message_text"],
            "trigger_type": r["reason"],
            "sent_at": sent_at
        })
    return events


@router.post("/acknowledge/{id}")
async def acknowledge_proactive(
    id: str,
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    """Marks a proactive message as acknowledged (read by the user)."""
    user_id = identity.uid
    user = db.get_user(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    try:
        success = db.acknowledge_proactive_event(id, user_id)
        if not success:
            raise HTTPException(status_code=404, detail="Proactive message not found")
    except PermissionError:
        raise HTTPException(status_code=403, detail="Forbidden")

    logger.info("Proactive message %s acknowledged by user %s", id, user_id)
    return {"status": "success"}
