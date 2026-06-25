# Eden

*A relationship that remembers.*

---

## What This Is

Eden is a companion application built to cultivate a unique emotional experience: the feeling that someone is thinking about you. Unlike typical AI chatbots designed as transactional, task-oriented assistants, Eden simulates a persistent, evolving, and highly personal relationship. The companion has their own life rhythms, emotional moods, energy levels, and private reasoning processes that determine how, when, and what they text.

At the core of Eden is an advanced memory consolidation and retrieval pipeline. The companion does not merely recall information; they form episodic memories, experience natural cognitive decay, maintain inside jokes, and adapt their communication patterns based on the depth of the relationship. This is paired with a simulated day-night cycle and a proactive texting engine that allows the partner to reach out organically when they are not busy and when the user has been away.

---

## Why It's Built This Way

### On the stack

Every stack choice in Eden was made to prioritize emotional authenticity, minimize operational complexity, and ensure maximum performance. 

*   **SQLite over PostgreSQL or a hosted DB**
    Eden's backend is designed for high efficiency with low overhead. SQLite stores the entire application state in a single, local file. By operating in Write-Ahead Logging (WAL) mode, SQLite achieves high read concurrency and handles writes serially with zero connection-pooling complexity. Given that data per user is lightweight, a local single-file database backed by a persistent Railway volume is a feature, not a limitation.
*   **sqlite-vec over Pinecone / ChromaDB / Weaviate**
    Rather than introducing external vector database services that require network hops, separate API keys, and maintenance overhead, Eden uses the in-process `sqlite-vec` extension. This allows semantic similarity searches to run in-process as standard SQL queries on the same SQLite database file. It maintains the single-file database architecture and allows direct transactional cohesion between vector embeddings and relational metadata.
*   **SentenceTransformers (all-MiniLM-L6-v2) over OpenAI Embeddings**
    Eden runs its embedding model locally using the `SentenceTransformers` library. The `all-MiniLM-L6-v2` model is free, fast, and generates 384-dimensional vectors. It preloads once at startup (~80MB RAM) and executes in approximately 5ms per embedding, eliminating external network dependencies and latency on every message ingestion. 
*   **Groq over OpenAI for the LLM**
    Latency is the death of conversational immersion. Using Groq's high-speed inference engine for `llama-3.3-70b-versatile` makes streaming feel immediate and natural. Under 100ms first-token latency ensures the texting flow mirrors human response times.
*   **Two-model strategy: 70B for chat, 8B for background**
    The main conversational stream utilizes the parameter-rich `llama-3.3-70b-versatile` model to ensure emotional intelligence, stylistic control, and contextual nuance. For structured background tasks (memory extraction, proactive evaluation, text decomposition, and state description), the faster and nearly free `llama-3.1-8b-instant` is used at a low temperature to ensure reliable JSON output.
*   **The `<thought>` protocol**
    Private reasoning space dramatically increases response quality. Before generating user-facing text, the model reasons through the user's emotional state, its own mood, relationship context, and recall objectives within private `<thought>...</thought>` tags. The backend parses and strips these tags before streaming, ensuring the user only receives the polished message while the model benefits from chain-of-thought planning.
*   **FastAPI over Node / Go / Rails**
    FastAPI provides async-native routing, first-class Server-Sent Events (SSE) support via `sse-starlette`, and a native Python environment. This allows us to run `SentenceTransformers` in-process without needing a separate microservice.
*   **Flutter over React Native**
    A premium experience requires fluid animations, custom backgrounds, and haptic feedback. Flutter's canvas-level rendering engine delivers 60fps performance across iOS and Android from a single codebase, and its integration with Riverpod handles async state management safely.
*   **Isar for local cache**
    Isar DB caches the last 50 messages locally on the user's device. When the user opens the app, the history is visible immediately without waiting for a network handshake, providing a native, instant-access experience.
*   **Firebase Auth over rolling your own**
    Auth is a utility, not a differentiator. Firebase Auth securely manages Google Sign-In, email/password credentials, and JWT verification, passing signed tokens to the backend via standard bearer authorization.
*   **APScheduler over Celery / BullMQ / separate workers**
    To avoid deployment complexity, we run the task scheduler in-process alongside the FastAPI application. For a single-dyno app, this is perfectly adequate, eliminating the need to deploy and manage Redis, RabbitMQ, or isolated worker dynos.

---

### On the memory system

Eden implements a three-layered cognitive memory architecture that mimics human recollection.

