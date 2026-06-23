import sys
import os
import asyncio
from datetime import datetime, timedelta

# Ensure backend folder is in path for imports
sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))

from memory.store import db
from core.life_simulator import LifeSimulator
from core.burst_engine import BurstEngine, plan_burst_response
from core.llm import get_llm_core

# ---------------------------------------------------------
# Mock LLM calls so we don't hit external APIs
# ---------------------------------------------------------
llm_core_inst = get_llm_core()

async def mock_complete_structured(system_prompt: str, messages: list[dict], output_schema: dict, temperature: float = 0.3):
    # Mocking burst splitter
    if "split" in system_prompt.lower():
        # Extracted user message content to split
        user_content = messages[0]["content"]
        if "Message to split:\n" in user_content:
            user_content = user_content.replace("Message to split:\n", "")
        # Split on sentences
        parts = [p.strip() for p in user_content.split(". ") if p.strip()]
        bursts = []
        for p in parts:
            if not p.endswith("."):
                p = p + "."
            bursts.append(p)
        return {"bursts": bursts}
    return {}

llm_core_inst.complete_structured = mock_complete_structured

# ---------------------------------------------------------
# Seeding Database Helper
# ---------------------------------------------------------
def setup_database_data():
    db.connect()
    
    # Clear old test data
    db.conn.execute("DELETE FROM users WHERE id = 'test_user_sim'")
    db.conn.execute("DELETE FROM companions WHERE id = 'nova'")
    db.conn.execute("DELETE FROM partners WHERE user_id = 'test_user_sim'")
    db.conn.execute("DELETE FROM relationship_pairs WHERE user_id = 'test_user_sim'")
    db.conn.execute("DELETE FROM life_state WHERE user_id = 'test_user_sim'")
    
    # Seed user with timezone
    db.conn.execute(
        """
        INSERT INTO users (id, name, preferred_name, timezone, onboarding_completed, created_at)
        VALUES ('test_user_sim', 'Sim User', 'Simmy', 'UTC', 1, ?)
        """,
        (datetime.utcnow().isoformat(),)
    )

    # Seed companion
    db.conn.execute(
        """
        INSERT INTO companions (id, name, status, created_at, updated_at)
        VALUES ('nova', 'Nova', 'active', ?, ?)
        """,
        (datetime.utcnow().isoformat(), datetime.utcnow().isoformat())
    )
    
    # Seed relationship pair
    db.conn.execute(
        """
        INSERT INTO relationship_pairs (id, user_id, companion_id, current_stage, is_primary, created_at, updated_at)
        VALUES ('test_user_sim::nova', 'test_user_sim', 'nova', 'new', 1, ?, ?)
        """,
        (datetime.utcnow().isoformat(), datetime.utcnow().isoformat())
    )

# ---------------------------------------------------------
# Test Suites
# ---------------------------------------------------------
async def test_life_simulator():
    print("\n=== RUNNING LIFE SIMULATOR TESTS ===")
    simulator = LifeSimulator()

    # 1. Test initialize_life_state
    await simulator.initialize_life_state("test_user_sim")
    
    state = db.get_life_state("test_user_sim::nova")
    assert state is not None, "Life state row not created!"
    assert state["mood"] == "content", f"Expected initial mood 'content', got {state['mood']}"
    assert state["energy"] == "normal", f"Expected initial energy 'normal', got {state['energy']}"
    assert state["day_arc"] in ("morning", "afternoon (early)", "afternoon", "evening", "night"), f"Invalid day arc: {state['day_arc']}"
    assert state["partner_busy_until"] is None, "Expected partner not to be busy initially"
    print("[OK] Life state initialized successfully.")

    # 2. Test get_partner_state_description
    desc = await simulator.get_partner_state_description("test_user_sim")
    print(f"Partner State Description: {desc}")
    assert isinstance(desc, str) and len(desc) > 0, "Partner state description must be a non-empty string"
    print("[OK] Natural language state description generated successfully.")

    # 3. Test tick (mood and energy drift)
    # Let's seed an old tick time and test a tick run
    db.conn.execute(
        "UPDATE life_state SET last_tick_at = ? WHERE pair_id = 'test_user_sim::nova'",
        ((datetime.utcnow() - timedelta(minutes=10)).isoformat(),)
    )
    await simulator.tick("test_user_sim")
    
    updated_state = db.get_life_state("test_user_sim::nova")
    assert updated_state is not None
    print(f"State after tick - Mood: {updated_state['mood']}, Energy: {updated_state['energy']}, Busy Until: {updated_state['partner_busy_until']}")
    print("[OK] Life simulator ticked successfully.")

