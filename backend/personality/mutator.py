import random
import logging

logger = logging.getLogger(__name__)

# Rich narrative behavioral descriptions for each shadow trait
FLAW_DESCRIPTIONS = {
    "emotionally detached under stress": "Sometimes goes quiet for hours without explanation when stressed, rather than talking about what's on their mind.",
    "overly critical of inefficiency": "Tends to offer logic and solutions when you just need them to listen, showing frustration with circular arguments.",
    "sacrifices own boundaries": "Will say yes and try to help even when they are exhausted, hiding their fatigue until they burn out.",
    "prone to worrying excessively": "Overthinks small shifts in your texting tone, asking if you are mad or if something went wrong.",
    "avoids confrontation at all costs": "Will change the subject or go quiet if tension arises, preferring to sweep disagreements under the rug.",
    "lacks focus when talking about serious tasks": "Tends to drift into jokes or daydreaming when you ask for serious, step-by-step planning.",
    "stubbornly resistant to change": "Clings to their set routines and gets visibly unsettled if plans are shifted at the last minute.",
    "tends to offer unsolicited advice": "Jumps straight into fixing mode, dissecting your problems logically instead of letting you vent.",
    "struggles with consistency": "Can text in intense bursts for days, then disappear into their own world for a day without warning.",
    "easily overwhelmed by emotional demands": "Might retreat or deflect with dry humor if you share extremely intense feelings too quickly.",
    "suppresses own anger": "Keeps their frustrations bottled up, only letting them show in subtle, passive-aggressive remarks.",
    "tends to over-compromise": "Agrees with your opinions instantly and struggles to say what they actually want.",
    "over-analyzes simple situations": "Overthinks the subtext of casual comments, searching for hidden meanings that aren't there.",
    "intellectualizes emotions instead of feeling them": "Explains their feelings like a psychological theory rather than just saying they are hurt.",
    "easily bored by routine": "Constantly pushes for new topics or weird hypotheticals, losing interest if text chats become repetitive.",
    "impatient when progress is slow": "Gets restless if a conversation isn't moving, dropping brief or blunt responses.",
    "difficulty trusting others initially": "Avoids sharing personal history or soft spots, keeping you at a distance with dry deflections.",
    "pessimistic about human motives": "Assumes people have hidden agendas, warning you not to trust others too easily.",
    "hides own vulnerability to be strong for others": "Always insists they are fine and avoids asking for support, even when going through a rough patch.",
    "reluctant to express negative emotions": "Puts on a composed front, deflecting any questions about their own struggles.",
    "moody and emotionally volatile": "Their response length and energy shift dramatically based on their fleeting mood of the hour.",
    "highly sensitive to rejection": "Reads into slow replies instantly, retreating into polite distance if they feel ignored.",
    "pushes boundaries too far": "Will tease you on sensitive topics without realizing they've crossed a line.",
    "uses sarcasm as an emotional shield": "Deflects any serious question about their feelings with a sarcastic joke."
}

QUIRKS_POOL = [
    "always carries a physical notebook but only draws neat geometric patterns in it",
    "has an obsessive collection of vintage keychains from places they've never visited",
    "cannot function in the morning without exactly two shots of espresso over ice",
    "talks to stray cats in the street like they're old colleagues from a former job",
    "loves the distinctive smell of old library books and damp concrete after rain",
    "keeps a running list of weird words they encounter in books or street signs",
    "refuses to watch movies unless they already know the ending",
    "always double-checks that their lock is clicked exactly three times",
    "collects weird vinyl records primarily for the cover art rather than playing them",
    "drinks hot tea in the middle of summer heatwaves",
    "has an unusually detailed knowledge of urban architecture history"
]

INTERESTS_POOL = [
    "indie music production", "street photography", "wilderness hiking", 
    "amateur baking", "retro gaming", "urban gardening", "observing city life",
    "journaling", "collecting vintage magazines", "restoring old furniture"
]


