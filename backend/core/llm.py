# ═══════════════════════════════════════════════════════════════════
# FILE: backend/core/llm.py
# PURPOSE: Groq API client with retry, streaming, and structured output support.
# CONTEXT: Used by chat API (streaming) and all background jobs (sync).
# ═══════════════════════════════════════════════════════════════════

import asyncio
import json
import logging
import re
from typing import Optional, Any

from groq import Groq, AsyncGroq
from config import settings

logger = logging.getLogger(__name__)

# Mock/Stub db variable for compatibility
db = None


# ---------------------------------------------------------------------------
# Custom Exceptions
# ---------------------------------------------------------------------------

class LLMError(Exception):
    """Base exception for all LLM core errors."""
    pass


class LLMRateLimitError(LLMError):
    """Raised specifically when Groq API returns a rate limit error (HTTP 429)."""
    pass


class LLMParseError(LLMError):
    """Raised when structured response parsing or validation fails."""
    pass


# ---------------------------------------------------------------------------
# LLMCore Class
# ---------------------------------------------------------------------------

class LLMCore:
    def __init__(self, config: Optional[Any] = None):
        self.config = config or settings
        api_key = getattr(self.config, "GROQ_API_KEY", settings.GROQ_API_KEY)
        self.client = Groq(api_key=api_key)
        self.async_client = AsyncGroq(api_key=api_key)
        
        # Keep old attribute names for backwards compatibility
        self.api_key = api_key
        self.model = getattr(self.config, "GROQ_MODEL", settings.GROQ_CHAT_MODEL)
        self.environment = getattr(self.config, "ENVIRONMENT", "development")
    
    async def stream(
        self,
        system_prompt: str,
        messages: list[dict],
        model: str | None = None,
        temperature: float | None = None
    ):
        """
        Yields text chunks from Groq streaming response.
        
        CRITICAL: Strips <thought>...</thought> blocks from stream.
        The model's private reasoning must never reach the client.
        
        Stripping logic:
        - Buffer incoming chunks
        - When <thought> detected: enter suppression mode
        - When </thought> detected: exit suppression mode, flush buffer
        - Outside suppression: yield chunk immediately
        - Handle edge cases: tags split across chunks
        
        Use settings.GROQ_CHAT_MODEL if model not specified.
        Use settings.LLM_TEMPERATURE if temperature not specified.
        Retry up to 3 times on rate limit (429) with 2s backoff.
        """
        chat_model = model or settings.GROQ_CHAT_MODEL
        temp = temperature if temperature is not None else settings.LLM_TEMPERATURE
        
        formatted_messages = [
            {"role": "system", "content": system_prompt},
            *messages
        ]
        
        retries = 3
        delay = 2.0
        response_stream = None
        
        for attempt in range(retries + 1):
            try:
                response_stream = await self.async_client.chat.completions.create(
                    model=chat_model,
                    messages=formatted_messages,
                    temperature=temp,
                    stream=True
                )
                break
            except Exception as e:
                import groq
                is_rate_limit = isinstance(e, groq.RateLimitError) or (hasattr(e, "status_code") and e.status_code == 429)
                if is_rate_limit:
                    if attempt == retries:
                        logger.error("Rate limit exceeded after %d retries in stream.", retries)
                        raise LLMRateLimitError("Groq API rate limit exceeded") from e
                    logger.warning("Rate limit hit in stream. Retrying in %.1fs...", delay)
                    await asyncio.sleep(delay)
                    delay *= 2.0
                else:
                    logger.error("Groq stream API call failed: %s", e)
                    raise LLMError(f"Groq API call failed: {e}") from e

        if not response_stream:
            raise LLMError("Failed to initiate Groq response stream.")

        buffer = ""
        in_thought = False
        
        async for chunk in response_stream:
            delta = chunk.choices[0].delta.content
            if not delta:
                continue
            buffer += delta
            
            while buffer:
                if not in_thought:
                    # Look for "<thought>"
                    tag_idx = buffer.find("<thought>")
                    if tag_idx != -1:
                        # Yield everything before the tag
                        pre_tag = buffer[:tag_idx]
                        if pre_tag:
                            yield pre_tag
                        # Enter suppression mode
                        in_thought = True
                        # Remove everything up to end of "<thought>"
                        buffer = buffer[tag_idx + len("<thought>"):]
                    else:
                        # Check for partial prefix of "<thought>" at the end of buffer
                        longest_prefix_len = 0
                        for i in range(1, len("<thought>")):
                            prefix = "<thought>"[:i]
                            if buffer.endswith(prefix):
                                longest_prefix_len = i
                        
                        if longest_prefix_len > 0:
                            to_yield = buffer[:-longest_prefix_len]
                            if to_yield:
                                yield to_yield
                            buffer = buffer[-longest_prefix_len:]
                            break
                        else:
                            yield buffer
                            buffer = ""
                else:
                    # in_thought is True. Look for "</thought>"
                    tag_idx = buffer.find("</thought>")
                    if tag_idx != -1:
                        # Exit suppression mode
                        in_thought = False
                        buffer = buffer[tag_idx + len("</thought>"):]
                    else:
                        # Keep only the last 10 characters to avoid infinite memory leak,
                        # and wait for next chunks to complete the tag.
                        if len(buffer) > 10:
                            buffer = buffer[-10:]
                        break
    
    async def complete(
        self,
        system_prompt: str,
        messages: list[dict],
        model: str | None = None,
        temperature: float = 0.3,
        max_tokens: int = 400,
        response_format: Optional[dict] = None
    ) -> str:
        """
        Non-streaming completion. Returns full response text.
        Strips <thought> tags from result.
        Used by background jobs, extractors, proactive engine.
        """
        chat_model = model or settings.GROQ_CHAT_MODEL
        formatted_messages = [
            {"role": "system", "content": system_prompt},
            *messages
        ]
        
        retries = 3
        delay = 2.0
        response = None
        
        for attempt in range(retries + 1):
            try:
                payload = {
                    "model": chat_model,
                    "messages": formatted_messages,
                    "temperature": temperature,
                    "max_tokens": max_tokens
                }
                if response_format:
                    payload["response_format"] = response_format
                    
                response = await self.async_client.chat.completions.create(**payload)
                break
            except Exception as e:
                import groq
                is_rate_limit = isinstance(e, groq.RateLimitError) or (hasattr(e, "status_code") and e.status_code == 429)
                if is_rate_limit:
                    if attempt == retries:
                        logger.error("Rate limit exceeded after %d retries in complete.", retries)
                        raise LLMRateLimitError("Groq API rate limit exceeded") from e
                    logger.warning("Rate limit hit in complete. Retrying in %.1fs...", delay)
                    await asyncio.sleep(delay)
                    delay *= 2.0
                else:
                    logger.error("Groq complete API call failed: %s", e)
                    raise LLMError(f"Groq API call failed: {e}") from e

        if not response:
            raise LLMError("Failed to obtain Groq completion response.")

        content = response.choices[0].message.content or ""
        
        # Log token usage to stdout in development
        if self.environment == "development":
            usage = getattr(response, "usage", None)
            if usage:
                prompt_tokens = getattr(usage, "prompt_tokens", "?")
                completion_tokens = getattr(usage, "completion_tokens", "?")
                total_tokens = getattr(usage, "total_tokens", "?")
                print(
                    f"[LLM Token Usage] Prompt: {prompt_tokens} | "
                    f"Completion: {completion_tokens} | Total: {total_tokens}"
                )

        # Strip <thought>...</thought> tags from result
        content = re.sub(r'<thought>.*?</thought>', '', content, flags=re.DOTALL)
        if "<thought>" in content:
            content = content.split("<thought>")[0]
            
        return content
    
    async def complete_json(
        self,
        system_prompt: str,
        messages: list[dict],
        model: str | None = None
    ) -> dict | list:
        """
        Completion that returns parsed JSON.
        Appends "Respond ONLY with valid JSON, no markdown, no explanation."
        to system prompt.
        Parses response. On failure: returns {} or [].
        Always uses temperature=0.1 (deterministic for structured output).
        """
        chat_model = model or settings.GROQ_CHAT_MODEL
        json_system_prompt = f"{system_prompt}\nRespond ONLY with valid JSON, no markdown, no explanation."
        
        try:
            response_text = await self.complete(
                system_prompt=json_system_prompt,
                messages=messages,
                model=chat_model,
                temperature=0.1,
                max_tokens=1000,
                response_format={"type": "json_object"}
            )
            cleaned_text = response_text.strip()
            if cleaned_text.startswith("```"):
                cleaned_text = cleaned_text.strip("`").strip()
                if cleaned_text.startswith("json"):
                    cleaned_text = cleaned_text[4:].strip()
            
            parsed = json.loads(cleaned_text)
            return parsed
        except Exception as e:
            logger.error("complete_json failed: %s", e)
            try:
                if 'response_text' in locals() and response_text.strip().startswith('['):
                    return []
            except Exception:
                pass
            return {}

    async def complete_structured(
        self,
        system_prompt: str,
        messages: list[dict],
        output_schema: dict,
        temperature: float = 0.3
    ) -> dict:
        """
        Backward compatibility helper matching schema expectation.
        Delegates to complete with response_format json_object and appends schema instruction.
        """
        schema_instruction = f"respond only in valid JSON matching this schema: {json.dumps(output_schema)}"
        structured_prompt = f"{system_prompt}\n\n{schema_instruction}"

        response_text = await self.complete(
            system_prompt=structured_prompt,
            messages=messages,
            temperature=temperature,
            max_tokens=1000,
            response_format={"type": "json_object"}
        )

        try:
            cleaned_text = response_text.strip()
            if cleaned_text.startswith("```"):
                cleaned_text = cleaned_text.strip("`").strip()
                if cleaned_text.startswith("json"):
                    cleaned_text = cleaned_text[4:].strip()
            return json.loads(cleaned_text)
        except json.JSONDecodeError as e:
            raise LLMParseError(f"Failed to parse structured JSON response: {e}. Raw response: {response_text}") from e


