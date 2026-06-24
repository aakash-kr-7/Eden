PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
PRAGMA busy_timeout=5000;
PRAGMA foreign_keys=ON;

-- Users
CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    email TEXT NOT NULL UNIQUE,
    display_name TEXT,
    fcm_token TEXT,
    notification_preferences TEXT DEFAULT '{"proactive":true,"emotional_followup":true,"anniversaries":true,"absence_check":true}',
    onboarding_complete INTEGER DEFAULT 0,
    onboarding_data TEXT DEFAULT '{}',
    relationship_type_intent TEXT,
    attachment_style TEXT,
    communication_pace TEXT,
    emotional_depth_preference TEXT,
    humor_style TEXT,
    created_at TEXT NOT NULL,
    last_active_at TEXT
);

-- Partners (one per user, permanent)
CREATE TABLE IF NOT EXISTS partners (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    archetype_seed TEXT NOT NULL,
    persona_json TEXT NOT NULL,
    voice_style TEXT NOT NULL,
    flaw_profile TEXT NOT NULL,
    relationship_stage TEXT NOT NULL DEFAULT 'new',
    intimacy_tier INTEGER DEFAULT 1,
    blueprint_json TEXT DEFAULT '{}',
    inside_jokes TEXT DEFAULT '[]',
    shared_rituals TEXT DEFAULT '[]',
    generated_at TEXT NOT NULL,
    last_evolved_at TEXT
);

-- Conversations
CREATE TABLE IF NOT EXISTS conversations (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    started_at TEXT NOT NULL,
    last_message_at TEXT,
    message_count INTEGER DEFAULT 0,
    emotional_tone TEXT,
    summary TEXT,
    processed INTEGER DEFAULT 0
);

-- Messages (working memory — truncated after processing)
CREATE TABLE IF NOT EXISTS messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK(role IN ('user', 'partner')),
    content TEXT NOT NULL,
    sent_at TEXT NOT NULL,
    emotional_signal TEXT
);

-- Episodic memories (metadata)
CREATE TABLE IF NOT EXISTS episodic_memories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    memory_text TEXT NOT NULL,
    memory_type TEXT NOT NULL,
    salience_score REAL NOT NULL DEFAULT 0.5,
    emotional_valence TEXT,
    is_pinned INTEGER DEFAULT 0,
    recall_count INTEGER DEFAULT 0,
    decay_factor REAL DEFAULT 1.0,
    source_conversation_id TEXT,
    tags TEXT DEFAULT '[]',
    created_at TEXT NOT NULL,
    last_recalled_at TEXT
);

-- Vector memories (sqlite-vec — 384 dimensions)
CREATE VIRTUAL TABLE IF NOT EXISTS vec_memories USING vec0(
    embedding float[384]
);

-- FTS5 keyword search
CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts USING fts5(
    memory_text,
    content='episodic_memories',
    content_rowid='id'
);

-- Relationship events
CREATE TABLE IF NOT EXISTS relationship_events (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL,
    description TEXT NOT NULL,
    occurred_at TEXT NOT NULL,
    emotional_weight REAL
);

-- Life state (partner's simulated day)
CREATE TABLE IF NOT EXISTS life_state (
    user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    partner_mood TEXT NOT NULL DEFAULT 'content',
    partner_energy TEXT NOT NULL DEFAULT 'normal',
    partner_busy_until TEXT,
    day_arc TEXT NOT NULL DEFAULT 'morning',
    last_proactive_at TEXT,
    updated_at TEXT NOT NULL
);

-- Proactive queue
CREATE TABLE IF NOT EXISTS proactive_queue (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    trigger_type TEXT NOT NULL,
    message_draft TEXT NOT NULL,
    scheduled_for TEXT NOT NULL,
    sent INTEGER DEFAULT 0,
    sent_at TEXT,
    cancelled INTEGER DEFAULT 0
);

-- Notification log
CREATE TABLE IF NOT EXISTS notification_log (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    notification_type TEXT NOT NULL,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    sent_at TEXT NOT NULL,
    opened INTEGER DEFAULT 0
);

-- Onboarding sessions (temporary)
CREATE TABLE IF NOT EXISTS onboarding_sessions (
    user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    current_step INTEGER DEFAULT 0,
    responses TEXT DEFAULT '{}',
    started_at TEXT NOT NULL,
    completed_at TEXT
);

-- Schema version
CREATE TABLE IF NOT EXISTS schema_version (
    version INTEGER PRIMARY KEY,
    applied_at TEXT NOT NULL
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(conversation_id, sent_at);
CREATE INDEX IF NOT EXISTS idx_messages_user ON messages(user_id);
CREATE INDEX IF NOT EXISTS idx_memories_user_salience ON episodic_memories(user_id, salience_score DESC);
CREATE INDEX IF NOT EXISTS idx_memories_user_type ON episodic_memories(user_id, memory_type);
CREATE INDEX IF NOT EXISTS idx_conversations_user ON conversations(user_id, last_message_at DESC);
CREATE INDEX IF NOT EXISTS idx_proactive_pending ON proactive_queue(user_id, scheduled_for) WHERE sent=0 AND cancelled=0;
