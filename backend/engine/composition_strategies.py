# ═══════════════════════════════════════════════════════════════════
# FILE: engine/composition_strategies.py
# PURPOSE: Mood-specific texting patterns and decomposition strategies.
# CONTEXT: Used by composition_engine.py to customize burst behavior.
# ═══════════════════════════════════════════════════════════════════

from typing import Dict, Any

COMPOSITION_STRATEGIES: Dict[str, Dict[str, Any]] = {
    "playful_high": {
        "max_bursts": 4,
        "min_bursts": 2,
        "max_sentences_per_burst": 1,
        "delays": [400, 700, 500],
        "typing_time_range": (150, 300),
        "prefer_short_bursts": True,
        "reaction_first": True,
    },
    "warm_normal": {
        "max_bursts": 3,
        "min_bursts": 2,
        "max_sentences_per_burst": 2,
        "delays": [800, 1200],
        "typing_time_range": (350, 600),
        "prefer_short_bursts": False,
        "emotional_first": True,
    },
    "reflective_low": {
        "max_bursts": 2,
        "min_bursts": 1,
        "max_sentences_per_burst": 3,
        "delays": [2000, 4000],
        "typing_time_range": (700, 1200),
        "prefer_short_bursts": False,
    },
    "quiet_low": {
        "max_bursts": 2,
        "min_bursts": 1,
        "max_sentences_per_burst": 1,
        "delays": [3000, 6000],
        "typing_time_range": (400, 800),
        "prefer_short_bursts": True,
        "allow_fragments": True,
    },
    "distracted_normal": {
        "max_bursts": 4,
        "min_bursts": 2,
        "max_sentences_per_burst": 2,
        "delays": "randomized",  # Handled dynamically (erratic, scattered)
        "typing_time_range": "inconsistent",  # Handled dynamically
        "prefer_short_bursts": False,
        "allow_self_corrections": True,
    },
    "content_normal": {
        "max_bursts": 3,
        "min_bursts": 2,
        "max_sentences_per_burst": 2,
        "delays": [1000, 2000],
        "typing_time_range": (400, 600),
        "prefer_short_bursts": False,
    },
    "tired_low": {
        "max_bursts": 2,
        "min_bursts": 1,
        "max_sentences_per_burst": 1,
        "delays": [3000, 5000],
        "typing_time_range": (300, 700),
        "prefer_short_bursts": True,
    }
}

def get_strategy(mood: str, energy: str) -> Dict[str, Any]:
    """
    Returns the composition strategy dictionary based on partner mood and energy.
    Falls back gracefully if no exact match is found.
    """
    m = (mood or "content").lower().strip()
    e = (energy or "normal").lower().strip()
    key = f"{m}_{e}"
    
    if key in COMPOSITION_STRATEGIES:
        return COMPOSITION_STRATEGIES[key]
        
    # Fallback to mood-specific matches with reasonable energy assumptions
    if m == "playful":
        return COMPOSITION_STRATEGIES["playful_high"]
    elif m == "warm":
        return COMPOSITION_STRATEGIES["warm_normal"]
    elif m == "reflective":
        return COMPOSITION_STRATEGIES["reflective_low"]
    elif m == "quiet":
        return COMPOSITION_STRATEGIES["quiet_low"]
    elif m == "distracted":
        return COMPOSITION_STRATEGIES["distracted_normal"]
    elif m == "tired":
        return COMPOSITION_STRATEGIES["tired_low"]
    elif m == "content":
        return COMPOSITION_STRATEGIES["content_normal"]
        
    # General fallback
    return COMPOSITION_STRATEGIES["content_normal"]
