# ═══════════════════════════════════════════════════════════════════
# FILE: engine/life_simulator.py
# PURPOSE: Simulates partner's mood, energy, and daily arc between conversations.
# CONTEXT: Runs every 5 minutes via APScheduler for all active users.
# ═══════════════════════════════════════════════════════════════════

import logging
import random
import hashlib
from datetime import datetime, timezone, timedelta

logger = logging.getLogger(__name__)

class LifeSimulator:
    async def initialize(self, db, user_id: str):
        """
        Initializes life state with sensible defaults.
        Called when onboarding completes.
        """
        if hasattr(db, "get_connection"):
            conn = db.get_connection()
            close_conn = True
        else:
            conn = db
            close_conn = False

        try:
            now = datetime.now(timezone.utc).isoformat()
            
            # Day arc based on UTC hour with ±2 hour randomness per user
            utc_hour = datetime.now(timezone.utc).hour
            offset = int(hashlib.sha256(user_id.encode("utf-8")).hexdigest(), 16) % 5 - 2
            local_hour = (utc_hour + offset) % 24

            if 5 <= local_hour < 10:
                day_arc = "morning"
            elif 10 <= local_hour < 14:
                day_arc = "afternoon (early)"
            elif 14 <= local_hour < 18:
                day_arc = "afternoon"
            elif 18 <= local_hour < 22:
                day_arc = "evening"
            else:
                day_arc = "night"

            # Check if user already has life state
            existing = conn.execute("SELECT user_id FROM life_state WHERE user_id = ?", (user_id,)).fetchone()
            if existing:
                conn.execute("""
                    UPDATE life_state
                    SET partner_mood = 'content',
                        partner_energy = 'normal',
                        partner_busy_until = NULL,
                        day_arc = ?,
                        updated_at = ?
                    WHERE user_id = ?
                """, (day_arc, now, user_id))
            else:
                conn.execute("""
                    INSERT INTO life_state (user_id, partner_mood, partner_energy, partner_busy_until, day_arc, updated_at)
                    VALUES (?, 'content', 'normal', NULL, ?, ?)
                """, (user_id, day_arc, now))
            
            conn.commit()
            logger.info(f"Initialized life state for user {user_id} with day_arc={day_arc}")
        except Exception as e:
            logger.error(f"Failed to initialize life state for user {user_id}: {e}", exc_info=True)
        finally:
            if close_conn:
                conn.close()

    async def tick(self, db, user_id: str):
        """
        Executes a single simulation tick (mood transitions, day arc progression, busy window status).
        """
        if hasattr(db, "get_connection"):
            conn = db.get_connection()
            close_conn = True
        else:
            conn = db
            close_conn = False

        try:
            # 1. Fetch current life_state
            row = conn.execute("SELECT * FROM life_state WHERE user_id = ?", (user_id,)).fetchone()
            if not row:
                logger.warning(f"No life state found for user {user_id} during tick. Initializing...")
                # Run initialization sync
                now = datetime.now(timezone.utc).isoformat()
                conn.execute("""
                    INSERT INTO life_state (user_id, partner_mood, partner_energy, partner_busy_until, day_arc, updated_at)
                    VALUES (?, 'content', 'normal', NULL, 'morning', ?)
                """, (user_id, now))
                conn.commit()
                row = conn.execute("SELECT * FROM life_state WHERE user_id = ?", (user_id,)).fetchone()

            state = dict(row)
            current_mood = state.get("partner_mood") or "content"
            current_energy = state.get("partner_energy") or "normal"
            busy_until_str = state.get("partner_busy_until")

            # Determine local hour with per-user randomized offset
            utc_now = datetime.now(timezone.utc)
            utc_hour = utc_now.hour
            offset = int(hashlib.sha256(user_id.encode("utf-8")).hexdigest(), 16) % 5 - 2
            local_hour = (utc_hour + offset) % 24

            if 5 <= local_hour < 10:
                day_arc = "morning"
            elif 10 <= local_hour < 14:
                day_arc = "afternoon (early)"
            elif 14 <= local_hour < 18:
                day_arc = "afternoon"
            elif 18 <= local_hour < 22:
                day_arc = "evening"
            else:
                day_arc = "night"

            # 2. Check Busy Window Status
            is_busy = False
            if busy_until_str:
                try:
                    busy_until = datetime.fromisoformat(busy_until_str)
                    if busy_until > utc_now:
                        is_busy = True
                except Exception:
                    pass

            new_busy_until = busy_until_str
            if not is_busy:
                # Busy window: 2% base chance per tick.
                # More likely (5% chance) between 9am-5pm.
                # Otherwise, 0.5% chance.
                busy_chance = 0.02
                if 9 <= local_hour <= 17:
                    busy_chance = 0.05
                else:
                    busy_chance = 0.005

                if random.random() < busy_chance:
                    # 30-120 min duration
                    duration_min = random.randint(30, 120)
                    busy_until_dt = utc_now + timedelta(minutes=duration_min)
                    new_busy_until = busy_until_dt.isoformat()
                    logger.info(f"User {user_id}'s partner became busy for {duration_min} minutes (until {new_busy_until})")

            # 3. Transition mood based on matrix from EDEN_ARCHITECTURE.md
            # - content -> playful: 15%, reflective: 10%, warm: 20%
            # - quiet -> reflective: 30%, content: 15%
            # - tired -> quiet: 40%, reflective: 20%
            transitions = {
                "content": {"playful": 0.15, "reflective": 0.10, "warm": 0.20},
                "quiet": {"reflective": 0.30, "content": 0.15},
                "tired": {"quiet": 0.40, "reflective": 0.20}
            }

            # Sensible defaults for other moods
            default_transitions = {
                "playful": {"content": 0.20, "reflective": 0.10},
                "reflective": {"content": 0.15, "quiet": 0.15, "tired": 0.10},
                "warm": {"content": 0.20, "playful": 0.10},
                "distracted": {"content": 0.30, "quiet": 0.10}
            }

            mood_weights = transitions.get(current_mood) or default_transitions.get(current_mood) or {}
            
            new_mood = current_mood
            r = random.random()
            cumulative = 0.0
            transitioned = False

            for target, prob in mood_weights.items():
                cumulative += prob
                if r < cumulative:
                    new_mood = target
                    transitioned = True
                    break

            # If no transition from matrix, check if we do a time of day transition (10% chance)
            if not transitioned and random.random() < 0.10:
                # Time of day influences:
                # - morning: favors content, warm, playful
                # - evening: favors tired, reflective
                # - night: favors quiet, reflective
                if "morning" in day_arc:
                    choices = ["content", "warm", "playful", "reflective", "quiet", "distracted", "tired"]
                    weights = [0.35, 0.30, 0.20, 0.05, 0.05, 0.03, 0.02]
                elif "evening" in day_arc:
                    choices = ["tired", "reflective", "content", "warm", "quiet", "playful", "distracted"]
                    weights = [0.35, 0.35, 0.10, 0.10, 0.05, 0.03, 0.02]
                elif "night" in day_arc:
                    choices = ["quiet", "reflective", "tired", "content", "warm", "playful", "distracted"]
                    weights = [0.40, 0.40, 0.15, 0.02, 0.01, 0.00, 0.00]
                else: # afternoon/afternoon (early)
                    choices = ["content", "playful", "distracted", "warm", "reflective", "quiet", "tired"]
                    weights = [0.30, 0.25, 0.25, 0.10, 0.05, 0.03, 0.02]

                new_mood = random.choices(choices, weights=weights)[0]

            # 4. Transition energy (15% chance to change based on day arc)
            new_energy = current_energy
            if random.random() < 0.15:
                if "night" in day_arc:
                    new_energy = random.choices(["low", "normal", "high"], weights=[0.70, 0.25, 0.05])[0]
                elif "morning" in day_arc:
                    new_energy = random.choices(["high", "normal", "low"], weights=[0.40, 0.50, 0.10])[0]
                elif "evening" in day_arc:
                    new_energy = random.choices(["low", "normal", "high"], weights=[0.40, 0.50, 0.10])[0]
                else:
                    new_energy = random.choices(["normal", "high", "low"], weights=[0.60, 0.25, 0.15])[0]

            # 5. Save changes to DB
            now_iso = utc_now.isoformat()
            conn.execute("""
                UPDATE life_state
                SET partner_mood = ?,
                    partner_energy = ?,
                    partner_busy_until = ?,
                    day_arc = ?,
                    updated_at = ?
                WHERE user_id = ?
            """, (new_mood, new_energy, new_busy_until, day_arc, now_iso, user_id))
            conn.commit()
            
            logger.info(f"Ticked life state for user {user_id}: mood={new_mood}, energy={new_energy}, day_arc={day_arc}, busy_until={new_busy_until}")
        except Exception as e:
            logger.error(f"Error in LifeSimulator.tick for user {user_id}: {e}", exc_info=True)
        finally:
            if close_conn:
                conn.close()

    async def run_for_all_active(self, db):
        """
        Runs the simulation tick for all users active in the last 7 days.
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
            logger.info(f"Running life simulation tick for {len(user_ids)} active users")
            for uid in user_ids:
                await self.tick(conn, uid)
        except Exception as e:
            logger.error(f"Error in LifeSimulator.run_for_all_active: {e}", exc_info=True)
        finally:
            if close_conn:
                conn.close()

    def get_state_description_input(self, life_state: dict) -> dict:
        """
        Returns structured dict that ContextBuilder uses to generate natural language.
        """
        return {
            "mood": life_state.get("partner_mood") or "content",
            "energy": life_state.get("partner_energy") or "normal",
            "day_arc": life_state.get("day_arc") or "morning",
            "recent_event": life_state.get("recent_event") or ""
        }
