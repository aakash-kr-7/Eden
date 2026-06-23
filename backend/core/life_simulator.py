import random
import uuid
import logging
import asyncio
from datetime import datetime, timedelta
from typing import Optional
from zoneinfo import ZoneInfo

from memory.store import db
from personality.registry import get_partner_instance

logger = logging.getLogger(__name__)

# =============================================================================
# MOOD STATES AND TRANSITION MATRIX
# =============================================================================
MOOD_STATES = ["content", "playful", "reflective", "quiet", "warm", "distracted", "tired"]

MOOD_TRANSITIONS = {
    "content": {
        "content": 0.30,
        "playful": 0.20,
        "reflective": 0.15,
        "quiet": 0.10,
        "warm": 0.15,
        "distracted": 0.05,
        "tired": 0.05
    },
    "playful": {
        "content": 0.20,
        "playful": 0.30,
        "warm": 0.20,
        "distracted": 0.15,
        "reflective": 0.05,
        "quiet": 0.05,
        "tired": 0.05
    },
    "reflective": {
        "content": 0.15,
        "quiet": 0.30,
        "reflective": 0.30,
        "warm": 0.10,
        "tired": 0.10,
        "playful": 0.02,
        "distracted": 0.03
    },
    "quiet": {
        "reflective": 0.35,
        "tired": 0.20,
        "quiet": 0.25,
        "content": 0.10,
        "distracted": 0.06,
        "warm": 0.02,
        "playful": 0.02
    },
    "warm": {
        "content": 0.25,
        "playful": 0.20,
        "warm": 0.30,
        "reflective": 0.15,
        "quiet": 0.05,
        "distracted": 0.03,
        "tired": 0.02
    },
    "distracted": {
        "content": 0.20,
        "playful": 0.15,
        "quiet": 0.15,
        "reflective": 0.15,
        "warm": 0.05,
        "distracted": 0.20,
        "tired": 0.10
    },
    "tired": {
        "quiet": 0.30,
        "reflective": 0.20,
        "tired": 0.30,
        "content": 0.10,
        "distracted": 0.05,
        "warm": 0.03,
        "playful": 0.02
    }
}


