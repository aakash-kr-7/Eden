-- =============================================================================
-- EDEN canonical schema
-- =============================================================================
PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;

-- =============================================================================
-- USERS
-- =============================================================================
CREATE TABLE IF NOT EXISTS users (
    id                    TEXT PRIMARY KEY,
    display_name          TEXT,
    email                 TEXT,
    created_at            DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_seen             DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_active_at        DATETIME,
    name                  TEXT,
    preferred_name        TEXT,
    onboarding_signals    TEXT,
    onboarding_completed  INTEGER DEFAULT 0,
    fcm_token             TEXT
);

-- =============================================================================
-- PARTNERS
-- =============================================================================
CREATE TABLE IF NOT EXISTS partners (
    id                    TEXT PRIMARY KEY,
    user_id               TEXT UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name                  TEXT NOT NULL,
    archetype_id          TEXT NOT NULL,
    persona_json          TEXT NOT NULL,
    voice_style_json      TEXT NOT NULL,
    relationship_stage    TEXT,
    stage_voice_overlay   TEXT,
    created_at            DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at            DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- =============================================================================
-- CONVERSATIONS
-- =============================================================================
CREATE TABLE IF NOT EXISTS conversations (
    id                    TEXT PRIMARY KEY,
    user_id               TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    session_number        INTEGER DEFAULT 1,
    session_status        TEXT DEFAULT 'active',
    message_count         INTEGER DEFAULT 0,
    is_deleted            INTEGER DEFAULT 0,
    emotional_arc         TEXT,
    topics_discussed      TEXT,
    session_summary       TEXT,
    started_at            DATETIME DEFAULT CURRENT_TIMESTAMP,
    ended_at              DATETIME
);

-- =============================================================================
-- MESSAGES
-- =============================================================================
CREATE TABLE IF NOT EXISTS messages (
    id                    TEXT PRIMARY KEY,
    conversation_id       TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id               TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role                  TEXT NOT NULL CHECK(role IN ('user', 'assistant')),
    content               TEXT NOT NULL,
    created_at            DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- =============================================================================
-- MEMORIES
-- =============================================================================
CREATE TABLE IF NOT EXISTS memories (
    id                    TEXT PRIMARY KEY,
    user_id               TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    content               TEXT NOT NULL,
    memory_type           TEXT,
    salience              REAL DEFAULT 0.0,
    emotional_valence     TEXT,
    tags                  TEXT, -- JSON list of tags
    decay_factor          REAL DEFAULT 1.0,
    is_pinned             INTEGER DEFAULT 0,
    last_recalled_at      DATETIME,
    recall_count          INTEGER DEFAULT 0,
    created_at            DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- =============================================================================
-- RELATIONSHIP EVENTS
-- =============================================================================
CREATE TABLE IF NOT EXISTS relationship_events (
    id                    INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id               TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    event_type            TEXT NOT NULL,
    description           TEXT NOT NULL,
    confidence            REAL DEFAULT 1.0,
    created_at            DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- =============================================================================
-- PROACTIVE QUEUE
-- =============================================================================
CREATE TABLE IF NOT EXISTS proactive_queue (
    id                    TEXT PRIMARY KEY,
    user_id               TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    trigger_type          TEXT,
    scheduled_at          DATETIME,
    status                TEXT DEFAULT 'pending',
    payload_json          TEXT,
    created_at            DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at            DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- =============================================================================
-- LIFE STATE
-- =============================================================================
CREATE TABLE IF NOT EXISTS life_state (
    user_id               TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    mood                  TEXT NOT NULL DEFAULT 'content',
    energy                TEXT NOT NULL DEFAULT 'balanced',
    day_arc               TEXT NOT NULL DEFAULT 'morning',
    partner_busy_until    DATETIME,
    last_tick_at          DATETIME DEFAULT CURRENT_TIMESTAMP,
    created_at            DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at            DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- =============================================================================
-- NOTIFICATION LOG
-- =============================================================================
CREATE TABLE IF NOT EXISTS notification_log (
    id                    TEXT PRIMARY KEY,
    user_id               TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title                 TEXT NOT NULL,
    body                  TEXT NOT NULL,
    sent_at               DATETIME DEFAULT CURRENT_TIMESTAMP,
    status                TEXT NOT NULL DEFAULT 'success',
    error_message         TEXT
);

-- =============================================================================
-- ONBOARDING SESSIONS
-- =============================================================================
CREATE TABLE IF NOT EXISTS onboarding_sessions (
    user_id               TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    current_step          INTEGER DEFAULT 0,
    responses             TEXT DEFAULT '{}',
    started_at            TEXT NOT NULL,
    completed_at          TEXT
);

-- =============================================================================
-- NOTIFICATION PREFERENCES
-- =============================================================================
CREATE TABLE IF NOT EXISTS notification_preferences (
    user_id               TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    proactive             INTEGER DEFAULT 1,
    emotional_followup    INTEGER DEFAULT 1,
    anniversaries         INTEGER DEFAULT 1,
    absence_check         INTEGER DEFAULT 1,
    created_at            DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at            DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- =============================================================================
-- SCHEMA VERSION
-- =============================================================================
CREATE TABLE IF NOT EXISTS schema_version (
    version               INTEGER PRIMARY KEY,
    applied_at            TEXT NOT NULL
);
INSERT OR IGNORE INTO schema_version VALUES (1, datetime('now'));

-- =============================================================================
-- INDEXES
-- =============================================================================
CREATE INDEX IF NOT EXISTS idx_conversations_user_started ON conversations(user_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_conversation_created ON messages(conversation_id, created_at ASC);
CREATE INDEX IF NOT EXISTS idx_messages_user_created ON messages(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_memories_user_pinned ON memories(user_id, is_pinned DESC, salience DESC);
CREATE INDEX IF NOT EXISTS idx_relationship_events_user_created ON relationship_events(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_proactive_queue_user_status ON proactive_queue(user_id, status, scheduled_at ASC);
CREATE INDEX IF NOT EXISTS idx_notification_log_user_sent ON notification_log(user_id, sent_at DESC);
