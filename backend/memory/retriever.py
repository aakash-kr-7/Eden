import logging
import json
from datetime import datetime, timedelta
from typing import Optional
from core.llm import get_llm_core
from memory.store import memory_store, db

logger = logging.getLogger(__name__)

class MemoryRetriever:
    async def retrieve(
        self,
        user_id: str,
        current_message: str,
        conversation_context: str,
        limit: int = 12
    ) -> list[dict]:
        try:
            # 1. Fetch all candidate memories for the user
            candidates = await memory_store.get_all(user_id, limit=200)
            if not candidates:
                return []

            # Stage 1: Always-include (pinned memories)
            pinned = [m for m in candidates if m.get("is_pinned") == 1]

            # Stage 2: Recency boost (memories recalled in last 7 days, recall_count > 0)
            now = datetime.utcnow()
            seven_days_ago = now - timedelta(days=7)
            
            recently_recalled = []
            for m in candidates:
                if m.get("is_pinned") == 1:
                    continue  # Already in Stage 1
                
                last_recalled = m.get("last_recalled_at")
                recall_count = m.get("recall_count") or 0
                
                if last_recalled and recall_count > 0:
                    try:
                        recalled_dt = datetime.fromisoformat(str(last_recalled))
                        if recalled_dt > seven_days_ago:
                            recently_recalled.append(m)
                    except ValueError:
                        pass

            # Stage 3: Topic relevance
            # Use LLMCore.complete_structured() to extract topics from current_message
            extracted_topics = []
            try:
                llm = get_llm_core()
                topic_prompt = "Extract a list of distinct, general topic keywords (e.g., family, work, health, hobby) related to the following user message."
                output_schema = {
                    "type": "object",
                    "properties": {
                        "topics": {
                            "type": "array",
                            "items": {"type": "string"}
                        }
                    },
                    "required": ["topics"]
                }
                result = await llm.complete_structured(
                    system_prompt=topic_prompt,
                    messages=[{"role": "user", "content": current_message}],
                    output_schema=output_schema,
                    temperature=0.0
                )
                extracted_topics = [t.strip().lower() for t in result.get("topics", [])]
            except Exception as e:
                logger.error("Failed to extract topics for retrieval: %s", e)

            # Score candidates not yet included in Stage 1 or 2
            scored_candidates = []
            included_ids = {m["chroma_id"] for m in pinned + recently_recalled}

            for m in candidates:
                if m["chroma_id"] in included_ids:
                    continue

                salience = float(m.get("salience") or 0.0)
                decay_factor = float(m.get("decay_factor") or 1.0)
                
                # Check for tag matches
                tag_match = False
                tags = [t.strip().lower() for t in (m.get("tags") or [])]
                for tag in tags:
                    if tag in extracted_topics:
                        tag_match = True
                        break
                
                tag_match_bonus = 2.0 if tag_match else 1.0
                score = salience * decay_factor * tag_match_bonus
                
                scored_candidates.append((score, m))

            # Sort by score DESC
            scored_candidates.sort(key=lambda x: x[0], reverse=True)
            topic_relevant = [item[1] for item in scored_candidates]

            # Stage 4: Fill remaining slots with highest-salience memories not yet included
            # Create the final prioritized list of selected memories
            selected = []
            selected.extend(pinned)
            
            for m in recently_recalled:
                if len(selected) >= limit:
                    break
                if m not in selected:
                    selected.append(m)

            for m in topic_relevant:
                if len(selected) >= limit:
                    break
                if m not in selected:
                    selected.append(m)

            # If we still have slots left, grab remaining candidates sorted by salience
            if len(selected) < limit:
                remaining = [m for m in candidates if m not in selected]
                remaining.sort(key=lambda x: float(x.get("salience") or 0.0), reverse=True)
                for m in remaining:
                    if len(selected) >= limit:
                        break
                    selected.append(m)

            # Update recall metadata in the database
            retrieved_ids = [m["chroma_id"] for m in selected]
            if retrieved_ids:
                placeholders = ",".join("?" for _ in retrieved_ids)
                now_str = datetime.utcnow().isoformat()
                db.conn.execute(
                    f"""
                    UPDATE memory_index 
                    SET last_recalled_at = ?, recall_count = recall_count + 1 
                    WHERE chroma_id IN ({placeholders})
                    """,
                    (now_str, *retrieved_ids)
                )

            # Return ordered: pinned first, then by relevance score/salience DESC
            # To compute sort key: pinned gets 10.0 bonus
            def sort_key(m: dict) -> float:
                score = 0.0
                if m.get("is_pinned") == 1:
                    score += 10.0
                salience = float(m.get("salience") or 0.0)
                decay = float(m.get("decay_factor") or 1.0)
                score += salience * decay
                return score

            selected.sort(key=sort_key, reverse=True)
            return selected

        except Exception as e:
            logger.error("Failed to retrieve memories: %s", e, exc_info=True)
            return []