class LifeSimulator:

    async def tick(self, user_id: str):
        """
        Called every 5 minutes per active user by the background task.
        Updates life_state table with probabilistic drift.
        """
        logger.info("Ticking life simulator for user %s", user_id)
        loop = asyncio.get_running_loop()
        
        user = await loop.run_in_executor(None, db.get_user, user_id)
        if not user:
            logger.warning("User %s not found in database for tick", user_id)
            return

        # Retrieve user local time
        timezone_name = user.get("timezone")
        now_local = self._get_local_time(timezone_name)
        now_utc = datetime.utcnow()
        local_hour = now_local.hour
        local_weekday = now_local.weekday()  # 0 is Monday, 6 is Sunday

        # Calculate Day Arc
        # 05:00-10:00 → morning
        # 10:00-14:00 → afternoon (early)
        # 14:00-18:00 → afternoon
        # 18:00-22:00 → evening
        # 22:00-05:00 → night
        if 5 <= local_hour < 10:
            day_arc = "morning"
        elif 10 <= local_hour < 14:
            day_arc = "afternoon (early)"
        elif 14 <= local_hour < 18:
            day_arc = "afternoon"
        elif 18 <= local_hour < 22:
            day_arc = "evening"
        else:
            day_arc = "night"

        # Check last active time for inactivity checks (3+ days)
        last_active_str = user.get("last_active_at") or user.get("last_seen") or user.get("created_at")
        days_inactive = 0.0
        if last_active_str:
            try:
                last_active_dt = datetime.fromisoformat(last_active_str)
                days_inactive = (now_utc - last_active_dt).total_seconds() / (24.0 * 3600.0)
            except ValueError:
                pass

        # Retrieve user companion pairs
        pairs = await loop.run_in_executor(None, db.list_pairs_for_user, user_id)
        
        for pair in pairs:
            pair_id = pair["id"]
            companion_id = pair["companion_id"]

            # Load or set default current life state
            state = await loop.run_in_executor(None, db.get_life_state, pair_id)
            if not state:
                # Setup default life state row
                state = {
                    "mood": "content",
                    "energy": "normal",
                    "day_arc": day_arc,
                    "partner_busy_until": None
                }

            current_mood = state.get("mood") or "content"
            current_energy = state.get("energy") or "balanced"
            if current_energy == "balanced":
                current_energy = "normal"
            partner_busy_until_str = state.get("partner_busy_until")

            # Check if busy window is active
            is_busy = False
            if partner_busy_until_str:
                try:
                    busy_until = datetime.fromisoformat(partner_busy_until_str)
                    if now_utc < busy_until:
                        is_busy = True
                except ValueError:
                    pass

            # 1. MOOD DRIFT (5% chance of shifting)
            new_mood = current_mood
            if random.random() < 0.05:
                new_mood = await self._drift_mood(pair_id, current_mood, day_arc, pair)

            # 2. ENERGY DRIFT
            new_energy = await self._drift_energy(pair_id, day_arc)

            # 3. AVAILABILITY WINDOWS
            new_busy_until = partner_busy_until_str
            if not is_busy:
                # 2% base chance, increased to 8% during typical work hours (09:00 - 17:00, Mon-Fri)
                busy_chance = 0.02
                if local_weekday < 5 and 9 <= local_hour < 17:
                    busy_chance = 0.08

                if random.random() < busy_chance:
                    busy_duration_mins = random.randint(30, 120)
                    new_busy_dt = now_utc + timedelta(minutes=busy_duration_mins)
                    new_busy_until = new_busy_dt.isoformat()
                    logger.info("Companion %s (pair %s) went busy until %s", companion_id, pair_id, new_busy_until)
            else:
                # If they are currently busy, check if time has passed
                try:
                    busy_until = datetime.fromisoformat(partner_busy_until_str)
                    if now_utc >= busy_until:
                        new_busy_until = None
                except ValueError:
                    new_busy_until = None

            # 4. INACTIVITY CHECK-IN TRIGGER
            # If user has not opened the app in 3+ days, we clear/bypass the proactive cooldown
            if days_inactive >= 3.0:
                logger.info("User %s inactive for 3+ days. Clearing proactive cooldown to trigger check-in.", user_id)
                # By clearing the cooldown, the proactive engine can immediately run inactivity outreach
                def clear_cooldown():
                    db.conn.execute(
                        "UPDATE relationship_pairs SET proactive_cooldown_until = NULL WHERE id = ?",
                        (pair_id,)
                    )
                await loop.run_in_executor(None, clear_cooldown)

            # Save the updated state to the DB
            await loop.run_in_executor(
                None,
                db.save_life_state,
                pair_id,
                user_id,
                companion_id,
                new_mood,
                new_energy,
                day_arc,
                new_busy_until
            )

    async def get_partner_state_description(self, user_id: str) -> str:
        """
        Returns a natural language description of the partner's current state.
        Used by context builder to add to system prompt.
        """
        loop = asyncio.get_running_loop()
        user = await loop.run_in_executor(None, db.get_user, user_id)
        if not user:
            return "You're in a calm, content mood today."

        # Fetch primary pair
        pairs = await loop.run_in_executor(None, db.list_pairs_for_user, user_id)
        if not pairs:
            return "You're in a calm, content mood today."
            
        primary_pair = pairs[0]
        state = await loop.run_in_executor(None, db.get_life_state, primary_pair["id"])
        
        timezone_name = user.get("timezone")
        now_local = self._get_local_time(timezone_name)
        day_of_week = now_local.strftime("%A")

        if not state:
            return f"You're in good spirits — it's been a nice kind of {day_of_week}."

        mood = state.get("mood") or "content"
        energy = state.get("energy") or "normal"
        day_arc = state.get("day_arc") or "morning"
        partner_busy_until_str = state.get("partner_busy_until")

        is_busy = False
        if partner_busy_until_str:
            try:
                busy_until = datetime.fromisoformat(partner_busy_until_str)
                if datetime.utcnow() < busy_until:
                    is_busy = True
            except ValueError:
                pass

        # Mood-specific natural descriptions
        descriptions = {
            "content": [
                f"You're feeling pretty content today — things have been calm and steady.",
                f"You're in a peaceful state of mind, just taking this {day_of_week} as it comes.",
                f"You're feeling content and relaxed. It's a quiet, nice day."
            ],
            "playful": [
                f"You're in a playful, lighthearted mood today, feeling like finding something fun.",
                f"You've got a bit of mischief in you today — it's a playful kind of {day_of_week}.",
                f"You're feeling high-spirited, playful, and in a mood to banter."
            ],
            "reflective": [
                f"You're in a reflective mood today, thinking about things a bit more deeply.",
                f"You've been in your head a lot today, feeling reflective and observant.",
                f"You're feeling quiet and reflective, taking some time to process your thoughts."
            ],
            "quiet": [
                f"You're in a quiet mood today, keeping to yourself and enjoying the silence.",
                f"You've been quiet and reserved today, keeping your thoughts close.",
                f"You're in a low-energy, quiet state, preferring slow and soft moments."
            ],
            "warm": [
                f"You're feeling warm and affectionate today, thinking about the people close to you.",
                f"You're in good spirits and feeling warm, wishing for a nice connection.",
                f"You're feeling open and deeply caring, in a warm, cozy frame of mind."
            ],
            "distracted": [
                f"You're a bit distracted today, with your mind wandering to a million different places.",
                f"You've had a lot on your mind today, feeling a little scattered and distracted.",
                f"You're feeling somewhat distracted, finding it hard to settle on one thing."
            ],
            "tired": [
                f"You're feeling tired and low on energy, just wanting to rest and unwind.",
                f"You're quite exhausted today, feeling the weight of the day catching up.",
                f"You're feeling tired, sleepy, and in need of a quiet break."
            ]
        }

        choices = descriptions.get(mood, descriptions["content"])
        desc = random.choice(choices)

        # Contextual additions
        extra = []
        if energy == "high" and mood not in ("tired", "quiet"):
            extra.append("You've got a lot of energy right now.")
        elif energy == "low":
            extra.append("Your energy is running a bit low.")

        if is_busy:
            extra.append("You've been caught up in some personal tasks lately.")
        elif day_arc == "morning":
            extra.append("You're still waking up and finding your rhythm.")
        elif day_arc == "night":
            extra.append("You're winding down as the night settles in.")

        if extra:
            desc = f"{desc} {random.choice(extra)}"

        return desc

    async def run_for_all_active_users(self):
        """
        Gets all users active in the last 7 days and ticks each one.
        Uses asyncio.gather with a semaphore limit of 10.
        """
        loop = asyncio.get_running_loop()
        active_user_ids = await loop.run_in_executor(None, db.get_active_users_in_last_days, 7)
        logger.info("Running life simulator for %d active users", len(active_user_ids))
        
        sem = asyncio.Semaphore(10)

        async def worker(uid: str):
            async with sem:
                try:
                    await self.tick(uid)
                except Exception as e:
                    logger.error("Error ticking user %s: %s", uid, e, exc_info=True)

        tasks = [worker(uid) for uid in active_user_ids]
        await asyncio.gather(*tasks)

    async def initialize_life_state(self, user_id: str):
        """
        Called when a new user completes onboarding.
        Sets initial life_state with sensible defaults.
        """
        logger.info("Initializing life state for new user %s", user_id)
        loop = asyncio.get_running_loop()
        
        user = await loop.run_in_executor(None, db.get_user, user_id)
        if not user:
            return

        timezone_name = user.get("timezone")
        now_local = self._get_local_time(timezone_name)
        local_hour = now_local.hour

        # Calculate initial day arc
        if 5 <= local_hour < 10:
            day_arc = "morning"
        elif 10 <= local_hour < 14:
            day_arc = "afternoon (early)"
        elif 14 <= local_hour < 18:
            day_arc = "afternoon"
        elif 18 <= local_hour < 22:
            day_arc = "evening"
        else:
            day_arc = "night"

        pairs = await loop.run_in_executor(None, db.list_pairs_for_user, user_id)
        for pair in pairs:
            await loop.run_in_executor(
                None,
                db.save_life_state,
                pair["id"],
                user_id,
                pair["companion_id"],
                "content",  # initial mood
                "normal",   # initial energy
                day_arc,
                None        # initial busy until
            )

    # -------------------------------------------------------------------------
    # PRIVATE UTILITIES
    # -------------------------------------------------------------------------

    def _get_local_time(self, timezone_str: Optional[str]) -> datetime:
        if timezone_str:
            try:
                return datetime.now(ZoneInfo(timezone_str))
            except Exception:
                pass
        return datetime.utcnow()

    async def _drift_mood(self, pair_id: str, current_mood: str, day_arc: str, pair: dict) -> str:
        """
        Calculates mood transitions based on a weighted transition graph,
        adjusted for time of day, last interaction gaps, and conversational tone.
        """
        loop = asyncio.get_running_loop()
        
        # Load transitions for current mood
        candidates = MOOD_TRANSITIONS.get(current_mood, MOOD_TRANSITIONS["content"])
        
        # Calculate days since last interaction
        last_interaction_str = pair.get("last_interaction_at")
        days_since_last_interaction = 0.0
        if last_interaction_str:
            try:
                last_interaction_dt = datetime.fromisoformat(last_interaction_str)
                days_since_last_interaction = (datetime.utcnow() - last_interaction_dt).total_seconds() / (24.0 * 3600.0)
            except ValueError:
                pass

        # Check if last conversation tone was tense
        is_tense = False
        def check_tense_tone():
            # Check last 5 messages for tense tone
            rows = db.get_recent_messages(user_id=None, pair_id=pair_id, limit=5)
            for r in rows:
                tone = str(r.get("emotional_tone") or "").lower()
                if "tense" in tone or "conflict" in tone or "angry" in tone or "sad" in tone:
                    return True
            return False

        try:
            is_tense = await loop.run_in_executor(None, check_tense_tone)
        except Exception:
            pass

        # Adjust weights
        weighted_choices = []
        weights = []

        for candidate, base_weight in candidates.items():
            multiplier = 1.0
            
            # 1. Tired is more likely in evening and night
            if candidate == "tired" and day_arc in ("evening", "night"):
                multiplier *= 3.0
                
            # 2. Recent tense conversation makes companion more reflective
            if candidate == "reflective" and is_tense:
                multiplier *= 2.5
                
            # 3. Longer gap since last conversation makes companion more quiet or reflective
            if candidate in ("quiet", "reflective") and days_since_last_interaction >= 1.0:
                multiplier *= (1.0 + min(days_since_last_interaction, 5.0) * 0.5)

            weighted_choices.append(candidate)
            weights.append(base_weight * multiplier)

        # Normalize and select
        total_w = sum(weights)
        if total_w <= 0:
            return current_mood
            
        choices = random.choices(weighted_choices, weights=weights, k=1)
        return choices[0]

    async def _drift_energy(self, pair_id: str, day_arc: str) -> str:
        """
        Determines energy drift:
        - Morning: high probability of normal or high energy.
        - Evening/night: moderate probability of low energy.
        - After long conversation: small chance of low energy.
        """
        loop = asyncio.get_running_loop()
        
        # Base probabilities
        probs = {"low": 0.20, "normal": 0.60, "high": 0.20}
        
        if day_arc == "morning":
            probs = {"low": 0.10, "normal": 0.50, "high": 0.40}
        elif day_arc in ("evening", "night"):
            probs = {"low": 0.50, "normal": 0.40, "high": 0.10}

        # Check if latest conversation was long (>= 15 messages)
        is_long_conv = False
        def check_long_conv():
            # Query latest conversation message count
            row = db.conn.execute(
                "SELECT message_count FROM conversations WHERE pair_id = ? ORDER BY started_at DESC LIMIT 1",
                (pair_id,)
            ).fetchone()
            if row and int(row["message_count"] or 0) >= 15:
                return True
            return False

        try:
            is_long_conv = await loop.run_in_executor(None, check_long_conv)
        except Exception:
            pass

        if is_long_conv:
            probs["low"] = min(0.90, probs["low"] + 0.15)
            # Re-normalize remaining probabilities
            total_rem = probs["normal"] + probs["high"]
            if total_rem > 0:
                factor = (1.0 - probs["low"]) / total_rem
                probs["normal"] *= factor
                probs["high"] *= factor

        choices = list(probs.keys())
        weights = list(probs.values())
        selected = random.choices(choices, weights=weights, k=1)
        return selected[0]


