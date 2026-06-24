# ═══════════════════════════════════════════════════════════════════
# FILE: memory/store.py
# PURPOSE: Writes memories to SQLite (episodic_memories + vec_memories + FTS5).
# CONTEXT: Called by memory extractor after dream loop processing.
# ═══════════════════════════════════════════════════════════════════

import sqlite3
import json
from datetime import datetime, timezone
from memory.embedder import Embedder
from db.init import get_connection
import logging

logger = logging.getLogger(__name__)

class MemoryStore:
    
    def add(
        self,
        db: sqlite3.Connection,
        user_id: str,
        memory_text: str,
        memory_type: str,
        salience_score: float,
        emotional_valence: str,
        source_conversation_id: str,
        tags: list[str] = [],
        is_pinned: bool = False
    ) -> int:
        """
        Inserts a memory into:
        1. episodic_memories (metadata + text)
        2. vec_memories (embedding, same rowid)
        3. memories_fts (full-text search index)
        
        Returns the new memory's id.
        """
        now = datetime.now(timezone.utc).isoformat()
        tags_json = json.dumps(tags)
        
        # Insert metadata
        cursor = db.execute("""
            INSERT INTO episodic_memories 
            (user_id, memory_text, memory_type, salience_score, 
             emotional_valence, is_pinned, source_conversation_id,
             tags, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (user_id, memory_text, memory_type, salience_score,
              emotional_valence, 1 if is_pinned else 0,
              source_conversation_id, tags_json, now))
        
        memory_id = cursor.lastrowid
        
        # Insert vector (same rowid)
        embedding_bytes = Embedder.embed(memory_text)
        db.execute("""
            INSERT INTO vec_memories (rowid, embedding)
            VALUES (?, ?)
        """, (memory_id, embedding_bytes))
        
        # Insert into FTS5
        db.execute("""
            INSERT INTO memories_fts (rowid, memory_text)
            VALUES (?, ?)
        """, (memory_id, memory_text))
        
        db.commit()
        logger.info(f"Memory stored: user={user_id}, type={memory_type}, salience={salience_score}")
        return memory_id
    
    def get_all(
        self,
        db: sqlite3.Connection,
        user_id: str,
        limit: int = 100,
        memory_type: str | None = None
    ) -> list[dict]:
        """Fetch all memories for a user, ordered by salience DESC."""
        if memory_type:
            rows = db.execute("""
                SELECT * FROM episodic_memories
                WHERE user_id = ? AND memory_type = ?
                ORDER BY is_pinned DESC, salience_score DESC
                LIMIT ?
            """, (user_id, memory_type, limit)).fetchall()
        else:
            rows = db.execute("""
                SELECT * FROM episodic_memories
                WHERE user_id = ?
                ORDER BY is_pinned DESC, salience_score DESC
                LIMIT ?
            """, (user_id, limit)).fetchall()
        return [dict(r) for r in rows]
    
    def pin(self, db: sqlite3.Connection, memory_id: int, user_id: str):
        """Pin a memory — it will never decay."""
        db.execute("""
            UPDATE episodic_memories SET is_pinned = 1, salience_score = MAX(salience_score, 0.85)
            WHERE id = ? AND user_id = ?
        """, (memory_id, user_id))
        db.commit()
    
    def delete(self, db: sqlite3.Connection, memory_id: int, user_id: str):
        """Delete a memory and its vector + FTS entry."""
        db.execute("DELETE FROM episodic_memories WHERE id = ? AND user_id = ?",
                   (memory_id, user_id))
        db.execute("DELETE FROM vec_memories WHERE rowid = ?", (memory_id,))
        db.execute("DELETE FROM memories_fts WHERE rowid = ?", (memory_id,))
        db.commit()
    
    def count(self, db: sqlite3.Connection, user_id: str) -> int:
        return db.execute(
            "SELECT COUNT(*) FROM episodic_memories WHERE user_id = ?", (user_id,)
        ).fetchone()[0]


class Database:
    def __init__(self):
        self._ensure_columns()
        
    def get_connection(self) -> sqlite3.Connection:
        """Returns a thread-safe connection object."""
        return get_connection()

    @property
    def conn(self) -> sqlite3.Connection:
        """For legacy code expecting db.conn attribute directly."""
        return self.get_connection()

    def _ensure_columns(self):
        conn = self.get_connection()
        try:
            # 1. users table columns
            cursor = conn.execute("PRAGMA table_info(users)")
            cols = [r["name"] for r in cursor.fetchall()]
            if "preferred_name" not in cols:
                conn.execute("ALTER TABLE users ADD COLUMN preferred_name TEXT")
            if "onboarding_signals" not in cols:
                conn.execute("ALTER TABLE users ADD COLUMN onboarding_signals TEXT")
            if "onboarding_completed" not in cols:
                conn.execute("ALTER TABLE users ADD COLUMN onboarding_completed INTEGER DEFAULT 0")

            # 2. conversations table columns
            cursor = conn.execute("PRAGMA table_info(conversations)")
            cols = [r["name"] for r in cursor.fetchall()]
            if "pair_id" not in cols:
                conn.execute("ALTER TABLE conversations ADD COLUMN pair_id TEXT")
            if "partner_id" not in cols:
                conn.execute("ALTER TABLE conversations ADD COLUMN partner_id TEXT")
            if "ended_at" not in cols:
                conn.execute("ALTER TABLE conversations ADD COLUMN ended_at TEXT")

            # 3. messages table columns
            cursor = conn.execute("PRAGMA table_info(messages)")
            cols = [r["name"] for r in cursor.fetchall()]
            if "pair_id" not in cols:
                conn.execute("ALTER TABLE messages ADD COLUMN pair_id TEXT")
            if "partner_id" not in cols:
                conn.execute("ALTER TABLE messages ADD COLUMN partner_id TEXT")

            # 4. relationship_pairs table
            conn.execute("""
            CREATE TABLE IF NOT EXISTS relationship_pairs (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                partner_id TEXT NOT NULL,
                current_stage TEXT NOT NULL DEFAULT 'new',
                closeness_score REAL DEFAULT 0.18,
                trust_score REAL DEFAULT 0.18,
                openness_score REAL DEFAULT 0.12,
                comfort_score REAL DEFAULT 0.14,
                rhythm_score REAL DEFAULT 0.10,
                topic_familiarity_score REAL DEFAULT 0.05,
                proactive_cadence TEXT DEFAULT 'balanced',
                created_at TEXT NOT NULL
            )
            """)

            # 5. proactive_events table
            conn.execute("""
            CREATE TABLE IF NOT EXISTS proactive_events (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                pair_id TEXT,
                message_text TEXT NOT NULL,
                reason TEXT,
                delivered_at TEXT,
                scheduled_for TEXT,
                created_at TEXT NOT NULL,
                status TEXT DEFAULT 'sent'
            )
            """)

            # 6. user_preferences table
            conn.execute("""
            CREATE TABLE IF NOT EXISTS user_preferences (
                user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
                allow_memory_storage INTEGER DEFAULT 1,
                allow_proactive_messages INTEGER DEFAULT 1,
                allow_push_notifications INTEGER DEFAULT 1
            )
            """)

            # 7. user_facts table
            conn.execute("""
            CREATE TABLE IF NOT EXISTS user_facts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                pair_id TEXT,
                fact_key TEXT NOT NULL,
                fact_value TEXT NOT NULL,
                category TEXT,
                confidence REAL,
                source_type TEXT,
                created_at TEXT NOT NULL
            )
            """)

            # 8. partner_facts table
            conn.execute("""
            CREATE TABLE IF NOT EXISTS partner_facts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                pair_id TEXT,
                partner_id TEXT,
                category TEXT,
                fact_key TEXT NOT NULL,
                fact_value TEXT NOT NULL,
                confidence REAL,
                source_type TEXT,
                created_at TEXT NOT NULL
            )
            """)

            # 9. entities table
            conn.execute("""
            CREATE TABLE IF NOT EXISTS entities (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                pair_id TEXT,
                name TEXT NOT NULL,
                relationship_to_user TEXT,
                description TEXT,
                created_at TEXT NOT NULL
            )
            """)

            # 10. entity_relationships table
            conn.execute("""
            CREATE TABLE IF NOT EXISTS entity_relationships (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                pair_id TEXT,
                entity_id_1 INTEGER NOT NULL,
                entity_id_2 INTEGER NOT NULL,
                description TEXT,
                created_at TEXT NOT NULL
            )
            """)

            # 11. emotional_events table
            conn.execute("""
            CREATE TABLE IF NOT EXISTS emotional_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                pair_id TEXT,
                emotion TEXT,
                intensity REAL,
                trigger_entity TEXT,
                trigger_topic TEXT,
                created_at TEXT NOT NULL
            )
            """)

            # 12. behavioral_patterns table
            conn.execute("""
            CREATE TABLE IF NOT EXISTS behavioral_patterns (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                pair_id TEXT,
                description TEXT NOT NULL,
                confidence REAL,
                created_at TEXT NOT NULL
            )
            """)

            # 13. narrative_summaries table
            conn.execute("""
            CREATE TABLE IF NOT EXISTS narrative_summaries (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                pair_id TEXT,
                summary TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            """)

            # 14. life_events table
            conn.execute("""
            CREATE TABLE IF NOT EXISTS life_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                pair_id TEXT,
                event_description TEXT NOT NULL,
                resolved INTEGER DEFAULT 0,
                injected INTEGER DEFAULT 0,
                created_at TEXT NOT NULL
            )
            """)
            conn.commit()
        except Exception as e:
            logger.error(f"Error in Database._ensure_columns migrations: {e}", exc_info=True)
        finally:
            conn.close()

    def get_user(self, user_id: str) -> dict | None:
        with self.get_connection() as conn:
            row = conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
            return dict(row) if row else None

    def get_or_create_user(self, user_id: str, email: str = "") -> dict:
        with self.get_connection() as conn:
            row = conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
            if row:
                return dict(row)
            now = datetime.now(timezone.utc).isoformat()
            conn.execute(
                "INSERT INTO users (id, email, onboarding_complete, onboarding_completed, created_at, last_active_at) VALUES (?, ?, 0, 0, ?, ?)",
                (user_id, email or f"{user_id}@example.com", now, now)
            )
            conn.commit()
            row = conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
            return dict(row)

    def get_pair_by_id(self, pair_id: str) -> dict | None:
        with self.get_connection() as conn:
            row = conn.execute("SELECT * FROM relationship_pairs WHERE id = ?", (pair_id,)).fetchone()
            return dict(row) if row else None

    def get_primary_pair(self, user_id: str) -> dict | None:
        with self.get_connection() as conn:
            row = conn.execute("SELECT * FROM relationship_pairs WHERE user_id = ? LIMIT 1", (user_id,)).fetchone()
            return dict(row) if row else None

    def get_partner(self, user_id: str) -> dict | None:
        with self.get_connection() as conn:
            row = conn.execute("SELECT * FROM partners WHERE user_id = ? LIMIT 1", (user_id,)).fetchone()
            if row:
                d = dict(row)
                for k in ("persona_json", "voice_style_json", "voice_style", "blueprint_json", "inside_jokes", "shared_rituals"):
                    if k in d and isinstance(d[k], str):
                        try:
                            d[k] = json.loads(d[k])
                        except Exception:
                            pass
                return d
            return None

    def get_partner_by_id(self, partner_id: str) -> dict | None:
        with self.get_connection() as conn:
            row = conn.execute("SELECT * FROM partners WHERE id = ? LIMIT 1", (partner_id,)).fetchone()
            if row:
                d = dict(row)
                for k in ("persona_json", "voice_style_json", "voice_style", "blueprint_json", "inside_jokes", "shared_rituals"):
                    if k in d and isinstance(d[k], str):
                        try:
                            d[k] = json.loads(d[k])
                        except Exception:
                            pass
                return d
            return None

    def get_or_create_user_preferences(self, user_id: str) -> dict:
        with self.get_connection() as conn:
            row = conn.execute("SELECT * FROM user_preferences WHERE user_id = ?", (user_id,)).fetchone()
            if row:
                return dict(row)
            conn.execute(
                "INSERT OR IGNORE INTO user_preferences (user_id, allow_memory_storage, allow_proactive_messages, allow_push_notifications) VALUES (?, 1, 1, 1)",
                (user_id,)
            )
            conn.commit()
            row = conn.execute("SELECT * FROM user_preferences WHERE user_id = ?", (user_id,)).fetchone()
            return dict(row) if row else {"user_id": user_id, "allow_memory_storage": 1, "allow_proactive_messages": 1, "allow_push_notifications": 1}

    def get_message(self, message_id: int) -> dict | None:
        with self.get_connection() as conn:
            row = conn.execute("SELECT * FROM messages WHERE id = ?", (message_id,)).fetchone()
            return dict(row) if row else None

    def get_user_facts(self, user_id: str, pair_id: str = None) -> dict:
        with self.get_connection() as conn:
            rows = conn.execute(
                "SELECT fact_key, fact_value FROM user_facts WHERE user_id = ? OR pair_id = ?",
                (user_id, pair_id)
            ).fetchall()
            return {r["fact_key"]: r["fact_value"] for r in rows}

    def get_user_fact_rows(self, user_id: str, pair_id: str = None, limit: int = 10) -> list[dict]:
        with self.get_connection() as conn:
            rows = conn.execute(
                "SELECT * FROM user_facts WHERE user_id = ? OR pair_id = ? LIMIT ?",
                (user_id, pair_id, limit)
            ).fetchall()
            return [dict(r) for r in rows]

    def get_partner_facts(self, user_id: str, pair_id: str = None) -> dict:
        with self.get_connection() as conn:
            rows = conn.execute(
                "SELECT fact_key, fact_value FROM partner_facts WHERE user_id = ? OR pair_id = ?",
                (user_id, pair_id)
            ).fetchall()
            return {r["fact_key"]: r["fact_value"] for r in rows}

    def save_partner_fact(self, user_id: str, pair_id: str, partner_id: str, category: str, key: str, value: str, confidence: float, source_type: str):
        now = datetime.now(timezone.utc).isoformat()
        with self.get_connection() as conn:
            conn.execute(
                """
                INSERT INTO partner_facts (user_id, pair_id, partner_id, category, fact_key, fact_value, confidence, source_type, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (user_id, pair_id, partner_id, category, key, value, confidence, source_type, now)
            )
            conn.commit()

    def get_recent_messages(self, user_id: str, pair_id: str, limit: int, conversation_id: str = None) -> list[dict]:
        with self.get_connection() as conn:
            if conversation_id:
                rows = conn.execute(
                    "SELECT * FROM messages WHERE conversation_id = ? ORDER BY sent_at DESC LIMIT ?",
                    (conversation_id, limit)
                ).fetchall()
            else:
                rows = conn.execute(
                    "SELECT * FROM messages WHERE user_id = ? OR pair_id = ? ORDER BY sent_at DESC LIMIT ?",
                    (user_id, pair_id, limit)
                ).fetchall()
            return list(reversed([dict(r) for r in rows]))

    def get_entities_for_context(self, user_id: str, pair_id: str, query: str, limit: int) -> list[dict]:
        with self.get_connection() as conn:
            rows = conn.execute("SELECT * FROM entities WHERE user_id = ? OR pair_id = ? LIMIT ?", (user_id, pair_id, limit)).fetchall()
            return [dict(r) for r in rows]

    def get_relationships_for_entities(self, user_id: str, pair_id: str, entity_ids: list[int], limit: int) -> list[dict]:
        if not entity_ids:
            return []
        placeholders = ",".join("?" for _ in entity_ids)
        with self.get_connection() as conn:
            rows = conn.execute(
                f"SELECT * FROM entity_relationships WHERE (user_id = ? OR pair_id = ?) AND (entity_id_1 IN ({placeholders}) OR entity_id_2 IN ({placeholders})) LIMIT ?",
                [user_id, pair_id] + entity_ids + entity_ids + [limit]
            ).fetchall()
            return [dict(r) for r in rows]

    def get_emotional_summary(self, user_id: str, pair_id: str, limit: int) -> dict:
        with self.get_connection() as conn:
            rows = conn.execute(
                "SELECT emotion FROM emotional_events WHERE user_id = ? OR pair_id = ? ORDER BY created_at DESC LIMIT ?",
                (user_id, pair_id, limit)
            ).fetchall()
            emotions = [r["emotion"] for r in rows if r["emotion"]]
            return {"dominant_emotions": emotions} if emotions else {}

    def get_recent_emotional_events(self, user_id: str, pair_id: str, limit: int) -> list[dict]:
        with self.get_connection() as conn:
            rows = conn.execute(
                "SELECT * FROM emotional_events WHERE user_id = ? OR pair_id = ? ORDER BY created_at DESC LIMIT ?",
                (user_id, pair_id, limit)
            ).fetchall()
            return [dict(r) for r in rows]

    def get_active_patterns(self, user_id: str, pair_id: str, limit: int) -> list[dict]:
        with self.get_connection() as conn:
            rows = conn.execute(
                "SELECT * FROM behavioral_patterns WHERE user_id = ? OR pair_id = ? LIMIT ?",
                (user_id, pair_id, limit)
            ).fetchall()
            return [dict(r) for r in rows]

    def get_current_narrative(self, user_id: str, pair_id: str) -> dict | None:
        with self.get_connection() as conn:
            row = conn.execute(
                "SELECT * FROM narrative_summaries WHERE user_id = ? OR pair_id = ? ORDER BY updated_at DESC LIMIT 1",
                (user_id, pair_id)
            ).fetchone()
            return dict(row) if row else None

    def get_relationship_state_snapshot(self, pair_id: str) -> dict:
        with self.get_connection() as conn:
            row = conn.execute("SELECT * FROM relationship_pairs WHERE id = ?", (pair_id,)).fetchone()
            return dict(row) if row else {}

    def get_fact_conflicts(self, pair_id: str, limit: int) -> list[dict]:
        return []

    def get_latest_unresolved_life_event(self, pair_id: str) -> dict | None:
        with self.get_connection() as conn:
            row = conn.execute(
                "SELECT * FROM life_events WHERE pair_id = ? AND resolved = 0 AND injected = 0 ORDER BY created_at DESC LIMIT 1",
                (pair_id,)
            ).fetchone()
            return dict(row) if row else None

    def mark_life_event_injected(self, event_id: int):
        with self.get_connection() as conn:
            conn.execute("UPDATE life_events SET injected = 1 WHERE id = ?", (event_id,))
            conn.commit()

    def get_life_state(self, pair_id: str) -> dict | None:
        with self.get_connection() as conn:
            row = conn.execute(
                "SELECT * FROM life_state WHERE user_id = ? OR user_id = (SELECT user_id FROM relationship_pairs WHERE id = ?)",
                (pair_id, pair_id)
            ).fetchone()
            return dict(row) if row else None

    def get_current_conversation(self, user_id: str, pair_id: str = None) -> str | None:
        with self.get_connection() as conn:
            if pair_id:
                row = conn.execute("SELECT id FROM conversations WHERE pair_id = ? ORDER BY started_at DESC LIMIT 1", (pair_id,)).fetchone()
            else:
                row = conn.execute("SELECT id FROM conversations WHERE user_id = ? ORDER BY started_at DESC LIMIT 1", (user_id,)).fetchone()
            return row["id"] if row else None

    def create_conversation(self, user_id: str, pair_id: str, partner_id: str) -> str:
        conv_id = f"conv_{user_id}_{int(datetime.now(timezone.utc).timestamp())}"
        now = datetime.now(timezone.utc).isoformat()
        with self.get_connection() as conn:
            conn.execute(
                """
                INSERT INTO conversations (id, user_id, pair_id, partner_id, started_at, message_count, processed)
                VALUES (?, ?, ?, ?, ?, 0, 0)
                """,
                (conv_id, user_id, pair_id, partner_id, now)
            )
            conn.commit()
        return conv_id

    def get_conversation(self, conversation_id: str) -> dict | None:
        with self.get_connection() as conn:
            row = conn.execute("SELECT * FROM conversations WHERE id = ?", (conversation_id,)).fetchone()
            return dict(row) if row else None

    def save_message(self, conversation_id: str, user_id: str, pair_id: str, partner_id: str, role: str, content: str, emotional_signal: str = None):
        now = datetime.now(timezone.utc).isoformat()
        with self.get_connection() as conn:
            conn.execute(
                """
                INSERT INTO messages (conversation_id, user_id, pair_id, partner_id, role, content, sent_at, emotional_signal)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (conversation_id, user_id, pair_id, partner_id, role, content, now, emotional_signal)
            )
            # Update conversation's message count and last_message_at
            conn.execute(
                """
                UPDATE conversations
                SET message_count = message_count + 1,
                    last_message_at = ?
                WHERE id = ?
                """,
                (now, conversation_id)
            )
            # Also update last_active_at for the user
            conn.execute(
                "UPDATE users SET last_active_at = ? WHERE id = ?",
                (now, user_id)
            )
            conn.commit()

    def get_user_conversations(self, user_id: str) -> list[dict]:
        with self.get_connection() as conn:
            rows = conn.execute(
                "SELECT * FROM conversations WHERE user_id = ? ORDER BY last_message_at DESC",
                (user_id,)
            ).fetchall()
            return [dict(r) for r in rows]

    def get_paginated_messages(self, conversation_id: str, limit: int = 20, before_id: int = None) -> list[dict]:
        with self.get_connection() as conn:
            if before_id:
                rows = conn.execute(
                    "SELECT * FROM messages WHERE conversation_id = ? AND id < ? ORDER BY id DESC LIMIT ?",
                    (conversation_id, before_id, limit)
                ).fetchall()
            else:
                rows = conn.execute(
                    "SELECT * FROM messages WHERE conversation_id = ? ORDER BY id DESC LIMIT ?",
                    (conversation_id, limit)
                ).fetchall()
            return [dict(r) for r in rows]

    def soft_delete_conversation(self, conversation_id: str):
        with self.get_connection() as conn:
            conn.execute("DELETE FROM conversations WHERE id = ?", (conversation_id,))
            conn.commit()

    def get_onboarding_session(self, user_id: str) -> dict | None:
        with self.get_connection() as conn:
            row = conn.execute("SELECT * FROM onboarding_sessions WHERE user_id = ?", (user_id,)).fetchone()
            if row:
                d = dict(row)
                if isinstance(d["responses"], str):
                    try:
                        d["responses"] = json.loads(d["responses"])
                    except Exception:
                        d["responses"] = {}
                return d
            return None

    def create_onboarding_session(self, user_id: str):
        now = datetime.now(timezone.utc).isoformat()
        with self.get_connection() as conn:
            conn.execute(
                "INSERT OR IGNORE INTO onboarding_sessions (user_id, current_step, responses, started_at) VALUES (?, 0, '{}', ?)",
                (user_id, now)
            )
            conn.commit()

    def update_onboarding_session(self, user_id: str, step: int, responses: dict):
        with self.get_connection() as conn:
            conn.execute(
                "UPDATE onboarding_sessions SET current_step = ?, responses = ? WHERE user_id = ?",
                (step, json.dumps(responses), user_id)
            )
            conn.commit()

    def save_onboarding_signals(self, user_id: str, preferred_name: str, signals: dict, onboarding_completed: int):
        with self.get_connection() as conn:
            conn.execute(
                "UPDATE users SET preferred_name = ?, onboarding_signals = ?, onboarding_completed = ?, onboarding_complete = ? WHERE id = ?",
                (preferred_name, json.dumps(signals), onboarding_completed, onboarding_completed, user_id)
            )
            conn.commit()

    def save_partner(self, user_id: str, partner_id: str, name: str, archetype_id: str, persona_json: dict, voice_style_json: dict):
        now = datetime.now(timezone.utc).isoformat()
        with self.get_connection() as conn:
            conn.execute(
                """
                INSERT OR REPLACE INTO partners 
                (id, user_id, name, archetype_seed, persona_json, voice_style, flaw_profile, relationship_stage, intimacy_tier, generated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, 'new', 1, ?)
                """,
                (
                    partner_id,
                    user_id,
                    name,
                    archetype_id,
                    json.dumps(persona_json),
                    json.dumps(voice_style_json),
                    persona_json.get("flaw_profile") or "none",
                    now
                )
            )
            # Also insert or replace a relationship pair
            pair_id = f"{user_id}::{partner_id}"
            conn.execute(
                """
                INSERT OR REPLACE INTO relationship_pairs
                (id, user_id, partner_id, current_stage, closeness_score, trust_score, openness_score, comfort_score, rhythm_score, created_at)
                VALUES (?, ?, ?, 'new', 0.18, 0.18, 0.12, 0.14, 0.10, ?)
                """,
                (pair_id, user_id, partner_id, now)
            )
            # Initialize life state for the user if not exists
            conn.execute(
                """
                INSERT OR IGNORE INTO life_state (user_id, partner_mood, partner_energy, day_arc, updated_at)
                VALUES (?, 'content', 'balanced', 'morning', ?)
                """,
                (user_id, now)
            )
            conn.commit()

    def update_pair_proactive_settings(self, pair_id: str, proactive_cadence: str):
        with self.get_connection() as conn:
            conn.execute(
                "UPDATE relationship_pairs SET proactive_cadence = ? WHERE id = ?",
                (proactive_cadence, pair_id)
            )
            conn.commit()

    def delete_onboarding_session(self, user_id: str):
        with self.get_connection() as conn:
            conn.execute("DELETE FROM onboarding_sessions WHERE user_id = ?", (user_id,))
            conn.commit()

    def update_user_display_name(self, user_id: str, display_name: str):
        with self.get_connection() as conn:
            conn.execute("UPDATE users SET display_name = ? WHERE id = ?", (display_name, user_id))
            conn.commit()

    def update_pair_proactive_cadence(self, pair_id: str, cadence: str):
        with self.get_connection() as conn:
            conn.execute("UPDATE relationship_pairs SET proactive_cadence = ? WHERE id = ?", (cadence, pair_id))
            conn.commit()

    def update_user_onboarding_depth_preference(self, user_id: str, depth: str):
        with self.get_connection() as conn:
            conn.execute("UPDATE users SET emotional_depth_preference = ? WHERE id = ?", (depth, user_id))
            conn.commit()

    def update_user_preferences(self, user_id: str, **kwargs):
        if not kwargs:
            return
        set_clause = ", ".join(f"{k} = ?" for k in kwargs.keys())
        params = list(kwargs.values()) + [user_id]
        with self.get_connection() as conn:
            conn.execute(f"UPDATE user_preferences SET {set_clause} WHERE user_id = ?", params)
            conn.commit()

    def get_memories_paginated(self, pair_id: str, memory_type: str = None, sort: str = "recent", page: int = 1, limit: int = 10) -> tuple[list[dict], int]:
        offset = (page - 1) * limit
        user_id = pair_id.split("::")[0]
        
        where_clause = "WHERE user_id = ?"
        params = [user_id]
        if memory_type:
            where_clause += " AND memory_type = ?"
            params.append(memory_type)
            
        order_clause = "ORDER BY created_at DESC"
        if sort == "salience":
            order_clause = "ORDER BY is_pinned DESC, salience_score DESC"
        elif sort == "recalled":
            order_clause = "ORDER BY recall_count DESC"
            
        with self.get_connection() as conn:
            total = conn.execute(f"SELECT COUNT(*) FROM episodic_memories {where_clause}", params).fetchone()[0]
            rows = conn.execute(f"SELECT * FROM episodic_memories {where_clause} {order_clause} LIMIT ? OFFSET ?", params + [limit, offset]).fetchall()
            return [dict(r) for r in rows], total

    def verify_memory_ownership(self, pair_id: str, memory_id: str) -> bool:
        user_id = pair_id.split("::")[0]
        with self.get_connection() as conn:
            row = conn.execute("SELECT id FROM episodic_memories WHERE id = ? AND user_id = ?", (memory_id, user_id)).fetchone()
            return row is not None

    def clear_all_memories(self, pair_id: str):
        user_id = pair_id.split("::")[0]
        with self.get_connection() as conn:
            conn.execute("DELETE FROM episodic_memories WHERE user_id = ?", (user_id,))
            conn.execute("DELETE FROM vec_memories WHERE rowid NOT IN (SELECT id FROM episodic_memories)")
            conn.execute("DELETE FROM memories_fts WHERE rowid NOT IN (SELECT id FROM episodic_memories)")
            conn.commit()

    def delete_user(self, user_id: str):
        with self.get_connection() as conn:
            conn.execute("DELETE FROM users WHERE id = ?", (user_id,))
            conn.commit()

    def update_last_active(self, user_id: str):
        now = datetime.now(timezone.utc).isoformat()
        with self.get_connection() as conn:
            conn.execute("UPDATE users SET last_active_at = ? WHERE id = ?", (now, user_id))
            conn.commit()

db = Database()
