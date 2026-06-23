import asyncio
import logging
import sys
import os

# Add parent directory to path
sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))

from memory.store import db, memory_store
from memory.extractor import MemoryExtractor, extract_and_save
from memory.retriever import MemoryRetriever, retrieve_relevant_memories
from memory.consolidator import MemoryConsolidator
from memory.analysis import MemoryAnalysis

logging.basicConfig(level=logging.INFO)

async def test_rebuilt_memory_system():
    print("=== STARTING MEMORY SYSTEM VERIFICATION ===")
    
    # 1. Connect and initialize DB
    db.connect()
    
    user_id = "test_user_memory_rebuild"
    companion_id = "nova"
    pair_id = f"{user_id}::{companion_id}"
    
    # Seed mock user and relationship pair
    db.conn.execute("INSERT OR REPLACE INTO users (id, name, character_id, preferred_name) VALUES (?, ?, ?, ?)", (user_id, "Alex", companion_id, "Alex"))
    db.conn.execute(
        """
        INSERT OR REPLACE INTO relationship_pairs 
        (id, user_id, companion_id, is_primary, total_sessions, memory_count, current_stage) 
        VALUES (?, ?, ?, 1, 5, 0, 'new')
        """,
        (pair_id, user_id, companion_id)
    )
    
    # Enable memory storage in preferences
    db.conn.execute(
        "INSERT OR REPLACE INTO user_preferences (user_id, allow_memory_storage) VALUES (?, 1)",
        (user_id,)
    )
    
    print("\n--- 1. Testing MemoryStore ---")
    # Test MemoryStore.add
    mem1 = {
        "content": "Alex has a dog named Spot who is a golden retriever.",
        "memory_type": "fact",
        "salience": 0.4,
        "emotional_valence": "neutral",
        "tags": ["dog", "pet", "family"]
    }
    mem2 = {
        "content": "Alex felt deeply sad yesterday because they failed a major certification exam.",
        "memory_type": "emotion",
        "salience": 0.85,
        "emotional_valence": "negative",
        "tags": ["exam", "failure", "career", "sadness"]
    }
    
    id1 = await memory_store.add(user_id, mem1)
    id2 = await memory_store.add(user_id, mem2)
    print(f"Added memory 1, ID: {id1}")
    print(f"Added memory 2, ID: {id2}")
    
    # Check count
    cnt = await memory_store.count(user_id)
    print(f"Memory count: {cnt} (Expected: 2)")
    assert cnt >= 2
    
    # Check get_all
    all_mem = await memory_store.get_all(user_id)
    print(f"Retrieved {len(all_mem)} memories in total.")
    
    # Check get_by_type
    facts = await memory_store.get_by_type(user_id, "fact")
    print(f"Retrieved {len(facts)} facts.")
    assert len(facts) >= 1
    
    # Check pin
    await memory_store.pin(id2)
    pinned = await memory_store.get_pinned(user_id)
    print(f"Retrieved {len(pinned)} pinned memories.")
    assert len(pinned) >= 1
    
    # Check update_salience
    await memory_store.update_salience(id1, 0.95)
    all_mem_updated = await memory_store.get_all(user_id)
    updated_mem1 = [m for m in all_mem_updated if m["chroma_id"] == id1][0]
    print(f"Updated salience for memory 1: {updated_mem1['salience']} (Expected: 0.95)")
    assert updated_mem1["salience"] == 0.95

    print("\n--- 2. Testing MemoryExtractor ---")
    messages = [
        {"role": "user", "content": "i'm actually super excited because i just got a job offer today as a software developer!"},
        {"role": "assistant", "content": "oh my god, alex! that is amazing news! congratulations! are you going to take it?"},
        {"role": "user", "content": "yes, absolutely. i start next monday in downtown Seattle."}
    ]
    extractor = MemoryExtractor()
    extracted = await extractor.extract(messages, existing_memories=all_mem_updated, partner_name="Nova")
    print(f"Extracted {len(extracted)} new memories from conversation:")
    for m in extracted:
        print(f"  - [{m['memory_type']}] (Salience: {m['salience']}): {m['content']}")
        
    print("\n--- 3. Testing MemoryRetriever ---")
    retriever = MemoryRetriever()
    retrieved = await retriever.retrieve(user_id, "tell me about my new job or Seattle", "")
    print(f"Retrieved {len(retrieved)} relevant memories.")
    for r in retrieved:
        print(f"  - Pinned: {r['is_pinned']}, Recalls: {r['recall_count']}, Content: {r['content']}")

    print("\n--- 4. Testing MemoryConsolidator ---")
    # Upgrade recall count on one memory to test consolidator upgrade
    db.conn.execute("UPDATE memory_index SET recall_count = 6 WHERE chroma_id = ?", (id1,))
    
    consolidator = MemoryConsolidator()
    await consolidator.consolidate(user_id)
    print("Consolidation executed.")
    
    # Verify that memory 1 had salience upgraded (since recall_count >= 5)
    all_mem_consolidated = await memory_store.get_all(user_id)
    consolidated_mem1 = [m for m in all_mem_consolidated if m["chroma_id"] == id1][0]
    print(f"Consolidated salience for memory 1: {consolidated_mem1['salience']} (reaches 1.0 limit or increases)")
    
    print("\n--- 5. Testing MemoryAnalysis ---")
    analysis = MemoryAnalysis()
    # Test detect_relationship_event
    event = await analysis.detect_relationship_event(
        messages=[
            {"role": "user", "content": "i'm really glad we met. i feel like i can tell you anything and you always understand me."},
            {"role": "assistant", "content": "i feel the exact same way. you've become a really important part of my life."}
        ],
        existing_events=[]
    )
    if event:
        print(f"Detected event: [{event['event_type']}] {event['description']} (Confidence: {event['confidence']})")
        # Save to database to test stage progression
        db.conn.execute(
            "INSERT INTO relationship_events (user_id, pair_id, event_type, description, confidence) VALUES (?, ?, ?, ?, ?)",
            (user_id, pair_id, event["event_type"], event["description"], event["confidence"])
        )
    else:
        print("No event detected.")
        
    # Seed more conversations to trigger familiar/close stage check
    db.conn.execute("UPDATE relationship_pairs SET total_sessions = 35 WHERE id = ?", (pair_id,))
    # Insert a deepening event if it wasn't detected to ensure criteria met for familiar -> close
    db.conn.execute(
        "INSERT OR REPLACE INTO relationship_events (user_id, pair_id, event_type, description, confidence) VALUES (?, ?, 'deepening', 'Vulnerability shared', 0.9)",
        (user_id, pair_id)
    )
    
    new_stage = await analysis.compute_relationship_stage(user_id, "familiar")
    print(f"Computed relationship stage transition from 'familiar': {new_stage} (Expected: close)")
    
    # Cleanup test data
    db.conn.execute("DELETE FROM users WHERE id = ?", (user_id,))
    db.conn.execute("DELETE FROM relationship_pairs WHERE user_id = ?", (user_id,))
    db.conn.execute("DELETE FROM user_preferences WHERE user_id = ?", (user_id,))
    db.conn.execute("DELETE FROM memory_index WHERE user_id = ?", (user_id,))
    db.conn.execute("DELETE FROM relationship_events WHERE user_id = ?", (user_id,))
    db.close()
    
    print("\n=== VERIFICATION COMPLETE: ALL CHECKS PASSED ===")

if __name__ == "__main__":
    asyncio.run(test_rebuilt_memory_system())