# ---------------------------------------------------------------------------
# Compatibility Layers and Helpers
# ---------------------------------------------------------------------------

llm_core = None

def get_llm_core() -> LLMCore:
    """Singleton getter for LLMCore."""
    global llm_core
    if llm_core is None:
        llm_core = LLMCore(settings)
    return llm_core


def _clean_response(text: str) -> str:
    """
    Strips role labels, markdown formatting, quotes and multiple blank lines.
    Preserved to keep frontend displays perfectly clean.
    """
    if not text:
        return ""

    cleaned = text.strip()

    # Remove a leaked speaker prefix if the model echoed the role label.
    labels = "|".join(re.escape(label) for label in _known_speaker_labels())
    cleaned = re.sub(rf'^(?:{labels})\s*:\s*', '', cleaned, flags=re.IGNORECASE)

    # Remove markdown bold and italic
    cleaned = re.sub(r'\*\*(.+?)\*\*', r'\1', cleaned)  # **bold** → bold
    cleaned = re.sub(r'\*(.+?)\*', r'\1', cleaned)        # *italic* → italic

    # Remove markdown headers
    cleaned = re.sub(r'^#{1,6}\s+', '', cleaned, flags=re.MULTILINE)

    # Remove markdown bullet points
    cleaned = re.sub(r'^\s*[-*•]\s+', '', cleaned, flags=re.MULTILINE)

    # Strip surrounding quotes if the entire response is quoted
    if (cleaned.startswith('"') and cleaned.endswith('"')) or \
       (cleaned.startswith("'") and cleaned.endswith("'")):
        cleaned = cleaned[1:-1]

    # Collapse multiple blank lines into one
    cleaned = re.sub(r'\n{3,}', '\n\n', cleaned)

    return cleaned.strip()


