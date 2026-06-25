# ═══════════════════════════════════════════════════════════════════
# FILE: main.py
# PURPOSE: FastAPI application entry point for Eden backend.
# CONTEXT: Startup, middleware, router mounting, background scheduler.
# ═══════════════════════════════════════════════════════════════════

import time
import logging
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from apscheduler.schedulers.background import BackgroundScheduler

from config import settings
from db.init import initialize_database
from auth.firebase import initialize_firebase

# Import routers
from api.chat_v4 import router as chat_router
from api.onboarding import router as onboarding_router
from api.profile import router as profile_router
from api.proactive import router as proactive_router
from api.notifications import router as notifications_router
from api.ops import router as ops_router

# Setup logging
logging.basicConfig(level=settings.LOG_LEVEL)
logger = logging.getLogger(__name__)

app = FastAPI(title="Eden API", version="2.0.0")

# CORS Middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Request logging middleware
@app.middleware("http")
async def log_requests(request: Request, call_next):
    start_time = time.time()
    response = await call_next(request)
    duration_ms = (time.time() - start_time) * 1000
    logger.info(
        f"Method: {request.method} Path: {request.url.path} Status: {response.status_code} Duration: {duration_ms:.2f}ms"
    )
    return response

# Global Exception Handler
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.error(f"Global exception: {exc}", exc_info=True)
    return JSONResponse(
        status_code=500,
        content={"error": str(exc), "type": type(exc).__name__}
    )

# Mount routers
app.include_router(chat_router, prefix="/api")
app.include_router(onboarding_router, prefix="/api")
app.include_router(profile_router, prefix="/api")
app.include_router(proactive_router, prefix="/api")
app.include_router(notifications_router, prefix="/api")
app.include_router(ops_router, prefix="/api")

@app.get("/health")
async def health():
    return {"status": "ok", "version": "2.0.0", "environment": settings.ENVIRONMENT}

# Scheduler jobs (connected to actual simulation and proactive outreach logic)
def life_simulator_tick():
    logger.info("Executing scheduled job: life_simulator_tick")
    import asyncio
    from engine.life_simulator import LifeSimulator
    from memory.store import db
    try:
        simulator = LifeSimulator()
        asyncio.run(simulator.run_for_all_active(db))
    except Exception as e:
        logger.error(f"Error in life_simulator_tick scheduled job: {e}", exc_info=True)

def proactive_evaluate():
    logger.info("Executing scheduled job: proactive_evaluate")
    import asyncio
    from engine.proactive_engine import ProactiveEngine
    from memory.store import db
    try:
        engine = ProactiveEngine()
        asyncio.run(engine.evaluate_all(db))
    except Exception as e:
        logger.error(f"Error in proactive_evaluate scheduled job: {e}", exc_info=True)

def proactive_deliver():
    logger.info("Executing scheduled job: proactive_deliver")
    import asyncio
    from engine.proactive_engine import ProactiveEngine
    from memory.store import db
    try:
        engine = ProactiveEngine()
        asyncio.run(engine.deliver_pending(db))
    except Exception as e:
        logger.error(f"Error in proactive_deliver scheduled job: {e}", exc_info=True)

def dream_loop_check():
    logger.info("Executing scheduled job: dream_loop_check")
    import asyncio
    import sqlite3
    from config import settings
    from memory.consolidator import MemoryConsolidator
    
    db_path = settings.DATABASE_URL
    conn = sqlite3.connect(
        db_path,
        check_same_thread=False,
        isolation_level=None
    )
    conn.row_factory = sqlite3.Row
    try:
        conn.enable_load_extension(True)
        import sqlite_vec
        sqlite_vec.load(conn)
        conn.enable_load_extension(False)
        conn.execute("PRAGMA foreign_keys=ON")
    except Exception as e:
        logger.error(f"Failed to load sqlite-vec in dream_loop_check: {e}")
        conn.close()
        return

    try:
        consolidator = MemoryConsolidator()
        asyncio.run(consolidator.run_pending(conn))
    except Exception as e:
        logger.error(f"Error executing dream_loop_check: {e}", exc_info=True)
    finally:
        conn.close()

scheduler = BackgroundScheduler()

def start_scheduler():
    scheduler.add_job(life_simulator_tick, "interval", minutes=5)
    scheduler.add_job(proactive_evaluate, "interval", minutes=15)
    scheduler.add_job(proactive_deliver, "interval", minutes=5)
    scheduler.add_job(dream_loop_check, "interval", minutes=10)
    scheduler.start()
    logger.info("Background scheduler started successfully")

def stop_scheduler():
    scheduler.shutdown()
    logger.info("Background scheduler stopped successfully")

@app.on_event("startup")
async def startup_event():
    logger.info("Starting up Eden application...")
    
    # Production guards
    if settings.ENVIRONMENT == "production":
        logger.info("Running production checks...")
        # 1. DATABASE_URL check
        if not settings.DATABASE_URL.startswith("/app/data/"):
            logger.critical(f"DATABASE_URL must start with /app/data/ in production. Current: {settings.DATABASE_URL}")
            raise SystemExit(1)
            
        # 2. FIREBASE_CREDENTIALS check
        has_b64 = bool(settings.FIREBASE_CREDENTIALS_B64 and settings.FIREBASE_CREDENTIALS_B64.strip())
        has_path = False
        if settings.FIREBASE_CREDENTIALS_PATH:
            import os
            has_path = os.path.exists(settings.FIREBASE_CREDENTIALS_PATH)
        if not (has_b64 or has_path):
            logger.critical("Neither FIREBASE_CREDENTIALS_B64 is set nor does FIREBASE_CREDENTIALS_PATH exist in production.")
            raise SystemExit(1)
            
        # 3. GROQ_API_KEY check
        if not settings.GROQ_API_KEY or not settings.GROQ_API_KEY.strip():
            logger.critical("GROQ_API_KEY must not be empty in production.")
            raise SystemExit(1)
            
        # 4. OPS_SECRET_KEY check
        if settings.OPS_SECRET_KEY == "dev-only-change-in-production":
            logger.warning("OPS_SECRET_KEY is set to default 'dev-only-change-in-production' in production.")

    # Preload SentenceTransformers embedding model
    try:
        from memory.embedder import Embedder
        Embedder.get()
        logger.info("Embedding model loaded: all-MiniLM-L6-v2")
    except Exception as e:
        logger.error(f"Failed to preload embedding model: {e}", exc_info=True)
        if settings.ENVIRONMENT == "production":
            raise SystemExit(1)

    initialize_database()
    initialize_firebase()
    start_scheduler()

@app.on_event("shutdown")
async def shutdown_event():
    logger.info("Shutting down Eden application...")
    stop_scheduler()
