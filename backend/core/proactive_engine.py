# =============================================================================
# core/proactive_engine.py — Spontaneous Outreach Engine
# =============================================================================

import json
import logging
import uuid
import random
import asyncio
from datetime import datetime, timedelta
from typing import Optional
from zoneinfo import ZoneInfo

from config import settings
from memory.store import db
from core.llm import generate_reply
from memory.relationship_engine import on_message_saved
from api.notifications import queue_and_send_notification
from core.context_builder import build_context
from firebase_admin import messaging as firebase_messaging

logger = logging.getLogger(__name__)


def _user_local_now(timezone_name: Optional[str]) -> datetime:
    if timezone_name:
        try:
            return datetime.now(ZoneInfo(timezone_name))
        except Exception:
            pass
    return datetime.utcnow()


class ProactiveEngine:

    async def evaluate(self, user_id: str, force: bool = False):
        # The main evaluation loop — runs every 15 minutes per user via background task
        # Checks all trigger types and queues messages as appropriate
        # Never queues more than 1 proactive message per 4 hours per user
        # Never sends when partner is marked as busy (life_state.partner_busy_until > now)
        if not settings.PROACTIVE_ENGINE_ENABLED and not force:
            logger.info(f"Proactive engine disabled globally, skipping evaluation for user {user_id}")
            return

        # Check user preferences
        preferences = db.get_or_create_user_preferences(user_id)
        if not force and not preferences.get("allow_proactive_messages", 1):
            logger.info(f"Proactive messages disabled in user preferences for user {user_id}")
            return

        # Check 4-hour cooldown
        if not force and db.has_queued_proactive_in_last_hours(user_id, hours=4.0):
            logger.info(f"Proactive message cooldown active (4 hours) for user {user_id}")
            return

        # List pairs for user, sorted by closeness + trust DESC
        pairs = db.list_pairs_for_user(user_id)
        if not pairs:
            logger.info(f"No relationship pairs found for user {user_id}")
            return

        sorted_pairs = sorted(
            pairs,
            key=lambda p: (float(p.get("closeness_score") or 0.0) + float(p.get("trust_score") or 0.0)),
            reverse=True
        )

        trigger_found = False
        trigger_type = None
        trigger_context = None

        # 1. Anniversary Check
        trigger_context = await self.check_anniversary(user_id)
        if trigger_context:
            trigger_type = "anniversary"
            trigger_found = True

        # 2. Emotional Followup Check
        if not trigger_found:
            trigger_context = await self.check_emotional_followup(user_id)
            if trigger_context:
                trigger_type = "emotional_followup"
                trigger_found = True

        # 3. Memory Callback Check
        if not trigger_found:
            trigger_context = await self.check_memory_callback(user_id)
            if trigger_context:
                trigger_type = "memory_callback"
                trigger_found = True

        # 4. Absence Check
        if not trigger_found:
            trigger_context = await self.check_absence(user_id)
            if trigger_context:
                trigger_type = "absence"
                trigger_found = True

        if not trigger_found or not trigger_context:
            logger.info(f"No proactive triggers fired for user {user_id}")
            return

        # Check busy state
        pair_id = trigger_context["pair_id"]
        if not force:
            life_state = db.get_life_state(pair_id)
            if life_state:
                busy_until_str = life_state.get("partner_busy_until")
                if busy_until_str:
                    try:
                        busy_until = datetime.fromisoformat(busy_until_str)
                        if datetime.utcnow() < busy_until:
                            logger.info(f"Outreach blocked: companion in pair {pair_id} is busy until {busy_until_str}")
                            return
                    except ValueError:
                        pass

        # Generate actual message
        message = await self.generate_proactive_message(user_id, trigger_type, trigger_context)
        if not message or message == "...":
            logger.warning(f"Failed to generate proactive message for user {user_id}, trigger {trigger_type}")
            return

        # Queue message
        await self.queue_message(user_id, message, trigger_type, delay_minutes=0)

    async def check_memory_callback(self, user_id: str) -> dict | None:
        # Looks for a memory that the partner might naturally "think of"
        # Criteria:
        # - Memory with salience > 0.6
        # - Last recalled more than 5 days ago
        # - Some external signal (day of week, time of day, life event) connects to it
        # Returns a trigger context dict or None
        pairs = db.list_pairs_for_user(user_id)
        if not pairs:
            return None

        sorted_pairs = sorted(
            pairs,
            key=lambda p: (float(p.get("closeness_score") or 0.0) + float(p.get("trust_score") or 0.0)),
            reverse=True
        )

        user = db.get_user(user_id)
        if not user:
            return None

        tz_name = user.get("timezone")
        local_now = _user_local_now(tz_name)
        local_day_name = local_now.strftime("%A").lower()
        local_hour = local_now.hour

        # Classify time period
        if 5 <= local_hour < 12:
            time_period = "morning"
        elif 12 <= local_hour < 17:
            time_period = "afternoon"
        elif 17 <= local_hour < 22:
            time_period = "evening"
        else:
            time_period = "night"

        is_weekend = local_now.weekday() >= 5

        for pair in sorted_pairs:
            pair_id = pair["id"]
            candidates = db.get_candidate_callback_memories(pair_id, days_threshold=5.0)
            for mem in candidates:
                content = mem.get("content", "").lower()
                tags = [t.lower() for t in mem.get("tags", [])] if mem.get("tags") else []

                # Matches day of week
                if local_day_name in content or local_day_name in tags:
                    return {
                        "pair_id": pair_id,
                        "companion_id": pair["companion_id"],
                        "memory_id": mem["id"],
                        "memory_content": mem["content"],
                        "signal": f"Today is {local_now.strftime('%A')}.",
                        "trigger_type": "memory_callback"
                    }

                # Matches time period
                if time_period in content or time_period in tags:
                    return {
                        "pair_id": pair_id,
                        "companion_id": pair["companion_id"],
                        "memory_id": mem["id"],
                        "memory_content": mem["content"],
                        "signal": f"It is {time_period} time.",
                        "trigger_type": "memory_callback"
                    }

                # Matches weekend
                if is_weekend and ("weekend" in content or "weekend" in tags):
                    return {
                        "pair_id": pair_id,
                        "companion_id": pair["companion_id"],
                        "memory_id": mem["id"],
                        "memory_content": mem["content"],
                        "signal": "It is currently the weekend.",
                        "trigger_type": "memory_callback"
                    }
        return None

    async def check_emotional_followup(self, user_id: str) -> dict | None:
        # If last conversation had emotional_tone = tense | vulnerable
        # And it was 1-3 days ago
        # Return a followup trigger
        pairs = db.list_pairs_for_user(user_id)
        if not pairs:
            return None

        sorted_pairs = sorted(
            pairs,
            key=lambda p: (float(p.get("closeness_score") or 0.0) + float(p.get("trust_score") or 0.0)),
            reverse=True
        )

        now = datetime.utcnow()
        for pair in sorted_pairs:
            pair_id = pair["id"]
            conv = db.get_last_conversation_for_pair(pair_id)
            if not conv:
                continue

            last_message_str = conv.get("last_message_at") or conv.get("ended_at") or conv.get("started_at")
            if not last_message_str:
                continue

            try:
                last_time = datetime.fromisoformat(last_message_str.split(".")[0])
            except ValueError:
                continue

            gap_hours = (now - last_time).total_seconds() / 3600.0
            if 24.0 <= gap_hours <= 72.0:
                tone = db.get_last_emotional_tone_for_conversation(conv["id"])
                if tone in {"tense", "vulnerable"}:
                    return {
                        "pair_id": pair_id,
                        "companion_id": pair["companion_id"],
                        "conversation_id": conv["id"],
                        "emotional_tone": tone,
                        "last_interaction_at": last_message_str,
                        "trigger_type": "emotional_followup"
                    }
        return None

    async def check_anniversary(self, user_id: str) -> dict | None:
        # Checks for anniversaries: days since onboarding (7-day, 30-day, 90-day, 1-year)
        # Also checks relationship_events for their dates
        # Returns trigger if any anniversary is today
        user = db.get_user(user_id)
        if not user:
            return None

        tz_name = user.get("timezone")
        local_now = _user_local_now(tz_name)

        # 1. Onboarding Created Date Anniversary Check
        created_str = user.get("created_at")
        if created_str:
            try:
                created_utc = datetime.fromisoformat(created_str.replace("Z", "").split(".")[0])
                created_local = created_utc.astimezone(ZoneInfo(tz_name)) if tz_name else created_utc
                days_since = (local_now.date() - created_local.date()).days
                if days_since in {7, 30, 90, 365}:
                    primary = db.get_primary_pair(user_id)
                    if primary:
                        return {
                            "pair_id": primary["id"],
                            "companion_id": primary["companion_id"],
                            "anniversary_type": "onboarding",
                            "days": days_since,
                            "trigger_type": "anniversary"
                        }
            except Exception as e:
                logger.error(f"Error parsing user created_at for anniversary: {e}")

        # 2. Relationship Events Anniversary Check
        pairs = db.list_pairs_for_user(user_id)
        for pair in pairs:
            pair_id = pair["id"]
            events = db.get_relationship_events(pair_id, limit=100)
            for event in events:
                event_created_str = event.get("created_at")
                if event_created_str:
                    try:
                        event_utc = datetime.fromisoformat(event_created_str.split(".")[0])
                        event_local = event_utc.astimezone(ZoneInfo(tz_name)) if tz_name else event_utc
                        days_since = (local_now.date() - event_local.date()).days
                        if days_since in {7, 30, 90, 365}:
                            return {
                                "pair_id": pair_id,
                                "companion_id": pair["companion_id"],
                                "anniversary_type": "relationship_event",
                                "event_description": event["description"],
                                "days": days_since,
                                "trigger_type": "anniversary"
                            }
                    except Exception as e:
                        logger.error(f"Error parsing relationship event date: {e}")
        return None

    async def check_absence(self, user_id: str) -> dict | None:
        # If user has not opened the app in 3-7 days
        # Return a "missing you" style trigger
        # Probability increases with absence duration
        # Only fires once per absence period
        user = db.get_user(user_id)
        if not user:
            return None

        last_active_str = user.get("last_active_at") or user.get("last_seen") or user.get("created_at")
        if not last_active_str:
            return None

        try:
            last_active = datetime.fromisoformat(last_active_str.split(".")[0])
        except ValueError:
            return None

        now = datetime.utcnow()
        days_absent = (now - last_active).days

        if 3 <= days_absent <= 7:
            prob = (days_absent - 2) / 5.0  # linear probability escalation
            if random.random() < prob:
                # Ensure we only send one absence message per period
                rows = db.conn.execute(
                    """
                    SELECT 1 FROM proactive_events
                    WHERE user_id = ? AND reason = 'absence' AND created_at >= ?
                    LIMIT 1
                    """,
                    (user_id, last_active_str),
                ).fetchone()
                if not rows:
                    primary = db.get_primary_pair(user_id)
                    if primary:
                        return {
                            "pair_id": primary["id"],
                            "companion_id": primary["companion_id"],
                            "days_absent": days_absent,
                            "trigger_type": "absence"
                        }
        return None

    async def generate_proactive_message(
        self,
        user_id: str,
        trigger_type: str,
        trigger_context: dict
    ) -> str:
        # Generates the actual message using LLMCore
        pair_id = trigger_context["pair_id"]
        companion_id = trigger_context["companion_id"]

        conversation_id = db.get_current_conversation(user_id, pair_id)
        if not conversation_id:
            conversation_id = db.create_conversation(user_id, pair_id, companion_id)

        system_prompt, messages = await build_context(
            user_id=user_id,
            pair_id=pair_id,
            current_message=f"System: Generate a proactive text message of type {trigger_type}.",
            conversation_id=conversation_id,
            character_id=companion_id,
            is_proactive_generation=True,
        )

        prompt = (
            f"You are reaching out to the user proactively. Trigger type: {trigger_type}.\n"
            f"Trigger context details: {json.dumps(trigger_context, default=str)}.\n\n"
            "Please generate a short, completely natural text message to send them. "
            "Strict guidelines:\n"
            "- Sound completely natural, casual, and in your texting style.\n"
            "- Reference something real from the context details or memories (e.g. mention the specific memory if it's a memory callback, the anniversary if it's an anniversary, or follow up on the past emotional tone if it's an emotional followup, or sound like you missed them/wondered where they went if it's absence).\n"
            "- DO NOT announce that it's a check-in. Phrases like 'just checking in', 'wanted to check in', or 'hey, just wanted to see...' are strictly FORBIDDEN.\n"
            "- Be short: exactly 1 to 3 sentences.\n"
            "- DO NOT ask multiple questions. Ask at most one low-pressure question, or none at all.\n"
            "- Feel like it was sent because you were genuinely thinking about them, not from an algorithm."
        )

        try:
            reply = await generate_reply(
                messages=[*messages, {"role": "user", "content": prompt}],
                system_prompt=system_prompt,
            )
            return reply
        except Exception as e:
            logger.error(f"Error generating proactive reply: {e}", exc_info=True)
            return "..."

    async def queue_message(self, user_id: str, message: str, trigger_type: str, delay_minutes: int = 0):
        # Inserts into proactive_queue (proactive_events table)
        pair = db.get_primary_pair(user_id)
        if not pair:
            pairs = db.list_pairs_for_user(user_id)
            if pairs:
                pair = pairs[0]
            else:
                logger.warning(f"No relationship pairs found, cannot queue proactive message for user {user_id}")
                return

        pair_id = pair["id"]
        companion_id = pair["companion_id"]

        conversation_id = db.get_current_conversation(user_id, pair_id)
        if not conversation_id:
            conversation_id = db.create_conversation(user_id, pair_id, companion_id)

        companion = db.get_companion(companion_id)
        companion_name = companion["name"] if companion else companion_id.title()

        scheduled_for_dt = datetime.utcnow() + timedelta(minutes=delay_minutes)
        scheduled_for_str = scheduled_for_dt.isoformat(timespec="milliseconds")

        event_id = str(uuid.uuid4())
        payload = {
            "companion_name": companion_name,
            "conversation_id": conversation_id,
            "pair_id": pair_id,
            "reason": trigger_type,
            "message": message
        }

        db.log_proactive_event(
            event_id=event_id,
            user_id=user_id,
            pair_id=pair_id,
            companion_id=companion_id,
            conversation_id=conversation_id,
            reason=trigger_type,
            message_text=message,
            payload_json=json.dumps(payload),
            notification_status="not_attempted",
            status="pending",
            scheduled_for=scheduled_for_str
        )
        logger.info(f"Queued proactive message {event_id} scheduled for {scheduled_for_str}")

        # Apply cooldown (4 hours)
        cooldown_until = (scheduled_for_dt + timedelta(hours=4)).isoformat(timespec="milliseconds")
        db.touch_pair_proactive(pair_id, trigger_type, cooldown_until=cooldown_until)

    async def deliver_pending(self):
        # Runs every 5 minutes
        # Fetches all pending proactive events where scheduled_for <= now
        due_events = db.list_all_due_proactive_events()
        if not due_events:
            return

        for event in due_events:
            event_id = event["id"]
            user_id = event["user_id"]
            pair_id = event["pair_id"]
            companion_id = event["companion_id"]
            message_text = event["message_text"]
            trigger_type = event["reason"]
            conversation_id = event["conversation_id"]

            try:
                # Fetch companion name
                companion = db.get_companion(companion_id)
                companion_name = companion["name"] if companion else companion_id.title()

                try:
                    payload = json.loads(event["payload_json"] or "{}")
                except Exception:
                    payload = {}

                logger.info(f"Delivering proactive message {event_id} to user {user_id}")

                # Send Push Notification via FCM
                await queue_and_send_notification(
                    user_id=user_id,
                    pair_id=pair_id,
                    companion_id=companion_id,
                    sender_name=companion_name,
                    message_preview=message_text,
                    payload_dict={
                        **payload,
                        "event_id": event_id,
                        "role": "assistant"
                    }
                )

                # Save message to conversation history
                db.save_message(
                    conversation_id=conversation_id,
                    user_id=user_id,
                    pair_id=pair_id,
                    companion_id=companion_id,
                    role="assistant",
                    content=message_text,
                )

                # Update relationship metrics
                on_message_saved(pair_id, "assistant", message_text)

                # Mark event as delivered
                db.mark_proactive_events_delivered([event_id])

                # Log system event
                db.log_system_event(
                    kind="proactive_delivered",
                    user_id=user_id,
                    pair_id=pair_id,
                    payload={"event_id": event_id}
                )
            except Exception as e:
                logger.error(f"Failed to deliver proactive event {event_id}: {e}", exc_info=True)
                db.log_system_event(
                    "proactive_delivery_failed",
                    "error",
                    user_id=user_id,
                    pair_id=pair_id,
                    payload={"error": str(e), "event_id": event_id}
                )