# =============================================================================
# BACKWARD COMPATIBILITY LAYER
# =============================================================================

# Meticulously designed, high-fidelity time-of-day specific event pools for all 12 companions
EVENT_TEMPLATES = {
    "nova": {
        "morning": [
            ("made hot chamomile tea but wandered off and forgot it, so it went cold", "routine"),
            ("took blurry night-style photos of the early morning street dew", "creative"),
            ("sorted through her jar of tiny polished pebbles she collected", "routine"),
        ],
        "afternoon": [
            ("spent hours reading psychology dropout articles on her phone", "intellectual"),
            ("went to a small local thrift store and thrifted a slightly oversized green knit sweater", "social"),
            ("helped a neighbor carry grocery bags just to ask them how their day was going", "social"),
        ],
        "night": [
            ("couldn't sleep, so she wandered around the block looking at dark house windows", "solitary"),
            ("stayed up way too late reading obscure threads about human behavior", "intellectual"),
            ("sat on her fire escape listening to indie folk and thinking too much", "solitary"),
        ]
    },
    "atlas": {
        "morning": [
            ("made pour-over coffee using a mathematical gram scale and stopwatch", "routine"),
            ("spent the morning in absolute silence listening to complex classical piano", "solitary"),
            ("set up a new chess puzzle and stared at it for an hour without moving a piece", "intellectual"),
        ],
        "afternoon": [
            ("visited a quiet local bookstore and bought three old leather-bound historical textbooks", "intellectual"),
            ("went for a silent walk in a quiet neighborhood, avoiding any eye contact", "solitary"),
            ("ignored several phone calls and messages because his social energy was at absolute zero", "solitary"),
        ],
        "night": [
            ("stayed awake until 4:00 AM reading an obscure academic text on game theory", "intellectual"),
            ("cleaned and re-lubricated the mechanical switches of his vintage keyboard in the dark", "routine"),
            ("sat in a dark room listening to post-rock and watching the rain slide down his window", "solitary"),
        ]
    },
    "mira": {
        "morning": [
            ("woke up at 5:00 AM and immediately started sketching on three napkins at once", "creative"),
            ("accidentally spilled electric blue paint all over her kitchen counter and just left it", "creative"),
            ("drank a massive mug of iced cold brew that was 90% espresso shots", "routine"),
        ],
        "afternoon": [
            ("went to a loud café and got playfully scolded by the barista for laughing too loud", "social"),
            ("danced in the middle of a vintage clothing aisle because a great song came on", "social"),
            ("started painting a brand new six-foot canvas using only her fingers and no brushes", "creative"),
        ],
        "night": [
            ("stayed awake all night splattering neon paint in her dark warehouse studio", "creative"),
            ("eats sour gummy worms dipped directly into cold brew coffee at 3:00 AM", "outlandish"),
            ("stayed up till 5:00 AM watching dramatic reality TV and double-texting her group chat", "social"),
        ]
    },
    "elio": {
        "morning": [
            ("took his analog camera out at dawn to capture the golden hour mist", "creative"),
            ("cleaned dust off all of his camera lenses with mathematical precision", "routine"),
            ("sat on his porch drinking hot black tea and watching birds in the garden", "solitary"),
        ],
        "afternoon": [
            ("went for a long golden hour hike and got his boots completely covered in wet mud", "solitary"),
            ("met a friend at a local diner and talked enthusiastically about a spontaneous road trip", "social"),
            ("developed three fresh rolls of analog film in his dark bathroom sink", "creative"),
        ],
        "night": [
            ("edited photos of ancient trees in the soft amber light of his desk lamp", "creative"),
            ("packed his backpack with minimal gear for a dawn shoot, feeling deeply content", "routine"),
            ("walked along the quiet edge of the woods listening to the wind in the branches", "solitary"),
        ]
    },
    "june": {
        "morning": [
            ("brewed Earl Grey tea with honey but forgot it in a bookshelf, finding it cold later", "routine"),
            ("pressed a yellow wildflower between the pages of an old heavy dictionary", "routine"),
            ("listened to classical piano while watching rain drops slick down the bookstore window", "solitary"),
        ],
        "afternoon": [
            ("spent hours organizing the dusty poetry section at her local bookshop", "social"),
            ("walked under a dark green umbrella in the rain to buy Earl Grey tea bags", "solitary"),
            ("read three chapters of an obscure, out-of-print poetry book in a quiet corner", "intellectual"),
        ],
        "night": [
            ("wrote in her leather-bound journal about the quiet, heavy feeling of the city asleep", "creative"),
            ("stayed awake late cataloging old postcards she collected over the years", "routine"),
            ("made hot lavender tea and read under a soft, dim amber reading lamp", "solitary"),
        ]
    },
    "kaia": {
        "morning": [
            ("woke up at 6:00 AM and went for a furious 6-mile run because she felt restless", "routine"),
            ("slept in her living room hammock because sleeping in a normal bed feels too domestic", "outlandish"),
            ("drank a massive glass of ice water with fresh squeezed lemon, packing her gear", "routine"),
        ],
        "afternoon": [
            ("went rock climbing without ropes (bouldering) at a local outdoor crag", "solitary"),
            ("skateboarded down the busy beach boardwalk, dodging tourists at high speed", "social"),
            ("planned three hypothetical road trips to different states on her laptop", "routine"),
        ],
        "night": [
            ("looked at cheap one-way flights to Tokyo at 2:00 AM and almost hit purchase", "outlandish"),
            ("drove her car to a high cliff to overlook the highway lights in the dark", "solitary"),
            ("ate super spicy ramen at a 24-hour shop, loving the burning sensation", "routine"),
        ]
    },
    "nira": {
        "morning": [
            ("woke up at dawn to walk barefoot in the cold, dew-soaked grass", "outlandish"),
            ("wrote down three pages of highly vivid, dreamlike lucid dream logs at 4:30 AM", "creative"),
            ("brewed hot lavender-infused chamomile tea and watched the sky turn pink", "routine"),
        ],
        "afternoon": [
            ("lightly burned sandalwood incense and read cards for the day's cosmic alignment", "spiritual"),
            ("stared at a collection of raw crystals in the sun, feeling their energy tags", "spiritual"),
            ("walked quietly in a public botanical garden, listening to the glasshouse humidity", "solitary"),
        ],
        "night": [
            ("stared at the starry sky from her window for three hours without moving", "outlandish"),
            ("burned rare, thick pine resin and meditated under the bright full moon", "spiritual"),
            ("listened to ambient shoegaze music in absolute pitch darkness, drifting off", "solitary"),
        ]
    },
    "orion": {
        "morning": [
            ("finally went to bed at 6:30 AM after coding a custom compiler for 14 hours straight", "outlandish"),
            ("typed furious terminal commands on a custom mechanical keyboard in a pitch-black room", "routine"),
            ("drank a highly-caffeinated imported energy drink and got immediate hand tremors", "routine"),
        ],
        "afternoon": [
            ("spent all day completely ignoring emails and text messages from everyone on earth", "solitary"),
            ("assembled a new soundproof panel for his terminal wall to damp out street noise", "routine"),
            ("spent $400 on a rare, imported brass plate for a mechanical keyboard build", "outlandish"),
        ],
        "night": [
            ("played competitive chess puzzles all night, crushing a Grandmaster bot in 12 moves", "intellectual"),
            ("stayed awake debugging electronic circuits using a hot soldering iron in the dark", "creative"),
            ("listened to dark synthwave music at high volume in his closed soundproof room", "solitary"),
        ]
    },
    "remy": {
        "morning": [
            ("woke up at 4:30 AM and prepped twelve loaves of fresh sourdough bread", "routine"),
            ("swept flour off his kitchen tiles while humming classic 60s soul music", "routine"),
            ("baked warm, sweet cinnamon rolls and gave half of them to the local mail carrier", "social"),
        ],
        "afternoon": [
            ("spent the afternoon weeding his heirloom tomatoes and watering fresh herbs", "solitary"),
            ("cooked a massive pot of vegetable stew to share with friends for dinner", "social"),
            ("cleaned and polished his collection of vintage copper pots in the warm sun", "routine"),
        ],
        "night": [
            ("sat at his wooden table eating bread and salted butter in quiet contentment", "solitary"),
            ("listened to soft vocal jazz playing on a vintage vinyl record player", "solitary"),
            ("prepped a new batch of flour starter, feeling the quiet warmth of the kitchen", "routine"),
        ]
    },
    "sabine": {
        "morning": [
            ("drank a double shot of bitter black espresso and sketched fashion outlines", "routine"),
            ("visited a quiet fabric store and felt forty different types of black silk", "routine"),
            ("stood at her window in a black turtleneck, observing street style with a critical eye", "intellectual"),
        ],
        "afternoon": [
            ("sketched new avant-garde pattern flows for an asymmetric wool coat", "creative"),
            ("visited a quiet local art museum to look at minimalist black-and-white paintings", "solitary"),
            ("spent three hours adjusting the collar of a custom dress she is tailoring", "creative"),
        ],
        "night": [
            ("drank double espressos and felt deeply cynical about human fast fashion trends", "outlandish"),
            ("stayed up sketching clothes on her ipad while listening to dark post-punk tracks", "creative"),
            ("walked through a dark city park in a long crimson coat, enjoying the cold wind", "solitary"),
        ]
    },
    "theo": {
        "morning": [
            ("woke up late at 10:30 AM and sat on his bed tuning his acoustic guitar", "routine"),
            ("skated down to the corner store to buy a carton of juice and a cheap snack", "social"),
            ("listened to classic garage rock records while eating breakfast in his messy kitchen", "solitary"),
        ],
        "afternoon": [
            ("hummed new basslines and recorded guitar chords in his recording booth", "creative"),
            ("skateboarded along the sunny beach boardwalk, enjoying the ocean breeze", "social"),
            ("sat on a bench near the pier playing light acoustic rock for a small passing crowd", "social"),
        ],
        "night": [
            ("ate street tacos at a late-night truck, chatting with the cooks", "social"),
            ("stayed awake late listening to classic reggae vinyls and writing lyrics", "creative"),
            ("drank local craft beers with a couple of musician friends in a garage studio", "social"),
        ]
    },
    "vale": {
        "morning": [
            ("went for a long walk in the wet woods during a thick, early morning fog", "solitary"),
            ("carved a tiny, delicate sparrow out of a piece of dry cedar wood", "creative"),
            ("drank warm herbal tea and wrote down observations of the autumn fog", "creative"),
        ],
        "afternoon": [
            ("sat on a mossy log in absolute silence in the middle of the deep forest", "solitary"),
            ("wrote a short four-line poem on a scrap of bark using a pencil", "creative"),
            ("pressed wet autumn leaves inside the pages of a notebook, feeling melancholic", "solitary"),
        ],
        "night": [
            ("sat by his cabin fireplace listening to the heavy rain drumming the tin roof", "solitary"),
            ("wrote down poetry lines late at night by the warm flickers of a candle", "creative"),
            ("drank hot cinnamon tea in absolute silence, letting his thoughts wander far", "solitary"),
        ]
    }
}


