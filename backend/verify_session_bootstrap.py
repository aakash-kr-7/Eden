import sys
import os
import json
import asyncio
from datetime import datetime, timezone
from contextlib import asynccontextmanager

# Ensure backend folder is in path for imports
sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))

from fastapi.testclient import TestClient
from main import app
from memory.store import db
from core.concurrency import concurrency, pair_lock_context, get_pair_lock
from core.summarizer import Summarizer
from core.session_loader import SessionLoader
from auth.firebase import get_authenticated_identity, User
from core.llm import get_llm_core

from typing import Optional

# ---------------------------------------------------------
# Dynamic User ID for auth overrides
# ---------------------------------------------------------
current_test_user = "test_user_api"

async def mock_get_authenticated_identity(authorization: Optional[str] = None):
    return User(user_id=current_test_user, email=f"{current_test_user}@sol.app")

app.dependency_overrides[get_authenticated_identity] = mock_get_authenticated_identity

# ---------------------------------------------------------
# Mock LLM calls so we don't hit external APIs
# ---------------------------------------------------------
llm_core_inst = get_llm_core()

async def mock_complete(system_prompt: str, messages: list[dict], temperature: float = 0.85, max_tokens: int = 400, response_format=None):
    return "hey. this is a mock companion response."

async def mock_complete_structured(system_prompt: str, messages: list[dict], output_schema: dict, temperature: float = 0.3):
    prompt_lower = system_prompt.lower()
    if "summariz" in prompt_lower:
        return {"summary": "We talked about recent things."}
    if "emotion" in prompt_lower or "tone" in prompt_lower:
        return {"tone": "intimate"}
    return {}

llm_core_inst.complete = mock_complete
llm_core_inst.complete_structured = mock_complete_structured

