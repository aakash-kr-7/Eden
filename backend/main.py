import logging
import sys
import time
import asyncio
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError
from starlette.exceptions import HTTPException as StarletteHTTPException
from apscheduler.schedulers.asyncio import AsyncIOScheduler

from auth.firebase import initialize_firebase_auth
from config import settings

from api.auth import router as auth_router
from api.chat import router as chat_router
from api.onboarding import router as onboarding_router
from api.profile import router as profile_router
from api.proactive import router as proactive_router
from api.notifications import router as notifications_router
from api.ops import router as ops_router

# Setup logger before anything else
logging.basicConfig(
    level=logging.getLevelName(settings.LOG_LEVEL),
    format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
    datefmt="%H:%M:%S",
    handlers=[
        logging.StreamHandler(sys.stdout),
    ]
)

logger = logging.getLogger("main")

# Background scheduler instance
scheduler = AsyncIOScheduler()

async def run_life_simulator():
    """Trigger life simulator checks for all active user-companion pairs."""
    logger.info("Executing life simulator background check...")
    try:
        from core.life_simulator import LifeSimulator
        simulator = LifeSimulator()
        await simulator.run_for_all_active_users()
        logger.info("Life simulator background check complete.")
    except Exception as exc:
        logger.error("Error encountered in life simulator background task: %s", exc, exc_info=True)

async def run_proactive_engine():
    """Periodically evaluate and dispatch proactive messages to users."""
    logger.info("Executing proactive engine background check...")
    if not settings.PROACTIVE_ENGINE_ENABLED:
        logger.info("Proactive engine task skipped (disabled).")
        return

    try:
        from memory.store import db
        from core.proactive_engine import maybe_generate_for_user
        
        user_ids = await asyncio.to_thread(db.list_user_ids)
        sem = asyncio.Semaphore(10)

        async def process_single_user(user_id: str):
            async with sem:
                try:
                    events = await maybe_generate_for_user(user_id, limit=1)
                    if events:
                        logger.info("Successfully generated and queued %d proactive events for user %s", len(events), user_id)
                except Exception as exc:
                    logger.error("Failed proactive event generation for user %s: %s", user_id, exc)

        tasks = [process_single_user(uid) for uid in user_ids]
        await asyncio.gather(*tasks)
        logger.info("Proactive engine background check complete.")
    except Exception as exc:
        logger.error("Error encountered in proactive engine background task: %s", exc, exc_info=True)


async def run_proactive_delivery():
    """Periodically check and deliver pending proactive outreach messages."""
    logger.info("Executing proactive delivery background check...")
    if not settings.PROACTIVE_ENGINE_ENABLED:
        logger.info("Proactive engine delivery skipped (disabled globally).")
        return

    try:
        from core.proactive_engine import ProactiveEngine
        engine = ProactiveEngine()
        await engine.deliver_pending()
        logger.info("Proactive delivery background check complete.")
    except Exception as exc:
        logger.error("Error encountered in proactive delivery background task: %s", exc, exc_info=True)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # ── STARTUP ────────────────────────────────────────────────────────────
    logger.info("=" * 60)
    logger.info("Eden API starting up")
    logger.info("=" * 60)

    # 1. Validate configuration
    try:
        settings.validate()
        logger.info("Configuration validation succeeded.")
    except ValueError as e:
        logger.critical("Configuration validation failed: %s", e)
        sys.exit(1)

    # 2. Connect database (this automatically runs schema setup/migrations)
    from memory.store import db
    try:
        db.connect()
        logger.info("Database connection established successfully.")
    except Exception as e:
        logger.critical("Database connection and schema setup failed: %s", e)
        sys.exit(1)

    # 3. Connect ChromaDB client
    from memory.retriever import get_chroma_client
    try:
        get_chroma_client()
        logger.info("ChromaDB client connected.")
    except Exception as e:
        logger.error("ChromaDB initialization failed: %s. Memory features may be degraded.", e)

    # 4. Initialize Firebase SDK Auth
    try:
        initialize_firebase_auth()
        logger.info("Firebase SDK Auth initialized.")
    except Exception as e:
        logger.critical("Firebase Admin initialization failed: %s", e)
        sys.exit(1)

    # 5. Start background jobs
    scheduler.add_job(
        run_life_simulator,
        "interval",
        seconds=settings.LIFE_SIMULATOR_TICK_SECONDS,
        id="life_simulator",
        replace_existing=True
    )
    scheduler.add_job(
        run_proactive_engine,
        "interval",
        seconds=600,
        id="proactive_engine",
        replace_existing=True
    )
    scheduler.add_job(
        run_proactive_delivery,
        "interval",
        seconds=300,
        id="proactive_delivery",
        replace_existing=True
    )
    scheduler.start()
    logger.info("Background job scheduler initialized and started.")

    yield # Serves API calls

    # ── SHUTDOWN ───────────────────────────────────────────────────────────
    logger.info("Graceful shutdown initiated...")
    scheduler.shutdown(wait=False)
    db.close()
    logger.info("Graceful shutdown completed successfully.")


# FastAPI Application Definition
app = FastAPI(
    title="Eden API",
    description="Production backend API for Eden companion relationship platform.",
    version="2.0.0",
    docs_url="/docs" if settings.DEBUG else None,
    redoc_url="/redoc" if settings.DEBUG else None,
    lifespan=lifespan,
)

# CORS Middleware Setup
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# Request Logging Middleware
@app.middleware("http")
async def request_logging_middleware(request: Request, call_next):
    start_time = time.perf_counter()
    try:
        response = await call_next(request)
        duration_ms = round((time.perf_counter() - start_time) * 1000, 2)
        logger.info(
            "%s %s - Status: %s - Duration: %sms",
            request.method,
            request.url.path,
            response.status_code,
            duration_ms
        )
        return response
    except Exception as exc:
        duration_ms = round((time.perf_counter() - start_time) * 1000, 2)
        logger.error(
            "%s %s - Failed - Duration: %sms - Error: %s",
            request.method,
            request.url.path,
            duration_ms,
            exc,
            exc_info=True
        )
        raise exc


# Exception Handlers for Structured JSON Errors
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.error("Unhandled server exception caught: %s", exc, exc_info=True)
    return JSONResponse(
        status_code=500,
        content={
            "error": "InternalServerError",
            "detail": "An unexpected error occurred on the server.",
            "message": str(exc)
        }
    )

@app.exception_handler(StarletteHTTPException)
async def http_exception_handler(request: Request, exc: StarletteHTTPException):
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "error": "HTTPException",
            "detail": exc.detail
        }
    )

@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    return JSONResponse(
        status_code=422,
        content={
            "error": "ValidationError",
            "detail": "Input validation failed.",
            "errors": exc.errors()
        }
    )


# Mount Routers (group tags cleanly under /api prefix)
app.include_router(auth_router, prefix="/api/auth", tags=["auth"])
app.include_router(chat_router, prefix="/api", tags=["chat"])
app.include_router(onboarding_router, prefix="/api", tags=["onboarding"])
app.include_router(profile_router, prefix="/api", tags=["profile"])
app.include_router(proactive_router, prefix="/api", tags=["proactive"])
app.include_router(notifications_router, prefix="/api", tags=["notifications"])
app.include_router(ops_router, prefix="/api", tags=["ops"])


# Health Check Endpoint
@app.get("/health", tags=["health"])
async def health_check():
    return {
        "status": "ok",
        "version": "2.0.0",
        "environment": settings.ENVIRONMENT
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host=settings.APP_HOST,
        port=settings.APP_PORT,
        reload=settings.DEBUG
    )
