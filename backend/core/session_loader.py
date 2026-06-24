# ═══════════════════════════════════════════════════════════════════
# FILE: session_loader.py
# PURPOSE: Assembles full session bootstrap payload for Flutter app open.
# CONTEXT: Called by GET /api/chat/session on every app open.
# ═══════════════════════════════════════════════════════════════════

import asyncio
import logging
import sqlite3
import time
from datetime import datetime, timezone
from personality.registry import get_partner_instance, resolve_or_assign_primary_pair

logger = logging.getLogger(__name__)

class SessionLoader:
    async def load(self, db: sqlite3.Connection, user_id: str) -> dict:
        """
        Runs all queries in parallel (asyncio.gather).
        Returns complete session payload.
        Updates users.last_active_at.
        """
        # Gather user, pair, partner, and life_state in parallel
        def get_user_sync():
            row = db.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
            return dict(row) if row else None

        def get_pair_sync():
            # Ensure primary pair is resolved
            pair = db.execute("SELECT * FROM relationship_pairs WHERE user_id = ? LIMIT 1", (user_id,)).fetchone()
            if not pair:
                # resolve_or_assign_primary_pair is synchronous in db terms, but performs commits. Let's call it.
                resolve_or_assign_primary_pair(user_id)
                pair = db.execute("SELECT * FROM relationship_pairs WHERE user_id = ? LIMIT 1", (user_id,)).fetchone()
            return dict(pair) if pair else None

        def get_partner_sync():
            row = db.execute("SELECT * FROM partners WHERE user_id = ? LIMIT 1", (user_id,)).fetchone()
            return dict(row) if row else None

        def get_life_state_sync():
            row = db.execute("SELECT * FROM life_state WHERE user_id = ? LIMIT 1", (user_id,)).fetchone()
            return dict(row) if row else None

        user, pair, partner, life_state = await asyncio.gather(
            asyncio.to_thread(get_user_sync),
            asyncio.to_thread(get_pair_sync),
            asyncio.to_thread(get_partner_sync),
            asyncio.to_thread(get_life_state_sync)
        )

        if not user:
            raise ValueError(f"User {user_id} not found")

        last_active = user.get("last_active_at")

        # Update last active at
        now_str = datetime.now(timezone.utc).isoformat()
        db.execute("UPDATE users SET last_active_at = ? WHERE id = ?", (now_str, user_id))
        db.commit()

        # Get or create active conversation
        conversation_id = self._get_or_create_conversation(db, user_id)

        # Get unread proactive messages since last_active_at
        unread_proactive = self._get_unread_proactive(db, user_id, last_active)

        # Fetch recent messages (last 20 messages)
        msg_rows = db.execute(
            "SELECT * FROM messages WHERE conversation_id = ? ORDER BY sent_at DESC LIMIT 20",
            (conversation_id,)
        ).fetchall()
        recent_messages = []
        for r in reversed(msg_rows):
            d = dict(r)
            recent_messages.append({
                "id": d["id"],
                "role": d["role"],
                "content": d["content"],
                "sent_at": d["sent_at"],
                "emotional_signal": d.get("emotional_signal")
            })

        # Get memory count
        memory_count = db.execute(
            "SELECT COUNT(*) FROM episodic_memories WHERE user_id = ?",
            (user_id,)
        ).fetchone()[0]

        # Days together calculation
        days_together = 1
        created_str = (partner or {}).get("generated_at") or (pair or {}).get("created_at") or user.get("created_at")
        if created_str:
            try:
                dt = datetime.fromisoformat(created_str.replace("Z", "+00:00"))
                days_together = max(1, (datetime.now(timezone.utc) - dt).days)
            except Exception as e:
                logger.error(f"Failed to calculate days together: {e}")

        # Mood & Energy
        mood = life_state.get("partner_mood", "content") if life_state else "content"
        energy = life_state.get("partner_energy", "normal") if life_state else "normal"

        partner_payload = {
            "name": partner.get("name") if partner else "Partner",
            "relationship_stage": pair.get("current_stage", "new") if pair else "new",
            "current_mood": mood,
            "current_energy": energy,
            "days_together": days_together
        }

        return {
            "partner": partner_payload,
            "conversation_id": conversation_id,
            "recent_messages": recent_messages,
            "unread_proactive": unread_proactive,
            "memory_count": memory_count,
            "days_together": days_together,
            "last_seen": last_active
        }

    def _get_or_create_conversation(self, db, user_id: str) -> str:
        """
        Gets the active conversation (most recent) or creates a new one.
        Eden has one ongoing conversation — not a list.
        Returns conversation_id.
        """
        row = db.execute(
            "SELECT id FROM conversations WHERE user_id = ? ORDER BY started_at DESC LIMIT 1",
            (user_id,)
        ).fetchone()
        if row:
            return row["id"]

        # If conversation doesn't exist, we must create it.
        # Find partner_id
        partner_row = db.execute("SELECT id FROM partners WHERE user_id = ? LIMIT 1", (user_id,)).fetchone()
        partner_id = partner_row["id"] if partner_row else "default_partner"
        
        # Get pair_id
        pair_row = db.execute("SELECT id FROM relationship_pairs WHERE user_id = ? LIMIT 1", (user_id,)).fetchone()
        pair_id = pair_row["id"] if pair_row else f"{user_id}::{partner_id}"

        conv_id = f"conv_{user_id}_{int(time.time())}"
        now_str = datetime.now(timezone.utc).isoformat()
        db.execute(
            """
            INSERT INTO conversations (id, user_id, pair_id, partner_id, started_at, message_count, processed)
            VALUES (?, ?, ?, ?, ?, 0, 0)
            """,
            (conv_id, user_id, pair_id, partner_id, now_str)
        )
        db.commit()
        return conv_id

    def _get_unread_proactive(self, db, user_id: str, since: str | None) -> list[dict]:
        """
        Returns proactive messages sent since last_active_at.
        Marks them as acknowledged.
        """
        if not since:
            return []

        rows = db.execute(
            """
            SELECT id, message_text, reason, delivered_at, scheduled_for, created_at
            FROM proactive_events
            WHERE user_id = ? AND status IN ('delivered', 'sent') AND created_at > ?
            ORDER BY created_at ASC
            """,
            (user_id, since)
        ).fetchall()

        events = []
        for r in rows:
            events.append({
                "id": r["id"],
                "message": r["message_text"],
                "trigger_type": r["reason"],
                "sent_at": r["delivered_at"] or r["scheduled_for"] or r["created_at"]
            })

        if events:
            ids = [e["id"] for e in events]
            placeholders = ",".join("?" for _ in ids)
            db.execute(
                f"UPDATE proactive_events SET status = 'acknowledged' WHERE id IN ({placeholders})",
                ids
            )
            db.commit()

        return events

    async def load_session(self, user_id: str) -> dict:
        """
        Legacy/compatibility method pointing to load.
        """
        from memory.store import db as store_db
        # Open connection and run load
        with store_db.get_connection() as conn:
            return await self.load(conn, user_id)

    async def update_last_active(self, user_id: str):
        """
        Updates users.last_active_at to now.
        """
        from memory.store import db as store_db
        await asyncio.to_thread(store_db.update_last_active, user_id)
