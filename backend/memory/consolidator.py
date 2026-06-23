import logging
import json
from datetime import datetime, timedelta
from core.llm import get_llm_core
from memory.store import memory_store, db

logger = logging.getLogger(__name__)

class MemoryConsolidator:
    async def consolidate(self, user_id: str):
        try:
            primary = db.get_primary_pair(user_id)
            if not primary:
                return
            pair_id = primary["id"]

            # 1. Apply decay
            await self.apply_decay(user_id)

            # 2. Merge duplicates
            active_memories = await memory_store.get_all(user_id, limit=300)
            if len(active_memories) > 1:
                # Format memories for the LLM
                memory_list_str = ""
                id_map = {}
                for idx, m in enumerate(active_memories):
                    memory_list_str += f"{idx}. [ID: {m['chroma_id']}] {m['content']}\n"
                    id_map[m['chroma_id']] = m

                system_prompt = (
                    "You are a semantic memory consolidation engine.\n"
                    "Your task is to identify memories in the list that represent duplicate information or cover the exact same event, fact, or preference.\n"
                    "Group duplicate memories together by their IDs."
                )

                output_schema = {
                    "type": "object",
                    "properties": {
                        "duplicate_groups": {
                            "type": "array",
                            "items": {
                                "type": "array",
                                "items": {"type": "string"}
                            },
                            "description": "Groups of duplicate memory IDs. Example: [['id1', 'id2'], ['id3', 'id4']]"
                        }
                    },
                    "required": ["duplicate_groups"]
                }

                try:
                    llm = get_llm_core()
                    result = await llm.complete_structured(
                        system_prompt=system_prompt,
                        messages=[{"role": "user", "content": f"Analyze these memories for duplicates:\n{memory_list_str}"}],
                        output_schema=output_schema,
                        temperature=0.0
                    )
                    
                    duplicate_groups = result.get("duplicate_groups", [])
                    for group in duplicate_groups:
                        # Filter to ensure IDs exist in our map
                        valid_group = [m_id for m_id in group if m_id in id_map]
                        if len(valid_group) <= 1:
                            continue
                        
                        # Find the memory with highest salience
                        sorted_group = sorted(
                            valid_group,
                            key=lambda m_id: float(id_map[m_id].get("salience") or 0.0),
                            reverse=True
                        )
                        
                        best_id = sorted_group[0]
                        to_delete = sorted_group[1:]
                        
                        for del_id in to_delete:
                            logger.info("Merging duplicate memory %s into %s", del_id, best_id)
                            await memory_store.delete(del_id)
                except Exception as e:
                    logger.error("Failed to merge duplicate memories: %s", e)

            # 3. Upgrade salience: if recalled 5+ times, increase salience by 0.1
            db.conn.execute(
                """
                UPDATE memory_index
                SET salience = MIN(1.0, salience + 0.1)
                WHERE pair_id = ? AND recall_count >= 5 AND archived = 0
                """,
                (pair_id,)
            )

            # 4. Pin promotion: if salience reaches 0.9+, set is_pinned = 1
            db.conn.execute(
                """
                UPDATE memory_index
                SET is_pinned = 1
                WHERE pair_id = ? AND salience >= 0.9 AND archived = 0
                """,
                (pair_id,)
            )

            # 5. Prune: delete memories where decay_factor < 0.1 AND is_pinned = 0 AND recall_count = 0
            prune_rows = db.conn.execute(
                """
                SELECT chroma_id FROM memory_index
                WHERE pair_id = ? AND decay_factor < 0.1 AND is_pinned = 0 AND recall_count = 0 AND archived = 0
                """,
                (pair_id,)
            ).fetchall()
            for row in prune_rows:
                logger.info("Pruning decayed memory %s", row["chroma_id"])
                await memory_store.delete(row["chroma_id"])

        except Exception as e:
            logger.error("Error during memory consolidation: %s", e, exc_info=True)

    async def apply_decay(self, user_id: str):
        try:
            primary = db.get_primary_pair(user_id)
            if not primary:
                return
            pair_id = primary["id"]

            now = datetime.utcnow()
            seven_days_ago = now - timedelta(days=7)

            # Fetch unpinned candidate memories
            rows = db.conn.execute(
                """
                SELECT id, last_recalled_at, decay_factor FROM memory_index
                WHERE pair_id = ? AND is_pinned = 0 AND archived = 0
                """,
                (pair_id,)
            ).fetchall()

            for row in rows:
                last_recalled = row["last_recalled_at"]
                skip = False
                if last_recalled:
                    try:
                        lr_dt = datetime.fromisoformat(str(last_recalled))
                        if lr_dt > seven_days_ago:
                            skip = True
                    except ValueError:
                        pass
                if not skip:
                    new_decay = float(row["decay_factor"] or 1.0) * 0.95
                    db.conn.execute(
                        "UPDATE memory_index SET decay_factor = ? WHERE id = ?",
                        (new_decay, row["id"])
                    )
        except Exception as e:
            logger.error("Error applying memory decay: %s", e, exc_info=True)
