# ═══════════════════════════════════════════════════════════════════
# FILE: memory/store.py
# PURPOSE: Writes memories to SQLite (episodic_memories + vec_memories + FTS5).
# CONTEXT: Called by memory extractor after dream loop processing.
# ═══════════════════════════════════════════════════════════════════

import sqlite3
import json
from datetime import datetime, timezone
from memory.embedder import Embedder
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
