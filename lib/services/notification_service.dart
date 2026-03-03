import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Top-level handler for background/terminated messages
// Must be a top-level function with @pragma to run in a separate isolate
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // We only need firebase_core here — other plugins may not be ready
  await Firebase.initializeApp();

  final title = message.notification?.title ?? message.data['title'] ?? 'Vanguard';
  final body  = message.notification?.body  ?? message.data['body']  ?? 'New message';

  // Show local notification even when app is killed
  final local = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/launcher_icon');
  await local.initialize(const InitializationSettings(android: androidInit));

  const android = AndroidNotificationDetails(
    'vanguard_alerts',
    'Vanguard Alerts',
    importance: Importance.max,
    priority: Priority.max,
    playSound: true,
    enableVibration: true,
    ticker: 'Vanguard',                // shows in status bar ticker
    fullScreenIntent: true,            // pops over lock screen
    styleInformation: BigTextStyleInformation(''),
    icon: '@mipmap/launcher_icon',
  );
  await local.show(
    DateTime.now().millisecond,
    title,
    body,
    const NotificationDetails(android: android),
  );

  debugPrint('📩 Background message shown: ${message.messageId}');
}

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    // 1. Request Permission
    final settings = await _messaging.requestPermission(
      alert: true, badge: true, sound: true, provisional: false,
    );
    debugPrint(settings.authorizationStatus == AuthorizationStatus.authorized
        ? 'User granted permission'
        : 'User denied permission');

    // 2. Setup Local Notifications
    const androidInit = AndroidInitializationSettings('@mipmap/launcher_icon');
    const initSettings = InitializationSettings(android: androidInit);
    await _local.initialize(initSettings, onDidReceiveNotificationResponse: _onNotificationTap);

    // 3. Create High Priority Channel
    final channel = AndroidNotificationChannel(
      'vanguard_alerts', 'Vanguard Alerts',
      description: 'Critical alerts and messages from Vanguard',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      enableLights: true,
      ledColor: const Color(0xff38B6FF),
    );
    await _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);

    // 4. Background handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 5. Foreground messages → show local notification
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        _showLocal(
          title: message.notification!.title ?? 'Vanguard',
          body: message.notification!.body ?? '',
        );
      }
    });

    // 6. Message opened from notification tray
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('📲 Notification opened: ${message.data}');
    });

    // 7. Save FCM Token (Run in background)
    _saveToken();

    // 8. Listen for token refresh
    _messaging.onTokenRefresh.listen((newToken) => _saveToken());

    // 9. Start foreground global listeners for chats and alerts (without backend)
    startGlobalChatListener();
  }

  static void _onNotificationTap(NotificationResponse details) {
    debugPrint('Notification tapped: ${details.payload}');
  }

  static Future<void> _showLocal({required String title, required String body}) async {
    final android = AndroidNotificationDetails(
      'vanguard_alerts', 'Vanguard Alerts',
      importance: Importance.max,
      priority: Priority.max,
      showWhen: true,
      ticker: 'Vanguard',
      fullScreenIntent: true,
      enableVibration: true,
      enableLights: true,
      ledColor: const Color(0xff38B6FF),
      styleInformation: const BigTextStyleInformation(''),
      icon: '@mipmap/launcher_icon',
    );
    final details = NotificationDetails(android: android);
    await _local.show(DateTime.now().millisecond, title, body, details);
  }

  static Future<void> _saveToken() async {
    final token = await _messaging.getToken();
    final user = FirebaseAuth.instance.currentUser;

    if (token != null) {
      debugPrint('\n🔔 VANGUARD FCM TOKEN: $token 🔔');
      debugPrint('Copy this token to Firebase Console > Messaging > New Campaign to test.\n');

      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'fcmToken': token,
          'lastTokenUpdate': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }
  }

  /// Call this to show a local notification for a new chat message
  static Future<void> showChatNotification({required String senderName, required String message}) async {
    await _showLocal(title: senderName, body: message);
  }

  static final Map<String, StreamSubscription> _chatSubs = {};
  static final Map<String, int> _lastNotifiedTimestamps = {};
  static StreamSubscription? _alertSub;
  static StreamSubscription? _contactSub;

  /// Keep listening to all chats the user is part of while the app is in the foreground.
  /// This bridges the gap for immediate local notifications if Cloud Functions are delayed/not deployed.
  static void startGlobalChatListener() {
    final auth = FirebaseAuth.instance;
    final firestore = FirebaseFirestore.instance;

    final db = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: 'https://emergency-alert-9cff6-default-rtdb.asia-southeast1.firebasedatabase.app',
    );

    auth.authStateChanges().listen((user) {
      // Clear previous subscriptions when auth state changes
      _contactSub?.cancel();
      _alertSub?.cancel();
      for (var sub in _chatSubs.values) {
        sub.cancel();
      }
      _chatSubs.clear();

      if (user == null) return;
      final uid = user.uid;

      // Stream all emergency contacts to dynamically form Chat IDs
      _contactSub = firestore.collection('users').doc(uid).collection('contacts').snapshots().listen((snap) {
        for (var doc in snap.docs) {
          final friendId = doc.id;
          final ids = [uid, friendId]..sort();
          final chatId = ids.join('_');

          // Only subscribe once per chat group
          if (!_chatSubs.containsKey(chatId)) {
            _chatSubs[chatId] = db.ref('chats/$chatId/lastMessage').onValue.listen((event) {
              final val = event.snapshot.value;
              if (val is Map) {
                final senderId = val['senderId'];
                final status = val['status'];
                final timestamp = val['timestamp'] as int? ?? 0;
                final text = val['text']?.toString() ?? '📷 Photo';
                final senderName = val['senderName']?.toString() ?? 'Someone';

                // If I am NOT the sender, and the message hasn't been seen yet
                if (senderId != uid && status != 'seen') {
                  // Prevent duplicate notifications caused by state bumps for the exact same message
                  if (_lastNotifiedTimestamps[chatId] != timestamp) {
                    _lastNotifiedTimestamps[chatId] = timestamp;
                    showChatNotification(senderName: senderName, message: text);
                  }
                }
              }
            });
          }
        }
      }, onError: (e) => debugPrint('❌ Firestore Contact Stream Error: $e'));

      // We can also add a global listener for Emergency Alerts
      _alertSub = firestore.collection('alerts').where('status', isEqualTo: 'active').snapshots().listen((snap) {
        for (var docChange in snap.docChanges) {
          if (docChange.type == DocumentChangeType.added) {
            final data = docChange.doc.data();
            if (data != null) {
              final senderId = data['senderId'];
              final senderName = data['senderName'] ?? 'Someone';
              final alertType = data['alertType'] ?? 'Emergency';
              final timestamp = (data['timestamp'] as Timestamp?)?.toDate();

              // Only notify if the alert is FRESH (triggered within the last 2 minutes)
              // This prevents older active alerts from spamming when the app starts
              final isFresh = timestamp != null && 
                             DateTime.now().difference(timestamp).inMinutes < 2;

              if (senderId != uid && isFresh) {
                _showLocal(title: '🚨 $alertType Alert', body: '$senderName has triggered an alert!');
              }
            }
          }
        }
      }, onError: (e) => debugPrint('❌ Firestore Alerts Stream Error: $e'));
    });
  }
}
