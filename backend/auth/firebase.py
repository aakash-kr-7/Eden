import logging
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import firebase_admin
from fastapi import Header, HTTPException
from firebase_admin import auth as firebase_auth
from firebase_admin import credentials

from config import settings

logger = logging.getLogger(__name__)

@dataclass(frozen=True)
class User:
    user_id: str
    email: Optional[str] = None

    @property
    def uid(self) -> str:
        """Alias for backwards compatibility with the old AuthenticatedIdentity."""
        return self.user_id

    @property
    def display_name(self) -> Optional[str]:
        """Alias for backwards compatibility with the old AuthenticatedIdentity."""
        if self.email:
            return self.email.split("@")[0]
        return "User"

# Keep the alias AuthenticatedIdentity so other files importing it don't break
AuthenticatedIdentity = User

# Simple in-memory token cache: token -> (User object, expiry_timestamp)
_TOKEN_CACHE = {}

def initialize_firebase_auth() -> None:
    """Initialize Firebase Admin SDK or raise a clear startup error if credentials file doesn't exist."""
    if firebase_admin._apps:
        return

    cred_path_str = settings.FIREBASE_CREDENTIALS_PATH.strip()
    if not cred_path_str:
        raise RuntimeError(
            "FIREBASE_CREDENTIALS_PATH is empty or not configured. "
            "Please set FIREBASE_CREDENTIALS_PATH in your environment variables or .env file."
        )

    path = Path(cred_path_str)
    if not path.exists():
        raise FileNotFoundError(
            f"Firebase credentials file not found at '{path}'. "
            "Please ensure that the path is correct and the file exists."
        )

    app_kwargs = {"options": {"projectId": settings.FIREBASE_PROJECT_ID}}
    cred = credentials.Certificate(path)
    firebase_admin.initialize_app(cred, **app_kwargs)
    logger.info("Firebase Admin initialized with credentials from: %s", path)

def get_or_create_user(user_id: str, email: Optional[str]) -> None:
    """Ensure user exists in the database and preference table (stubbed)."""
    pass

def verify_id_token(id_token: str) -> User:
    """Verify Firebase ID token, cache verified token for 5 minutes, and register user in SQLite."""
    now = time.time()
    
    # Check cache first
    if id_token in _TOKEN_CACHE:
        cached_user, cache_expiry = _TOKEN_CACHE[id_token]
        if now < cache_expiry:
            return cached_user
        else:
            del _TOKEN_CACHE[id_token]

    # Clean cache if it gets too large
    if len(_TOKEN_CACHE) > 1000:
        expired_keys = [k for k, (_, exp) in _TOKEN_CACHE.items() if now >= exp]
        for k in expired_keys:
            del _TOKEN_CACHE[k]

    try:
        decoded = firebase_auth.verify_id_token(id_token, check_revoked=False)
    except Exception as exc:
        logger.warning("Firebase token verification failed: %s", exc)
        raise HTTPException(
            status_code=401,
            detail=f"Invalid or expired Firebase token: {str(exc)}"
        ) from exc

    uid = decoded.get("uid") or decoded.get("user_id") or decoded.get("sub")
    if not uid:
        raise HTTPException(
            status_code=401,
            detail="Firebase token missing user identity identifier (uid)"
        )

    email = decoded.get("email")

    # Upsert user records into db
    try:
        get_or_create_user(uid, email)
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Database synchronization failed during authentication: {str(exc)}"
        )

    user = User(user_id=uid, email=email)
    _TOKEN_CACHE[id_token] = (user, now + 300) # Cache for 5 minutes
    return user

async def get_authenticated_identity(
    authorization: Optional[str] = Header(default=None),
) -> User:
    """Dependency provider to fetch and verify Bearer token from authorization header."""
    if not authorization:
        raise HTTPException(status_code=401, detail="Missing Authorization header")

    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token.strip():
        raise HTTPException(status_code=401, detail="Authorization header must use Bearer token")

    return verify_id_token(token.strip())
