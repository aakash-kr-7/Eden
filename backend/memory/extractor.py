import logging
from core.llm import get_llm_core
from memory.store import db, memory_store

logger = logging.getLogger(__name__)

class MemoryExtractor:
    async def extract(
        self,
        messages: list[dict],
        existing_memories: list[dict],
        partner_name: str
    ) -> list[dict]:
        # Formulate conversation text
        conversation_text = ""
        for msg in messages:
            role_label = "User" if msg.get("role") == "user" else partner_name
            content = msg.get("content") or ""
            conversation_text += f"{role_label}: {content}\n"

        # Formulate existing memories text for deduplication
        existing_text = ""
        if existing_memories:
            existing_text = "\nExisting memories (DO NOT extract these again):\n"
            for m in existing_memories:
                existing_text += f"- {m.get('content')}\n"

        system_prompt = f"""You are the memory extraction engine for {partner_name}, a companion.
Your goal is to extract key memories from the conversation that {partner_name} would personally remember about the user or their interaction.
Memories should be emotionally weighted, natural language statements written from {partner_name}'s perspective (e.g. "I remember that they...", "They told me...", or "We joked about...").

Analyze the conversation and extract up to 5 memories. Quality is highly prioritized over quantity; if nothing significant occurred, return an empty list.

Identify:
1. Facts the user revealed (job, family, location, etc.)
2. Emotional moments (what the user felt, what they struggled with)
3. Preferences (what they like, dislike, care about)
4. Growth moments (things they realized, decisions they made)
5. Events (things that happened in their life)
6. Inside jokes or shared references that emerged

Rules:
- Deduplicate: Skip any information already captured in the existing memories listed below.
- Salience guidelines:
  - 0.9+: something they cried about, a trauma, a major life event
  - 0.7-0.9: something they care deeply about, a recurring theme
  - 0.5-0.7: a preference, a habit, a mild feeling
  - 0.3-0.5: a casual fact, a passing comment
  - Below 0.3: skip, not worth storing
"""

        output_schema = {
            "type": "object",
            "properties": {
                "memories": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "content": {
                                "type": "string",
                                "description": "The natural language description of the memory written from the companion's perspective."
                            },
                            "memory_type": {
                                "type": "string",
                                "enum": ["fact", "emotion", "preference", "growth", "event", "joke", "other"]
                            },
                            "salience": {
                                "type": "number",
                                "description": "The salience score from 0.0 to 1.0."
                            },
                            "emotional_valence": {
                                "type": "string",
                                "enum": ["positive", "negative", "neutral"]
                            },
                            "tags": {
                                "type": "array",
                                "items": {
                                    "type": "string"
                                },
                                "description": "Short topic keywords related to this memory (e.g., ['family', 'job', 'fear'])."
                            }
                        },
                        "required": ["content", "memory_type", "salience", "emotional_valence", "tags"]
                    }
                }
            },
            "required": ["memories"]
        }

        user_content = f"Conversation:\n{conversation_text}\n{existing_text}"
        
        try:
            llm = get_llm_core()
            result = await llm.complete_structured(
                system_prompt=system_prompt,
                messages=[{"role": "user", "content": user_content}],
                output_schema=output_schema,
                temperature=0.2
            )
            extracted_memories = result.get("memories", [])
            # Filter out low salience memories (below 0.3) and limit to 5
            valid_memories = [m for m in extracted_memories if m.get("salience", 0.0) >= 0.3]
            return valid_memories[:5]
        except Exception as e:
            logger.error("Failed memory extraction: %s", e, exc_info=True)
            return []


async def extract_and_save(user_id: str, pair_id: str, companion_id: str, conversation_id: str) -> None:
    try:
        pending_messages = db.get_unextracted_messages(user_id, pair_id=pair_id, conversation_id=conversation_id)
        if not pending_messages:
            return

        preferences = db.get_or_create_user_preferences(user_id)
        if not int(preferences.get("allow_memory_storage") or 0):
            db.mark_messages_extracted([int(message["id"]) for message in pending_messages])
            return

        message_ids = [int(message["id"]) for message in pending_messages]
        
        # Get existing memories for deduplication
        existing = await memory_store.get_all(user_id, limit=100)
        
        # Get companion name
        partner = db.get_partner(user_id) or {}
        partner_name = partner.get("name", "Companion")
        
        extractor = MemoryExtractor()
        extracted = await extractor.extract(
            messages=pending_messages,
            existing_memories=existing,
            partner_name=partner_name
        )
        
        with db.transaction():
            for m in extracted:
                await memory_store.add(user_id, m)
            
            db.mark_messages_extracted(message_ids)
            
        logger.info("Successfully extracted %d memories for user %s", len(extracted), user_id)
    except Exception as e:
        logger.error("Failed to run extract_and_save: %s", e, exc_info=True)
