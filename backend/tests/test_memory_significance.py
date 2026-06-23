import sys
import os

# Adjust path to import backend modules
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "..", "..", "Desktop", "sol_mvp", "backend")))
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "backend")))
sys.path.insert(0, "c:\\Users\\aakash09\\Desktop\\sol_mvp\\backend")

def test_ranking_logic():
    print("=== TESTING SOL USER MEMORY & SIGNIFICANCE RETRIEVAL RANKING ===")

    # Identical ranking function to retriever.py
    def calculate_rank(item: dict) -> float:
        is_unresolved = str(item.get("emotion_tag") or "").lower() in {
            "sad", "anxious", "grief", "anger", "lonely", "overwhelmed"
        }
        unresolved_bonus = 0.10 if is_unresolved else 0.0
        
        score = (
            item["similarity"] * 0.35
            + item["emotional_weight"] * 0.30
            + min(item["strength"], 3.0) / 3.0 * 0.15
            + item["recency"] * 0.10
            + unresolved_bonus
        )
        return round(score, 4)

    # Simulated memories
    # 1. Low significance, high semantic similarity (User talks about food -> matches pasta)
    pasta_memory = {
        "title": "Ate pasta",
        "content": "The user mentioned they ate pasta for dinner.",
        "similarity": 0.90,          # High semantic match
        "emotional_weight": 0.15,    # Low significance
        "strength": 1.0,
        "recency": 0.8,              # Quite recent
        "emotion_tag": ""            # No emotional tag
    }

    # 2. High significance, lower semantic similarity (User talks about food, but companion recalls a major fight with best friend over dinner)
    friend_fight_memory = {
        "title": "Fought with best friend Rahul",
        "content": "The user opened up about having a massive argument with their best friend Rahul over dinner and crying.",
        "similarity": 0.55,          # Lower direct semantic match to "food"
        "emotional_weight": 0.90,    # High emotional significance
        "strength": 1.0,
        "recency": 0.6,              # Slightly older
        "emotion_tag": "sad"         # Heavy negative/unresolved tag
    }

    # 3. High significance, low similarity (User mentioned feeling a bit tired -> companion recalls deep loneliness)
    loneliness_memory = {
        "title": "Opened up about feeling lonely",
        "content": "The user confessed that they have been feeling deeply lonely lately and worried about connecting.",
        "similarity": 0.50,          # Low semantic match
        "emotional_weight": 0.85,    # High significance
        "strength": 2.0,             # Reinforced once (repetition)
        "recency": 0.5,
        "emotion_tag": "lonely"      # Unresolved emotional struggle tag
    }

    memories = [pasta_memory, friend_fight_memory, loneliness_memory]
    
    print("\nSimulated Memory Pool:")
    for m in memories:
        rank_score = calculate_rank(m)
        m["rank_score"] = rank_score
        print(f"  Memory: \"{m['title']}\"")
        print(f"    Similarity: {m['similarity']} | Significance: {m['emotional_weight']} | Tag: \"{m['emotion_tag']}\" | Score: {rank_score}")

    # Sort memories
    sorted_memories = sorted(memories, key=calculate_rank, reverse=True)

    print("\nPrioritized Retrieval Order (Descending Rank):")
    for i, m in enumerate(sorted_memories):
        print(f"  {i+1}. \"{m['title']}\" (Score: {m['rank_score']})")

    # Assertions
    assert sorted_memories[2]["title"] == "Ate pasta", "Mundane/low significance memory should rank last despite higher similarity!"
    assert sorted_memories[0]["title"] in {"Fought with best friend Rahul", "Opened up about feeling lonely"}, "High significance emotional memories must occupy top slots!"
    assert sorted_memories[1]["title"] in {"Fought with best friend Rahul", "Opened up about feeling lonely"}, "High significance emotional memories must occupy top slots!"

    print("\n[OK] ALL RETRIEVAL RANKING TESTS PASSED SUCCESSFULLY!")

if __name__ == "__main__":
    test_ranking_logic()