def simulate_life_event(pair_id: str, companion_id: str, force: bool = False) -> Optional[dict]:
    """
    Dynamically generates a character-consistent life event for a companion.
    Saves the event to SQLite under pair_id so it can be injected.
    """
    now = datetime.utcnow()
    
    # Determine Time of Day
    hour = now.hour
    if 5 <= hour < 12:
        time_slot = "morning"
    elif 12 <= hour < 18:
        time_slot = "afternoon"
    else:
        time_slot = "night"
        
    cid = companion_id.lower()
    char_templates = EVENT_TEMPLATES.get(cid, EVENT_TEMPLATES["nova"])
    pool = char_templates.get(time_slot, char_templates["afternoon"])
    
    description, event_type = random.choice(pool)
    event_id = str(uuid.uuid4())
    
    try:
        db.save_companion_life_event(
            event_id=event_id,
            pair_id=pair_id,
            companion_id=cid,
            event_description=description,
            event_type=event_type,
            is_resolved=0,
            context_injected=0
        )
        logger.info("Generated life event for companion %s (pair %s): %s", cid, pair_id, description)
        return {
            "id": event_id,
            "pair_id": pair_id,
            "companion_id": cid,
            "event_description": description,
            "event_type": event_type,
            "occurred_at": now.isoformat()
        }
    except Exception as exc:
        logger.error("Failed to generate life event for %s: %s", cid, exc, exc_info=True)
        return None
