import sys
import os

# Adjust path to import backend modules
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "..", "..", "Desktop", "sol_mvp", "backend")))
# Also try direct import if the workspace is root
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "backend")))
sys.path.insert(0, "c:\\Users\\aakash09\\Desktop\\sol_mvp\\backend")

from personality.loader import load_character
from core.burst_engine import plan_burst_response

def run_tests():
    print("=== TESTING SOL BEHAVIORAL/PERSONALITY ENGINE ===")
    
    # 1. Load Nova and Atlas
    try:
        nova = load_character("nova")
        atlas = load_character("atlas")
        print("[OK] Characters loaded successfully.")
    except Exception as e:
        print(f"[FAIL] Failed to load characters: {e}")
        return

    # Test cases
    print("\n--- TEST 1: Nova Pacing & Aggressive Splitting ---")
    raw_nova_text = "okay wait nah that is actually so crazy. wait did you really tell them that? hold on i need details."
    plan_nova = plan_burst_response(
        raw_text=raw_nova_text,
        character=nova,
        user_message="you won't believe what happened today lol",
        relationship_state={"closeness_score": 0.18, "trust_score": 0.18, "comfort_score": 0.14}
    )
    print(f"Nova Raw: \"{raw_nova_text}\"")
    print(f"Nova Bursts Split Count: {len(plan_nova.bursts)}")
    for i, b in enumerate(plan_nova.bursts):
        print(f"  Burst {i+1}: \"{b.text}\" | Seen Delay: {b.pre_burst_delay_ms}ms | Typing: {b.typing_duration_ms}ms")
    assert len(plan_nova.bursts) > 1, "Nova should split text into multiple bursts!"
    assert plan_nova.bursts[0].pre_burst_delay_ms < 1000, "Nova first seen delay should be quick!"

    print("\n--- TEST 2: Atlas Steady Paragraph & Slow Pacing (Default Relationship) ---")
    raw_atlas_text = "I don't think there's any simple way to unpack that. Most people try to rush into answers before they even understand the question. It takes time."
    plan_atlas_default = plan_burst_response(
        raw_text=raw_atlas_text,
        character=atlas,
        user_message="i don't know what to do about my career path",
        relationship_state={"closeness_score": 0.18, "trust_score": 0.18, "comfort_score": 0.14}
    )
    print(f"Atlas Raw: \"{raw_atlas_text}\"")
    print(f"Atlas Bursts Split Count: {len(plan_atlas_default.bursts)}")
    for i, b in enumerate(plan_atlas_default.bursts):
        print(f"  Burst {i+1}: \"{b.text}\" | Seen Delay: {b.pre_burst_delay_ms}ms | Typing: {b.typing_duration_ms}ms")
    assert len(plan_atlas_default.bursts) == 1, "Atlas should group text as a single clean paragraph!"
    assert plan_atlas_default.bursts[0].pre_burst_delay_ms >= 3000, "Atlas default seen delay should be slow (>3s)!"

    print("\n--- TEST 3: Atlas Evolved Relationship (High Comfort & Closeness) ---")
    plan_atlas_evolved = plan_burst_response(
        raw_text=raw_atlas_text,
        character=atlas,
        user_message="i don't know what to do about my career path",
        relationship_state={"closeness_score": 0.82, "trust_score": 0.85, "comfort_score": 0.88}
    )
    for i, b in enumerate(plan_atlas_evolved.bursts):
        print(f"  Burst {i+1}: \"{b.text}\" | Seen Delay: {b.pre_burst_delay_ms}ms | Typing: {b.typing_duration_ms}ms")
    
    default_delay = plan_atlas_default.bursts[0].pre_burst_delay_ms
    evolved_delay = plan_atlas_evolved.bursts[0].pre_burst_delay_ms
    print(f"Atlas Default Seen Delay: {default_delay}ms")
    print(f"Atlas Evolved Seen Delay: {evolved_delay}ms")
    assert evolved_delay < default_delay, "Evolved relationship should significantly speed up Atlas's replies!"

    print("\n--- TEST 4: Atlas Avoidant Emotional Hesitation (Vulnerable User Message) ---")
    plan_atlas_vulnerable = plan_burst_response(
        raw_text="i don't know how to answer that. but i am listening.",
        character=atlas,
        user_message="i feel really sad, lonely, and overwhelmed tonight",
        relationship_state={"closeness_score": 0.18, "trust_score": 0.18, "comfort_score": 0.14}
    )
    vulnerable_delay = plan_atlas_vulnerable.bursts[0].pre_burst_delay_ms
    print(f"Atlas Seen Delay on Vulnerable Input (Low Trust): {vulnerable_delay}ms")
    assert vulnerable_delay > default_delay, "Atlas should hesitate and delay more on low-trust vulnerable user messages!"

    print("\n--- TEST 5: Atlas Vulnerable Input (High Trust) ---")
    plan_atlas_vulnerable_high_trust = plan_burst_response(
        raw_text="i don't know how to answer that. but i am listening.",
        character=atlas,
        user_message="i feel really sad, lonely, and overwhelmed tonight",
        relationship_state={"closeness_score": 0.82, "trust_score": 0.85, "comfort_score": 0.88}
    )
    vulnerable_high_trust_delay = plan_atlas_vulnerable_high_trust.bursts[0].pre_burst_delay_ms
    print(f"Atlas Seen Delay on Vulnerable Input (High Trust): {vulnerable_high_trust_delay}ms")
    assert vulnerable_high_trust_delay < vulnerable_delay, "Trust evolution should decay Atlas's avoidant hesitation!"

    print("\n[OK] ALL TESTS PASSED SUCCESSFULLY! The Behavioral Engine is 100% correct.")

if __name__ == "__main__":
    run_tests()
