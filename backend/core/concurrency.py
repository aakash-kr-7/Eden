import asyncio
import logging
from contextlib import asynccontextmanager
from typing import AsyncContextManager

logger = logging.getLogger(__name__)


class ConcurrencyManager:
    def __init__(self):
        self._user_locks: dict[str, asyncio.Lock] = {}
        self._registry_lock = asyncio.Lock()

    @asynccontextmanager
    async def acquire(self, user_id: str, timeout: float = 120.0):
        """
        Safely acquires a user-scoped lock as an async context manager.
        """
        async with self._registry_lock:
            if user_id not in self._user_locks:
                self._user_locks[user_id] = asyncio.Lock()
            lock = self._user_locks[user_id]

        try:
            await asyncio.wait_for(lock.acquire(), timeout=timeout)
        except asyncio.TimeoutError:
            logger.error("Lock acquisition timed out for user: %s", user_id)
            raise TimeoutError(f"Concurrency lock acquisition timed out for user: {user_id}")

        try:
            yield self
        finally:
            try:
                lock.release()
            except RuntimeError:
                # Lock was not acquired or already released
                pass

            # Cleanup registry to prevent memory leaks for inactive locks
            async with self._registry_lock:
                if user_id in self._user_locks:
                    active_lock = self._user_locks[user_id]
                    if not active_lock.locked() and not getattr(active_lock, "_waiters", None):
                        self._user_locks.pop(user_id, None)
                        logger.debug("Garbage collected inactive lock for user: %s", user_id)

    async def release(self, user_id: str):
        """
        Explicitly release a lock associated with user_id.
        """
        async with self._registry_lock:
            lock = self._user_locks.get(user_id)
        if lock:
            try:
                lock.release()
            except RuntimeError:
                pass


# Create singleton instance
concurrency = ConcurrencyManager()


@asynccontextmanager
async def pair_lock_context(pair_id: str, timeout: float = 120.0):
    """
    Backward-compatible wrapper for pair-scoped locking.
    Extracts user_id from pair_id and delegates to ConcurrencyManager.
    """
    user_id = pair_id.split("::")[0] if "::" in pair_id else pair_id
    async with concurrency.acquire(user_id, timeout=timeout):
        async with concurrency._registry_lock:
            lock = concurrency._user_locks.get(user_id)
        yield lock


async def get_pair_lock(pair_id: str) -> asyncio.Lock:
    """
    Backward-compatible getter for pair-scoped locks.
    Extracts user_id from pair_id and resolves user-scoped Lock.
    """
    user_id = pair_id.split("::")[0] if "::" in pair_id else pair_id
    async with concurrency._registry_lock:
        if user_id not in concurrency._user_locks:
            concurrency._user_locks[user_id] = asyncio.Lock()
        return concurrency._user_locks[user_id]
