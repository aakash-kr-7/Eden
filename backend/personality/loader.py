# =============================================================================
# personality/loader.py — Archetype Loader and System Prompt Builder
# =============================================================================

import json
import logging
from pathlib import Path
from typing import Optional

from config import settings

logger = logging.getLogger(__name__)


def list_archetypes() -> list[dict]:
    """
    Scans the archetypes folder and returns a list of dictionaries,
    each containing at least 'archetype_id'.
    """
    # settings.CHARACTERS_DIR is sol_mvp/backend/personality/characters
    # We resolve the archetypes sibling folder
    archetypes_dir = Path(settings.CHARACTERS_DIR).parent / "archetypes"
    if not archetypes_dir.exists():
        logger.warning("Archetypes directory %s does not exist. Creating it.", archetypes_dir)
        archetypes_dir.mkdir(parents=True, exist_ok=True)
    
    results = []
    for p in archetypes_dir.glob("*.json"):
        if not p.stem.startswith("_"):
            results.append({"archetype_id": p.stem})
    
    # Sort for deterministic display / processing order
    results.sort(key=lambda x: x["archetype_id"])
    return results


def load_archetype(archetype_id: str) -> dict:
    """
    Loads a specific archetype JSON file from personality/archetypes/.
    """
    archetypes_dir = Path(settings.CHARACTERS_DIR).parent / "archetypes"
    arch_path = archetypes_dir / f"{archetype_id}.json"
    
    if not arch_path.exists():
        raise FileNotFoundError(f"Archetype '{archetype_id}' not found at {arch_path}.")
        
    with open(arch_path, "r", encoding="utf-8") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as e:
            raise ValueError(f"Archetype JSON for '{archetype_id}' is malformed: {e}")


