# =============================================================================
# api/proactive.py — Proactive Engine Endpoints
# =============================================================================

from typing import Optional
from fastapi import APIRouter, Depends, Header, HTTPException, Query

from auth.firebase import AuthenticatedIdentity, get_authenticated_identity
from memory.store import db
from core.proactive_engine import ProactiveEngine
from config import settings

router = APIRouter(prefix="/proactive")


def _require_ops_access(x_admin_token: Optional[str] = Header(default=None)) -> None:
    if settings.DEBUG:
        return
    if settings.ADMIN_DEBUG_TOKEN and x_admin_token == settings.ADMIN_DEBUG_TOKEN:
        return
    raise HTTPException(status_code=403, detail="Ops access denied")


@router.get("/pending")
async def get_pending_proactive(
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    """
    Returns all unsent (unacknowledged but sent/delivered to FCM) proactive messages for this user.
    These are the messages that the companion sent while the user was away.
    """
    user_id = identity.uid
    rows = db.conn.execute(
        """
        SELECT id, message_text, reason, delivered_at, scheduled_for, created_at
        FROM proactive_events
        WHERE user_id = ? AND status IN ('delivered', 'sent')
        ORDER BY delivered_at DESC, created_at DESC
        """,
        (user_id,),
    ).fetchall()

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


@router.post("/acknowledge/{message_id}")
async def acknowledge_proactive(
    message_id: str,
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    """Marks a proactive message as acknowledged (read by the user)."""
    user_id = identity.uid
    row = db.conn.execute(
        "SELECT user_id FROM proactive_events WHERE id = ?", (message_id,)
    ).fetchone()

    if not row:
        raise HTTPException(status_code=404, detail="Proactive message not found")
    if row["user_id"] != user_id:
        raise HTTPException(status_code=403, detail="Forbidden")

    db.conn.execute(
        "UPDATE proactive_events SET status = 'acknowledged' WHERE id = ?",
        (message_id,)
    )
    return {"status": "success"}


@router.post("/trigger")
async def trigger_proactive(
    user_id: Optional[str] = Query(default=None),
    x_admin_token: Optional[str] = Header(default=None),
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    """Admin-only endpoint to manually trigger evaluation for a user."""
    _require_ops_access(x_admin_token)

    target_user_id = user_id or identity.uid
    engine = ProactiveEngine()
    # Runs the evaluation loop (forcing it to bypass standard time check thresholds)
    await engine.evaluate(target_user_id, force=True)

    return {"status": "success"}