# ---------------------------------------------------------
# Seeding Database Helper
# ---------------------------------------------------------
def setup_database_data():
    db.connect()
    
    # Clear old data
    db.conn.execute("DELETE FROM users WHERE id IN ('test_user_session', 'test_user_api', 'user_concurrent')")
    db.conn.execute("DELETE FROM companions WHERE id = 'nova' OR id LIKE 'partner_%'")
    db.conn.execute("DELETE FROM partners WHERE user_id IN ('test_user_session', 'test_user_api', 'user_concurrent')")
    db.conn.execute("DELETE FROM relationship_pairs WHERE user_id IN ('test_user_session', 'test_user_api', 'user_concurrent')")
    db.conn.execute("DELETE FROM conversations WHERE user_id IN ('test_user_session', 'test_user_api', 'user_concurrent')")
    
    # Create users first to satisfy foreign key constraints
    db.get_or_create_user("test_user_session")
    db.get_or_create_user("test_user_api")
    db.get_or_create_user("user_concurrent")

    # Seed companion
    db.conn.execute(
        """
        INSERT OR REPLACE INTO companions (id, name, status, created_at, updated_at)
        VALUES ('nova', 'Nova', 'active', ?, ?)
        """,
        (datetime.utcnow().isoformat(), datetime.utcnow().isoformat())
    )
    
    # Persona template
    persona_json = {
        "name": "Nova",
        "archetype_id": "the_provocateur",
        "summary": "Sarcastic but loyal.",
        "dominant_traits": ["rebellious", "sarcastic"],
        "shadow_traits": ["defensive under pressure"],
        "quirks": ["rolls eyes frequently"],
        "interests": ["punk rock"],
        "romance_note": "Guarded romantic.",
        "communication_rhythm": "rapid-fire",
        "core_temperament": "warm",
        "emotional_availability": "high"
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
    
    # Save partners
    db.save_partner("test_user_session", "partner_test_user_session", "Nova", "the_provocateur", persona_json, voice_style_json)
    db.save_partner("test_user_api", "partner_test_user_api", "Nova", "the_provocateur", persona_json, voice_style_json)
    db.save_partner("user_concurrent", "partner_user_concurrent", "Nova", "the_provocateur", persona_json, voice_style_json)
    
    # Save user preferences
    db.get_or_create_user_preferences("test_user_session")
    db.get_or_create_user_preferences("test_user_api")
    db.get_or_create_user_preferences("user_concurrent")

# ---------------------------------------------------------
# Test Suites
# ---------------------------------------------------------
async def run_concurrency_tests():
    print("\n=== RUNNING CONCURRENCY TESTS ===")
    shared_log = []
    
    async def task_1():
        async with concurrency.acquire("user_concurrent"):
            shared_log.append("task_1_start")
            await asyncio.sleep(0.3)
            shared_log.append("task_1_end")
            
    async def task_2():
        await asyncio.sleep(0.05) # ensure task 1 acquires first
        async with concurrency.acquire("user_concurrent"):
            shared_log.append("task_2_start")
            shared_log.append("task_2_end")
            
    await asyncio.gather(task_1(), task_2())
    print(f"Concurrency execution log: {shared_log}")
    assert shared_log == ["task_1_start", "task_1_end", "task_2_start", "task_2_end"], \
        "Locks did not serialize execution for the same user!"
    print("[OK] ConcurrencyManager lock serialized execution successfully.")

    # Test backward-compatibility wrappers
    async with pair_lock_context("user_concurrent::nova"):
        print("[OK] pair_lock_context acquired lock.")
    
    lock = await get_pair_lock("user_concurrent::nova")
    assert isinstance(lock, asyncio.Lock), "get_pair_lock did not return an asyncio.Lock instance"
    print("[OK] get_pair_lock works correctly.")

async def run_summarizer_tests():
    print("\n=== RUNNING SUMMARIZER TESTS ===")
    summarizer = Summarizer()
    messages = [
        {"role": "user", "content": "hi nova, i had a bad day at work"},
        {"role": "assistant", "content": "ugh, what happened? tell me about it"}
    ]
    summary = await summarizer.summarize_conversation(messages, partner_name="Nova")
    print(f"Summarizer output summary: {summary}")
    assert summary == "We talked about recent things.", f"Unexpected summary: {summary}"
    print("[OK] Summarizer summarized conversation successfully.")
    
    tone = await summarizer.extract_emotional_tone(messages)
    print(f"Summarizer extracted tone: {tone}")
    assert tone == "intimate", f"Unexpected tone: {tone}"
    print("[OK] Summarizer extracted tone successfully.")

async def run_session_loader_tests():
    print("\n=== RUNNING SESSION LOADER TESTS ===")
    
    # 1. Update user last active
    db.conn.execute("UPDATE users SET last_active_at = NULL WHERE id = 'test_user_session'")
    loader = SessionLoader()
    await loader.update_last_active("test_user_session")
    
    user = db.get_user("test_user_session")
    assert user["last_active_at"] is not None, "update_last_active did not set last_active_at!"
    print("[OK] SessionLoader updated last_active_at correctly.")
    
    # 2. Check days_together math handles offset-aware datetimes cleanly
    # Set partner created_at to an offset-aware ISO string
    db.conn.execute(
        "UPDATE partners SET created_at = '2026-06-20T12:00:00+00:00' WHERE user_id = 'test_user_session'"
    )
    # Clear the local partner cache to reload from DB
    from personality.registry import clear_cache
    clear_cache("test_user_session")
    
    payload = await loader.load_session("test_user_session")
    print(f"SessionLoader load_session payload: {payload}")
    assert "partner" in payload, "Session payload missing 'partner'"
    assert "days_together" in payload, "Session payload missing 'days_together'"
    assert payload["days_together"] >= 0, "days_together is negative!"
    print("[OK] SessionLoader load_session ran successfully with timezone-aware created_at.")

def run_api_tests():
    print("\n=== RUNNING API ROUTING & ONBOARDING GUARD TESTS ===")
    global current_test_user
    current_test_user = "test_user_api"
    
    client = TestClient(app)
    
    # --- Test Case A: User has NOT completed onboarding ---
    # Create user in DB with onboarding_completed = 0
    db.get_or_create_user(current_test_user, display_name="API Tester", email="api@sol.app")
    db.conn.execute("UPDATE users SET onboarding_completed = 0 WHERE id = ?", (current_test_user,))
    
    # Verify the onboarding guards reject requests with 403 onboarding_required
    routes_to_test = [
        ("POST", "/api/chat/session/start", None),
        ("POST", "/api/chat/message", {"message": "hello"}),
        ("GET", "/api/chat/conversations", None),
        ("GET", "/api/chat/conversations/123-abc/messages", None),
        ("DELETE", "/api/chat/conversations/123-abc", None),
    ]
    
    for method, path, payload in routes_to_test:
        if method == "POST":
            res = client.post(path, json=payload)
        elif method == "DELETE":
            res = client.delete(path)
        else:
            res = client.get(path)
            
        print(f"Auth Guard Check: {method} {path} -> Status: {res.status_code}")
        if res.status_code != 403:
            print(f"DEBUG: Response body was: {res.text}")
        assert res.status_code == 403, f"{method} {path} did not return 403 under incomplete onboarding! Got {res.status_code}"
        assert res.json() == {"error": "onboarding_required"}, f"Unexpected guard error body: {res.json()}"
        
    print("[OK] Onboarding Guard successfully rejects all requests with 403 when onboarding is incomplete.")
    
    # --- Test Case B: Onboarding is complete ---
    db.conn.execute("UPDATE users SET onboarding_completed = 1 WHERE id = ?", (current_test_user,))
    print("\nOnboarding completed set to 1. Testing actual endpoints...")
    
    # 1. Test POST /api/chat/session/start
    res = client.post("/api/chat/session/start")
    print(f"POST /api/chat/session/start -> Status: {res.status_code}")
    assert res.status_code == 200, f"session start failed: {res.text}"
    session_data = res.json()
    assert "partner" in session_data, "Response missing partner details"
    print("[OK] POST /api/chat/session/start returned 200 with session details.")
    
    # 2. Test GET /api/chat/conversations (expect empty list or newly generated from bootstrap)
    res = client.get("/api/chat/conversations")
    print(f"GET /api/chat/conversations -> Status: {res.status_code}")
    assert res.status_code == 200, f"get conversations failed: {res.text}"
    convs = res.json()
    print(f"Conversations list: {convs}")
    
    # 3. Test POST /api/chat/message (generates/continues a conversation)
    res = client.post("/api/chat/message", json={"message": "hey nova, let's talk about rock music"})
    print(f"POST /api/chat/message -> Status: {res.status_code}")
    assert res.status_code == 200, f"send message failed: {res.text}"
    msg_data = res.json()
    print(f"Send message response: {msg_data}")
    assert "response" in msg_data
    assert "conversation_id" in msg_data
    conversation_id = msg_data["conversation_id"]
    print(f"[OK] POST /api/chat/message successfully returned response and conversation_id.")
    
    # Seed emotional tone to messages table for testing
    db.conn.execute(
        "UPDATE messages SET emotional_tone = 'intimate' WHERE conversation_id = ?",
        (conversation_id,)
    )
    
    # 4. Test GET /api/chat/conversations again (should show the active conversation with correct metadata)
    res = client.get("/api/chat/conversations")
    print(f"GET /api/chat/conversations -> Status: {res.status_code}")
    assert res.status_code == 200
    convs = res.json()
    print(f"Conversations list with active conversation: {convs}")
    assert len(convs) >= 1, "Conversations list is empty after sending message!"
    target_conv = [c for c in convs if c["id"] == conversation_id][0]
    assert target_conv["emotional_tone"] == "intimate", "Conversation emotional tone did not match!"
    print("[OK] GET /api/chat/conversations returns conversation list with tone/fields.")
    
    # 5. Test GET /api/chat/conversations/{conversation_id}/messages (pagination)
    res = client.get(f"/api/chat/conversations/{conversation_id}/messages?limit=10")
    print(f"GET /api/chat/conversations/messages -> Status: {res.status_code}")
    assert res.status_code == 200
    msgs = res.json()
    print(f"Messages count: {len(msgs)}")
    assert len(msgs) >= 2, "Expected at least 2 messages (user + companion)"
    
    # Verify cursor-based pagination
    latest_msg_id = msgs[1]["id"] # newest message is at index 1 in chronological order
    print(f"First message (oldest): {msgs[0]}")
    print(f"Second message (newest): {msgs[1]}")
    
    res_paginated = client.get(f"/api/chat/conversations/{conversation_id}/messages?limit=1&before_id={latest_msg_id}")
    assert res_paginated.status_code == 200
    paginated_msgs = res_paginated.json()
    print(f"Paginated messages count (limit 1, before_id {latest_msg_id}): {len(paginated_msgs)}")
    assert len(paginated_msgs) == 1, "Expected exactly 1 message in paginated query"
    print("[OK] GET /api/chat/conversations/{id}/messages pagination works.")

    # 6. Test DELETE /api/chat/conversations/{conversation_id} (soft delete)
    res = client.delete(f"/api/chat/conversations/{conversation_id}")
    print(f"DELETE /api/chat/conversations -> Status: {res.status_code}")
    assert res.status_code == 200
    assert res.json() == {"success": True, "deleted": True}
    
    # Verify is_deleted is updated in database
    row = db.conn.execute("SELECT is_deleted FROM conversations WHERE id = ?", (conversation_id,)).fetchone()
    assert row["is_deleted"] == 1, "Conversation was not soft-deleted in DB!"
    print("[OK] SQLite row updated to is_deleted = 1.")
    
    # Verify GET /api/chat/conversations does NOT return soft-deleted conversations
    res = client.get("/api/chat/conversations")
    convs_after_delete = res.json()
    print(f"Conversations after soft-delete: {convs_after_delete}")
    active_ids = [c["id"] for c in convs_after_delete]
    assert conversation_id not in active_ids, "Soft-deleted conversation was returned by get_conversations endpoint!"
    print("[OK] Soft-deleted conversation is omitted from active conversations query.")

async def main():
    print("=========================================================")
    print("Eden Session Bootstrap & Chat API Pipeline Verification")
    print("=========================================================")
    setup_database_data()
    
    await run_concurrency_tests()
    await run_summarizer_tests()
    await run_session_loader_tests()
    run_api_tests()
    
    print("\n=========================================================")
    print("[ALL OK] All tests passed successfully!")
    print("=========================================================")

if __name__ == "__main__":
    asyncio.run(main())