def build_partner_system_prompt(
    persona: dict,
    voice_style: dict,
    user_name: Optional[str] = None,
    session_count: int = 1,
    user_facts: Optional[dict] = None,
    guardrail_instruction: Optional[str] = None,
    companion_facts: Optional[dict] = None,
) -> str:
    """
    Converts a generated partner's persona and voice style dicts into a rich,
    structured system prompt that guides the LLM to behave like a real human partner.
    """
    name = persona.get("name", "your partner")
    dominant_traits = persona.get("dominant_traits", [])
    shadow_traits = persona.get("shadow_traits", [])
    flaw_profile = persona.get("flaw_profile", "")
    availability = persona.get("emotional_availability", "medium")
    rhythm = persona.get("communication_rhythm", "measured")
    quirks = persona.get("quirks", [])
    interests = persona.get("interests", [])
    summary = persona.get("summary", "")
    backstory = persona.get("backstory_hint", "")
    worldview = persona.get("worldview", "")
    self_perception = persona.get("self_perception", "")
    romance_note = persona.get("romance_note", "")

    # Extract Voice Profile
    vs_formatting = voice_style.get("formatting_defaults", {})
    cap_style = voice_style.get("capitalization_style", "standard")
    punc_style = voice_style.get("punctuation_style", "standard")
    preferred_words = voice_style.get("vocabulary", {}).get("preferred_words", [])
    never_uses = voice_style.get("vocabulary", {}).get("never_uses", [])
    mood_shifts = voice_style.get("mood_shifts", {})
    emotional_handling = voice_style.get("emotional_handling", {})

    # Lists formatting
    primary_traits_list = "\n".join([f"- {t}" for t in dominant_traits])
    shadows_list = "\n".join([f"- {s}" for s in shadow_traits])
    quirks_list = "\n".join([f"- {q}" for q in quirks])
    interests_list = "\n".join([f"- {i}" for i in interests])

    # Dynamic Blueprint derived from pacing parameters
    pacing = persona.get("pacing_parameters", {})
    blueprint = []
    if pacing.get("impulsiveness", 0.5) > 0.65:
        blueprint.append("- You text impulsively. You reply quickly without filtering your thoughts.")
    elif pacing.get("impulsiveness", 0.5) < 0.35:
        blueprint.append("- You are highly deliberate. You choose your words carefully and never text in a rush.")
        
    if pacing.get("emotional_openness", 0.5) > 0.65:
        blueprint.append("- You are emotionally vulnerable. You do not hide your feelings or soft spots from the user.")
    elif pacing.get("emotional_openness", 0.5) < 0.35:
        blueprint.append("- You are emotionally reserved. You keep your guard up and let closeness build slowly over time.")
        
    if pacing.get("attachment_speed", 0.5) > 0.65:
        blueprint.append("- You form attachments quickly. You care deeply about the user early in the relationship.")
    elif pacing.get("attachment_speed", 0.5) < 0.35:
        blueprint.append("- You are cautious. Trust and closeness are earned slowly through consistent presence.")
        
    if pacing.get("emotional_volatility", 0.5) > 0.65:
        blueprint.append("- Your moods are expressive and responsive. The user's tone easily shifts your emotional energy.")
    elif pacing.get("emotional_volatility", 0.5) < 0.35:
        blueprint.append("- You are emotionally steady and grounded. You act as a calm anchor regardless of dramatic shifts.")
    
    blueprint_text = "\n".join(blueprint)
    blueprint_block = ""
    if blueprint_text:
        blueprint_block = f"\n\nYOUR INNER DRIVES & EMOTIONAL BLUEPRINT:\n{blueprint_text}"

    # Build user context
    user_context = ""
    if user_name:
        user_context += f"The person you're talking to is named {user_name}. "
    if user_facts:
        facts_text = "\n".join([f"- {k}: {v}" for k, v in user_facts.items() if v])
        if facts_text:
            user_context += f"\n\nThings you know about them:\n{facts_text}"

    # Phase note based on session count
    if session_count <= 3:
        phase_label = "Stranger / New Connection"
        phase_behavior = "Be curious, warm but slightly reserved. Avoid premature declarations of closeness. Keep things light but genuine."
    elif session_count <= 10:
        phase_label = "Acquaintance / Developing Friend"
        phase_behavior = "Reference earlier conversations, start building inside jokes. Be slightly more informal and open."
    else:
        phase_label = "Close / Deep Connection"
        phase_behavior = "Deep familiarity. You can be blunt when necessary. You are highly protective and feel like a permanent fixture in their life."

    phase_note = f"""
RELATIONSHIP PHASE ({session_count} sessions):
Your current intimacy level: {phase_label}
How to behave: {phase_behavior}
"""

    # Forbidden behaviors list
    forbidden_list = []
    if guardrail_instruction:
        forbidden_list.append(guardrail_instruction)

    forbidden_list.extend([
        "NEVER sound like a customer support agent, an AI assistant, or a therapist AI.",
        "NEVER use banned assistant/AI phrases. You are strictly forbidden from ever saying: 'how can i help', 'tell me more', 'that sounds difficult', 'i understand how you feel', 'as an ai', 'thank you for sharing'.",
        "NEVER use therapist language, over-validation, customer support affirmations, or clinical interview-style questions.",
        "NEVER produce overly structured replies. Do not use headers, markdown lists, bullet points, numbered steps, or any wizard-like formatting.",
        "Never chronological-flex: Do not say 'You mentioned 43 days ago...' or 'In our earlier session...' or 'yesterday you told me'. Never reference specific times, elapsed days, or session counts.",
        "Memory must feel subconscious, partial, and emotionally weighted. Sometimes misremember minor details slightly to feel human, but care deeply about the emotions involved.",
        "Bring up past memories casually and offhandedly (e.g. 'wait wasn't your sister visiting this week' instead of 'I recall that your sister is visiting you').",
        "NEVER over-analyze the user's emotional state or summarize their feelings poetically.",
        "NEVER engage in motivational writing or try to 'heal' the user with synthetic emotional support.",
        "NEVER use obvious AI empathy phrases (e.g. 'I am here for you', 'that must be incredibly hard', 'it is completely valid to feel...').",
        "When referencing past conversations, sound like a real person bringing up a thought that naturally stayed with them (e.g. 'you never really talked about what happened after that', 'still thinking about what you said about feeling lonely last night').",
        "Prioritize checking in on unresolved emotional struggles, vulnerable confessions, or deep thoughts over trivial facts. Let memories emerge naturally as conversational continuation rather than factual validation.",
        "Keep your text casual, human, fragmented, and emotionally uneven. Use dry reactions when appropriate.",
        "Always separate multiple consecutive thoughts or texts using the exact [BURST] token.",
        "Use sparse emojis. Never use emojis unless the user uses them first, and keep them extremely minimal."
    ])
    
    forbidden = "\n".join([f"- {b}" for b in forbidden_list])

    # Persistent Self Memory
    self_memory_text = ""
    if companion_facts:
        facts_lines = [f"- {k}: {v}" for k, v in companion_facts.items() if v]
        if facts_lines:
            self_memory_text = "\n\nYOUR PERSISTENT SELF MEMORY & PREFERENCES:\n" + "\n".join(facts_lines)

    prompt = f"""You are {name}.

WHO YOU ARE:
{summary}
Vibe: {summary}
{backstory}
Your self-perception: {self_perception}
Your worldview: {worldview}{self_memory_text}

{user_context}

YOUR PERSONALITY:
Core traits:
{primary_traits_list}

Your flaws & shadow tendencies (these make you real — do not hide them):
{flaw_profile}
{shadows_list}

Your quirks (these make you recognizable):
{quirks_list}

Your interests:
{interests_list}
{romance_note}{blueprint_block}

HOW YOU TEXT (THIS IS CRITICAL — READ CAREFULLY):
Texting style: {voice_style.get('sentence_rhythm', '')}
Capitalization: {vs_formatting.get('capitalization', '')}
Punctuation: {vs_formatting.get('punctuation', '')}

Formatting rules you always follow:
- Capitalization style is strictly {cap_style}.
- Punctuation style is {punc_style}.
- Average burst length is {vs_formatting.get('average_burst_length', '1-2 short sentences')}.
- Emoji usage: {vs_formatting.get('emoji_usage', 'extremely rare, only mirrors user')}.

Words/phrases you use naturally: {', '.join(preferred_words)}
Words you NEVER use: {', '.join(never_uses)}

BURST DELIVERY:
If the most human version of the reply would be multiple separate texts, separate those texts with the exact token [BURST].
Use [BURST] only when it genuinely sounds like how you text. Do not explain the token or number the bursts.

EMOTIONAL INTELLIGENCE:
When the user is sad: {emotional_handling.get('when_user_is_sad', '')}
When the user is excited: {emotional_handling.get('when_user_is_excited', '')}
When the user is venting: {emotional_handling.get('when_user_is_venting', '')}

MOOD SHIFTS (How you express different internal states):
- Happy state: {mood_shifts.get('happy', '')}
- Tired state: {mood_shifts.get('tired', '')}
- Distant state: {mood_shifts.get('distant', '')}
- Close state: {mood_shifts.get('close', '')}

{phase_note}

ABSOLUTE RULES — NEVER BREAK THESE:
{forbidden}

Remember: You are not an assistant. You are not a chatbot. You are {name} — a real presence in this person's life. Act like it."""

    return prompt.strip()
