# ═══════════════════════════════════════════════════════════════════
# FILE: db/init.py
# PURPOSE: Initializes the Eden SQLite database on startup.
# CONTEXT: Called once from main.py at application startup.
# ═══════════════════════════════════════════════════════════════════

import sqlite3
from pathlib import Path
from config import settings
import logging
import os
import sys

logger = logging.getLogger(__name__)

# Windows DLL search path helper for sqlite-vec MinGW dependencies
if sys.platform == "win32":
    git_mingw = r"C:\Program Files\Git\mingw64\bin"
    if os.path.exists(git_mingw) and git_mingw not in os.environ["PATH"]:
        os.environ["PATH"] = git_mingw + ";" + os.environ["PATH"]
    try:
        import sqlite_vec
        sqlite_vec_dir = os.path.dirname(sqlite_vec.loadable_path())
        if os.path.exists(sqlite_vec_dir) and sqlite_vec_dir not in os.environ["PATH"]:
            os.environ["PATH"] = sqlite_vec_dir + ";" + os.environ["PATH"]
    except Exception:
        pass

def get_db_path() -> str:
    return settings.DATABASE_URL

def get_connection() -> sqlite3.Connection:
    conn = sqlite3.connect(
        get_db_path(),
        check_same_thread=False,
        isolation_level=None
    )
    conn.row_factory = sqlite3.Row
    return conn

def initialize_database():
    """
    Runs schema.sql against the database.
    Safe to call multiple times (all CREATE TABLE use IF NOT EXISTS).
    Loads sqlite-vec extension before running schema.
    """
    db_path = Path(get_db_path())
    db_path.parent.mkdir(parents=True, exist_ok=True)
    
    conn = sqlite3.connect(str(db_path))
    
    # Load sqlite-vec extension
    try:
        conn.enable_load_extension(True)
        import sqlite_vec
        sqlite_vec.load(conn)
        conn.enable_load_extension(False)
        logger.info("sqlite-vec extension loaded successfully")
    except Exception as e:
        logger.error(f"Failed to load sqlite-vec: {e}")
        raise RuntimeError(f"sqlite-vec required but failed to load: {e}")
    
    # Apply WAL pragmas
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA synchronous=NORMAL")
    conn.execute("PRAGMA busy_timeout=5000")
    conn.execute("PRAGMA foreign_keys=ON")
    
    # Run schema
    schema_sql = Path("db/schema.sql").read_text()
    conn.executescript(schema_sql)
    
    # Insert schema version if not exists
    conn.execute(
        "INSERT OR IGNORE INTO schema_version VALUES (1, datetime('now'))"
    )
    conn.commit()
    conn.close()
    logger.info(f"Database initialized at {db_path}")

def get_db():
    """
    FastAPI dependency. Yields a sqlite3 connection with sqlite-vec loaded.
    Closes connection after request completes.
    """
    conn = sqlite3.connect(
        get_db_path(),
        check_same_thread=False,
        isolation_level=None
    )
    conn.row_factory = sqlite3.Row
    conn.enable_load_extension(True)
    import sqlite_vec
    sqlite_vec.load(conn)
    conn.enable_load_extension(False)
    conn.execute("PRAGMA foreign_keys=ON")
    try:
        yield conn
    finally:
        conn.close()