def _known_speaker_labels() -> list[str]:
    labels = {"Assistant", "AI", "Partner"}
    try:
        names = db.list_partner_names()
        for name in names:
            labels.add(name)
            labels.add(f"partner_{name.lower()}")
    except Exception:
        labels.add(settings.DEFAULT_CHARACTER if hasattr(settings, "DEFAULT_CHARACTER") else "nova")
    return sorted(labels, key=len, reverse=True)


async def generate_reply(
    messages: list[dict],
    system_prompt: str,
    temperature: Optional[float] = None,
    max_tokens: Optional[int] = None,
    model: Optional[str] = None,
) -> str:
    """
    Compatibility wrapper delegating to get_llm_core().complete().
    """
    core = get_llm_core()
    
    # Save the original model so we don't bleed states if model is overridden
    original_model = core.model
    if model:
        core.model = model
    
    try:
        temp = temperature if temperature is not None else settings.LLM_TEMPERATURE
        tokens = max_tokens or settings.LLM_MAX_TOKENS
        
        raw_reply = await core.complete(
            system_prompt=system_prompt,
            messages=messages,
            temperature=temp,
            max_tokens=tokens
        )
        
        cleaned = _clean_response(raw_reply)
        if not cleaned:
            return "..."
        return cleaned
    except Exception as e:
        logger.error("generate_reply wrapper failed: %s", e)
        if isinstance(e, LLMError):
            raise e
        raise LLMError(str(e)) from e
    finally:
        if model:
            core.model = original_model


async def check_llm_health() -> dict:
    """
    Compatibility health check.
    """
    try:
        reply = await generate_reply(
            messages=[{"role": "user", "content": "say 'ok'"}],
            system_prompt="Reply with only the word 'ok'.",
            max_tokens=5,
            temperature=0.0,
        )
        model_name = getattr(settings, "GROQ_CHAT_MODEL", "llama-3.3-70b-versatile")
        return {"status": "ok", "model": model_name, "reply": reply}
    except Exception as e:
        return {"status": "error", "error": str(e)}
