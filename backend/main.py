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
from api.chat import router as chat_router
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

# Scheduler jobs (placeholder functions to run until underlying logic is implemented)
def life_simulator_tick():
    logger.info("Executing scheduled job: life_simulator_tick")

def proactive_evaluate():
    logger.info("Executing scheduled job: proactive_evaluate")

def proactive_deliver():
    logger.info("Executing scheduled job: proactive_deliver")

def dream_loop_check():
    logger.info("Executing scheduled job: dream_loop_check")

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
    initialize_database()
    initialize_firebase()
    start_scheduler()

@app.on_event("shutdown")
async def shutdown_event():
    logger.info("Shutting down Eden application...")
    stop_scheduler()
