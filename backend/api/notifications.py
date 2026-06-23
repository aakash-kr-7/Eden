# =============================================================================
# api/notifications.py — Notifications and FCM Token Management API
# =============================================================================

from datetime import datetime, timedelta
import json
import logging

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from auth.firebase import AuthenticatedIdentity, get_authenticated_identity
from memory.store import db
from core.fcm import FCMSender

logger = logging.getLogger(__name__)

router = APIRouter()

_ACTIVE_SESSIONS: dict[str, datetime] = {}


def update_user_presence(user_id: str) -> None:
    _ACTIVE_SESSIONS[user_id] = datetime.utcnow()
    logger.debug("Updated active presence for user %s", user_id)


def is_user_active(user_id: str) -> bool:
    last_seen = _ACTIVE_SESSIONS.get(user_id)
    if not last_seen:
        return False
    return datetime.utcnow() - last_seen < timedelta(seconds=15)


def _message_list_from_payload(payload_dict: dict, fallback_preview: str) -> list[str]:
    messages = payload_dict.get("messages") if isinstance(payload_dict, dict) else None
    if isinstance(messages, list) and messages:
        return [str(message) for message in messages if str(message).strip()]
    return [fallback_preview] if fallback_preview else []


def _delivery_status(outcome: str) -> str:
    if outcome == "sent":
        return "sent"
    if outcome == "no_tokens":
        return "no_tokens"
    return "failed"


# ── API Models ───────────────────────────────────────────────────────────────

class RegisterTokenRequest(BaseModel):
    fcm_token: str
    platform: str


class NotificationPreferencesRequest(BaseModel):
    proactive: bool
    emotional_followup: bool
    anniversaries: bool
    absence_check: bool


# ── API Endpoints ─────────────────────────────────────────────────────────────

