import sys
import os
import unittest
from datetime import datetime, timedelta

# Adjust path to import backend modules
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "..", "..", "Desktop", "sol_mvp", "backend")))
sys.path.insert(0, "c:\\Users\\aakash09\\Desktop\\sol_mvp\\backend")

from memory.store import db, make_pair_id
from core.life_simulator import simulate_life_event, EVENT_TEMPLATES
from core.context_builder import build_context

class LifeSimulatorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Ensure database is connected
        db.connect()
        cls.user_id = "test_user_life_sim"
        cls.companion_id = "nova"
        cls.pair_id = make_pair_id(cls.user_id, cls.companion_id)
        
        # Create test user and companion if they do not exist
        db.get_or_create_user(cls.user_id, character_id=cls.companion_id)
        
        # Insert a companion into companions table if not present
        db.conn.execute(
            "INSERT OR IGNORE INTO companions (id, name) VALUES (?, ?)",
            (cls.companion_id, "Nova")
        )
        db.conn.commit()

    def setUp(self):
        # Reset any existing records for our test pair
        db.reset_pair_memory(self.pair_id)
        db.conn.execute("DELETE FROM relationship_pairs WHERE id = ?", (self.pair_id,))
        db.conn.commit()

        # Seed initial relationship pair
        db.conn.execute(
            """
            INSERT INTO relationship_pairs (
                id, user_id, companion_id, closeness_score, trust_score,
                comfort_score, total_sessions, total_messages, last_interaction_at
            ) VALUES (?, ?, ?, 0.5, 0.5, 0.5, 1, 0, NULL)
            """,
            (self.pair_id, self.user_id, self.companion_id)
        )
        db.conn.commit()

    def tearDown(self):
        db.reset_pair_memory(self.pair_id)
        db.conn.execute("DELETE FROM relationship_pairs WHERE id = ?", (self.pair_id,))
        db.conn.commit()

    def test_01_event_templates_integrity(self):
        """Verify that all 12 characters are defined in the simulator templates and contain morning, afternoon, and night slots."""
        expected_chars = [
            "nova", "atlas", "mira", "elio", "june", "kaia",
            "nira", "orion", "remy", "sabine", "theo", "vale"
        ]
        for cid in expected_chars:
            self.assertIn(cid, EVENT_TEMPLATES)
            templates = EVENT_TEMPLATES[cid]
            self.assertIn("morning", templates)
            self.assertIn("afternoon", templates)
            self.assertIn("night", templates)
            self.assertTrue(len(templates["morning"]) > 0)
            self.assertTrue(len(templates["afternoon"]) > 0)
            self.assertTrue(len(templates["night"]) > 0)

    def test_02_simulation_and_persistence(self):
        """Verify simulate_life_event correctly generates and saves an unresolved, uninjected event."""
        event = simulate_life_event(self.pair_id, self.companion_id)
        self.assertIsNotNone(event)
        self.assertEqual(event["pair_id"], self.pair_id)
        self.assertEqual(event["companion_id"], self.companion_id)
        self.assertIsNotNone(event["event_description"])

        # Check DB state
        db_event = db.get_latest_unresolved_life_event(self.pair_id)
        self.assertIsNotNone(db_event)
        self.assertEqual(db_event["id"], event["id"])
        self.assertEqual(int(db_event["is_resolved"]), 0)
        self.assertEqual(int(db_event["context_injected"]), 0)

    def test_03_context_injection_lifecycle(self):
        """Verify that build_context retrieves, formats, injects, and marks the event as context_injected = 1."""
        # 1. Simulate an event
        event = simulate_life_event(self.pair_id, self.companion_id)
        
        # 2. Build context
        system_prompt, messages = asyncio_run(build_context(
            user_id=self.user_id,
            pair_id=self.pair_id,
            current_message="hey what's up"
        ))

        # Check prompt has context
        self.assertIn("YOUR CURRENT LIFE CONTEXT", system_prompt)
        self.assertIn(event["event_description"], system_prompt)

        # Check DB state has updated to context_injected = 1
        db_event = db.get_latest_unresolved_life_event(self.pair_id)
        self.assertIsNotNone(db_event)
        self.assertEqual(int(db_event["context_injected"]), 1)
        self.assertEqual(int(db_event["is_resolved"]), 0)

    def test_04_turn_resolution(self):
        """Verify that completing a turn resolves the event and prevents subsequent prompt injection."""
        # 1. Simulate and inject
        simulate_life_event(self.pair_id, self.companion_id)
        
        # Call build_context (marks injected)
        asyncio_run(build_context(self.user_id, self.pair_id, "hello"))

        # 2. Resolve turn (simulates assistant response complete in chat.py)
        active_event = db.get_latest_unresolved_life_event(self.pair_id)
        self.assertIsNotNone(active_event)
        db.mark_life_event_resolved(active_event["id"])

        # Check DB state: no more unresolved event
        resolved_event = db.get_latest_unresolved_life_event(self.pair_id)
        self.assertIsNone(resolved_event)

        # Update last_interaction_at to prevent new simulation on subsequent call
        now_str = datetime.utcnow().isoformat()
        db.conn.execute("UPDATE relationship_pairs SET last_interaction_at = ? WHERE id = ?", (now_str, self.pair_id))
        db.conn.commit()

        # 3. Call build_context again immediately
        system_prompt_2, _ = asyncio_run(build_context(self.user_id, self.pair_id, "how's it going"))
        self.assertNotIn("YOUR CURRENT LIFE CONTEXT", system_prompt_2)

    def test_05_time_gap_triggers(self):
        """Verify that the 6-hour cooldown correctly dictates whether a new simulation is triggered."""
        # Case A: First conversation (last_interaction_at is NULL) -> Should simulate
        db_event = db.get_latest_unresolved_life_event(self.pair_id)
        self.assertIsNone(db_event)
        
        asyncio_run(build_context(self.user_id, self.pair_id, "first msg"))
        
        db_event_first = db.get_latest_unresolved_life_event(self.pair_id)
        self.assertIsNotNone(db_event_first) # Event successfully simulated and injected
        
        # Mark resolved
        db.mark_life_event_resolved(db_event_first["id"])

        # Case B: Interaction was 2 hours ago (< 6 hours) -> Should NOT simulate
        two_hours_ago = (datetime.utcnow() - timedelta(hours=2)).isoformat()
        db.conn.execute("UPDATE relationship_pairs SET last_interaction_at = ? WHERE id = ?", (two_hours_ago, self.pair_id))
        db.conn.commit()

        asyncio_run(build_context(self.user_id, self.pair_id, "msg 2 hours later"))
        
        no_event = db.get_latest_unresolved_life_event(self.pair_id)
        self.assertIsNone(no_event)

        # Case C: Interaction was 7 hours ago (> 6 hours) -> Should simulate
        seven_hours_ago = (datetime.utcnow() - timedelta(hours=7)).isoformat()
        db.conn.execute("UPDATE relationship_pairs SET last_interaction_at = ? WHERE id = ?", (seven_hours_ago, self.pair_id))
        db.conn.commit()

        asyncio_run(build_context(self.user_id, self.pair_id, "msg 7 hours later"))
        
        db_event_seven = db.get_latest_unresolved_life_event(self.pair_id)
        self.assertIsNotNone(db_event_seven)


def asyncio_run(coro):
    import asyncio
    return asyncio.get_event_loop().run_until_complete(coro)

if __name__ == "__main__":
    unittest.main()