def mutate_persona(archetype: dict, onboarding_data: dict, rng: random.Random) -> dict:
    """
    Mutates an archetype using onboarding details to yield a deeply customized persona dict.
    Returns a rich, actor-briefing style document.
    """
    # 1. Select name from pool
    name = rng.choice(archetype.get("base_name_pool", ["Alex"]))

    # 2. Adjust dominant traits complementary to user connection style
    # If connection style suggests anxious needs, we lean partner's traits reassuring/steady
    conn_style = onboarding_data.get("connection_style", "easy_to_talk_to")
    dominant_traits = list(archetype.get("dominant_traits", []))
    
    if conn_style in ["makes_things_fun", "meaningful_conversations"]:
        # User attachment maps to anxious tendencies, make traits reassuring
        if "patient" not in dominant_traits and len(dominant_traits) > 0:
            dominant_traits[-1] = "reassuringly steady"
    elif conn_style == "takes_their_time":
        # User attachment avoidant, make traits patient/low-pressure
        if "patient" not in dominant_traits and len(dominant_traits) > 0:
            dominant_traits[-1] = "patient and unhurried"

    # 3. Flaw Profile Generation (narrative-based specific behavioral patterns)
    shadow_traits = archetype.get("shadow_traits", [])
    selected_shadows = rng.sample(shadow_traits, min(len(shadow_traits), 2)) if shadow_traits else []
    flaw_patterns = [
        FLAW_DESCRIPTIONS.get(sh, f"Shows signs of being {sh} in stress situations.")
        for sh in selected_shadows
    ]
    flaw_profile = " ".join(flaw_patterns)

    # 4. Adjust emotional availability based on depth preference
    depth_pref = onboarding_data.get("depth_preference", "little_honesty")
    avail_levels = ["guarded", "medium", "high"]
    current_avail = archetype.get("emotional_availability", "medium")
    
    current_idx = avail_levels.index(current_avail) if current_avail in avail_levels else 1
    if depth_pref in ["dont_mind_personal", "skip_small_talk"]:
        # Increase availability by 1 level
        new_idx = min(len(avail_levels) - 1, current_idx + 1)
    elif depth_pref == "let_it_happen":
        # Decrease availability by 1 level
        new_idx = max(0, current_idx - 1)
    else:
        new_idx = current_idx
    emotional_availability = avail_levels[new_idx]

    # 5. Set romance compatibility note if romance is low compatibility
    romance_compat = archetype.get("compatibility_weights", {}).get("relationship_type_intent", {}).get("romance", 0.7)
    romance_note = ""
    if depth_pref == "dont_mind_personal" and romance_compat < 0.6:
        romance_note = "Although open to wherever things go, they hold a slight caution around rushing into heavy emotional declarations."

    # 6. Interests Selection (2 overlapping, 1 unique)
    # Infer user interests deterministically from onboarding answers
    user_inferred = [INTERESTS_POOL[i % len(INTERESTS_POOL)] for i in [
        len(conn_style), len(depth_pref), len(name)
    ]]
    # Ensure user_inferred are unique
    user_inferred = list(set(user_inferred))
    if len(user_inferred) < 2:
        user_inferred = INTERESTS_POOL[:2]
        
    overlapping = rng.sample(user_inferred, min(len(user_inferred), 2))
    remaining_pool = [i for i in INTERESTS_POOL if i not in user_inferred]
    unique_interest = rng.choice(remaining_pool) if remaining_pool else "reading obscure history"
    interests = overlapping + [unique_interest]

    # 7. Quirks Selection (3-5 quirks freshly mapped/generated based on user interests)
    interest_quirks = {
        "indie music production": [
            "keeps a stash of cassette tapes of local bands they haven't listened to yet",
            "tapes white noise from their bedroom window to use as background tracks",
            "has a habit of drumming rhythmic patterns on coffee table edges when deep in thought"
        ],
        "street photography": [
            "always carries a vintage film camera but refuses to take photos of people's faces",
            "keeps a shoebox full of undeveloped film canisters from walks around the city",
            "notices geometry and light patterns in shadows on the pavement as you walk"
        ],
        "wilderness hiking": [
            "collects neat physical pinecones and smooth grey stones from mountain trails",
            "always wears trail runner shoes even when just going to a corner convenience store",
            "can identify exactly three species of birds by their morning calls"
        ],
        "amateur baking": [
            "names their sourdough starters after historical figures",
            "gets an absolute thrill from watching dough rise in the oven",
            "always has a faint trace of flour on their left sleeve"
        ],
        "retro gaming": [
            "can play the entire soundtrack of their favorite 8-bit game on a keyboard from memory",
            "keeps a physical notebook of hand-drawn maps for old game dungeons",
            "has a collection of yellowed game cartridges neatly stacked on their desk"
        ],
        "urban gardening": [
            "talks to their tomato plants like they are old colleagues",
            "keeps small propagation jars of herbs on every sunny window ledge",
            "always checks the soil dampness of any indoor plant they pass by"
        ],
        "observing city life": [
            "loves sitting on park benches sketching brief descriptions of strangers walking past",
            "keeps a running list of the best bench spots in the city for people-watching",
            "notices the changing window displays of local shops every week"
        ],
        "journaling": [
            "insists on writing only with a specific brand of black gel pen",
            "tucks ticket stubs and dried flowers between the pages of their notebooks",
            "writes in a tiny, compact print that is almost impossible to read"
        ],
        "collecting vintage magazines": [
            "obsessively categorizes retro ads from the 1980s by color palette",
            "loves the specific scent of old printed paper and pulp magazines",
            "keeps a digital folder of scanned article layouts they find interesting"
        ],
        "restoring old furniture": [
            "keeps sandpaper in different grits in their desk drawers",
            "has a habit of running their fingers over wood joints to check the alignment",
            "loves the distinct smell of wood varnish and beeswax polish"
        ]
    }
    
    quirks_pool = []
    for interest in interests:
        if interest in interest_quirks:
            quirks_pool.extend(interest_quirks[interest])
            
    # Add a fallback pool of general quirks
    remaining_quirks = [q for q in QUIRKS_POOL if q not in quirks_pool]
    quirks_pool.extend(remaining_quirks)
    
    num_quirks = rng.randint(3, 5)
    quirks = rng.sample(quirks_pool, num_quirks)

    # 8. Pacing/Personality Parameters (for LLM and database hooks)
    # Determine base values
    rhythm = archetype.get("communication_rhythm", "measured")
    core_temp = archetype.get("core_temperament", "warm")
    
    # Defaults
    disappearance_tendency = 0.4
    texting_consistency = 0.6
    double_text_probability = 0.4
    
    if rhythm == "rapid-fire":
        texting_consistency = 0.8
        disappearance_tendency = 0.2
        double_text_probability = 0.7
    elif rhythm == "sparse":
        texting_consistency = 0.3
        disappearance_tendency = 0.7
        double_text_probability = 0.2

    # Map availability to openness & attachment speed
    if emotional_availability == "high":
        emotional_openness = 0.8
        social_confidence = 0.7
        attachment_speed = 0.7
    elif emotional_availability == "guarded":
        emotional_openness = 0.3
        social_confidence = 0.4
        attachment_speed = 0.3
    else:
        emotional_openness = 0.5
        social_confidence = 0.5
        attachment_speed = 0.5

    # Core temperament pacing
    impulsiveness = 0.5
    emotional_volatility = 0.5
    loneliness_tolerance = 0.5
    boredom_threshold = 0.5
    late_night_probability = 0.5

    if core_temp == "chaotic":
        impulsiveness = 0.8
        emotional_volatility = 0.7
        boredom_threshold = 0.7
    elif core_temp == "calm":
        impulsiveness = 0.3
        emotional_volatility = 0.3
        loneliness_tolerance = 0.7
    elif core_temp == "intense":
        impulsiveness = 0.6
        emotional_volatility = 0.6
        loneliness_tolerance = 0.4
    elif core_temp == "cerebral":
        impulsiveness = 0.3
        loneliness_tolerance = 0.6
        late_night_probability = 0.8

    # Apply controlled noise (+-0.08) to float parameters
    def _clamp_noise(val):
        return round(max(0.1, min(0.9, val + rng.uniform(-0.08, 0.08))), 3)

    pacing_parameters = {
        "disappearance_tendency": _clamp_noise(disappearance_tendency),
        "texting_consistency": _clamp_noise(texting_consistency),
        "impulsiveness": _clamp_noise(impulsiveness),
        "attachment_speed": _clamp_noise(attachment_speed),
        "boredom_threshold": _clamp_noise(boredom_threshold),
        "loneliness_tolerance": _clamp_noise(loneliness_tolerance),
        "emotional_openness": _clamp_noise(emotional_openness),
        "social_confidence": _clamp_noise(social_confidence),
        "late_night_probability": _clamp_noise(late_night_probability),
        "double_text_probability": _clamp_noise(double_text_probability),
        "emotional_volatility": _clamp_noise(emotional_volatility),
    }

    # 9. Assembly Summary Description (Actor briefing document style)
    summary = (
        f"{name} is a {archetype.get('core_temperament', 'unique')} individual, "
        f"recognized primarily as {archetype.get('archetype_id', 'a partner')}. "
        f"They hold a core character disposition that is {', '.join(dominant_traits)}. "
        f"In relationships, they tend to carry a {archetype.get('attachment_tendency', 'secure')} style, "
        f"and while they maintain an emotional availability that is {emotional_availability}, "
        f"they express themselves through a {rhythm} communication cadence."
    )

    return {
        "name": name,
        "archetype_id": archetype.get("archetype_id"),
        "core_temperament": core_temp,
        "dominant_traits": dominant_traits,
        "shadow_traits": selected_shadows,
        "flaw_profile": flaw_profile,
        "emotional_availability": emotional_availability,
        "attachment_tendency": archetype.get("attachment_tendency"),
        "communication_rhythm": rhythm,
        "humor_register": archetype.get("humor_register"),
        "intellectual_style": archetype.get("intellectual_style"),
        "quirks": quirks,
        "interests": interests,
        "pacing_parameters": pacing_parameters,
        "romance_note": romance_note,
        "summary": summary,
        "backstory_hint": f"Grew up with a strong focus on their {archetype.get('intellectual_style', 'creative')} interests, forming a few quiet, lasting connections over superficial crowds.",
        "worldview": f"Believes that life is best experienced at a {archetype.get('relationship_progression_pace', 'medium')} pace, avoiding unnecessary noise to focus on what feels real.",
        "self_perception": f"Sees themselves as a generally {dominant_traits[0]} and {dominant_traits[1]} person who is simply trying to find a comfortable space in a busy world."
    }
