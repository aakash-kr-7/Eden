# =============================================================================
# core/fcm.py — Firebase Cloud Messaging Sender
# =============================================================================

import logging
from firebase_admin import messaging
from firebase_admin.exceptions import FirebaseError, InvalidArgumentError
from memory.store import db

logger = logging.getLogger(__name__)

class FCMSender:
    async def send(self, fcm_token: str, title: str, body: str, data: dict = {}) -> bool:
        """
        Sends FCM notification.
        Uses firebase-admin SDK.
        Returns True on success, False on failure.
        On InvalidArgument/NotRegistered error: mark token as invalid, don't retry.
        """
        if not fcm_token:
            logger.warning("FCM send requested but no fcm_token provided")
            return False

        try:
            # firebase-admin SDK requires keys and values to be strings in data dict
            string_data = {}
            if data:
                for k, v in data.items():
                    if v is not None:
                        string_data[str(k)] = str(v)
            
            message = messaging.Message(
                token=fcm_token,
                notification=messaging.Notification(title=title, body=body),
                data=string_data if string_data else None
            )
            # send is synchronous in the SDK, call it directly
            response = messaging.send(message)
            logger.info("Successfully sent FCM message: %s", response)
            return True
        except messaging.UnregisteredError as exc:
            logger.warning("FCM token unregistered/expired: %s. Invalidating token.", exc)
            self._invalidate_token(fcm_token)
            return False
        except InvalidArgumentError as exc:
            logger.warning("FCM token invalid argument: %s. Invalidating token.", exc)
            self._invalidate_token(fcm_token)
            return False
        except FirebaseError as exc:
            error_code = getattr(exc, "code", "")
            if error_code in ("registration-token-not-registered", "invalid-argument"):
                logger.warning("FCM token invalid (code: %s). Invalidating token.", error_code)
                self._invalidate_token(fcm_token)
            else:
                logger.error("Firebase error sending FCM: %s", exc)
            return False
        except Exception as exc:
            logger.exception("Unexpected error sending FCM: %s", exc)
            return False

    def _invalidate_token(self, fcm_token: str):
        try:
            db.invalidate_fcm_token(fcm_token)
            logger.info("FCM token %s has been set to NULL in the users table", fcm_token[:15] + "...")
        except Exception as e:
            logger.error("Failed to invalidate FCM token in DB: %s", e)
