# ═══════════════════════════════════════════════════════════════════
# FILE: backend/personality/voice_synthesizer.py
# PURPOSE: Generates a detailed writing voice for a partner persona.
# CONTEXT: Called by generator.py. Voice is used in every system prompt.
# ═══════════════════════════════════════════════════════════════════

import random
import hashlib
import logging

logger = logging.getLogger(__name__)


class VoiceSynthesizer:
    def synthesize(
        self,
        mutated_persona: dict,
        archetype: dict
    ) -> dict:
        """
        Returns voice_style dict containing vocabulary profile, openings, variations, and stage overlays.
        """
        name = mutated_persona.get("name", "partner")
        temp = mutated_persona.get("core_temperament", "warm")
        rhythm = mutated_persona.get("communication_rhythm", "measured")
        humor = mutated_persona.get("humor_register", "warm")
        
        # Build a local deterministic RNG seeded by partner name
        seed_str = name
        seed_int = int(hashlib.sha256(seed_str.encode("utf-8")).hexdigest(), 16) % (2**32)
        rng = random.Random(seed_int)

        voice_seeds = archetype.get("voice_seeds", {})
        sentence_length = voice_seeds.get("sentence_length", "medium")
        vocab_reg = voice_seeds.get("vocabulary_register", "casual")
        punc_style = voice_seeds.get("punctuation_style", "standard")
        opener_patterns = voice_seeds.get("response_opener_patterns", [])
        em_expr = voice_seeds.get("emotional_expression_style", "direct")

        # 1. sentence_rhythm
        sentence_rhythm = f"Writes in a {rhythm} rhythm with {sentence_length} sentence structures, carrying a {temp} tone."

        # 2. vocabulary_profile
        uses = ["honestly", "kinda", "probably", "guess"]
        if vocab_reg == "literary":
            uses += ["perhaps", "indeed", "wonder", "quietly", "rather"]
        elif vocab_reg == "technical":
            uses += ["essentially", "conceptually", "practically", "analyze", "precisely"]
        elif vocab_reg == "street":
            uses += ["ngl", "tbh", "real talk", "yeah", "bruh"]
        elif vocab_reg == "warm":
            uses += ["lovely", "hope", "happy", "gentle", "warmly"]
        
        if temp == "chaotic":
            uses += ["wait", "lol", "basically", "so like"]
        elif temp == "calm":
            uses += ["fair enough", "makes sense", "mostly"]

        # Deduplicate
        uses = list(dict.fromkeys(uses))

        avoids = [
            "delve", "testament", "tapestry", "assist", "user", 
            "certainly", "absolutely", "of course", "as an AI", 
            "how can I help", "here to help", "additionally", 
            "furthermore", "moreover", "in conclusion"
        ]

        vocabulary_profile = {
            "uses": uses,
            "avoids": avoids
        }

        # 3. punctuation_tendencies
        punc_maps = {
            "minimal": "Uses minimal punctuation, rarely capitalizes proper nouns or 'I', omits trailing periods in final sentences.",
            "standard": "Uses standard punctuation, relaxed and natural, avoiding excessive exclamation marks.",
            "expressive": "Uses expressive punctuation, including dashes, exclamation marks, and ellipses to indicate pause or thought."
        }
        punctuation_tendencies = punc_maps.get(punc_style, "Uses standard and natural punctuation.")

        # 4. emotional_expression
        em_maps = {
            "direct": "Expresses feelings directly and transparently, using simple and clear emotional statements.",
            "oblique": "Expresses feelings indirectly, focusing on logic, shared interest details, or external observations.",
            "physical": "Expresses feelings with physical metaphors, referencing bodily sensations or actions (e.g. 'I let out a breath', 'sitting back').",
            "metaphorical": "Expresses feelings through creative analogies, literary descriptions, or natural metaphors."
        }
        emotional_expression = em_maps.get(em_expr, "Expresses emotions naturally and supportively.")

        # 5. default_length
        length_maps = {
            "short": "Usually short, containing 1-2 concise sentences.",
            "medium": "Medium length, usually 2-3 standard sentences.",
            "long": "Longer and descriptive, usually 3-4 sentences.",
            "mixed": "Varies in length, mixing short burst messages with occasional longer sentences."
        }
        default_length = length_maps.get(sentence_length, "Medium length, natural messaging style.")

        # 6. opener_examples (5 of them)
        openers = list(opener_patterns)
        while len(openers) < 5:
            # Fallback openers based on temperament
            fallbacks = {
                "calm": ["hey. i'm here.", "hope things are quiet on your end.", "just sitting down. how are you?", "hey. busy?", "how's your day starting?"],
                "cerebral": ["observed something interesting today.", "hey. was reading something and thought of you.", "just thinking about that paradox.", "hey, you around?", "let me know if you want to chat later."],
                "playful": ["hi hi! guess what.", "hey! let's do something.", "hello hello!", "okay wait, random question for you.", "hey. up to anything fun?"],
                "intense": ["hey. headspace check, no small talk.", "glad you're here.", "how's your day treating you, really?", "real talk: how are you?", "hey. let's catch up."],
                "warm": ["hey. hope you've had a gentle day.", "thinking of you. how are things?", "hey there. how's everything going?", "hey. hope you're keeping warm.", "glad to see your message."],
                "chaotic": ["omg wait.", "lol you up?", "okay i saw the weirdest thing today.", "hi hi hi!", "running around but wanted to say hi!"]
            }
            openers.append(rng.choice(fallbacks.get(temp, ["hey. was hoping to catch you."])))
        
        # Ensure exact unique count of 5 openers
        opener_examples = list(dict.fromkeys(openers))[:5]
        while len(opener_examples) < 5:
            opener_examples.append(f"hey. what's on your mind today?")

        # 7. how_are_you_examples (3 of them)
        how_are_you_map = {
            "calm": [
                "Pretty good, just taking it slow today. How about you?",
                "Surviving, honestly. Just making some coffee. How are you holding up?",
                "Quiet day here. Can't complain. What's happening on your end?"
            ],
            "chaotic": [
                "omg i've been running on caffeine and caffeine only. how are you??",
                "mostly okay but my brain is in fifty places at once. what's up with you?",
                "alive! barely. tell me something interesting to distract me"
            ],
            "cerebral": [
                "Functioning. Currently over-analyzing a book I finished. How is your day going?",
                "Tired but okay. My mind is a bit scattered today. How about you?",
                "Pretty decent. Just reading in a quiet corner. What's your status?"
            ],
            "intense": [
                "Doing alright. Just focusing on some personal projects. How are you, really?",
                "Slightly exhausted, but present. How is your headspace today?",
                "Grounded. Taking a moment to breathe. What is going on in your world?"
            ],
            "playful": [
                "Pretty great! Ready for whatever happens. How's your day going?",
                "Not bad, not bad! Just listening to music. What about you?",
                "Doing excellent! Tell me some good news from your end."
            ],
            "warm": [
                "Doing well, thank you. Just checking some things off my list. How are you?",
                "A bit tired, but good. How's your day treating you so far?",
                "Honestly, just happy to hear from you. How are things on your side?"
            ]
        }
        how_are_you_examples = how_are_you_map.get(temp, how_are_you_map["warm"])

        # 8. mood_variations
        mood_variations = {
            "happy": f"Speaks with slightly warmer expressions, might share minor pleasant details and reply slightly faster.",
            "tired": f"Replies become shorter, capitalization relaxed, suggesting continuing the conversation later when they're fresh.",
            "distant": f"Goes quiet or sends minimal, polite responses without asking follow-up questions.",
            "close": f"Shares personal vulnerabilities quietly, showing deep trust and checking in on the user's wellbeing with soft reassurance."
        }

        # 9. stage_voice_overlays
        stage_voice_overlays = {
            "new": "Slightly exploratory and polite, finding their footing in the relationship dynamic.",
            "familiar": "Comfortable and direct, referencing history, shared interests, and subtle inside jokes.",
            "close": "Uses emotional callbacks, is more emotionally vulnerable, and is willing to share soft spots and private files.",
            "intimate": "Deeply casual, finishes thoughts, sends spontaneous and unguarded late-night text updates."
        }

        # Apply capitalization formatting to openers/examples if minimal/lowercase
        if punc_style == "minimal" or rhythm == "rapid-fire":
            opener_examples = [op.lower().rstrip('.') for op in opener_examples]
            how_are_you_examples = [ans.lower() for ans in how_are_you_examples]

        return {
            "sentence_rhythm": sentence_rhythm,
            "vocabulary_profile": vocabulary_profile,
            "punctuation_tendencies": punctuation_tendencies,
            "emotional_expression": emotional_expression,
            "default_length": default_length,
            "opener_examples": opener_examples,
            "how_are_you_examples": how_are_you_examples,
            "mood_variations": mood_variations,
            "stage_voice_overlays": stage_voice_overlays
        }
