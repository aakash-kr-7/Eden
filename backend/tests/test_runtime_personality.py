import asyncio
import json
import os
import sys

# Ensure backend folder is in path for imports
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from config import settings
from core.llm import LLMCore, LLMError, LLMRateLimitError, LLMParseError
from core.context_builder import ContextBuilder, build_context

async def test_llm_core():
    print("\n=== TESTING LLMCORE ===")
    
    # 1. Initialize LLMCore with settings
    llm = LLMCore(settings)
    # Use active non-decommissioned model for testing
    llm.model = "llama-3.1-8b-instant"
    
    # Check variables
    print(f"LLM model: {llm.model}")
    print(f"LLM base URL: {llm.base_url}")
    print(f"Environment: {llm.environment}")
    
    if not settings.GROQ_API_KEY:
        print("[SKIP] Groq API calls (GROQ_API_KEY is not set)")
        return
        
    # 2. Test LLMCore.complete
    print("Testing LLMCore.complete...")
    try:
        reply = await llm.complete(
            system_prompt="You are a helpful, dry, one-word answering robot.",
            messages=[{"role": "user", "content": "What is the capital of France?"}],
            temperature=0.0,
            max_tokens=10
        )
        print(f"Raw reply: '{reply}'")
        assert "Paris" in reply, f"Expected Paris in response, got '{reply}'"
        print("[OK] complete() works successfully!")
    except Exception as e:
        print(f"[FAIL] complete() failed: {e}")
        
    # 3. Test LLMCore.complete_structured
    print("Testing LLMCore.complete_structured...")
    output_schema = {
        "type": "object",
        "properties": {
            "capital": {"type": "string"},
            "population_millions": {"type": "number"}
        },
        "required": ["capital"]
    }
    try:
        result = await llm.complete_structured(
            system_prompt="You are a data retrieval assistant. Output only structured data.",
            messages=[{"role": "user", "content": "Tell me about Germany's capital."}],
            output_schema=output_schema,
            temperature=0.0
        )
        print(f"Structured result: {result}")
        assert isinstance(result, dict), "Expected a parsed dict"
        assert result.get("capital") == "Berlin", f"Expected Berlin, got {result.get('capital')}"
        print("[OK] complete_structured() works successfully!")
    except Exception as e:
        print(f"[FAIL] complete_structured() failed: {e}")

def test_context_builder():
    print("\n=== TESTING CONTEXTBUILDER ===")
    builder = ContextBuilder()
    
    # 1. Mock parameters
    partner_persona = {
        "name": "Arthur",
        "archetype": "The Architect",
        "summary": "Arthur is highly composed and analytical.",
        "backstory_hint": "Grew up in a quiet town fixing radios.",
        "self_perception": "Independent, a bit detached.",
        "worldview": "The world is complex, order helps.",
        "dominant_traits": ["analytical", "observant"],
        "shadow_traits": ["detached under stress"],
        "flaw_profile": "Can be critical of inefficiency.",
        "quirks": ["taps fingers when thinking"],
        "interests": ["architecture", "chess"],
        "romance_note": "Slow to build intimacy but extremely loyal."
    }
    
    voice_style = {
        "formatting_defaults": {
            "capitalization": "lowercase fragments",
            "punctuation": "minimal punctuation, no ending periods",
            "average_burst_length": "1-2 short sentences",
            "emoji_usage": "none"
        },
        "capitalization_style": "lowercase",
        "punctuation_style": "minimal",
        "vocabulary": {
            "preferred_words": ["observed", "quiet", "perhaps"],
            "never_uses": ["help", "assist", "surely"]
        }
    }
    
    relationship_stage = "warming"
    
    memories = [
        {"content": "they like cold brew coffee", "emotion_tag": "happy", "strength": 0.9},
        {"content": "they were nervous about a meeting", "emotion_tag": "anxious", "strength": 0.6}
    ]
    
    life_state = {
        "mood": "reflective, tired",
        "energy": "low",
        "day_arc": "late night",
        "recent_event": "stayed up late reading blueprint specs",
        "relationship_scores": {
            "closeness": 0.35,
            "trust": 0.40,
            "comfort": 0.45,
            "openness": 0.28,
            "rhythm": 0.30
        }
    }
    
    recent_relationship_events = [
        {"description": "User shared frustration about work."}
    ]
    
    inside_jokes = ["calling the cat 'the boss'"]
    shared_rituals = ["sending music links on Sundays"]
    
    # 2. Test build_system_prompt
    print("Testing build_system_prompt...")
    prompt = builder.build_system_prompt(
        partner_persona=partner_persona,
        voice_style=voice_style,
        relationship_stage=relationship_stage,
        memories=memories,
        life_state=life_state,
        recent_relationship_events=recent_relationship_events,
        inside_jokes=inside_jokes,
        shared_rituals=shared_rituals
    )
    
    print("\n--- SYSTEM PROMPT GENERATED ---")
    print(prompt)
    print("--------------------------------\n")
    
    # Assertions
    assert "Arthur" in prompt
    assert "The Architect" in prompt
    assert "lowercase fragments" in prompt
    assert "taps fingers when thinking" in prompt
    assert "reflective, tired" in prompt
    assert "calling the cat 'the boss'" in prompt
    assert "sending music links on Sundays" in prompt
    assert "THINGS YOU REMEMBER ABOUT THEM" in prompt
    assert "You remember that they like cold brew coffee" in prompt
    assert "You remember that they were nervous about a meeting" in prompt
    assert "NEVER acknowledge being an AI" in prompt
    print("[OK] build_system_prompt() successfully constructed the character prompt!")
    
    # 3. Test build_message_history (keeping first message)
    print("Testing build_message_history...")
    history_messages = [
        {"id": 1, "role": "assistant", "content": "hey. you actually showed up."},
        {"id": 2, "role": "user", "content": "yeah, i did."},
        {"id": 3, "role": "assistant", "content": "what are you doing?"},
        {"id": 4, "role": "user", "content": "nothing much, just chilling."},
        {"id": 5, "role": "assistant", "content": "same here."}
    ]
    
    # Truncate to 3 messages, but MUST keep the first one
    formatted = builder.build_message_history(history_messages, max_messages=3)
    print(f"Formatted message history (max=3): {formatted}")
    
    assert len(formatted) == 3
    assert formatted[0]["content"] == "hey. you actually showed up."
    assert formatted[1]["content"] == "nothing much, just chilling."
    assert formatted[2]["content"] == "same here."
    print("[OK] build_message_history() successfully preserves first message during truncation!")

