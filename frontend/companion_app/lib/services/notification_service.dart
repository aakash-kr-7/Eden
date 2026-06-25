// ═══════════════════════════════════════════════════════════════════
// FILE: notification_service.dart
// PURPOSE: Service managing push notifications and local channels.
// CONTEXT: Frontend services.
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'api_service.dart';

class NotificationService {
  final ApiService _apiService;
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  
  // Controller to emit foreground notification messages for in-app banner display
  final StreamController<RemoteMessage> _foregroundMessageController = StreamController<RemoteMessage>.broadcast();
  
  Stream<RemoteMessage> get foregroundMessages => _foregroundMessageController.stream;
  
  // Callback to trigger navigation on notification tap
  void Function()? onNavigateToChat;

  NotificationService(this._apiService);

  Future<void> initialize() async {
    // 1. Request Permissions
    await requestPermission();

    // 2. Setup Local Notifications for Foreground display
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings();
    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Handle local notification click
        onNavigateToChat?.call();
      },
    );

    // Create standard high importance notification channel for Android
    if (Platform.isAndroid) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            'eden_chats',
            'Eden Messages',
            description: 'Notifications for new messages from your Eden partner',
            importance: Importance.max,
          ));
    }

    // 3. Listen to foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _showLocalNotification(message);
      _foregroundMessageController.add(message);
    });

    // 4. Handle background / terminated app taps
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      onNavigateToChat?.call();
    });

    final initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      // App was opened from a terminated state via notification click
      Future.delayed(const Duration(milliseconds: 1000), () {
        onNavigateToChat?.call();
      });
    }

    // 5. Monitor FCM token changes & sync
    _fcm.onTokenRefresh.listen((token) {
      _syncToken(token);
    });

    // Sync current token initially
    final currentToken = await _fcm.getToken();
    if (currentToken != null) {
      await _syncToken(currentToken);
    }
  }

  Future<void> requestPermission() async {
    try {
      final settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint('User granted notification permission: ${settings.authorizationStatus}');
    } catch (e) {
      debugPrint('Error requesting notification permission: $e');
    }
  }

  Future<void> _syncToken(String token) async {
    try {
      final platformName = Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'web');
      await _apiService.registerFcmToken(
        token,
        platformName,
      );
      debugPrint('Successfully synced FCM token to backend.');
    } catch (e) {
      debugPrint('FCM token sync failed: $e');
    }
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    await _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'eden_chats',
          'Eden Messages',
          channelDescription: 'Notifications for new messages from your Eden partner',
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }
}