async def test_burst_engine():
    print("\n=== RUNNING BURST ENGINE TESTS ===")
    engine = BurstEngine()

    # 1. Test should_burst
    # Length < 250 characters should not burst
    assert not await engine.should_burst("short response", "playful"), "Response < 250 chars burst!"
    
    # Quiet or tired mood should not burst
    long_response = "This is a very long response that exceeds two hundred and fifty characters to trigger the burst split logic. " * 3
    assert not await engine.should_burst(long_response, "quiet"), "Quiet mood burst!"
    assert not await engine.should_burst(long_response, "tired"), "Tired mood burst!"

    # Playful mood should be eligible to burst
    # Since it's probabilistic, we don't assert absolute True, but we can verify mood influence logic does not crash
    should = await engine.should_burst(long_response, "playful")
    print(f"should_burst (playful, long response): {should}")

    # 2. Test split_response (LLM Splitter)
    response_to_split = "This is sentence one. This is sentence two. This is sentence three."
    bursts = await engine.split_response(response_to_split)
    print(f"Semantic bursts: {bursts}")
    assert len(bursts) >= 1, "split_response returned empty list"
    
    # 3. Test get_burst_delays
    delays = await engine.get_burst_delays(bursts)
    print(f"Burst delays: {delays}")
    assert len(delays) == len(bursts), "Delays list length mismatch"
    assert delays[0] == 0.0, "First burst delay must be 0.0"
    if len(delays) > 1:
        assert all(3.0 <= d <= 12.0 for d in delays[1:]), "Subsequent delays must be between 3.0 and 12.0 seconds"

    # 4. Test plan_burst_response compatibility wrapper
    from personality.registry import Partner
    partner_record = {
        "id": "nova",
        "name": "Nova",
        "persona_json": {
            "archetype_id": "the_provocateur",
            "summary": "Sarcastic but loyal.",
            "dominant_traits": [],
            "shadow_traits": [],
            "quirks": []
        },
        "voice_style_json": {
            "formatting_defaults": {},
            "vocabulary": {}
        }
    }
    mock_char = Partner(partner_record)
    
    # Explicit burst split test
    explicit_text = "hey. [BURST] you actually showed up. [BURST] cool."
    plan = await plan_burst_response(
        raw_text=explicit_text,
        character=mock_char,
        relationship_state={"id": "test_user_sim::nova"}
    )
    print(f"Explicit burst plan: {[b.text for b in plan.bursts]}")
    assert len(plan.bursts) == 3, f"Expected 3 bursts, got {len(plan.bursts)}"
    assert plan.bursts[0].text == "hey.", f"Unexpected first burst: {plan.bursts[0].text}"
    assert plan.bursts[1].is_follow_up, "Second burst should be a follow up"
    
    print("[OK] Burst engine verified successfully.")

async def main():
    print("=========================================================")
    print("Eden Life Simulator & Burst Engine Verification")
    print("=========================================================")
    setup_database_data()
    
    await test_life_simulator()
    await test_burst_engine()
    
    print("\n=========================================================")
    print("[ALL OK] All tests passed successfully!")
    print("=========================================================")

if __name__ == "__main__":
    asyncio.run(main())