# Compatibility wrapper function for context_builder.py
async def retrieve_relevant_memories(
    pair_id: str,
    query_text: str,
    user_id: Optional[str] = None,
    n_results: Optional[int] = None,
    min_similarity: Optional[float] = None,
) -> list[dict]:
    if not user_id:
        return []
    retriever = MemoryRetriever()
    limit = n_results or 12
    # Map context building queries to the retrieve method
    memories = await retriever.retrieve(
        user_id=user_id,
        current_message=query_text,
        conversation_context="",
        limit=limit
    )
    # Map memory_index fields to compatibility layout expected by context_builder.py
    compat_memories = []
    for m in memories:
        compat_memories.append({
            "id": m.get("chroma_id"),
            "content": m.get("content"),
            "emotion_tag": m.get("emotion_tag") or m.get("memory_type") or "",
            "strength": m.get("salience") or 0.5,
            "importance": m.get("salience") or 0.5,
            "emotional_weight": m.get("salience") or 0.5,
        })
    return compat_memories


def get_memory_count(pair_id: str, user_id: Optional[str] = None) -> int:
    try:
        row = db.conn.execute("SELECT COUNT(*) as count FROM memory_index WHERE pair_id = ? AND archived = 0", (pair_id,)).fetchone()
        return row["count"] if row else 0
    except Exception:
        return 0


def delete_memory(pair_id: str, memory_id: str, user_id: Optional[str] = None) -> bool:
    try:
        db.conn.execute("DELETE FROM memory_index WHERE pair_id = ? AND (chroma_id = ? OR id = ?)", (pair_id, memory_id, memory_id))
        return True
    except Exception:
        return False


def update_memory_document(
    pair_id: str,
    memory_id: str,
    *,
    content: str,
    title: Optional[str] = None,
    user_id: Optional[str] = None,
) -> bool:
    try:
        if title:
            db.conn.execute(
                "UPDATE memory_index SET content = ?, title = ? WHERE pair_id = ? AND (chroma_id = ? OR id = ?)",
                (content, title, pair_id, memory_id, memory_id)
            )
        else:
            db.conn.execute(
                "UPDATE memory_index SET content = ? WHERE pair_id = ? AND (chroma_id = ? OR id = ?)",
                (content, pair_id, memory_id, memory_id)
            )
        return True
    except Exception:
        return False


def clear_all_memories(pair_id: str) -> bool:
    try:
        db.conn.execute("DELETE FROM memory_index WHERE pair_id = ?", (pair_id,))
        return True
    except Exception:
        return False


def format_memories_for_prompt(memories: list[dict]) -> str:
    if not memories:
        return ""
    lines = []
    for memory in memories:
        emotion = f" [{memory['emotion_tag']}]" if memory.get("emotion_tag") else ""
        title = memory.get("title") or "Episode"
        lines.append(f"- {title}{emotion}: {memory['content']}")
    return "\n".join(lines)
