# ═══════════════════════════════════════════════════════════════════
# FILE: memory/retriever.py
# PURPOSE: Retrieves relevant memories using hybrid semantic + keyword search.
# CONTEXT: Called on every chat message before LLM context assembly.
# ═══════════════════════════════════════════════════════════════════

import sqlite3
import re
from datetime import datetime, timezone
from config import settings
from memory.embedder import Embedder
import logging

logger = logging.getLogger(__name__)

class MemoryRetriever:
    
    def retrieve(
        self,
        db: sqlite3.Connection,
        user_id: str,
        query_text: str,
        limit: int = 5
    ) -> list[dict]:
        """
        Hybrid retrieval strategy:
        
        1. SEMANTIC: sqlite-vec cosine distance search
        2. KEYWORD FALLBACK: FTS5 search (only if semantic has 0 results)
        3. PINNED: always include (max 3)
        4. DEDUP and RANK:
           - Merge, deduplicate by id
           - Fallback to most recent memory if 0 results
           - Sort: pinned first, then salience DESC
           - Return top `limit` memories
        5. UPDATE recall stats for returned memories
        """
        results = []
        semantic_results = []
        
        # 1. SEMANTIC search
        try:
            query_vec = Embedder.embed(query_text)
            threshold = settings.MEMORY_SIMILARITY_THRESHOLD
            
            rows = db.execute("""
                SELECT em.id, em.memory_text, em.memory_type, em.salience_score,
                       em.emotional_valence, em.is_pinned,
                       vec_distance_cosine(vm.embedding, :query_vec) as distance
                FROM vec_memories vm
                JOIN episodic_memories em ON em.id = vm.rowid
                WHERE em.user_id = :user_id
                  AND vec_distance_cosine(vm.embedding, :query_vec) < :threshold
                ORDER BY distance ASC
                LIMIT 2
            """, {
                "query_vec": query_vec,
                "user_id": user_id,
                "threshold": threshold
            }).fetchall()
            
            semantic_results = [dict(r) for r in rows]
            results.extend(semantic_results)
            logger.debug(f"Semantic memory search returned {len(semantic_results)} results")
        except Exception as e:
            logger.error(f"Semantic search failed: {e}", exc_info=True)
            
        # 2. KEYWORD FALLBACK search (only if semantic returned 0)
        if not semantic_results:
            try:
                words = re.findall(r'\w+', query_text)
                if words:
                    fts_query = " OR ".join(words)
                    rows = db.execute("""
                        SELECT em.id, em.memory_text, em.memory_type, em.salience_score,
                               em.emotional_valence, em.is_pinned
                        FROM memories_fts mf
                        JOIN episodic_memories em ON em.id = mf.rowid
                        WHERE mf.memory_text MATCH :query
                          AND em.user_id = :user_id
                        ORDER BY em.salience_score DESC
                        LIMIT 2
                    """, {
                        "query": fts_query,
                        "user_id": user_id
                    }).fetchall()
                    
                    fts_results = [dict(r) for r in rows]
                    results.extend(fts_results)
                    logger.debug(f"Keyword memory fallback search returned {len(fts_results)} results")
            except Exception as e:
                logger.error(f"FTS5 keyword search failed: {e}", exc_info=True)
                
        # 3. PINNED memories
        try:
            pinned_rows = db.execute("""
                SELECT id, memory_text, memory_type, salience_score, emotional_valence, is_pinned
                FROM episodic_memories
                WHERE user_id = ? AND is_pinned = 1
                ORDER BY salience_score DESC
                LIMIT 3
            """, (user_id,)).fetchall()
            
            results.extend([dict(r) for r in pinned_rows])
        except Exception as e:
            logger.error(f"Pinned memories retrieval failed: {e}", exc_info=True)
            
        # 4. DEDUP and RANK
        # Deduplicate by id
        unique_memories = {}
        for mem in results:
            # Strip extra fields like distance to keep output signature clean
            clean_mem = {
                "id": mem["id"],
                "memory_text": mem["memory_text"],
                "memory_type": mem["memory_type"],
                "salience_score": mem["salience_score"],
                "emotional_valence": mem["emotional_valence"],
                "is_pinned": mem["is_pinned"]
            }
            unique_memories[mem["id"]] = clean_mem
            
        final_results = list(unique_memories.values())
        
        # Fallback to most recent memory if 0 results
        if not final_results:
            try:
                recent_row = db.execute("""
                    SELECT id, memory_text, memory_type, salience_score, emotional_valence, is_pinned
                    FROM episodic_memories
                    WHERE user_id = ?
                    ORDER BY created_at DESC
                    LIMIT 1
                """, (user_id,)).fetchone()
                if recent_row:
                    final_results.append(dict(recent_row))
            except Exception as e:
                logger.error(f"Recent fallback retrieval failed: {e}", exc_info=True)
                
        # Sort: pinned first, then salience DESC
        final_results.sort(key=lambda m: (m["is_pinned"], m["salience_score"]), reverse=True)
        
        # Take top `limit`
        final_results = final_results[:limit]
        
        # 5. UPDATE recall stats
        if final_results:
            returned_ids = [m["id"] for m in final_results]
            now = datetime.now(timezone.utc).isoformat()
            try:
                placeholders = ",".join("?" for _ in returned_ids)
                db.execute(f"""
                    UPDATE episodic_memories
                    SET recall_count = recall_count + 1,
                        last_recalled_at = ?
                    WHERE id IN ({placeholders})
                """, [now] + returned_ids)
                db.commit()
            except Exception as e:
                logger.error(f"Failed to update memory recall stats: {e}", exc_info=True)
                
        return final_results
