# ═══════════════════════════════════════════════════════════════════
# FILE: config.py
# PURPOSE: All environment variable configuration for Eden backend.
# CONTEXT: Imported everywhere via `from config import settings`.
# ═══════════════════════════════════════════════════════════════════

from pydantic_settings import BaseSettings
from functools import lru_cache

class Settings(BaseSettings):
    ENVIRONMENT: str = "development"
    LOG_LEVEL: str = "INFO"
    APP_HOST: str = "0.0.0.0"
    APP_PORT: int = 8001
    ALLOWED_ORIGINS: list[str] = ["*"]
    
    DATABASE_URL: str = "./data/eden.db"
    
    GROQ_API_KEY: str
    GROQ_CHAT_MODEL: str = "llama-3.3-70b-versatile"
    GROQ_FAST_MODEL: str = "llama-3.1-8b-instant"
    LLM_TEMPERATURE: float = 0.85
    LLM_MAX_TOKENS: int = 400
    MAX_CONTEXT_MESSAGES: int = 10
    
    FIREBASE_PROJECT_ID: str
    FIREBASE_CREDENTIALS_PATH: str = "./firebase-credentials.json"
    FIREBASE_CREDENTIALS_B64: str | None = None
    
    MEMORY_EXTRACTION_ENABLED: bool = True
    MEMORY_SIMILARITY_THRESHOLD: float = 0.4
    MAX_MEMORIES_IN_CONTEXT: int = 5
    
    PROACTIVE_ENGINE_ENABLED: bool = True
    LIFE_SIMULATOR_TICK_SECONDS: int = 300
    
    BURST_MAX_MESSAGES: int = 4
    BURST_MIN_DELAY_SECONDS: int = 3
    BURST_MAX_DELAY_SECONDS: int = 12
    
    OPS_SECRET_KEY: str = "dev-only-change-in-production"
    
    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        extra = "ignore"

@lru_cache()
def get_settings() -> Settings:
    return Settings()

settings = get_settings()
