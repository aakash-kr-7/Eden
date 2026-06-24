# ═══════════════════════════════════════════════════════════════════
# FILE: memory/consolidator.py
# PURPOSE: Dream loop — runs after conversations, extracts memories, updates blueprint.
# CONTEXT: Triggered by APScheduler every 10 minutes for unprocessed conversations.
# ═══════════════════════════════════════════════════════════════════

import sqlite3
import json
from datetime import datetime, timezone
from config import settings
from core.llm import LLMCore
from memory.extractor import MemoryExtractor
from memory.store import MemoryStore
import logging

logger = logging.getLogger(__name__)

class MemoryConsolidator:
    
    async def process_conversation(
        self,
        db: sqlite3.Connection,
        conversation_id: str,
        user_id: str
    ):
        """
        The dream loop:
        1. Fetch all messages from conversation
        2. Fetch partner name from partners table
        3. Fetch existing memories for dedup
        4. Call MemoryExtractor.extract()
        5. For each extracted memory: call MemoryStore.add()
        6. Update partners.blueprint_json, inside_jokes, stage
        7. Mark conversation as processed=1, save summary & tone
        8. Prune: keep last 50 messages per user, delete the rest
        """
        logger.info(f"Processing conversation {conversation_id} for user {user_id} in dream loop")
        
        # 1. Fetch messages
        message_rows = db.execute("""
            SELECT role, content FROM messages
            WHERE conversation_id = ?
            ORDER BY sent_at ASC
        """, (conversation_id,)).fetchall()
        messages_list = [dict(row) for row in message_rows]
        
        if not messages_list:
            logger.warning(f"No messages found for conversation {conversation_id}, skipping")
            # Mark processed to avoid processing indefinitely
            db.execute("UPDATE conversations SET processed = 1 WHERE id = ?", (conversation_id,))
            db.commit()
            return
            
        # 2. Fetch partner name
        partner_row = db.execute("""
            SELECT name, blueprint_json, inside_jokes, relationship_stage
            FROM partners
            WHERE user_id = ?
        """, (user_id,)).fetchone()
        
        if not partner_row:
            logger.error(f"No partner found for user {user_id}, cannot run dream loop")
            return
            
        partner_name = partner_row["name"]
        
        # 3. Fetch existing memories
        store = MemoryStore()
        existing_memories = store.get_all(db, user_id)
        
        # 4. Extract memories
        extractor = MemoryExtractor()
        new_memories = await extractor.extract(messages_list, partner_name, existing_memories)
        
        # 5. Store new memories
        for mem in new_memories:
            try:
                store.add(
                    db=db,
                    user_id=user_id,
                    memory_text=mem["memory_text"],
                    memory_type=mem["memory_type"],
                    salience_score=mem["salience_score"],
                    emotional_valence=mem["emotional_valence"],
                    source_conversation_id=conversation_id,
                    tags=mem.get("tags", []),
                    is_pinned=False
                )
            except Exception as e:
                logger.error(f"Failed to add memory: {e}", exc_info=True)
                
        # 6. Parse and update partners blueprint and inside jokes
        blueprint = {}
        if partner_row["blueprint_json"]:
            try:
                blueprint = json.loads(partner_row["blueprint_json"])
            except Exception:
                blueprint = {}
                
        try:
            inside_jokes = json.loads(partner_row["inside_jokes"]) if partner_row["inside_jokes"] else []
        except Exception:
            inside_jokes = []
            
        # Detect new jokes
        new_jokes = [mem["memory_text"] for mem in new_memories if mem["memory_type"] == "joke"]
        for joke in new_jokes:
            if joke not in inside_jokes:
                inside_jokes.append(joke)
                
        blueprint["inside_jokes"] = inside_jokes
        
        # 7. Generate conversation summary & emotional tone
        summary = "No summary generated."
        emotional_tone = "neutral"
        try:
            core = LLMCore(settings)
            core.model = settings.GROQ_FAST_MODEL
            
            summary_prompt = f"""Analyze the following conversation transcript between a User and their partner {partner_name}.
Generate a brief summary (1-2 sentences) and determine the dominant emotional tone (e.g. warm, distant, vulnerable, playful, tense, neutral).
"""
            
            transcript_text = "\n".join([
                f"{partner_name if msg['role'] in ('partner', 'assistant') else 'User'}: {msg['content']}"
                for msg in messages_list
            ])
            
            summary_schema = {
                "type": "object",
                "properties": {
                    "summary": {"type": "string"},
                    "emotional_tone": {"type": "string"}
                },
                "required": ["summary", "emotional_tone"]
            }
            
            summary_res = await core.complete_structured(
                system_prompt=summary_prompt,
                messages=[{"role": "user", "content": f"Transcript:\n{transcript_text}"}],
                output_schema=summary_schema,
                temperature=0.2
            )
            
            summary = summary_res.get("summary", summary)
            emotional_tone = summary_res.get("emotional_tone", emotional_tone)
        except Exception as e:
            logger.error(f"Failed to generate conversation summary: {e}", exc_info=True)
            
        # Update conversations table with summary, tone, and processed=1
        db.execute("""
            UPDATE conversations
            SET summary = ?, emotional_tone = ?, processed = 1
            WHERE id = ?
        """, (summary, emotional_tone, conversation_id))
        
        # Update emotional trajectory in blueprint
        if "emotional_trajectory" not in blueprint:
            blueprint["emotional_trajectory"] = []
        blueprint["emotional_trajectory"].append(emotional_tone)
        blueprint["emotional_trajectory"] = blueprint["emotional_trajectory"][-10:]
        
        # Save partner updates (blueprint and inside jokes)
        db.execute("""
            UPDATE partners
            SET blueprint_json = ?,
                inside_jokes = ?
            WHERE user_id = ?
        """, (json.dumps(blueprint), json.dumps(inside_jokes), user_id))

        # Check stage advancement via RelationshipEngine
        from engine.relationship_engine import RelationshipEngine
        rel_engine = RelationshipEngine()
        await rel_engine.evaluate_progression(db, user_id)
        
        # 8. Prune messages: keep last 50 per user
        db.execute("""
            DELETE FROM messages
            WHERE id IN (
                SELECT id FROM messages
                WHERE user_id = ?
                ORDER BY sent_at DESC
                LIMIT 999999 OFFSET 50
            )
        """, (user_id,))
        
        db.commit()
        logger.info(f"Conversation {conversation_id} successfully consolidated. Stage: {next_stage}, Jokes: {len(inside_jokes)}")
        
    async def apply_decay(self, db: sqlite3.Connection, user_id: str):
        """
        Daily: decay_factor *= 0.95 for unpinned memories not recalled in 7 days.
        Delete if decay_factor < 0.1 and is_pinned = 0 and recall_count = 0.
        """
        now_ts = int(datetime.now(timezone.utc).timestamp())
        seven_days_seconds = 7 * 86400
        
        # Apply decay to qualifying memories
        db.execute("""
            UPDATE episodic_memories
            SET decay_factor = decay_factor * 0.95
            WHERE user_id = :user_id
              AND is_pinned = 0
              AND (
                  (last_recalled_at IS NOT NULL AND :now_ts - strftime('%s', last_recalled_at) > :seven_days)
                  OR
                  (last_recalled_at IS NULL AND :now_ts - strftime('%s', created_at) > :seven_days)
              )
        """, {
            "user_id": user_id,
            "now_ts": now_ts,
            "seven_days": seven_days_seconds
        })
        
        # Prune decayed memories
        decayed_rows = db.execute("""
            SELECT id FROM episodic_memories
            WHERE user_id = ?
              AND decay_factor < 0.1
              AND is_pinned = 0
              AND recall_count = 0
        """, (user_id,)).fetchall()
        
        decayed_ids = [row["id"] for row in decayed_rows]
        if decayed_ids:
            placeholders = ",".join("?" for _ in decayed_ids)
            db.execute(f"DELETE FROM episodic_memories WHERE id IN ({placeholders})", decayed_ids)
            db.execute(f"DELETE FROM vec_memories WHERE rowid IN ({placeholders})", decayed_ids)
            db.execute(f"DELETE FROM memories_fts WHERE rowid IN ({placeholders})", decayed_ids)
            logger.info(f"Pruned {len(decayed_ids)} decayed memories for user {user_id}")
            
        db.commit()
        
    async def run_pending(self, db: sqlite3.Connection):
        """
        Called by APScheduler every 10 minutes.
        Finds conversations where:
        - processed = 0
        - last_message_at < NOW() - 2 hours
        Runs process_conversation() for each.
        """
        now_ts = int(datetime.now(timezone.utc).timestamp())
        two_hours_seconds = 2 * 3600
        
        rows = db.execute("""
            SELECT id, user_id FROM conversations
            WHERE processed = 0
              AND last_message_at IS NOT NULL
              AND :now_ts - strftime('%s', last_message_at) > :two_hours
        """, {
            "now_ts": now_ts,
            "two_hours": two_hours_seconds
        }).fetchall()
        
        if rows:
            logger.info(f"Found {len(rows)} pending conversations for dream loop consolidation")
            for row in rows:
                try:
                    await self.process_conversation(db, row["id"], row["user_id"])
                except Exception as e:
                    logger.error(f"Failed to run pending conversation processing for {row['id']}: {e}", exc_info=True)
        else:
            logger.debug("No pending conversations to process in dream loop")
