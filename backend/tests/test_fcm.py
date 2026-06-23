import sys
import os
import asyncio
from unittest.mock import MagicMock, patch

# Adjust path to import backend modules
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from firebase_admin import messaging
from core.fcm import FCMSender
from memory.store import db

def test_fcm_sender_success():
    print("=== TESTING FCM SENDER SUCCESS ===")
    
    sender = FCMSender()
    
    with patch("firebase_admin.messaging.send") as mock_send:
        mock_send.return_value = "projects/mock-project/messages/mock-id"
        
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        try:
            success = loop.run_until_complete(
                sender.send(
                    fcm_token="mock_token_123",
                    title="Hello",
                    body="World",
                    data={"key": 42}
                )
            )
        finally:
            loop.close()
            
        assert success is True
        mock_send.assert_called_once()
        # Verify the structure of the message passed to send
        args, kwargs = mock_send.call_args
        message = args[0]
        assert message.token == "mock_token_123"
        assert message.notification.title == "Hello"
        assert message.notification.body == "World"
        assert message.data == {"key": "42"}  # values converted to string!
        
    print("[OK] FCM send success verified.")

def test_fcm_sender_unregistered():
    print("=== TESTING FCM SENDER UNREGISTERED ===")
    
    sender = FCMSender()
    
    with patch("firebase_admin.messaging.send") as mock_send, \
         patch.object(db, "invalidate_fcm_token") as mock_invalidate:
         
        mock_send.side_effect = messaging.UnregisteredError("Token unregistered")
        
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        try:
            success = loop.run_until_complete(
                sender.send(
                    fcm_token="mock_token_456",
                    title="Hello",
                    body="World"
                )
            )
        finally:
            loop.close()
            
        assert success is False
        mock_invalidate.assert_called_once_with("mock_token_456")
        
    print("[OK] FCM send unregistered handling verified.")

def test_fcm_sender_sender_id_mismatch():
    print("=== TESTING FCM SENDER SENDER ID MISMATCH ===")
    
    sender = FCMSender()
    
    with patch("firebase_admin.messaging.send") as mock_send, \
         patch.object(db, "invalidate_fcm_token") as mock_invalidate:
         
        mock_send.side_effect = messaging.SenderIdMismatchError("Sender ID mismatch")
        
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        try:
            success = loop.run_until_complete(
                sender.send(
                    fcm_token="mock_token_789",
                    title="Hello",
                    body="World"
                )
            )
        finally:
            loop.close()
            
        assert success is False
        mock_invalidate.assert_called_once_with("mock_token_789")
        
    print("[OK] FCM send sender ID mismatch handling verified.")

if __name__ == "__main__":
    test_fcm_sender_success()
    test_fcm_sender_unregistered()
    test_fcm_sender_sender_id_mismatch()