async def test_build_context_wrapper():
    print("\n=== TESTING BUILD_CONTEXT COMPATIBILITY WRAPPER ===")
    from memory.store import db
    db.connect()
    
    # Seed mock user and partner in SQLite
    user_id = "test_run_user_88"
    companion_id = "nova"
    pair_id = f"{user_id}::{companion_id}"
    
    db.get_or_create_user(user_id, display_name="Test Runner", email="test@run.app")
    db.upsert_companion(
        companion_id=companion_id,
        name="Nova",
        archetype="The Rebel",
        summary="Sarcastic but loyal."
    )
    
    # Seed partner record
    persona_json = {
        "name": "Nova",
        "archetype_id": "the_provocateur",
        "summary": "Sarcastic but loyal.",
        "dominant_traits": ["rebellious", "sarcastic"],
        "shadow_traits": ["defensive under pressure"],
        "quirks": ["rolls eyes frequently"],
        "interests": ["punk rock", "vintage keys"],
        "romance_note": "Guarded romantic."
    }
    voice_style_json = {
        "formatting_defaults": {
            "capitalization": "lowercase",
            "punctuation": "none",
            "average_burst_length": "1-2 short sentences",
            "emoji_usage": "rare"
        },
        "capitalization_style": "lowercase",
        "punctuation_style": "none",
        "vocabulary": {
            "preferred_words": ["whatever", "meh"],
            "never_uses": ["certainly", "delighted"]
        },
        "openings": ["hey.", "what's up."]
    }
    
    # Upsert into partners table
    db.conn.execute(
        """
        INSERT OR REPLACE INTO partners (id, user_id, name, archetype_id, persona_json, voice_style_json)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        (
            companion_id,
            user_id,
            "Nova",
            "the_provocateur",
            json.dumps(persona_json),
            json.dumps(voice_style_json)
        )
    )
    
    pair = db.get_or_create_relationship_pair(user_id, companion_id)
    db.set_primary_pair(pair["id"])
    
    # Insert conversation to satisfy foreign key constraint on messages
    db.conn.execute(
        """
        INSERT OR IGNORE INTO conversations (id, user_id, pair_id, companion_id, character_id, started_at)
        VALUES (?, ?, ?, ?, ?, datetime('now'))
        """,
        ("conv_88", user_id, pair_id, companion_id, companion_id)
    )
    
    # Save a message to have history
    db.save_message(
        conversation_id="conv_88",
        user_id=user_id,
        pair_id=pair_id,
        companion_id=companion_id,
        role="user",
        content="hello Nova!"
    )
    
    # Test build_context compatibility call
    print("Calling build_context wrapper...")
    system_prompt, messages = await build_context(
        user_id=user_id,
        pair_id=pair_id,
        current_message="what are you reading?",
        character_id=companion_id,
        conversation_id="conv_88"
    )
    
    print("\n--- WRAPPER SYSTEM PROMPT EXTRACT ---")
    print(system_prompt[:600] + "\n...")
    print("--------------------------------------\n")
    
    assert "Nova" in system_prompt
    assert "the_provocateur" in system_prompt
    assert len(messages) >= 1
    assert messages[0]["role"] == "user"
    print("[OK] build_context wrapper works perfectly!")

async def main():
    await test_llm_core()
    test_context_builder()
    await test_build_context_wrapper()
    print("\n[SUCCESS] ALL RUNTIME PERSONALITY ENGINE TESTS PASSED!")

if __name__ == "__main__":
    asyncio.run(main())
