import asyncio
import os
import sys
import json
from datetime import datetime

# Add path for backend module imports
sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))

from fastapi.testclient import TestClient
from main import app
from auth.firebase import get_authenticated_identity, AuthenticatedIdentity
from memory.store import db, memory_store
from memory.relationship_engine import RelationshipEngine

# 1. Override FastAPI Dependency for Authentication
class MockIdentity:
    def __init__(self):
        self.uid = "test_user_relationship"
        self.display_name = "Alex"
        self.email = "alex@test.com"

async def override_get_identity():
    return MockIdentity()

app.dependency_overrides[get_authenticated_identity] = override_get_identity
client = TestClient(app)

async def run_tests():
    print("=== STARTING RELATIONSHIP ENGINE & PROFILE API VERIFICATION ===")
    
    # 2. Setup DB context
    db.connect()
    
    user_id = "test_user_relationship"
    companion_id = "nova"
    pair_id = f"{user_id}::{companion_id}"
    
    # Seed mock tables
    db.conn.execute("INSERT OR REPLACE INTO users (id, name, character_id, preferred_name, onboarding_completed) VALUES (?, ?, ?, ?, 1)", (user_id, "Alex", companion_id, "Alex"))
    db.conn.execute(
        """
        INSERT OR REPLACE INTO relationship_pairs 
        (id, user_id, companion_id, is_primary, total_sessions, memory_count, current_stage, proactive_cadence) 
        VALUES (?, ?, ?, 1, 5, 0, 'new', 'balanced')
        """,
        (pair_id, user_id, companion_id)
    )
    db.conn.execute(
        """
        INSERT OR REPLACE INTO partners (id, user_id, name, archetype_id, persona_json, voice_style_json, relationship_stage)
        VALUES (?, ?, ?, 'rebel', '{}', '{}', 'new')
        """,
        (companion_id, user_id, "Nova")
    )
    db.conn.execute(
        "INSERT OR REPLACE INTO user_preferences (user_id, allow_memory_storage) VALUES (?, 1)",
        (user_id,)
    )

    # 3. Test GET /api/profile/me
    response = client.get("/api/profile/me")
    print(f"GET /api/profile/me -> Status: {response.status_code}")
    print(response.json())
    assert response.status_code == 200
    assert response.json()["user"]["preferred_name"] == "Alex"
    assert response.json()["partner"]["name"] == "Nova"

    # 4. Test PATCH /api/profile/me
    patch_data = {
        "display_name": "Alex Mercer",
        "communication_pace": "gentle",
        "emotional_depth_preference": "intense"
    }
    response = client.patch("/api/profile/me", json=patch_data)
    print(f"PATCH /api/profile/me -> Status: {response.status_code}")
    print(response.json())
    assert response.status_code == 200
    assert response.json()["user"]["display_name"] == "Alex Mercer"
    
    # Verify DB update for proactive_cadence
    pair_row = db.get_pair_by_id(pair_id)
    print(f"Updated pair cadence: {pair_row['proactive_cadence']} (Expected: gentle)")
    assert pair_row["proactive_cadence"] == "gentle"

    # 5. Test Memory Vault API operations
    # Add a memory first
    mem_payload = {
        "content": "Alex told Nova they bought a laptop.",
        "memory_type": "fact",
        "salience": 0.5,
        "emotional_valence": "neutral",
        "tags": ["laptop", "tech"]
    }
    mem_id = await memory_store.add(user_id, mem_payload)
    print(f"Added memory to vault, ID: {mem_id}")
    
    # GET /api/profile/memories
    response = client.get("/api/profile/memories")
    print(f"GET /api/profile/memories -> Status: {response.status_code}")
    print(response.json())
    assert response.status_code == 200
    assert len(response.json()["memories"]) >= 1
    
    # POST /api/profile/memories/{id}/pin
    response = client.post(f"/api/profile/memories/{mem_id}/pin")
    print(f"POST /api/profile/memories/{mem_id}/pin -> Status: {response.status_code}")
    print(response.json())
    assert response.status_code == 200
    assert response.json()["pinned"] is True
    assert response.json()["salience"] >= 0.85

    # 6. Test GET /api/profile/relationship summary
    # Insert mock relationship event first to test get_relationship_summary
    db.conn.execute(
        "INSERT INTO relationship_events (user_id, pair_id, event_type, description, confidence) VALUES (?, ?, 'deepening', 'Had a nice talk', 0.9)",
        (user_id, pair_id)
    )
    
    response = client.get("/api/profile/relationship")
    print(f"GET /api/profile/relationship -> Status: {response.status_code}")
    print(response.json())
    assert response.status_code == 200
    assert response.json()["days_together"] >= 1
    assert response.json()["inside_jokes_count"] == 0

    # 7. Test DELETE /api/profile/memories/{id}
    response = client.delete(f"/api/profile/memories/{mem_id}")
    print(f"DELETE /api/profile/memories/{mem_id} -> Status: {response.status_code}")
    print(response.json())
    assert response.status_code == 200
    assert response.json()["deleted"] is True

    # 8. Test RelationshipEngine.process_conversation_end
    # Create conversation and add messages
    conversation_id = "test_conv_end"
    db.conn.execute(
        "INSERT OR REPLACE INTO conversations (id, user_id, pair_id, companion_id) VALUES (?, ?, ?, ?)",
        (conversation_id, user_id, pair_id, companion_id)
    )
    db.conn.execute(
        """
        INSERT INTO messages (conversation_id, user_id, pair_id, companion_id, role, content, memory_extracted)
        VALUES (?, ?, ?, ?, 'user', 'today we talked about a funny joke about an umbrella that we shared last week.', 0)
        """,
        (conversation_id, user_id, pair_id, companion_id)
    )
    db.conn.execute(
        """
        INSERT INTO messages (conversation_id, user_id, pair_id, companion_id, role, content, memory_extracted)
        VALUES (?, ?, ?, ?, 'assistant', 'haha that umbrella was totally magic, i still remember it.', 0)
        """,
        (conversation_id, user_id, pair_id, companion_id)
    )
    
    engine = RelationshipEngine()
    print("Testing process_conversation_end...")
    await engine.process_conversation_end(user_id, conversation_id)
    print("process_conversation_end complete.")
    
    # Check if a joke was detected and saved
    jokes = db.conn.execute("SELECT * FROM user_facts WHERE pair_id = ? AND category = 'jokes'", (pair_id,)).fetchall()
    print(f"Inside jokes in DB count: {len(jokes)}")
    for j in jokes:
        print(f"  - {j['fact_value']}")
        
    # Cleanup mock data
    db.conn.execute("DELETE FROM users WHERE id = ?", (user_id,))
    db.conn.execute("DELETE FROM relationship_pairs WHERE user_id = ?", (user_id,))
    db.conn.execute("DELETE FROM partners WHERE user_id = ?", (user_id,))
    db.conn.execute("DELETE FROM user_preferences WHERE user_id = ?", (user_id,))
    db.conn.execute("DELETE FROM memory_index WHERE user_id = ?", (user_id,))
    db.conn.execute("DELETE FROM relationship_events WHERE user_id = ?", (user_id,))
    db.conn.execute("DELETE FROM conversations WHERE user_id = ?", (user_id,))
    db.conn.execute("DELETE FROM messages WHERE user_id = ?", (user_id,))
    db.conn.execute("DELETE FROM user_facts WHERE pair_id = ?", (pair_id,))
    db.close()
    
    print("\n=== ALL INTEGRATION AND TEST CHECKS PASSED SUCCESSFULLY ===")

if __name__ == "__main__":
    asyncio.run(run_tests())
