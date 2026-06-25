# ═══════════════════════════════════════════════════════════════════
# FILE: core/message_analyzer.py
# PURPOSE: Analyzes user messages to influence partner response timing.
# CONTEXT: Used by chat API before calling stream_partner_response_v2.
# ═══════════════════════════════════════════════════════════════════

import logging
from core.llm import get_llm_core
from config import settings

logger = logging.getLogger(__name__)

class MessageAnalyzer:
    
    async def analyze(self, user_message: str) -> dict:
        """
        Analyzes the user's message to determine response characteristics.
        
        Returns:
        {
            "urgency": "instant" | "quick" | "normal" | "thoughtful",
            "tone": "question" | "statement" | "emotional" | "casual",
            "length": "very_short" | "short" | "medium" | "long",
            "requires_thinking": bool,
            "is_question": bool,
            "sentiment": "positive" | "negative" | "neutral" | "vulnerable"
        }
        """
        if not user_message:
            return {
                "urgency": "instant",
                "tone": "casual",
                "length": "very_short",
                "requires_thinking": False,
                "is_question": False,
                "sentiment": "neutral"
            }

        msg_len = len(user_message)
        cleaned_msg = user_message.strip()
        lower_msg = cleaned_msg.lower()

        # 1. Determine urgency
        # urgency:
        # - very_short (<10 chars, no punctuation): "instant"
        # - short (10-30 chars): "quick"
        # - medium (30-100 chars): "normal"
        # - long (100+ chars): "thoughtful"
        has_punctuation = any(char in ".,!?\"';:()[]{}–—-" for char in cleaned_msg)
        if msg_len < 10 and not has_punctuation:
            urgency = "instant"
        elif msg_len <= 30:
            urgency = "quick"
        elif msg_len <= 100:
            urgency = "normal"
        else:
            urgency = "thoughtful"

        # 2. Determine length category
        if msg_len < 10:
            length = "very_short"
        elif msg_len <= 30:
            length = "short"
        elif msg_len <= 100:
            length = "medium"
        else:
            length = "long"

        # 3. Determine tone
        # tone:
        # - ends with ?: "question"
        # - emotional markers (miss, love, sorry, scared, etc): "emotional"
        # - punctuation intensity (!!! ...): "casual"
        # - neutral: "statement"
        emotional_words = [
            "miss", "love", "sorry", "scared", "afraid", "hurt", "sad", "lonely", 
            "happy", "excited", "hate", "worry", "worried", "feel", "fear", "glad", 
            "trust", "insecure", "confused", "warm", "close"
        ]
        
        if cleaned_msg.endswith("?"):
            tone = "question"
        elif any(word in lower_msg for word in emotional_words):
            tone = "emotional"
        elif "!!!" in cleaned_msg or "..." in cleaned_msg:
            tone = "casual"
        else:
            tone = "statement"

        # 4. Determine is_question (ends with ? OR contains question words)
        question_words = {
            "who", "what", "where", "when", "why", "how", "is", "are", 
            "can", "do", "does", "will", "would", "could", "should", 
            "did", "was", "were", "has", "have", "had", "am"
        }
        words = {w.strip(".,!?\"';:()[]{}") for w in lower_msg.split()}
        is_question = cleaned_msg.endswith("?") or not words.isdisjoint(question_words)

        # 5. Call LLM for sentiment and requires_thinking
        # sentiment: positive | negative | neutral | vulnerable
        # requires_thinking: bool
        sentiment = "neutral"
        requires_thinking = is_question

        try:
            llm = get_llm_core()
            model_name = getattr(settings, "GROQ_FAST_MODEL", "llama-3.1-8b-instant")
            
            system_prompt = (
                "Analyze the following user text message. "
                "Classify the sentiment as one of: 'positive', 'negative', 'neutral', 'vulnerable'.\n"
                "- 'positive': happy, excited, proud, warm\n"
                "- 'negative': frustrated, sad, angry, annoyed\n"
                "- 'vulnerable': scared, confused, uncertain, deep/intimate, insecure\n"
                "- 'neutral': matter-of-fact, none of the above\n\n"
                "Determine if the message 'requires_thinking' (true or false):\n"
                "- true if it contains a question, philosophical thoughts, multi-part requests, or complex/deep topics\n"
                "- false if it is a simple statement, a basic reaction (e.g. 'ok', 'cool', 'haha'), or casual greeting\n\n"
                "Respond ONLY with a JSON object containing keys 'sentiment' and 'requires_thinking'."
            )
            
            response = await llm.complete_json(
                system_prompt=system_prompt,
                messages=[{"role": "user", "content": user_message}],
                model=model_name
            )
            
            if isinstance(response, dict):
                sentiment = response.get("sentiment", "neutral").lower().strip()
                if sentiment not in ["positive", "negative", "neutral", "vulnerable"]:
                    sentiment = "neutral"
                
                requires_thinking_val = response.get("requires_thinking")
                if isinstance(requires_thinking_val, bool):
                    requires_thinking = requires_thinking_val
                elif isinstance(requires_thinking_val, str):
                    requires_thinking = requires_thinking_val.lower().strip() == "true"
                    
        except Exception as e:
            logger.error(f"MessageAnalyzer LLM analysis failed: {e}. Falling back to default heuristics.")

        return {
            "urgency": urgency,
            "tone": tone,
            "length": length,
            "requires_thinking": requires_thinking,
            "is_question": is_question,
            "sentiment": sentiment
        }
