import sys
import os

# Adjust path to import backend modules
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "..", "..", "Desktop", "sol_mvp", "backend")))
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "backend")))
sys.path.insert(0, "c:\\Users\\aakash09\\Desktop\\sol_mvp\\backend")

from personality.loader import load_character, get_character_self_memory_seeds

def test_seeding():
    print("=== STARTING COMPANION MEMORY SEEDING VERIFICATION ===")
    
    companions = [
        "nova", "atlas", "mira", "elio", "june", 
        "kaia", "nira", "orion", "remy", "sabine", 
        "theo", "vale"
    ]
    
    required_keys = [
        "age", "favorite_color", "favorite_food", "favorite_music", 
        "sleep_habits", "routines", "insecurities", "hobbies", 
        "attachment_style", "texting_habits", "emotional_tendencies", 
        "social_behavior", "opinions", "relationships_to_other_bots"
    ]
    
    all_success = True
    
    for cid in companions:
        try:
            char = load_character(cid)
            seeds = get_character_self_memory_seeds(char)
            
            # Print basic stats
            print(f"\n[OK] Loaded: {char.name} (ID: {cid})")
            print(f"  Summary: \"{char.summary}\"")
            print(f"  Age in seeds: {seeds.get('age')}")
            print(f"  Hobbies in seeds: \"{seeds.get('hobbies')}\"")
            print(f"  Insecurities in seeds: \"{seeds.get('insecurities')}\"")
            
            # Assert keys are present
            missing = [k for k in required_keys if k not in seeds]
            if missing:
                print(f"  [FAIL] Missing seeds keys: {missing}")
                all_success = False
            else:
                print("  [OK] All required memory seed keys are present.")
                
        except Exception as e:
            print(f"  [FAIL] Error loading/seeding companion {cid}: {e}")
            all_success = False
            
    print("\n=======================================================")
    if all_success:
        print("[OK] ALL 12 COMPANION MEMORY SEEDS ARE FULLY SEEDED AND COMPLETE!")
    else:
        print("[FAIL] SOME COMPANION MEMORIES ENCOUNTERED ISSUES.")
        sys.exit(1)

if __name__ == "__main__":
    test_seeding()
