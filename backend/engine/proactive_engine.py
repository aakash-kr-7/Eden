# ═══════════════════════════════════════════════════════════════════
# FILE: engine/proactive_engine.py
# PURPOSE: Partner reaches out proactively based on memories and relationship context.
# CONTEXT: Evaluates triggers every 15 minutes. Delivers every 5 minutes.
# ═══════════════════════════════════════════════════════════════════

import logging
import json
import random
import hashlib
from datetime import datetime, timezone, timedelta

from config import settings
from core.llm import get_llm_core, _clean_response
from core.fcm import FCMSender
from personality.registry import get_partner_instance

logger = logging.getLogger(__name__)

class ProactiveEngine:
    async def evaluate_all(self, db):
        """
        Evaluates proactive triggers for all active users.
        """
        if hasattr(db, "get_connection"):
            conn = db.get_connection()
            close_conn = True
        else:
            conn = db
            close_conn = False

        try:
            seven_days_ago = (datetime.now(timezone.utc) - timedelta(days=7)).isoformat()
            rows = conn.execute("""
                SELECT id FROM users
                WHERE onboarding_completed = 1
                  AND (last_active_at IS NULL OR last_active_at >= ?)
            """, (seven_days_ago,)).fetchall()

            user_ids = [r["id"] for r in rows]
            logger.info(f"Evaluating proactive outreach triggers for {len(user_ids)} active users")
            for uid in user_ids:
                await self.evaluate(conn, uid)
        except Exception as e:
            logger.error(f"Error in ProactiveEngine.evaluate_all: {e}", exc_info=True)
        finally:
            if close_conn:
                conn.close()

    async def evaluate(self, db, user_id: str, force: bool = False):
        """
        Checks constraints and trigger priority to queue outreach.
        """
        if hasattr(db, "get_connection"):
            conn = db.get_connection()
            close_conn = True
        else:
            conn = db
            close_conn = False

        try:
            utc_now = datetime.now(timezone.utc)

            # 1. Check constraints if not forced
            if not force:
                # Fetch life state (busy and last proactive outreach)
                ls = conn.execute("""
                    SELECT partner_busy_until, last_proactive_at FROM life_state
                    WHERE user_id = ?
                """, (user_id,)).fetchone()
                
                if ls:
                    busy_until_str = ls["partner_busy_until"]
                    last_proactive_str = ls["last_proactive_at"]

                    # Constraint: Partner busy
                    if busy_until_str:
                        try:
                            if datetime.fromisoformat(busy_until_str) > utc_now:
                                logger.info(f"Skipping proactive evaluation for {user_id}: partner is busy")
                                return
                        except Exception:
                            pass

                    # Constraint: Last proactive outreach < 4 hours ago
                    if last_proactive_str:
                        try:
                            if utc_now - datetime.fromisoformat(last_proactive_str) < timedelta(hours=4):
                                logger.info(f"Skipping proactive evaluation for {user_id}: last outreach was less than 4 hours ago")
                                return
                        except Exception:
                            pass

                # Constraint: User active in last 30 minutes
                user_row = conn.execute("SELECT last_active_at FROM users WHERE id = ?", (user_id,)).fetchone()
                if user_row and user_row["last_active_at"]:
                    try:
                        if utc_now - datetime.fromisoformat(user_row["last_active_at"]) < timedelta(minutes=30):
                            logger.info(f"Skipping proactive evaluation for {user_id}: user was active in last 30 minutes")
                            return
                    except Exception:
                        pass

            # 2. Check if a proactive message is already queued for this user and unsent
            pending = conn.execute("""
                SELECT COUNT(*) FROM proactive_queue
                WHERE user_id = ? AND sent = 0 AND cancelled = 0
            """, (user_id,)).fetchone()[0]
            if pending > 0:
                logger.info(f"User {user_id} already has a pending message in proactive queue. Skipping.")
                return

            # 3. Evaluate Triggers (Highest Priority First)
            trigger_type = None
            context = None

            # --- Trigger 1: Emotional followup (vulnerable/tense conversation 1-3 days ago) ---
            conv = conn.execute("""
                SELECT id, emotional_tone, last_message_at FROM conversations
                WHERE user_id = ?
                ORDER BY last_message_at DESC LIMIT 1
            """, (user_id,)).fetchone()

            if conv and conv["emotional_tone"] and conv["last_message_at"]:
                try:
                    last_msg_time = datetime.fromisoformat(conv["last_message_at"])
                    tone = conv["emotional_tone"].lower()
                    if tone in ["vulnerable", "tense", "sad", "anxious"] and timedelta(days=1) <= (utc_now - last_msg_time) <= timedelta(days=3):
                        trigger_type = "emotional_followup"
                        context = conv["emotional_tone"]
                except Exception:
                    pass

            # --- Trigger 2: Memory callback (salience > 0.7, context matches today) ---
            if not trigger_type:
                memories = conn.execute("""
                    SELECT memory_text, tags FROM episodic_memories
                    WHERE user_id = ? AND salience_score > 0.7
                """, (user_id,)).fetchall()

                today_weekday = utc_now.strftime("%A").lower()
                is_weekend = utc_now.weekday() >= 5

                for m in memories:
                    text = m["memory_text"].lower()
                    tags = []
                    try:
                        tags = json.loads(m["tags"]) if m["tags"] else []
                    except Exception:
                        pass
                    tags_lower = [t.lower() for t in tags]

                    # Match day of the week or weekend/weekday context
                    if today_weekday in text or today_weekday in tags_lower:
                        trigger_type = "memory_callback"
                        context = m["memory_text"]
                        break
                    elif is_weekend and ("weekend" in text or "weekend" in tags_lower):
                        trigger_type = "memory_callback"
                        context = m["memory_text"]
                        break

            # --- Trigger 3: Absence check (no app open in 3+ days) ---
            if not trigger_type:
                user_row = conn.execute("SELECT last_active_at, created_at FROM users WHERE id = ?", (user_id,)).fetchone()
                if user_row:
                    last_active_str = user_row["last_active_at"] or user_row["created_at"]
                    if last_active_str:
                        try:
                            last_active = datetime.fromisoformat(last_active_str)
                            if utc_now - last_active >= timedelta(days=3):
                                trigger_type = "absence_check"
                                context = last_active_str
                        except Exception:
                            pass

            # --- Trigger 4: Anniversary (7-day, 30-day, 90-day, 1-year) ---
            if not trigger_type:
                partner_row = conn.execute("SELECT generated_at FROM partners WHERE user_id = ?", (user_id,)).fetchone()
                if partner_row and partner_row["generated_at"]:
                    try:
                        gen_date = datetime.fromisoformat(partner_row["generated_at"].split(".")[0])
                        days_diff = (utc_now.date() - gen_date.date()).days
                        if days_diff in [7, 30, 90, 365]:
                            trigger_type = "anniversary"
                            context = f"{days_diff} days"
                    except Exception:
                        pass

            # If trigger matched, generate, and queue message
            if trigger_type:
                logger.info(f"Trigger matched for user {user_id}: {trigger_type} with context '{context}'")
                message = await self.generate_message(conn, user_id, trigger_type, context)
                if message:
                    await self.queue_message(conn, user_id, message, trigger_type)
            else:
                logger.info(f"No proactive triggers matched for user {user_id}")

        except Exception as e:
            logger.error(f"Error evaluating triggers for user {user_id}: {e}", exc_info=True)
        finally:
            if close_conn:
                conn.close()

    async def generate_message(self, db, user_id: str, trigger_type: str, context: str) -> str:
        """
        Generates a natural-sounding outreach message using llama-3.3-70b-versatile.
        """
        character = get_partner_instance(user_id)
        if not character:
            logger.error(f"No partner instance found for user {user_id} during message generation")
            return ""

        # Setup prompt guidelines per trigger type
        trigger_guidelines = ""
        if trigger_type == "emotional_followup":
            trigger_guidelines = (
                f"The last conversation you had was emotional, vulnerable, or tense (tone: '{context}'). "
                "Reach out casually to follow up, see how they're doing, or check in on how they are holding up. "
                "Be warm and supportive, but keep it casual like a text message."
            )
        elif trigger_type == "memory_callback":
            trigger_guidelines = (
                f"Reference something real you remember about them: '{context}'. "
                "Make a casual observation or link it to today's context. "
                "Make it sound completely natural and unprompted."
            )
        elif trigger_type == "absence_check":
            trigger_guidelines = (
                "The user hasn't messaged or opened the app in a few days. "
                "Reach out with a casual, low-pressure message. "
                "Mention something random you were doing, or a light thought, and suggest you'd love to hear from them."
            )
        elif trigger_type == "anniversary":
            trigger_guidelines = (
                f"Today marks an anniversary ({context} since you met). "
                "Casually acknowledge this milestone. "
                "Keep it warm, but not overly dramatic. Just a light mention."
            )

        system_prompt = f"""You are {character.name}. Here is your persona:
{character.persona.get("summary") or ""}
Your voice / texting style:
- Sentence rhythm: {character.voice_style.get("sentence_rhythm") or "casual"}
- Punctuation & capitalization: {character.voice_style.get("punctuation_tendencies") or "casual"}
- Vocabulary register: {character.voice_style.get("vocabulary_profile") or "casual"}

TASK:
Write a proactive text message to the user.

SCENARIO SPECIFICS:
{trigger_guidelines}

CRITICAL RULES:
- Send something natural. DO NOT say 'just checking in'.
- DO NOT announce that you're checking in.
- Reference something real you remember about them.
- 1-2 sentences maximum.
- Sound like a real person texting.
- Never acknowledge being an AI.
- Stay in character.
- Do not use assistant language or structural templates.
"""

        try:
            llm = get_llm_core()
            raw_reply = await llm.complete(
                system_prompt=system_prompt,
                messages=[{"role": "user", "content": "Write the text message."}],
                model=settings.GROQ_CHAT_MODEL,
                temperature=0.7
            )
            message = _clean_response(raw_reply)
            return message
        except Exception as e:
            logger.error(f"Failed to generate proactive message: {e}", exc_info=True)
            return ""

    async def queue_message(self, db, user_id: str, message: str, trigger_type: str):
        """
        Inserts message into proactive_queue.
        """
        # scheduled_for: now (delivers in next deliver cycle)
        now_str = datetime.now(timezone.utc).isoformat()
        queue_id = f"pq_{user_id}_{int(datetime.now(timezone.utc).timestamp())}"
        
        db.execute("""
            INSERT INTO proactive_queue (id, user_id, trigger_type, message_draft, scheduled_for, sent, cancelled)
            VALUES (?, ?, ?, ?, ?, 0, 0)
        """, (queue_id, user_id, trigger_type, message, now_str))
        db.commit()
        logger.info(f"Successfully queued proactive message {queue_id} for user {user_id}")

    async def deliver_pending(self, db):
        """
        Fetches and sends queued proactive messages via FCMSender.
        """
        if hasattr(db, "get_connection"):
            conn = db.get_connection()
            close_conn = True
        else:
            conn = db
            close_conn = False

        try:
            now_iso = datetime.now(timezone.utc).isoformat()
            
            # Fetch all unsent scheduled queue items
            rows = conn.execute("""
                SELECT id, user_id, trigger_type, message_draft, scheduled_for
                FROM proactive_queue
                WHERE sent = 0 AND cancelled = 0 AND scheduled_for <= ?
            """, (now_iso,)).fetchall()

            if not rows:
                return

            logger.info(f"Delivering {len(rows)} pending proactive messages")
            fcm_sender = FCMSender()

            for r in rows:
                queue_id = r["id"]
                user_id = r["user_id"]
                trigger_type = r["trigger_type"]
                message = r["message_draft"]

                # 1. Fetch user FCM token & partner details
                user_row = conn.execute("SELECT fcm_token FROM users WHERE id = ?", (user_id,)).fetchone()
                fcm_token = user_row["fcm_token"] if user_row else None

                partner_row = conn.execute("SELECT id, name FROM partners WHERE user_id = ?", (user_id,)).fetchone()
                partner_name = partner_row["name"] if partner_row else "Partner"
                partner_id = partner_row["id"] if partner_row else "default_partner"
                pair_id = f"{user_id}::{partner_id}"

                # 2. Try sending notification via FCM
                fcm_success = False
                if fcm_token:
                    fcm_success = await fcm_sender.send(
                        fcm_token=fcm_token,
                        title=partner_name,
                        body=message,
                        data={"type": "proactive", "trigger": trigger_type}
                    )

                # 3. Deliver to app inbox thread regardless of FCM token status so they see it in the app
                # Mark as sent in proactive_queue
                conn.execute("""
                    UPDATE proactive_queue
                    SET sent = 1,
                        sent_at = ?
                    WHERE id = ?
                """, (now_iso, queue_id))

                # Log the proactive event
                conn.execute("""
                    INSERT INTO proactive_events (id, user_id, pair_id, message_text, reason, delivered_at, scheduled_for, created_at, status)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'delivered')
                """, (queue_id, user_id, pair_id, message, trigger_type, now_iso, r["scheduled_for"], now_iso))

                # Get or create active conversation
                conv_row = conn.execute("""
                    SELECT id FROM conversations
                    WHERE pair_id = ?
                    ORDER BY started_at DESC LIMIT 1
                """, (pair_id,)).fetchone()
                
                if conv_row:
                    conversation_id = conv_row["id"]
                else:
                    conversation_id = f"conv_{user_id}_{int(datetime.now(timezone.utc).timestamp())}"
                    conn.execute("""
                        INSERT INTO conversations (id, user_id, pair_id, partner_id, started_at, message_count, processed)
                        VALUES (?, ?, ?, ?, ?, 0, 0)
                    """, (conversation_id, user_id, pair_id, partner_id, now_iso))

                # Save proactive message to messages table
                conn.execute("""
                    INSERT INTO messages (conversation_id, user_id, pair_id, partner_id, role, content, sent_at)
                    VALUES (?, ?, ?, ?, 'partner', ?, ?)
                """, (conversation_id, user_id, pair_id, partner_id, message, now_iso))

                # Update conversation message count & last_message_at
                conn.execute("""
                    UPDATE conversations
                    SET message_count = message_count + 1,
                        last_message_at = ?
                    WHERE id = ?
                """, (now_iso, conversation_id))

                # Update last proactive outreach timestamp in life_state
                conn.execute("""
                    UPDATE life_state
                    SET last_proactive_at = ?,
                        updated_at = ?
                    WHERE user_id = ?
                """, (now_iso, now_iso, user_id))

                conn.commit()
                logger.info(f"Delivered proactive message {queue_id} (FCM success: {fcm_success}) to user {user_id}")

        except Exception as e:
            logger.error(f"Error delivering pending proactive messages: {e}", exc_info=True)
        finally:
            if close_conn:
                conn.close()