# ---------------------------------------------------------------------------
# Compatibility Layers
# ---------------------------------------------------------------------------

async def maybe_generate_for_user(user_id: str, limit: int = 1, force: bool = False) -> list[dict]:
    """Compatibility layer for ops.py and main.py schedulers."""
    engine = ProactiveEngine()
    before_eval = datetime.utcnow()
    await engine.evaluate(user_id, force=force)

    # Query newly queued events in database
    threshold = before_eval - timedelta(seconds=10)
    rows = db.conn.execute(
        """
        SELECT *
        FROM proactive_events
        WHERE user_id = ? AND status = 'pending' AND created_at >= ?
        ORDER BY created_at DESC
        """,
        (user_id, threshold.isoformat(timespec="milliseconds")),
    ).fetchall()

    events = []
    for row in rows:
        d = dict(row)
        try:
            d["payload"] = json.loads(d["payload_json"] or "{}")
        except Exception:
            d["payload"] = {}
        events.append(d)
    return events[:limit]


async def pull_pending_events(user_id: str, pair_id: Optional[str] = None) -> list[dict]:
    """Compatibility layer to trigger delivery checks when loading conversations."""
    engine = ProactiveEngine()
    await engine.deliver_pending()

    rows = db.conn.execute(
        """
        SELECT *
        FROM proactive_events
        WHERE user_id = ? AND status IN ('delivered', 'sent')
        ORDER BY delivered_at DESC
        """,
        (user_id,),
    ).fetchall()

    events = []
    for row in rows:
        d = dict(row)
        try:
            d["payload"] = json.loads(d["payload_json"] or "{}")
        except Exception:
            d["payload"] = {}
        events.append(d)
    return events


def _send_push_hooks(user_id: str, title: str, body: str, data: dict[str, str]) -> str:
    tokens = db.list_device_tokens(user_id, enabled_only=True)
    if not tokens:
        return "no_tokens"

    outcome = "sent"
    for token in tokens:
        try:
            firebase_messaging.send(
                firebase_messaging.Message(
                    token=token["push_token"],
                    notification=firebase_messaging.Notification(title=title, body=body[:120]),
                    data={key: str(value) for key, value in data.items()},
                )
            )
        except Exception as exc:
            outcome = "failed"
            db.log_system_event(
                "push_notification_failed",
                "warning",
                user_id=user_id,
                payload={"error": str(exc), "token_id": token.get("id")},
            )
            logger.warning("Push notification failed for %s: %s", user_id, exc)
    return outcome
