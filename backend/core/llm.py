# =============================================================================
# core/llm.py — LLM Core Interface (Groq API Bridge)
# =============================================================================

import asyncio
import json
import logging
import re
from typing import Optional, Any

import httpx

from config import Settings, settings
from memory.store import db

logger = logging.getLogger(__name__)


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
    def __init__(self, config: Settings):
        self.config = config
        self.api_key = config.GROQ_API_KEY
        self.base_url = config.GROQ_BASE_URL or "https://api.groq.com/openai/v1"
        self.model = config.GROQ_MODEL or "llama-3.1-70b-versatile"
        self.environment = config.ENVIRONMENT or "development"

    async def complete(
        self,
        system_prompt: str,
        messages: list[dict],
        temperature: float = 0.85,
        max_tokens: int = 400,
        response_format: Optional[dict] = None
    ) -> str:
        """
        Sends a request to Groq API with retries on rate limit.
        Logs token usage to stdout in development.
        Returns only the text content of the response.
        Raises LLMError on unrecoverable failure.
        """
        if not self.api_key:
            raise LLMError("GROQ_API_KEY is not configured in settings")

        payload = {
            "model": self.model,
            "temperature": temperature,
            "max_tokens": max_tokens,
            "messages": [
                {"role": "system", "content": system_prompt},
                *messages,
            ],
            # Stop sequences: prevent generating user turn continuations
            "stop": ["User:", "Human:", "\nUser:", "\nHuman:"],
        }

        if response_format:
            payload["response_format"] = response_format

        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }

        retries = 3
        delay = 1.0

        for attempt in range(retries + 1):
            try:
                async with httpx.AsyncClient(timeout=30.0) as client:
                    response = await client.post(
                        f"{self.base_url}/chat/completions",
                        headers=headers,
                        json=payload,
                    )

                if response.status_code == 429:
                    raise LLMRateLimitError("Groq API returned HTTP 429 Rate Limit Exceeded")
                if response.status_code == 401:
                    raise LLMError("Groq API key is invalid (HTTP 401)")
                if response.status_code >= 400 and response.status_code < 500:
                    logger.error(f"Groq API client error: HTTP {response.status_code} - {response.text}")
                    raise LLMError(f"Groq API client error: HTTP {response.status_code} - {response.text}")
                if response.status_code >= 500:
                    raise LLMError(f"Groq server error: HTTP {response.status_code}")

                response.raise_for_status()
                data = response.json()

                # Log token usage to stdout in development
                if self.environment == "development":
                    usage = data.get("usage", {})
                    prompt_tokens = usage.get("prompt_tokens", "?")
                    completion_tokens = usage.get("completion_tokens", "?")
                    total_tokens = usage.get("total_tokens", "?")
                    print(
                        f"[LLM Token Usage] Prompt: {prompt_tokens} | "
                        f"Completion: {completion_tokens} | Total: {total_tokens}"
                    )

                content = data["choices"][0]["message"]["content"]
                return content

            except LLMRateLimitError as e:
                if attempt == retries:
                    raise LLMError(f"Rate limit exceeded after {retries} retries: {e}") from e
                logger.warning(
                    "Rate limit hit on attempt %d/%d. Retrying in %.1fs...",
                    attempt + 1, retries + 1, delay
                )
                await asyncio.sleep(delay)
                delay *= 2.0
            except httpx.TimeoutException as e:
                raise LLMError(f"Groq API timed out: {e}") from e
            except httpx.HTTPStatusError as e:
                raise LLMError(f"Groq API HTTP error: {e}") from e
            except Exception as e:
                if not isinstance(e, LLMError):
                    raise LLMError(f"Unexpected error calling Groq API: {e}") from e
                raise e

    async def complete_structured(
        self,
        system_prompt: str,
        messages: list[dict],
        output_schema: dict,  # JSON schema
        temperature: float = 0.3
    ) -> dict:
        """
        Same as complete() but appends "respond only in valid JSON matching this schema: {output_schema}"
        Parses and validates the response.
        Returns the parsed dict.
        """
        schema_instruction = f"respond only in valid JSON matching this schema: {json.dumps(output_schema)}"
        structured_prompt = f"{system_prompt}\n\n{schema_instruction}"

        # We pass json_object response format to enforce JSON mode
        response_text = await self.complete(
            system_prompt=structured_prompt,
            messages=messages,
            temperature=temperature,
            max_tokens=1000,
            response_format={"type": "json_object"}
        )

        try:
            cleaned_text = response_text.strip()
            # Clean markdown code fences if model wrapped response in ```json ... ```
            if cleaned_text.startswith("```"):
                cleaned_text = cleaned_text.strip("`")
                if cleaned_text.startswith("json"):
                    cleaned_text = cleaned_text[4:]
            cleaned_text = cleaned_text.strip()

            parsed_data = json.loads(cleaned_text)
            return parsed_data
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
        names = db.list_companion_names()
        for name in names:
            labels.add(name)
            labels.add(f"partner_{name.lower()}")
    except Exception:
        labels.add(settings.DEFAULT_CHARACTER)
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
        # Check if it was an LLMError, re-raise it
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
        return {"status": "ok", "model": settings.LLM_MODEL, "reply": reply}
    except Exception as e:
        return {"status": "error", "error": str(e)}
