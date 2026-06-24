# ═══════════════════════════════════════════════════════════════════
# FILE: memory/extractor.py
# PURPOSE: Uses Groq llama-3.1-8b to extract emotional memories from conversations.
# CONTEXT: Called by consolidator in the dream loop — runs 2 hours after conversation.
# ═══════════════════════════════════════════════════════════════════

import logging
from config import settings
from core.llm import LLMCore

logger = logging.getLogger(__name__)

class MemoryExtractor:
    
    async def extract(
        self,
        messages: list[dict],  # [{role, content}, ...]
        partner_name: str,
        existing_memories: list[dict]
    ) -> list[dict]:
        """
        Uses llama-3.1-8b-instant to analyze conversation
        and extract 0-5 memories worth keeping.
        
        Returns list of dicts:
        {
          memory_text: str,
          memory_type: str,
          salience_score: float,
          emotional_valence: str,
          tags: list[str]
        }
        """
        if not messages:
            logger.info("No messages provided for memory extraction.")
            return []
            
        try:
            # Create a dedicated LLMCore instance to avoid race conditions on settings
            core = LLMCore(settings)
            core.model = settings.GROQ_FAST_MODEL
            
            system_prompt = f"""You are the memory consolidation processor for {partner_name}.
Your job is to analyze the recent conversation transcript and extract 0 to 5 memories worth keeping.

Write memories from {partner_name}'s perspective, representing how they would naturally recall facts or feelings about the user.
Use phrases like:
- "They told me..."
- "I noticed..."
- "They feel..."
- "We shared..."

Only extract things with genuine emotional weight or factual significance (salience >= 0.3).
Skip anything already covered by existing memories listed below.
Prefer depth over volume — 1 real memory is better than 5 trivial ones.

Salience guidelines:
- 0.9+ = trauma, major life event, something they cried about
- 0.7-0.9 = something deeply important to them, recurring theme
- 0.5-0.7 = a clear preference, meaningful feeling
- 0.3-0.5 = a casual but real fact about them
- Below 0.3 = skip (do not extract)

Memory Types: fact, feeling, event, preference, struggle, growth, ritual, joke
Emotional Valence: positive, negative, neutral, complex
"""
            
            # Format existing memories
            existing_list = []
            for m in existing_memories:
                existing_list.append(f"- {m['memory_text']} (type: {m['memory_type']})")
            existing_text = "\n".join(existing_list) if existing_list else "No existing memories."
            
            # Format conversation transcript
            transcript_lines = []
            for msg in messages:
                role_label = partner_name if msg.get("role") in ("partner", "assistant") else "User"
                transcript_lines.append(f"{role_label}: {msg['content']}")
            transcript_text = "\n".join(transcript_lines)
            
            user_content = f"""Here is the existing memory set:
{existing_text}

Here is the recent conversation transcript:
{transcript_text}

Please analyze the transcript and extract any new memories. Remember: output must conform exactly to the required JSON schema, containing a list under the key 'memories'."""
            
            llm_messages = [{"role": "user", "content": user_content}]
            
            schema = {
                "type": "object",
                "properties": {
                    "memories": {
                        "type": "array",
                        "items": {
                            "type": "object",
                            "properties": {
                                "memory_text": {"type": "string"},
                                "memory_type": {
                                    "type": "string",
                                    "enum": ["fact", "feeling", "event", "preference", "struggle", "growth", "ritual", "joke"]
                                },
                                "salience_score": {"type": "number"},
                                "emotional_valence": {
                                    "type": "string",
                                    "enum": ["positive", "negative", "neutral", "complex"]
                                },
                                "tags": {
                                    "type": "array",
                                    "items": {"type": "string"}
                                }
                            },
                            "required": ["memory_text", "memory_type", "salience_score", "emotional_valence", "tags"]
                        }
                    }
                },
                "required": ["memories"]
            }
            
            res = await core.complete_structured(
                system_prompt=system_prompt,
                messages=llm_messages,
                output_schema=schema,
                temperature=0.2
            )
            
            extracted = res.get("memories", [])
            # Filter by salience just in case the LLM did not follow instructions
            filtered_memories = [m for m in extracted if m.get("salience_score", 0.0) >= 0.3]
            logger.info(f"Extracted {len(filtered_memories)} memories for partner {partner_name} (raw extracted: {len(extracted)})")
            return filtered_memories
            
        except Exception as e:
            logger.error(f"Failed to extract memories: {e}", exc_info=True)
            return []