@router.post("/notifications/register")
async def register_token(
    body: RegisterTokenRequest,
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    user = db.get_user(identity.uid)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    current_token = user.get("fcm_token")
    if current_token == body.fcm_token:
        return {"status": "success", "message": "Token already registered (skipped)"}

    db.update_user_fcm_token(identity.uid, body.fcm_token)
    return {"status": "success", "message": "Token registered successfully"}


@router.post("/notifications/unregister")
async def unregister_token(
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    db.update_user_fcm_token(identity.uid, None)
    return {"status": "success", "message": "Token unregistered successfully"}


@router.patch("/notifications/preferences")
async def update_preferences(
    body: NotificationPreferencesRequest,
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    prefs_dict = body.model_dump()
    db.update_user_notification_preferences(identity.uid, prefs_dict)
    return {"status": "success", "preferences": prefs_dict}


@router.get("/notifications/preferences")
async def get_preferences(
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
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


@router.post("/me/notifications/{notification_id}/receipt")
async def confirm_notification_receipt(
    notification_id: str,
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    notification = db.get_notification(notification_id)
    if not notification:
        raise HTTPException(status_code=404, detail="Notification not found")
    if notification["user_id"] != identity.uid:
        raise HTTPException(status_code=403, detail="Forbidden")

    db.log_system_event(
        kind="notification_delivered_receipt",
        severity="info",
        user_id=identity.uid,
        pair_id=notification.get("pair_id"),
        payload={"notification_id": notification_id},
    )

    updated = db.confirm_notification_delivery(notification_id)
    return {"status": "success", "notification": updated}


@router.post("/me/presence")
async def report_presence(
    identity: AuthenticatedIdentity = Depends(get_authenticated_identity),
):
    update_user_presence(identity.uid)
    return {"status": "active"}


# ── Background Compatibility / Proactive Engine Helper ───────────────────────

async def queue_and_send_notification(
    user_id: str,
    pair_id: str,
    companion_id: str,
    sender_name: str,
    message_preview: str,
    payload_dict: dict,
) -> dict:
    app_active = is_user_active(user_id)
    queued_at = datetime.utcnow().isoformat(timespec="milliseconds")
    payload = {
        **(payload_dict or {}),
        "notification_id": "",
        "sender_name": sender_name,
        "message_preview": message_preview,
        "pair_id": pair_id,
        "companion_id": companion_id,
        "timestamp": queued_at,
        "app_active": str(app_active).lower(),
    }

    notification = db.queue_notification(
        user_id=user_id,
        pair_id=pair_id,
        companion_id=companion_id,
        sender_name=sender_name,
        message_preview=message_preview,
        payload_dict=payload,
    )
    payload["notification_id"] = notification["id"]
    notification = db.update_queued_notification_payload(
        notification["id"],
        message_preview=message_preview,
        payload_dict=payload,
    ) or notification

    if app_active:
        return db.mark_notification_status(
            notification["id"],
            "skipped",
            error_message="User is active on screen",
        ) or notification

    # Get the user token from the users table
    user = db.get_user(user_id)
    fcm_token = user.get("fcm_token") if user else None

    dispatch_preview = message_preview
    dispatch_payload = payload
    recent = db.get_recent_queued_notification_for_pair(
        pair_id,
        exclude_id=notification["id"],
        within_seconds=15,
    )
    if recent:
        try:
            previous_payload = json.loads(recent.get("payload_json") or "{}")
        except json.JSONDecodeError:
            previous_payload = {}

        messages = _message_list_from_payload(previous_payload, recent.get("message_preview") or "")
        messages.extend(_message_list_from_payload(payload, message_preview))
        if len(messages) > 1:
            dispatch_preview = f"{sender_name}: [{len(messages)} messages] {messages[-1]}"
            dispatch_payload = {
                **previous_payload,
                "message_preview": dispatch_preview,
                "messages": messages,
                "grouped_count": len(messages),
                "coalesced": True,
            }
            # Update the FIRST (recent) notification in DB
            db.update_queued_notification_payload(
                recent["id"],
                message_preview=dispatch_preview,
                payload_dict=dispatch_payload,
            )

            outcome = "failed"
            data_dict = {
                "pair_id": pair_id,
                "companion_id": companion_id,
                "sender_name": sender_name,
                "message_preview": dispatch_preview,
                "conversation_id": str(dispatch_payload.get("conversation_id") or ""),
                "timestamp": queued_at,
                "notification_id": recent["id"],
                "app_active": str(app_active).lower(),
                "coalesced": "true",
                "grouped_count": str(len(messages)),
            }
            if fcm_token:
                success = await FCMSender().send(fcm_token, sender_name, dispatch_preview, data_dict)
                outcome = "sent" if success else "failed"
            else:
                from core.proactive_engine import _send_push_hooks
                outcome = _send_push_hooks(
                    user_id=user_id,
                    title=sender_name,
                    body=dispatch_preview,
                    data=data_dict,
                )

            # Mark the FIRST notification status
            db.mark_notification_status(
                recent["id"],
                _delivery_status(outcome),
                error_message=None if outcome == "sent" else outcome,
            )

            # Mark the CURRENT (second) notification as 'coalesced' and return it
            return db.mark_notification_status(
                notification["id"],
                "coalesced",
                error_message=f"Coalesced into notification {recent['id']}",
            ) or notification

    outcome = "failed"
    data_dict = {
        "pair_id": pair_id,
        "companion_id": companion_id,
        "sender_name": sender_name,
        "message_preview": dispatch_preview,
        "conversation_id": str(dispatch_payload.get("conversation_id") or ""),
        "timestamp": queued_at,
        "notification_id": notification["id"],
        "app_active": str(app_active).lower(),
        "coalesced": str(bool(dispatch_payload.get("coalesced"))).lower(),
        "grouped_count": str(dispatch_payload.get("grouped_count") or 1),
    }
    if fcm_token:
        success = await FCMSender().send(fcm_token, sender_name, dispatch_preview, data_dict)
        outcome = "sent" if success else "failed"
    else:
        from core.proactive_engine import _send_push_hooks
        outcome = _send_push_hooks(
            user_id=user_id,
            title=sender_name,
            body=dispatch_preview,
            data=data_dict,
        )

    return db.mark_notification_status(
        notification["id"],
        _delivery_status(outcome),
        error_message=None if outcome == "sent" else outcome,
    ) or notification