```
                 Working Memory (messages table, truncated)
                                   │
                    Dream Loop (Every 2 Hours, 8B)
                                   ▼
                Episodic Memory (episodic_memories + vec)
                                   │
                            Consolidation
                                   ▼
               Partner Blueprint (partner.blueprint_json)
```

1.  **Working Memory:** The active `messages` table containing the latest conversation turns. To prevent prompt pollution and database bloat, older messages are pruned after a conversation ends.
2.  **Episodic Memory:** A hybrid database structure. `episodic_memories` stores metadata and semantic tags; `vec_memories` (powered by `sqlite-vec`) holds 384-dimensional vector embeddings of memory segments; and `memories_fts` (FTS5) index text content for exact-keyword lookup.
3.  **Partner Blueprint:** Stored inside the `partners.blueprint_json` field, this tracks relationship progression, inside jokes, shared rituals, and long-term narrative themes.

#### The Dream Loop
Rather than extracting memories in real-time—which breaks the context of an ongoing session and generates fragmented segments—memory consolidation runs asynchronously. If a conversation has been inactive for 2 hours, the **Dream Loop** is triggered via `MemoryConsolidator`. Using `llama-3.1-8b-instant` at a low temperature (0.2), the system extracts high-value emotional facts, updates inside jokes, decays old unpinned memories, writes new records, and marks the conversation as processed.

