import os
from pathlib import Path
from typing import List, Optional
from pydantic import Field, computed_field
from pydantic_settings import BaseSettings, SettingsConfigDict

# Base directories
BACKEND_DIR = Path(__file__).parent.resolve()
ROOT_DIR = BACKEND_DIR.parent.resolve()

class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=(
            str(ROOT_DIR / ".env"),
            str(BACKEND_DIR / ".env")
        ),
        env_file_encoding="utf-8",
        extra="ignore"
    )

    # ── Required Settings ──────────────────────────────────────────────────
    DATABASE_URL: str = Field(default=str(BACKEND_DIR / "db" / "partner.db"))
    FIREBASE_CREDENTIALS_PATH: str = Field(default="")
    GROQ_API_KEY: str = Field(default="")
    GROQ_MODEL: str = Field(default="llama-3.1-70b-versatile")
    MAX_CONTEXT_MESSAGES: int = Field(default=20)
    MEMORY_EXTRACTION_ENABLED: bool = Field(default=True)
    PROACTIVE_ENGINE_ENABLED: bool = Field(default=True)
    BURST_MAX_MESSAGES: int = Field(default=4)
    BURST_MIN_DELAY_SECONDS: int = Field(default=3)
    BURST_MAX_DELAY_SECONDS: int = Field(default=12)
    LIFE_SIMULATOR_TICK_SECONDS: int = Field(default=300)
    LOG_LEVEL: str = Field(default="INFO")
    ENVIRONMENT: str = Field(default="development")
    ALLOWED_ORIGINS: List[str] = Field(default=["*"])
    ADMIN_DEBUG_TOKEN: str = Field(default="admin_secret")
    OPS_SECRET_KEY: str = Field(default="ops_secret_default_key")

    # ── Additional Existing Settings (for compatibility) ───────────────────
    ARCHETYPES_DIR: str = Field(default=str(BACKEND_DIR / "personality" / "archetypes"))
    DEFAULT_PARTNER: str = Field(default="the_anchor")
    LLM_TEMPERATURE: float = Field(default=0.82)
    LLM_MAX_TOKENS: int = Field(default=300)
    LLM_FALLBACK_MODEL: str = Field(default="llama-3.1-8b-instant")
    GROQ_BASE_URL: str = Field(default="https://api.groq.com/openai/v1")
    APP_HOST: str = Field(default="0.0.0.0")
    APP_PORT: int = Field(default=8000)
    FIREBASE_PROJECT_ID: str = Field(default="eden-platform-project")
    PROACTIVE_DEFAULT_QUIET_HOURS_START: int = Field(default=23)
    PROACTIVE_DEFAULT_QUIET_HOURS_END: int = Field(default=8)
    MEMORY_RETRIEVAL_COUNT: int = Field(default=6)
    MEMORY_SIMILARITY_THRESHOLD: float = Field(default=0.35)
    MEMORY_EXTRACTION_EVERY_N_TURNS: int = Field(default=1)

    # ── Computed Compatibility Aliases ─────────────────────────────────────
    @computed_field
    @property
    def SQLITE_DB_PATH(self) -> str:
        return self.DATABASE_URL

    @computed_field
    @property
    def LLM_MODEL(self) -> str:
        return self.GROQ_MODEL

    @computed_field
    @property
    def FIREBASE_SERVICE_ACCOUNT_PATH(self) -> str:
        return self.FIREBASE_CREDENTIALS_PATH

    @computed_field
    @property
    def RECENT_HISTORY_TURNS(self) -> int:
        return self.MAX_CONTEXT_MESSAGES

    @computed_field
    @property
    def PROACTIVE_MESSAGES_ENABLED(self) -> bool:
        return self.PROACTIVE_ENGINE_ENABLED

    @computed_field
    @property
    def CORS_ALLOWED_ORIGINS(self) -> List[str]:
        return self.ALLOWED_ORIGINS

    @computed_field
    @property
    def DEBUG(self) -> bool:
        return self.ENVIRONMENT == "development"

    def validate(self):
        """Catch critical misconfiguration early at startup."""
        if not self.GROQ_API_KEY:
            raise ValueError(
                "GROQ_API_KEY is missing. Add it to your .env file.\n"
                "Get one free at: https://console.groq.com"
            )
        return self

settings = Settings()
