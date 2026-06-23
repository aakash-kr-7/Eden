import asyncio
import logging
from datetime import datetime, timezone
from memory.store import db
from personality.registry import get_partner_instance, resolve_or_assign_primary_pair
from core.proactive_engine import pull_pending_events
from memory.retriever import get_memory_count

logger = logging.getLogger(__name__)


class SessionLoader:
    async def load_session(self, user_id: str) -> dict:
        """
        Loads everything the frontend needs on app open in parallel.
        """
        # Helper to run synchronous DB lookups in parallel
        def _get_user_and_pair():
            user = db.get_user(user_id)
            pair = db.get_primary_pair(user_id)
            if not pair:
                pair = resolve_or_assign_primary_pair(user_id)
            return user, pair

        # Gather user, pair, and unread events in parallel
        user_pair_task = asyncio.to_thread(_get_user_and_pair)
        unread_task = pull_pending_events(user_id)

        (user, pair), unread_messages = await asyncio.gather(
            user_pair_task, unread_task
        )

        pair_id = pair["id"]

        # Fetch partner details
        def _get_partner_details():
            summaries = db.get_recent_conversation_summaries(pair_id, limit=1)
            last_summary = summaries[0]["session_summary"] if summaries else None

            mem_count = get_memory_count(pair_id=pair_id, user_id=user_id)
            emotional_summary = db.get_emotional_summary(user_id, pair_id=pair_id, limit=6)

            return last_summary, mem_count, emotional_summary

        last_summary, mem_count, emotional_summary = await asyncio.to_thread(_get_partner_details)

        # Get partner instance from registry
        partner_inst = get_partner_instance(user_id)
        if not partner_inst:
            raise ValueError(f"No generated partner found for user {user_id}")

        # Calculate days together since partner creation
        created_at_str = partner_inst.raw.get("created_at") or pair.get("created_at") or user.get("created_at")
        days_together = 0
        if created_at_str:
            try:
                created_dt = datetime.fromisoformat(created_at_str.replace("Z", "+00:00"))
                now_aware = datetime.now(timezone.utc)
                days_together = max(0, (now_aware - created_dt).days)
            except Exception as e:
                logger.error("Failed to parse partner created_at '%s': %s", created_at_str, e)

        # Determine mood and energy
        mood = "neutral"
        if emotional_summary and emotional_summary.get("dominant_emotions"):
            mood = ", ".join(emotional_summary["dominant_emotions"])
        elif partner_inst.matching_profile:
            mood = partner_inst.matching_profile.get("social_energy", "neutral")

        energy = "balanced"
        if partner_inst.matching_profile:
            energy = partner_inst.matching_profile.get("social_energy", "balanced")

        last_seen = user.get("last_active_at") or user.get("last_seen")

        return {
            "partner": {
                "name": partner_inst.name,
                "relationship_stage": pair.get("current_stage") or "new",
                "current_mood": mood,
                "current_energy": energy,
            },
            "last_conversation_summary": last_summary,
            "unread_proactive_messages": unread_messages,
            "memory_count": mem_count,
            "days_together": days_together,
            "last_seen": last_seen,
        }

    async def update_last_active(self, user_id: str):
        """
        Updates users.last_active_at to now.
        """
        await asyncio.to_thread(db.update_last_active, user_id)