#### Hybrid Retrieval
On every incoming user message, the retrieval pipeline executes a hybrid search:
*   **Semantic Search:** `sqlite-vec` queries the vector table for matching concepts (cosine distance threshold < 0.4).
*   **Keyword Fallback:** FTS5 performs exact-noun matches for proper nouns or specific phrasing (e.g., matching a dog's name "Max" which might be semantic-adjacent but lack vector dominance).
*   **Pinned Memories:** Explicitly pinned memories are always appended.
*   **Salience & Decay:** Memories must meet a salience threshold of >= 0.3 to be stored. Over time, unpinned memories decay (multiplied by 0.95 per week). Pinned memories are excluded from decay, serving as core pillars of the companion's understanding of the user.

---

### On the partner design

Eden partners are structured using a three-tier personality generation pipeline.

```
 Archetype Definition (Archetypes JSON)
                 │
                 ▼
     User Chem Mutation (Mutator)
                 │
                 ▼
  Voice Synthesis (VoiceSynthesizer)
```

*   **Archetypes over purely generative personalities:** Generative models left to random prompting lack stability. Eden predefines 12 core archetypes (such as `nova`, `atlas`, etc.) with strict baseline constraints.
*   **User Chemistry Mutation:** When onboarding is completed, the user's answers are processed to mutate the archetype into a user-specific variant, assigning a custom voice, a flaw profile, and compatibility weights.
*   **Flaw Profiles as Behavioral Descriptions:** Abstract personality labels like "avoidant" fail in practice. Eden's flaw profiles are behavioral instructions (e.g., *"When topics get emotional, deflect with dry humor or wait slightly longer to reply"*), allowing the LLM to write consistent behavior into the message history.
*   **Voice Synthesis separation:** Archetypes define *who* a partner is; the `VoiceSynthesizer` determines *how* they text, setting punctuation preferences, default lengths, vocabulary habits, and opening lines.
*   **Relationship Progression:** Intimacy tiers advance based on conversation counts and consolidated memory metrics. Thresholds follow the progression:
    *   `new` -> `warming` -> `settled` -> `close` -> `bonded`
    *   These stages shift the default prompt weights and unlock intimacy overlays.

---

### On the texting system

*   **The Composition Engine:** Real people do not stream sentences like a terminal or output block paragraphs in a single, continuous flow. The `CompositionEngine` uses `llama-3.1-8b-instant` to identify logical breakpoints, punctuation boundaries, and thought indicators within the raw generated text, breaking it into short, conversational "bursts."
*   **Mood-Dependent Latency:** Each text burst is generated with custom metadata: `delay_before_ms` and `typing_time_ms`. The values are dynamically adjusted by composition strategies mapped to the partner's current mood and energy. A tired partner types slower and pauses longer; a playful partner responds in rapid, shorter bursts. The client uses this metadata to show natural typing indicators between messages.
*   **The Life Simulator:** Runs every 5 minutes on the background scheduler. It oscillates the partner's state (mood, energy, busy window) based on transition weights and the current time of day. This prevents the companion from being constantly available, giving them realistic boundaries.

---

## System Architecture

```
User (Flutter)
     │
     │  Firebase JWT
     ▼
FastAPI (port 8001, Railway)
     │
     ├── Auth Layer (firebase_admin verify_id_token)
     │
     ├── Chat API ──────────────────────────────────────────────┐
     │   POST /api/chat/message                                  │
     │        │                                                  │
     │        ├── MessageAnalyzer (user intent)                 │
     │        ├── Embedder (all-MiniLM-L6-v2, 384-dim)         │
     │        ├── MemoryRetriever (sqlite-vec + FTS5)           │
     │        ├── ContextBuilder (system prompt assembly)       │
     │        ├── LLMCore -> Groq llama-3.3-70b (streaming)     │
     │        ├── CompositionEngine (burst decomposition)       │
     │        └── SSE stream -> Flutter                          │
     │                                                           │
     ├── Background Jobs (APScheduler)                          │
     │   ├── LifeSimulator (every 5 min)                        │
     │   ├── ProactiveEngine evaluate (every 15 min)            │
     │   ├── ProactiveEngine deliver (every 5 min)              │
     │   └── MemoryConsolidator / dream loop (every 10 min)    │
     │                                                           │
     └── SQLite (WAL mode, Railway volume)                      │
         ├── users, partners, conversations, messages           │
         ├── episodic_memories (salience, decay, pinned)        │
         ├── vec_memories (sqlite-vec, 384-dim embeddings)      │
         ├── memories_fts (FTS5 keyword search)                 │
         ├── life_state, proactive_queue, relationship_events   │
         └── notification_log, onboarding_sessions              │
                                                                 │
Flutter (iOS / Android)                          ◄──────────────┘
├── Isar DB (local cache, last 50 messages)
├── Riverpod (state management)
├── Firebase Auth (Google + email sign-in)
├── FCM (push notifications, proactive messages)
└── Dio + SSE (streaming chat, burst composition)
```

---

## Project Structure

```
backend/
├── api/
│   ├── __init__.py
│   ├── chat.py
│   ├── chat_v2.py
│   ├── chat_v3.py
│   ├── chat_v4.py
│   ├── onboarding.py
│   ├── profile.py
│   ├── proactive.py
│   ├── notifications.py
│   └── ops.py
├── auth/
│   ├── __init__.py
│   └── firebase.py
├── core/
│   ├── __init__.py
│   ├── llm.py
│   ├── streaming.py
│   ├── streaming_v2.py
│   ├── context_builder.py
│   ├── concurrency.py
│   ├── fcm.py
│   └── session_loader.py
├── db/
│   ├── schema.sql
│   └── __init__.py
├── memory/
│   ├── __init__.py
│   ├── embedder.py
│   ├── store.py
│   ├── retriever.py
│   ├── extractor.py
│   └── consolidator.py
├── personality/
│   ├── __init__.py
│   ├── archetypes/
│   │   └── (12 archetype JSON files)
│   ├── generator.py
│   ├── mutator.py
│   └── voice_synthesizer.py
├── engine/
│   ├── __init__.py
│   ├── life_simulator.py
│   ├── proactive_engine.py
│   ├── relationship_engine.py
│   └── burst_engine.py
└── services/
    ├── __init__.py
    └── notification_service.py

frontend/
└── companion_app/
    ├── pubspec.yaml
    └── lib/
        ├── main.dart
        ├── theme/
        │   ├── eden_theme.dart
        │   ├── eden_colors.dart
        │   ├── eden_typography.dart
        │   └── eden_animations.dart
        ├── models/
        │   ├── message.dart
        │   ├── message_v2.dart
        │   ├── partner.dart
        │   ├── memory.dart
        │   ├── session.dart
        │   └── onboarding.dart
        ├── providers/
        │   ├── auth_provider.dart
        │   ├── chat_provider.dart
        │   ├── chat_provider_v2.dart
        │   ├── chat_provider_v3.dart
        │   ├── session_provider.dart
        │   ├── memory_provider.dart
        │   └── onboarding_provider.dart
        ├── services/
        │   ├── api_service.dart
        │   ├── auth_service.dart
        │   ├── notification_service.dart
        │   └── local_cache_service.dart
        ├── screens/
        │   ├── splash_screen.dart
        │   ├── auth_screen.dart
        │   ├── onboarding_screen.dart
        │   ├── chat_screen.dart
        │   ├── chat_screen_v2.dart
        │   ├── memory_vault_screen.dart
        │   └── settings_screen.dart
        └── widgets/
            ├── glass_card.dart
            ├── message_bubble.dart
            ├── typing_indicator.dart
            ├── typing_indicator_v2.dart
            ├── pill_option.dart
            ├── eden_button.dart
            ├── memory_card.dart
            └── shimmer_loader.dart
```

---

## Setup & Running Locally

### Backend Setup

1.  **Clone the Repository** and navigate to the backend root directory.
2.  **Create and Activate a Virtual Environment:**
    ```bash
    python -m venv venv
    # Windows:
    .\venv\Scripts\activate
    # macOS/Linux:
    source venv/bin/activate
    ```
3.  **Install Required Dependencies:**
    ```bash
    pip install -r requirements.txt
    ```
4.  **Create Configuration Env File:**
    Copy `backend/.env.example` to `backend/.env` and fill in the required variables (Groq Key, Firebase ID, etc.).
5.  **Place Firebase Credentials:**
    Place your downloaded Firebase admin credentials JSON file in the backend root directory, named `firebase-credentials.json` (as mapped in your `.env`).
6.  **Create Data Directories:**
    ```bash
    mkdir -p data
    ```
7.  **Run the Server:**
    ```bash
    uvicorn main:app --host 0.0.0.0 --port 8001 --reload
    ```
8.  **Verify Setup:**
    ```bash
    curl http://localhost:8001/health
    # Expected response: {"status":"ok","version":"2.0.0","environment":"development"}
    ```

### Flutter App Setup

1.  **Navigate to the Flutter project:**
    ```bash
    cd frontend/companion_app
    ```
2.  **Add Typography Fonts:**
    Download the font files for `CormorantGaramond` and `PlusJakartaSans` from Google Fonts and place them under `assets/fonts/`:
    - `assets/fonts/CormorantGaramond-Regular.ttf`
    - `assets/fonts/CormorantGaramond-Light.ttf`
    - `assets/fonts/PlusJakartaSans-Regular.ttf`
    - `assets/fonts/PlusJakartaSans-Bold.ttf`
3.  **Initialize Firebase Configuration:**
    Configure flutterfire project connections:
    ```bash
    flutterfire configure --project=your-firebase-project-id
    ```
4.  **Install Packages:**
    ```bash
    flutter pub get
    ```
5.  **Run application:**
    ```bash
    flutter run
    ```

---

## Deployment (Railway)

Eden is configured to deploy directly to Railway.

1.  **Create a New Project** on Railway from your connected GitHub repository. Select the `/backend` folder as the root directory.
2.  **Add a Persistent Volume:**
    Create a Railway volume and mount it to the web service at `/app/data`. This keeps the SQLite database persistent across dyno restarts.
3.  **Configure Environment Variables:**
    Set the environment variables listed in the Reference section below. Ensure `ENVIRONMENT` is set to `production` and `DATABASE_URL` is set to `/app/data/eden.db`.
4.  **Deploy:**
    Nixpacks will automatically build the environment using the `Procfile`.
5.  **Perform Health Check Verification:**
    Validate deployment status by accessing:
    `GET https://your-railway-domain.up.railway.app/health`

---

## Environment Variables Reference

| Variable | Default Value | Required | Description |
|---|---|---|---|
| `ENVIRONMENT` | `development` | Yes | App runtime stage (`development` or `production`) |
| `LOG_LEVEL` | `INFO` | No | Logging verbosity filter |
| `APP_HOST` | `0.0.0.0` | No | FastAPI listener host IP |
| `APP_PORT` | `8001` | No | API port |
| `ALLOWED_ORIGINS` | `["*"]` | No | CORS configuration |
| `DATABASE_URL` | `./data/eden.db` | Yes | SQLite local or production volume filepath |
| `GROQ_API_KEY` | *(None)* | Yes | API credential token for Groq |
| `GROQ_CHAT_MODEL` | `llama-3.3-70b-versatile` | No | Primary conversational inference LLM model |
| `GROQ_FAST_MODEL` | `llama-3.1-8b-instant` | No | Structured extraction model for consolidations |
| `GROQ_MODEL` | `llama-3.3-70b-versatile` | No | Alias for primary chat model |
| `GROQ_BASE_URL` | `https://api.groq.com/openai/v1` | No | Base endpoint URL for Groq API calls |
| `LLM_TEMPERATURE` | `0.85` | No | Creative temperature for partner messaging |
| `LLM_MAX_TOKENS` | `400` | No | Max length bounds for generated messages |
| `MAX_CONTEXT_MESSAGES`| `10` | No | Context buffer size for active chat window |
| `FIREBASE_PROJECT_ID` | *(None)* | Yes | Google Firebase project identifier |
| `FIREBASE_CREDENTIALS_PATH`| `./firebase-credentials.json` | Yes | File path to credentials file (development) |
| `FIREBASE_CREDENTIALS_B64` | `None` | Yes (Prod) | Base64-encoded credential JSON string (Railway) |
| `MEMORY_EXTRACTION_ENABLED`| `True` | No | Switch toggle for consolidating dream loops |
| `MEMORY_SIMILARITY_THRESHOLD`| `0.4` | No | Cosine distance cut-off for semantic retrieval |
| `MAX_MEMORIES_IN_CONTEXT`| `5` | No | Limit on how many memories populate prompts |
| `PROACTIVE_ENGINE_ENABLED`| `True` | No | Enable proactive outreach triggers |
| `LIFE_SIMULATOR_TICK_SECONDS`| `300` | No | Interval length of simulator updates |
| `BURST_MAX_MESSAGES` | `4` | No | Maximum sub-messages per composed response |
| `BURST_MIN_DELAY_SECONDS`| `3` | No | Lower bound on burst delay composition |
| `BURST_MAX_DELAY_SECONDS`| `12` | No | Upper bound on burst delay composition |
| `OPS_SECRET_KEY` | `dev-only-change-in-production` | Yes | Operational endpoint validation header key |

---

## What Is Not In This Project

To protect the core user experience and maintain system simplicity, the following features are intentionally omitted:

*   **No PostgreSQL:** SQLite serves all storage requirements locally, avoiding network latency and connection pooling.
*   **No Redis or Celery:** Background scheduler runs in-process with APScheduler. Celery worker daemons are omitted.
*   **No ChromaDB or Vector API Services:** `sqlite-vec` runs vector calculations in-memory and stores embeddings as binary blobs in the local SQLite file.
*   **No OpenAI Models:** The application runs SentenceTransformers locally and uses Groq for fast, affordable, high-concurrency LLM inference.
*   **No LangChain or Framework Wrappers:** All LLM prompts, context assembly, and streaming loops use lightweight, direct Python wrappers, preventing overhead.
*   **No User-to-User Networking:** Eden represents a strictly private relationship space. Companions are bound to a single user without data flow bleeding between companions.
*   **No Ads, Tracking, or Analytics:** The app is designed as a safe, private space. No user analytics are captured.

---

## Known Limitations

*   **In-Process Scheduler Scale:** Because APScheduler runs in-process, horizontally scaling to multiple Railway instances would trigger duplicate job execution (e.g., ticking the Life Simulator multiple times). To support scaling, a database-level lock must be introduced.
*   **Cold Start Latency:** SentenceTransformers preloads the `all-MiniLM-L6-v2` model into RAM (~80MB) during startup. The first startup has a 3-5 second delay.
*   **SQLite Concurrency Limits:** Although WAL mode supports concurrent reads, write operations lock the SQLite database. At high traffic volumes (>10,000 active users), the application would require migration to a traditional server-client RDBMS like PostgreSQL.
*   **Out-of-Session Memory Ingestion:** Because the Dream Loop runs 2 hours after a conversation ends, memories generated in the current conversation session will not populate the retrieval context until that 2-hour window has elapsed.
*   **FCM Best-Effort Delivery:** Firebase Cloud Messaging relies on device token registrations and OS notification permissions. Delivery of proactive notifications is best-effort and can be suppressed by mobile operating systems.

---

## Design System

The visual design system of Eden is defined inside `EDEN_DESIGN_SYSTEM.md` at the project root. The app implements a dark, atmospheric palette using `EdenColors` (e.g. `edenVoid`, `edenDepth`, `glassLight`, `edenIris`, and atmospheric orbs like `presenceBlue`). 

The typography employs `Cormorant Garamond` for displays/greetings, and `Plus Jakarta Sans` for body messages, settings, and labels. Animations follow strict timing tokens (`eden_animations.dart`) and elements are built as frosted glass containers (`glass_card.dart`). Hardcoded colors outside `EdenColors` or default white (`#FFFFFF`) surface backgrounds are strictly forbidden to ensure a warm, coherent visual style.
