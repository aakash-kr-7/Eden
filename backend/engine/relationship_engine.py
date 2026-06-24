# ═══════════════════════════════════════════════════════════════════
# FILE: engine/relationship_engine.py
# PURPOSE: Tracks relationship milestones and stage progression over time.
# CONTEXT: Called by consolidator after dream loop processing.
# ═══════════════════════════════════════════════════════════════════

import logging
import json
from datetime import datetime, timezone

logger = logging.getLogger(__name__)

class RelationshipEngine:
    async def evaluate_progression(self, db, user_id: str):
        """
        Evaluate relationship progression stage based on conversations and memories.
        """
        # Determine connection type
        if hasattr(db, "get_connection"):
            conn = db.get_connection()
            close_conn = True
        else:
            conn = db
            close_conn = False

        try:
            # 1. Fetch current stage & stats
            partner_row = conn.execute("""
                SELECT id, name, relationship_stage, intimacy_tier, blueprint_json
                FROM partners
                WHERE user_id = ?
            """, (user_id,)).fetchone()

            if not partner_row:
                logger.error(f"No partner found for user {user_id} in RelationshipEngine")
                return

            partner_id = partner_row["id"]
            current_stage = partner_row["relationship_stage"] or "new"
            current_intimacy = partner_row["intimacy_tier"] or 1
            blueprint_str = partner_row["blueprint_json"] or "{}"

            try:
                blueprint = json.loads(blueprint_str)
            except Exception:
                blueprint = {}

            # Count processed conversations
            conv_count = conn.execute(
                "SELECT COUNT(*) FROM conversations WHERE user_id = ? AND processed = 1", 
                (user_id,)
            ).fetchone()[0]
            
            # Count episodic memories
            memory_count = conn.execute(
                "SELECT COUNT(*) FROM episodic_memories WHERE user_id = ?", 
                (user_id,)
            ).fetchone()[0]

            # Progression rules:
            # - new → familiar: 10 conversations + 20 memories
            # - familiar → close: 30 conversations + 50 memories
            # - close → intimate: 70 conversations + 100 memories
            next_stage = "new"
            intimacy_tier = 1

            if conv_count >= 70 and memory_count >= 100:
                next_stage = "intimate"
                intimacy_tier = 4
            elif conv_count >= 30 and memory_count >= 50:
                next_stage = "close"
                intimacy_tier = 3
            elif conv_count >= 10 and memory_count >= 20:
                next_stage = "familiar"
                intimacy_tier = 2

            # If stage advanced
            if next_stage != current_stage:
                logger.info(f"User {user_id} advanced from stage {current_stage} to {next_stage}!")

                # 1. Create relationship_event of type 'milestone'
                now = datetime.now(timezone.utc).isoformat()
                event_id = f"re_{user_id}_{int(datetime.now(timezone.utc).timestamp())}"
                description = f"Advanced relationship stage from {current_stage} to {next_stage} ({conv_count} conversations, {memory_count} memories)"

                conn.execute("""
                    INSERT INTO relationship_events (id, user_id, event_type, description, occurred_at, emotional_weight)
                    VALUES (?, ?, 'milestone', ?, ?, 0.8)
                """, (event_id, user_id, description, now))

                # 2. Update blueprint_json with stage_advanced flag
                blueprint["stage_advanced"] = True

                # 3. Update partners table
                conn.execute("""
                    UPDATE partners
                    SET relationship_stage = ?,
                        intimacy_tier = ?,
                        blueprint_json = ?,
                        last_evolved_at = ?
                    WHERE user_id = ?
                """, (next_stage, intimacy_tier, json.dumps(blueprint), now, user_id))

                # 4. Update relationship_pairs table
                pair_id = f"{user_id}::{partner_id}"
                conn.execute("""
                    UPDATE relationship_pairs
                    SET current_stage = ?
                    WHERE id = ?
                """, (next_stage, pair_id))

                conn.commit()
                logger.info(f"Relationship stage updated to {next_stage} (tier {intimacy_tier}) for user {user_id}")
        except Exception as e:
            logger.error(f"Error in RelationshipEngine.evaluate_progression: {e}", exc_info=True)
        finally:
            if close_conn:
                conn.close()

    async def get_relationship_summary(self, db, user_id: str) -> dict:
        """
        Builds a comprehensive relationship summary for the user and their partner.
        """
        if hasattr(db, "get_connection"):
            conn = db.get_connection()
            close_conn = True
        else:
            conn = db
            close_conn = False

        try:
            # 1. Partner and Relationship Pair
            partner_row = conn.execute("""
                SELECT id, name, relationship_stage, intimacy_tier, generated_at
                FROM partners
                WHERE user_id = ?
            """, (user_id,)).fetchone()

            if not partner_row:
                return {}

            partner_id = partner_row["id"]
            partner_name = partner_row["name"]
            stage = partner_row["relationship_stage"] or "new"
            intimacy_tier = partner_row["intimacy_tier"] or 1

            pair_row = conn.execute("""
                SELECT closeness_score, trust_score, openness_score, comfort_score, rhythm_score, topic_familiarity_score, proactive_cadence, created_at
                FROM relationship_pairs
                WHERE user_id = ? AND partner_id = ?
            """, (user_id, partner_id)).fetchone()

            scores = {}
            proactive_cadence = "balanced"
            if pair_row:
                scores = {
                    "closeness": pair_row["closeness_score"] or 0.18,
                    "trust": pair_row["trust_score"] or 0.18,
                    "openness": pair_row["openness_score"] or 0.12,
                    "comfort": pair_row["comfort_score"] or 0.14,
                    "rhythm": pair_row["rhythm_score"] or 0.10,
                    "topic_familiarity": pair_row["topic_familiarity_score"] or 0.05,
                }
                proactive_cadence = pair_row["proactive_cadence"] or "balanced"

            # 2. Relationship Events
            event_rows = conn.execute("""
                SELECT event_type, description, occurred_at, emotional_weight
                FROM relationship_events
                WHERE user_id = ?
                ORDER BY occurred_at DESC
                LIMIT 10
            """, (user_id,)).fetchall()
            events = [dict(r) for r in event_rows]

            # 3. Narrative Summary
            narrative_row = conn.execute("""
                SELECT summary, updated_at
                FROM narrative_summaries
                WHERE user_id = ?
                ORDER BY updated_at DESC LIMIT 1
            """, (user_id,)).fetchone()
            narrative = narrative_row["summary"] if narrative_row else "Your story is just beginning."

            # 4. Basic counts
            conv_count = conn.execute(
                "SELECT COUNT(*) FROM conversations WHERE user_id = ?", (user_id,)
            ).fetchone()[0]
            memory_count = conn.execute(
                "SELECT COUNT(*) FROM episodic_memories WHERE user_id = ?", (user_id,)
            ).fetchone()[0]

            introduced_str = partner_row["generated_at"]
            days_together = 1
            if introduced_str:
                try:
                    intro_dt = datetime.fromisoformat(str(introduced_str).split(".")[0])
                    days_together = max(1, (datetime.utcnow() - intro_dt).days)
                except Exception:
                    pass

            return {
                "partner_name": partner_name,
                "stage": stage,
                "intimacy_tier": intimacy_tier,
                "days_together": days_together,
                "conversation_count": conv_count,
                "memory_count": memory_count,
                "proactive_cadence": proactive_cadence,
                "scores": scores,
                "narrative": narrative,
                "events": events
            }
        finally:
            if close_conn:
                conn.close()
