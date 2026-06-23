# =============================================================================
# core/fcm.py — Firebase Cloud Messaging Sender
# =============================================================================

import logging
import asyncio
from firebase_admin import messaging
db = None

logger = logging.getLogger(__name__)

class FCMSender:
    async def send(
        self,
        fcm_token: str,
        title: str,
        body: str,
        data: dict = {}
    ) -> bool:
        """
        Sends FCM notification using Firebase Admin SDK with FCM HTTP v1 API.
        Returns True on success, False on failure.
        """
        if not fcm_token:
            logger.warning("FCM send requested but no fcm_token provided")
            return False

        try:
            # FCM requires all keys and values to be strings
            string_data = {k: str(v) for k, v in data.items()} if data else {}
            
            message = messaging.Message(
                token=fcm_token,
                notification=messaging.Notification(title=title, body=body),
                data=string_data if string_data else None
            )
            
            # Send message in a thread pool via asyncio.to_thread()
            response = await asyncio.to_thread(messaging.send, message)
            logger.info("Successfully sent FCM message: %s", response)
            return True
        except (messaging.UnregisteredError, messaging.SenderIdMismatchError) as exc:
            logger.warning("Invalid FCM token %s: %s. Invalidating token.", fcm_token, exc)
            self._invalidate_token(fcm_token)
            return False
        except Exception as exc:
            logger.error("Error sending FCM: %s", exc)
            return False

    def _invalidate_token(self, fcm_token: str):
        try:
            db.invalidate_fcm_token(fcm_token)
            logger.info("FCM token %s has been set to NULL in the users table", fcm_token[:15] + "...")
        except Exception as e:
            logger.error("Failed to invalidate FCM token in DB: %s", e)
