# ═══════════════════════════════════════════════════════════════════
# FILE: auth/firebase.py
# PURPOSE: Firebase Auth initialization and JWT token verification.
# CONTEXT: Used as FastAPI dependency on all authenticated endpoints.
# ═══════════════════════════════════════════════════════════════════

import base64
import json
import os
import tempfile
import logging
import time
from datetime import datetime
from fastapi import Header, HTTPException, Depends
from pydantic import BaseModel
import firebase_admin
from firebase_admin import credentials, auth

from config import settings

logger = logging.getLogger(__name__)

# In-memory token cache: {token: (expiry_timestamp, data_dict)}
_TOKEN_CACHE: dict[str, tuple[float, dict]] = {}
TOKEN_CACHE_TTL = 300  # 5 minutes

class AuthenticatedIdentity(BaseModel):
    uid: str
    email: str | None = None

def initialize_firebase():
    """
    Called on startup. Decodes Firebase credentials from base64 env if present,
    otherwise loads from file path. Fallbacks to default app configuration.
    """
    if firebase_admin._apps:
        logger.info("Firebase already initialized.")
        return

    b64_creds = settings.FIREBASE_CREDENTIALS_B64
    if b64_creds:
        try:
            decoded = base64.b64decode(b64_creds).decode("utf-8")
            creds_dict = json.loads(decoded)
            
            # Write temp JSON file and use it
            fd, temp_path = tempfile.mkstemp(suffix=".json")
            try:
                with os.fdopen(fd, "w") as tmp:
                    tmp.write(decoded)
                cred = credentials.Certificate(temp_path)
                firebase_admin.initialize_app(cred)
                logger.info("Firebase initialized successfully via decoded base64 credentials in temp file.")
            finally:
                try:
                    os.remove(temp_path)
                except Exception:
                    pass
        except Exception as e:
            logger.error(f"Failed to initialize Firebase from base64 credentials: {e}")
            raise e
    else:
        creds_path = settings.FIREBASE_CREDENTIALS_PATH
        if os.path.exists(creds_path):
            try:
                cred = credentials.Certificate(creds_path)
                firebase_admin.initialize_app(cred)
                logger.info(f"Firebase initialized successfully from credential file: {creds_path}")
            except Exception as e:
                logger.error(f"Failed to initialize Firebase from credentials path {creds_path}: {e}")
                raise e
        else:
            logger.warning(
                f"Firebase credentials not found at {creds_path}. Initializing with default Application Credentials."
            )
            try:
                firebase_admin.initialize_app()
                logger.info("Firebase initialized via default credentials.")
            except Exception as e:
                logger.error(f"Failed to initialize Firebase with default credentials: {e}")
                if settings.ENVIRONMENT != "development":
                    raise e

async def verify_token(authorization: str = Header(...)) -> dict:
    """
    FastAPI dependency. Extracts Bearer token, verifies it via firebase-admin,
    and returns {"user_id": str, "email": str}. Caches results for 5 minutes.
    """
    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Invalid Authorization header format. Use 'Bearer <token>'.")
    
    token = authorization.split("Bearer ")[1].strip()
    now = time.time()

    # Check cache
    if token in _TOKEN_CACHE:
        cached_time, cached_data = _TOKEN_CACHE[token]
        if now - cached_time < TOKEN_CACHE_TTL:
            return cached_data
        else:
            _TOKEN_CACHE.pop(token, None)

    # Dev/Mock fallback
    if settings.ENVIRONMENT == "development" and (token.startswith("mock-") or token == "test"):
        user_id = token.replace("mock-", "") if token.startswith("mock-") else "test_user_id"
        email = f"{user_id}@example.com"
        data = {"user_id": user_id, "email": email}
        _TOKEN_CACHE[token] = (now, data)
        return data

    try:
        decoded_token = auth.verify_id_token(token)
        user_id = decoded_token.get("uid") or decoded_token.get("sub")
        email = decoded_token.get("email")
        if not user_id:
            raise HTTPException(status_code=401, detail="Invalid token: missing uid attribute.")
        
        data = {"user_id": user_id, "email": email}
        _TOKEN_CACHE[token] = (now, data)
        return data
    except Exception as e:
        logger.error(f"Firebase token verification failed: {e}")
        raise HTTPException(status_code=401, detail=f"Token verification failed: {str(e)}")

async def get_authenticated_identity(authorization: str = Header(...)) -> AuthenticatedIdentity:
    """
    FastAPI dependency. Returns AuthenticatedIdentity with uid and email.
    """
    data = await verify_token(authorization)
    return AuthenticatedIdentity(uid=data["user_id"], email=data.get("email"))

def get_or_create_user(db, user_id: str, email: str) -> dict:
    """
    Upserts user into the users table. If user is new, sets onboarding_complete = 0.
    Returns the user row dict.
    """
    cursor = db.execute("SELECT * FROM users WHERE id = ?", (user_id,))
    row = cursor.fetchone()
    if row:
        return dict(row)

    now_str = datetime.utcnow().isoformat()
    db.execute(
        """
        INSERT INTO users (id, email, onboarding_complete, created_at, last_active_at)
        VALUES (?, ?, 0, ?, ?)
        """,
        (user_id, email, now_str, now_str)
    )
    db.commit()

    cursor = db.execute("SELECT * FROM users WHERE id = ?", (user_id,))
    row = cursor.fetchone()
    return dict(row)
