# ═══════════════════════════════════════════════════════════════════
# FILE: api/ops.py
# PURPOSE: Admin and operational endpoints — health, user management, GDPR.
# CONTEXT: Protected by X-Ops-Key header. Never exposed to Flutter clients.
# ═══════════════════════════════════════════════════════════════════

import time
import logging
from typing import Optional

from fastapi import APIRouter, Depends, Header, HTTPException, Query

from config import settings
from core.llm import check_llm_health
from core.fcm import FCMSender
from memory.store import db
from memory.consolidator import MemoryConsolidator

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/ops")


def require_ops_key(x_ops_key: Optional[str] = Header(default=None)) -> str:
    """Dependency validator to ensure X-Ops-Key header matches configured OPS_SECRET_KEY."""
    if not x_ops_key or x_ops_key != settings.OPS_SECRET_KEY:
        raise HTTPException(status_code=403, detail="Ops access denied")
    return x_ops_key


@router.get("/health/deep")
async def deep_health(
    x_ops_key: str = Depends(require_ops_key),
):
    """Deep health check of database, LLM gateway, memory index, queue, and user metrics."""
    # 1. Database health
    try:
        db_health = db.get_database_health()
    except Exception as exc:
        db_health = {"ok": False, "error": str(exc), "tables": [], "row_counts": {}}

    # 2. LLM health & latency
    start_time = time.perf_counter()
    try:
        llm_res = await check_llm_health()
        latency_ms = round((time.perf_counter() - start_time) * 1000, 2)
        llm_ok = llm_res.get("status") == "ok"
    except Exception as exc:
        llm_ok = False
        latency_ms = round((time.perf_counter() - start_time) * 1000, 2)

    # 3. Memory system health
    try:
        mem_stats = db.get_memory_system_stats()
    except Exception as exc:
        mem_stats = {"ok": False, "error": str(exc), "total_memories": 0, "avg_salience": 0.0}

    # 4. Proactive queue health
    try:
        queue_stats = db.get_proactive_queue_stats()
    except Exception as exc:
        queue_stats = {"pending": 0, "oldest_pending_age_minutes": 0.0, "error": str(exc)}

    # 5. Active users count (7 days)
    try:
        active_users_7d = db.get_active_users_count(days=7)
    except Exception:
        active_users_7d = 0

    return {
        "database": db_health,
        "llm": {"ok": llm_ok, "latency_ms": latency_ms},
        "memory_system": mem_stats,
        "proactive_queue": queue_stats,
        "active_users_7d": active_users_7d,
    }


@router.get("/users")
async def list_users(
    page: int = Query(default=1, ge=1),
    x_ops_key: str = Depends(require_ops_key),
):
    """Get paginated list of users and relationship statuses (50 per page)."""
    users_list = db.list_ops_users_paginated(page=page, limit=50)
    return {
        "users": users_list,
        "page": page,
        "limit": 50,
        "count": len(users_list),
    }


@router.get("/export/{user_id}")
async def export_user(
    user_id: str,
    x_ops_key: str = Depends(require_ops_key),
):
    """GDPR-compliant data export of user profile, partner basics, memories, summaries, and events (no messages)."""
    user_export = db.get_user_gdpr_export(user_id)
    if not user_export:
        raise HTTPException(status_code=404, detail="User not found")
    return user_export


@router.post("/trigger_consolidation/{user_id}")
async def trigger_consolidation(
    user_id: str,
    x_ops_key: str = Depends(require_ops_key),
):
    """Trigger manual memory consolidation for a user."""
    user = db.get_user(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    consolidator = MemoryConsolidator()
    with db.get_connection() as conn:
        await consolidator.consolidate_user_conversations(conn, user_id)
    return {"status": "success", "message": "Memory consolidation triggered successfully"}


@router.post("/reset_user/{user_id}")
async def reset_user(
    user_id: str,
    x_confirm: str = Header(...),
    x_ops_key: str = Depends(require_ops_key),
):
    """Resets user onboarding and deletes all of their data except the users table entry."""
    if settings.ENVIRONMENT.lower() == "production":
        raise HTTPException(status_code=403, detail="Resetting user data is blocked in production")

    if x_confirm != "yes-delete-everything":
        raise HTTPException(status_code=400, detail="X-Confirm header must be 'yes-delete-everything'")

    user = db.get_user(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    db.reset_user_data(user_id)
    logger.info("Admin reset user data completed for user %s", user_id)
    return {"status": "success", "message": f"User {user_id} data reset complete"}


@router.delete("/users/{user_id}")
async def delete_user(
    user_id: str,
    x_ops_key: str = Depends(require_ops_key),
):
    """GDPR erasure request to delete user and all associated data."""
    user = db.get_user(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    db.delete_user(user_id)
    logger.info("Admin GDPR erasure completed for user %s", user_id)
    return {"status": "success", "message": f"User {user_id} and all related data deleted successfully"}


@router.post("/test_notification/{user_id}")
async def test_notification(
    user_id: str,
    x_ops_key: str = Depends(require_ops_key),
):
    """
    Fetches user's fcm_token, calls FCMSender.send() with a test message, and returns the result.
    """
    user = db.get_user(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    fcm_token = user.get("fcm_token")
    if not fcm_token:
        return {"sent": False, "token_exists": False}

    fcm_sender = FCMSender()
    sent = await fcm_sender.send(
        fcm_token=fcm_token,
        title="Test Notification",
        body="This is a test push notification.",
        data={"type": "test_notification"}
    )
    return {"sent": sent, "token_exists": True}
