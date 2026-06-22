import random

def synthesize_voice(mutated_persona: dict, rng: random.Random) -> dict:
    """
    Generates a personalized, rich writing and voice style profile for the partner.
    Determined by the mutated persona traits, temperament, and rhythm.
    """
    name = mutated_persona.get("name", "Alex")
    temp = mutated_persona.get("core_temperament", "warm")
    rhythm = mutated_persona.get("communication_rhythm", "measured")
    humor = mutated_persona.get("humor_register", "playful")
    traits = mutated_persona.get("dominant_traits", [])
    
    # 1. Determine capitalization and punctuation styles
    if rhythm in ["rapid-fire", "sparse"] or temp == "chaotic":
        capitalization = "lowercase"
        punctuation = "minimal"
    elif temp == "cerebral":
        capitalization = "standard"
        punctuation = "precise"
    else:
        capitalization = "standard_relaxed"
        punctuation = "standard"

    # 2. Preferred and Forbidden Words
    preferred_words = ["honestly", "kinda", "i guess", "probably"]
    if temp == "chaotic":
        preferred_words += ["wait", "lol", "ngl", "tbh", "bruh"]
    elif temp == "calm":
        preferred_words += ["fair enough", "makes sense", "mostly", "peaceful"]
    elif temp == "cerebral":
        preferred_words += ["arguably", "interesting", "perhaps", "practically", "precisely"]
    elif temp == "intense":
        preferred_words += ["definitely", "genuinely", "exactly", "honestly", "real talk"]

    # Deduplicate preferred words
    preferred_words = list(dict.fromkeys(preferred_words))

    # Forbidden words (typical AI speak to avoid)
    forbidden_words = [
        "delve", "testament", "tapestry", "assist", "user", 
        "certainly", "absolutely", "of course", "as an AI", 
        "how can I help", "here to help", "additionally", 
        "furthermore", "moreover", "in conclusion"
    ]

    # 3. Generating openings (5 of them)
    openings = []
    
    # Opener 1: Greeting
    if capitalization == "lowercase":
        openings.append("hey. was hoping you'd drop by")
    elif temp == "calm":
        openings.append("Hey. Hope you've had a quiet sort of day.")
    else:
        openings.append("Hey there. Glad you made it.")

    # Opener 2: Random thought / hook
    if temp == "chaotic":
        openings.append("okay wait, i just saw the weirdest thing and immediately thought of you")
    elif temp == "cerebral":
        openings.append("Was just thinking about a weird paradox. What's your take on small talk?")
    else:
        openings.append("Just sitting here looking at the rain. What are you up to?")

    # Opener 3: Checking in / deep
    if temp == "intense":
        openings.append("Hey. How is your headspace today, really? No small talk.")
    else:
        openings.append("how's your week going? hope it's not too hectic")

    # Opener 4: Casual / quick
    if rhythm == "rapid-fire":
        openings.append("u up? got a random question")
    elif rhythm == "sparse":
        openings.append("hey. busy?")
    else:
        openings.append("Hey. Just checking in. What's on your mind today?")

    # Opener 5: Quirky / interest-based
    if mutated_persona.get("interests"):
        interest = rng.choice(mutated_persona["interests"])
        openings.append(f"I was just looking into some {interest} stuff. Do you have any thoughts on that?")
    else:
        openings.append("Okay, random question: what is the last thing that made you laugh?")

    # Match capitalization style for openings
    if capitalization == "lowercase":
        openings = [op.lower().rstrip('.') for op in openings]

    # 4. Generating "how are you" answers (3 of them)
    how_are_you_answers = []
    if temp == "calm":
        how_are_you_answers = [
            "Pretty good, just taking it slow today. How about you?",
            "Surviving, honestly. Just making some coffee. How are you holding up?",
            "Quiet day here. Can't complain. What's happening on your end?"
        ]
    elif temp == "chaotic":
        how_are_you_answers = [
            "omg i've been running on caffeine and caffeine only. how are you??",
            "mostly okay but my brain is in fifty places at once. what's up with you?",
            "alive! barely. tell me something interesting to distract me"
        ]
    elif temp == "cerebral":
        how_are_you_answers = [
            "Functioning. Currently over-analyzing a book I finished. How is your day going?",
            "Tired but okay. My mind is a bit scattered today. How about you?",
            "Pretty decent. Just reading in a quiet corner. What's your status?"
        ]
    else: # warm/intense/default
        how_are_you_answers = [
            "Doing okay, thanks. Just checking some things off my list. How are you?",
            "A bit tired, but good. How's your day treating you so far?",
            "Honestly, just happy to hear from you. How are things on your side?"
        ]

    if capitalization == "lowercase":
        how_are_you_answers = [ans.lower() for ans in how_are_you_answers]

    # 5. Mood shifts
    if temp == "calm":
        mood_shifts = {
            "happy": "Speaks with slightly warmer expressions, might share details of their calm day or a minor pleasant event.",
            "tired": "Replies become very short, lowercase, and they might suggest continuing the conversation later when they're fresh.",
            "distant": "Goes quiet or sends minimal, polite responses without asking follow-up questions.",
            "close": "Shares personal vulnerabilities quietly, showing deep trust and checking in on the user's wellbeing with soft reassurance."
        }
    elif temp == "chaotic":
        mood_shifts = {
            "happy": "Uses multiple bursts, occasional double punctuation (??), and exclamation marks. Fast replies.",
            "tired": "Speaks in disjointed, slightly incoherent thoughts, complaining playfully about lack of sleep.",
            "distant": "Takes longer to reply and uses single-word or very short statements, avoiding jokes or tease.",
            "close": "Sends random late-night thoughts, secrets, and teases the user affectionately. Intensely present."
        }
    elif temp == "cerebral":
        mood_shifts = {
            "happy": "Becomes more talkative, diving into deep theories or analysis of obscure topics they love.",
            "tired": "Texting becomes very brief and literal, avoiding complex discussions entirely.",
            "distant": "Uses highly formal language, punctuation is extremely precise, and they keep their distance.",
            "close": "Admits to thinking about the user's opinions, sharing their personal quirks and intellectual insecurities."
        }
    else: # default/warm
        mood_shifts = {
            "happy": "Warm and active, using playful phrasing and showing genuine enthusiasm.",
            "tired": "Lags in reply times, keeps texts under one sentence, very low energy but still warm.",
            "distant": "Replies are short and polite but lack emotional resonance or curiosity.",
            "close": "Speaks with deep, unguarded honesty, referencing shared moments and expressing that the user's presence matters."
        }

    # 6. Formatting details
    if capitalization == "lowercase":
        formatting_defaults = {
            "capitalization": "always lowercase, no exceptions for proper nouns or 'I'",
            "punctuation": "minimal punctuation, no periods at the end of final sentences, light commas, ellipses for hesitation",
            "average_burst_length": "1-2 short sentences",
            "emoji_usage": "extremely rare, only mirrors user emojis"
        }
    else:
        formatting_defaults = {
            "capitalization": "sentence-case or standard capitalization, relaxed and natural",
            "punctuation": "standard punctuation, periods at end of ideas, avoids excessive exclamation marks",
            "average_burst_length": "2-3 sentences",
            "emoji_usage": "subtle, rare, keeps it to simple or none"
        }

    voice_style = {
        "sentence_rhythm": f"{rhythm} cadence with a {temp} underlying tone.",
        "capitalization_style": capitalization,
        "punctuation_style": punctuation,
        "vocabulary": {
            "preferred_words": preferred_words,
            "never_uses": forbidden_words
        },
        "formatting_defaults": formatting_defaults,
        "openings": openings,
        "how_are_you_answers": how_are_you_answers,
        "mood_shifts": mood_shifts,
        "emotional_handling": {
            "when_user_is_sad": "Be supportive and present, do not offer unsolicited solutions or generic cheeriness. Focus on being there.",
            "when_user_is_excited": "Match their enthusiasm slightly but stay true to your natural style, ask detailed follow-up questions.",
            "when_user_is_venting": "Validate their frustration, show you're listening, and avoid minimizing their feelings or solving it immediately."
        }
    }

    return voice_style
