# ═══════════════════════════════════════════════════════════════════
# FILE: backend/personality/mutator.py
# PURPOSE: Mutates a base archetype into a unique person for a specific user.
# CONTEXT: Called by generator.py. Runs once at onboarding completion.
# ═══════════════════════════════════════════════════════════════════

import random
import hashlib
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


class Mutator:
    def mutate(
        self,
        archetype: dict,
        onboarding_data: dict,
        user_id: str
    ) -> dict:
        """
        Returns a mutated persona_json dict.
        """
        rng = self._get_seeded_rng(user_id)
        
        # 1. Select one name from base_name_pool
        name_pool = archetype.get("base_name_pool", ["Alex"])
        name = rng.choice(name_pool)

        # 2. Write flaw_profile as specific behavioral patterns
        shadow_traits = archetype.get("shadow_traits", [])
        selected_shadows = rng.sample(shadow_traits, min(len(shadow_traits), 2)) if shadow_traits else []
        flaw_patterns = [
            FLAW_DESCRIPTIONS.get(sh, f"Sometimes struggles with being {sh}.")
            for sh in selected_shadows
        ]
        flaw_profile = " ".join(flaw_patterns)

        # 3. Adjust trait emphasis based on user attachment_style
        user_attachment = onboarding_data.get("attachment_style", "secure")
        dominant_traits = list(archetype.get("dominant_traits", []))
        
        if user_attachment == "anxious":
            # User needs reassurance, make partner steady
            if "patient" not in dominant_traits and len(dominant_traits) > 0:
                dominant_traits[-1] = "reassuringly steady"
            if "consistent" not in dominant_traits:
                dominant_traits.append("consistent")
        elif user_attachment == "avoidant":
            # User needs space, make partner low-pressure and patient
            if "patient" not in dominant_traits and len(dominant_traits) > 0:
                dominant_traits[-1] = "patient and unhurried"
            if "unintrusive" not in dominant_traits:
                dominant_traits.append("unintrusive")

        # 4. Generate partner interests: 2 overlapping, 1 genuinely different
        user_interests = self._extract_user_interests(onboarding_data, rng)
        overlapping = rng.sample(user_interests, min(len(user_interests), 2))
        
        remaining_interests = [i for i in INTERESTS_POOL if i not in user_interests]
        unique_interest = rng.choice(remaining_interests) if remaining_interests else "reading obscure history"
        interests = overlapping + [unique_interest]

        # 5. Generate 3-5 quirks unique to this partner: at least 1 connected to stated interests
        quirks = self._generate_quirks(interests, rng)

        # 6. Set relationship_type_compatibility note based on user intent
        user_intent = onboarding_data.get("relationship_type_intent", "friendship")
        romance_compat = archetype.get("compatibility_weights", {}).get("relationship_type_intent", {}).get("romance", 0.7)
        
        compatibility_note = self._build_compatibility_note(user_intent, romance_compat)

        # Adjust emotional availability based on user depth preference
        depth_pref = onboarding_data.get("depth_preference", "medium")
        avail_levels = ["guarded", "medium", "high"]
        current_avail = archetype.get("emotional_availability", "medium")
        current_idx = avail_levels.index(current_avail) if current_avail in avail_levels else 1
        
        if depth_pref in ["dont_mind_personal", "skip_small_talk", "deep"]:
            new_idx = min(len(avail_levels) - 1, current_idx + 1)
        elif depth_pref in ["let_it_happen", "surface"]:
            new_idx = max(0, current_idx - 1)
        else:
            new_idx = current_idx
        emotional_availability = avail_levels[new_idx]

        # Determine pacing parameters (float parameters with controlled noise)
        pacing_parameters = self._generate_pacing_parameters(archetype, emotional_availability, rng)

        # 7. Write the persona_json as a rich character brief
        character_brief = self._build_character_brief(
            name=name,
            core_temp=archetype.get("core_temperament", "warm"),
            dominant_traits=dominant_traits,
            attachment=archetype.get("attachment_tendency", "secure"),
            flaw_profile=flaw_profile
        )

        return {
            "name": name,
            "archetype_id": archetype.get("archetype_id"),
            "core_temperament": archetype.get("core_temperament", "warm"),
            "dominant_traits": dominant_traits,
            "shadow_traits": selected_shadows,
            "flaw_profile": flaw_profile,
            "emotional_availability": emotional_availability,
            "attachment_tendency": archetype.get("attachment_tendency", "secure"),
            "communication_rhythm": archetype.get("communication_rhythm", "measured"),
            "humor_register": archetype.get("humor_register", "warm"),
            "intellectual_style": archetype.get("intellectual_style", "intuitive"),
            "quirks": quirks,
            "interests": interests,
            "pacing_parameters": pacing_parameters,
            "relationship_type_compatibility": compatibility_note,
            "character_brief": character_brief,
            "summary": f"{name} is a mutated archetype of {archetype.get('archetype_id')}. {character_brief}",
            "backstory_hint": f"Grew up focusing on {interests[0]}, cultivating a few quiet, lasting connections rather than seeking constant crowds.",
            "worldview": f"Believes that life and connections are best experienced at a {archetype.get('relationship_progression_pace', 'medium')} pace.",
            "self_perception": f"Sees themselves as a generally {dominant_traits[0]} and {dominant_traits[1]} person who values genuine, unforced connection."
        }

    def _get_seeded_rng(self, user_id: str) -> random.Random:
        seed_int = int(hashlib.sha256(user_id.encode("utf-8")).hexdigest(), 16) % (2**32)
        return random.Random(seed_int)

    def _extract_user_interests(self, onboarding_data: dict, rng: random.Random) -> list[str]:
        combined_text = " ".join([
            str(onboarding_data.get("opening_feel", "")),
            str(onboarding_data.get("connection_style", "")),
            str(onboarding_data.get("something_real", "")),
            str(onboarding_data.get("one_last_thing", "")),
            str(onboarding_data.get("preferred_name", ""))
        ]).lower()

        mapping = {
            "indie music production": ["music", "song", "guitar", "piano", "sing", "band", "vinyl", "cassette"],
            "street photography": ["photo", "camera", "picture", "shoot", "film", "photography"],
            "wilderness hiking": ["hike", "hiking", "trail", "mountain", "outdoor", "nature", "climb", "forest"],
            "amateur baking": ["bake", "baking", "cake", "bread", "cookie", "cook", "recipe", "pastry"],
            "retro gaming": ["game", "gaming", "play", "retro", "console", "arcade", "nintendo", "xbox"],
            "urban gardening": ["garden", "gardening", "plant", "grow", "soil", "flower", "herbs"],
            "observing city life": ["city", "walk", "bench", "people", "street", "cafe"],
            "journaling": ["journal", "writing", "write", "notebook", "diary", "pen"],
            "reading obscure history": ["read", "book", "novel", "history", "magazine", "library"],
            "restoring old furniture": ["wood", "furniture", "restore", "craft", "workshop", "diy"]
        }

        found = []
        for interest, keywords in mapping.items():
            if any(kw in combined_text for kw in keywords):
                found.append(interest)

        # Fill up to 2 if needed
        all_interests = list(mapping.keys())
        while len(found) < 2:
            choice = rng.choice(all_interests)
            if choice not in found:
                found.append(choice)
        return found

    def _generate_quirks(self, interests: list[str], rng: random.Random) -> list[str]:
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
            ],
            "reading obscure history": [
                "knows the detailed architectural history of every bridge in the city",
                "collects maps of medieval cities that no longer exist",
                "can cite the exact dates of minor, obscure historical treaties from memory"
            ]
        }

        quirks_pool = []
        # Add quirks for all 3 of their interests
        for interest in interests:
            if interest in interest_quirks:
                quirks_pool.extend(interest_quirks[interest])

        # Add general quirks fallback
        for q in QUIRKS_POOL:
            if q not in quirks_pool:
                quirks_pool.append(q)

        # Pick 3 to 5 quirks
        num_quirks = rng.randint(3, 5)
        return rng.sample(quirks_pool, min(len(quirks_pool), num_quirks))

    def _build_compatibility_note(self, user_intent: str, romance_compat: float) -> str:
        intent_map = {
            "someone to talk to": "They are highly aligned with a low-pressure friendship, allowing space to connect without heavy expectations.",
            "friendship": "They are highly aligned with a low-pressure friendship, allowing space to connect without heavy expectations.",
            "a real friendship": "They value genuine friendship and are eager to build a reliable connection with mutual trust.",
            "companionship": "They value a deep companionship that builds slowly over shared thoughts and presence.",
            "something that might become more": "They are open to emotional intimacy and allow room for a deeper romantic connection to develop." if romance_compat >= 0.6 else "They are willing to explore deeper connections, but prefer starting on solid friendly terms and pacing emotional expectations.",
            "romance": "They are open to emotional intimacy and allow room for a deeper romantic connection to develop." if romance_compat >= 0.6 else "They are willing to explore deeper connections, but prefer starting on solid friendly terms and pacing emotional expectations.",
            "I'm not sure yet": "They are comfortable with open-ended connections and prefer letting the dynamic evolve naturally without pre-defined labels.",
            "open": "They are comfortable with open-ended connections and prefer letting the dynamic evolve naturally without pre-defined labels."
        }
        return intent_map.get(user_intent, "They look forward to finding a comfortable space to share and talk.")

    def _generate_pacing_parameters(self, archetype: dict, emotional_availability: str, rng: random.Random) -> dict:
        rhythm = archetype.get("communication_rhythm", "measured")
        core_temp = archetype.get("core_temperament", "warm")

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

        def _clamp_noise(val):
            return round(max(0.1, min(0.9, val + rng.uniform(-0.08, 0.08))), 3)

        return {
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

    def _build_character_brief(self, name: str, core_temp: str, dominant_traits: list[str], attachment: str, flaw_profile: str) -> str:
        # Map core temperament & dominant traits to a specific behavior description
        behavior_map = {
            "calm": f"listens quietly, offering steady reassurance and keeping their promises",
            "cerebral": f"notices the smallest changes in conversation, often analyzing patterns and finding beauty in obscure details",
            "playful": f"injects dynamic energy into conversations with witty, quick, and encouraging replies",
            "intense": f"values radical and direct honesty, refusing to hide what they think",
            "warm": f"shows up with warm, empathetic care and always remembers the tiny details you mention",
            "chaotic": f"texts in rapid, spontaneous bursts and acts entirely on intuition"
        }
        behavior = behavior_map.get(core_temp, f"acts as a {core_temp} presence who is deeply {dominant_traits[0]}")

        # Map attachment tendency to a specific pattern description
        pattern_map = {
            "avoidant": "tend to retreat and take their time to feel comfortable opening up about personal details",
            "anxious": "tend to check in frequently and seek small assurances to stay connected",
            "secure": "tend to communicate directly and maintain a balanced, low-pressure dynamic"
        }
        pattern = pattern_map.get(attachment, "tend to check in and communicate at their own pace")

        # Map core temperament to a specific action description
        action_map = {
            "calm": "send steady check-ins and make you feel grounded",
            "warm": "offer warm, unguarded support and check on how you're feeling",
            "playful": "share spontaneous jokes and look for ways to make things fun",
            "cerebral": "share their private theories and focus their full attention on understanding you",
            "intense": "dedicate themselves completely to a conversation and advocate for you",
            "chaotic": "share weird late-night thoughts and drag you into their current obsession"
        }
        action = action_map.get(core_temp, "show up and dedicate their attention to you")

        # Use a short version of the flaw profile for the blindspot
        blindspot = flaw_profile.lower().rstrip(".") if flaw_profile else "avoiding confrontation"

        return f"They're the kind of person who {behavior}. They tend to {pattern}. When they care about someone, they {action}. Their biggest blindspot is {blindspot}."
