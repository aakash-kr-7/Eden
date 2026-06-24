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
