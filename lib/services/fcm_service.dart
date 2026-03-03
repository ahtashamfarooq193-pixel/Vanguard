import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// Sends FCM push notifications directly via FCM v1 HTTP API
/// using a Firebase service account JSON file stored in assets.
/// This works WITHOUT Firebase Cloud Functions (no Blaze plan required).
class FcmService {
  static const _scopes = ['https://www.googleapis.com/auth/firebase.messaging'];
  static const _projectId = 'emergency-alert-9cff6';

  // Cache the access token to avoid re-generating on every message
  static String? _cachedToken;
  static DateTime? _tokenExpiry;

  /// Gets a valid OAuth2 access token using the service account key.
  static Future<String?> _getAccessToken() async {
    try {
      // Return cached token if still valid (with 5 min buffer)
      if (_cachedToken != null &&
          _tokenExpiry != null &&
          DateTime.now().isBefore(_tokenExpiry!.subtract(const Duration(minutes: 5)))) {
        return _cachedToken;
      }

      // Load service account JSON from assets
      final jsonStr = await rootBundle.loadString('assets/Images/emergency.json');
      final jsonMap = jsonDecode(jsonStr) as Map<String, dynamic>;

      final credentials = ServiceAccountCredentials.fromJson(jsonMap);
      final client = await clientViaServiceAccount(credentials, _scopes);

      _cachedToken = client.credentials.accessToken.data;
      _tokenExpiry = client.credentials.accessToken.expiry;
      client.close();

      debugPrint('✅ FCM access token obtained successfully');
      return _cachedToken;
    } catch (e) {
      debugPrint('❌ FCM auth error: $e');
      debugPrint('Make sure assets/service_account.json exists!');
      return null;
    }
  }

  /// Sends a push notification to a specific user.
  /// [receiverUid] — Firebase UID of the person to notify
  /// [title]       — Notification title (e.g. sender's name)
  /// [body]        — Notification body (e.g. message text)
  /// [data]        — Optional extra data payload
  static Future<void> sendNotification({
    required String receiverUid,
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    try {
      // 1. Fetch receiver's FCM token from Firestore
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(receiverUid)
          .get();

      if (!userDoc.exists) {
        debugPrint('FCM: User $receiverUid not found in Firestore');
        return;
      }

      final token = userDoc.data()?['fcmToken'] as String?;
      if (token == null || token.isEmpty) {
        debugPrint('FCM: No FCM token stored for user $receiverUid');
        return;
      }

      // 2. Get OAuth2 access token
      final accessToken = await _getAccessToken();
      if (accessToken == null) return;

      // 3. Call FCM v1 API
      const url =
          'https://fcm.googleapis.com/v1/projects/$_projectId/messages:send';

      final payload = {
        'message': {
          'token': token,
          'notification': {
            'title': title,
            'body': body,
          },
          'data': {
            'type': 'chat_message',
            'receiverUid': receiverUid,
            ...?data,
          },
          'android': {
            'priority': 'high', // Correct high priority for delivery
            'notification': {
              'channel_id': 'vanguard_alerts',
              'sound': 'default',
              'notification_priority': 'PRIORITY_MAX', // Max priority for device display
              'default_sound': true,
              'default_vibrate_timings': true,
              'notification_count': 1,
            },
            'ttl': '60s',
          },
          'apns': {
            'payload': {
              'aps': {
                'sound': 'default',
                'badge': 1,
              }
            }
          },
        }
      };

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        debugPrint('✅ FCM notification sent to $receiverUid');
      } else {
        debugPrint('❌ FCM error ${response.statusCode}: ${response.body}');
        // If token is stale/invalid, clear cache so next call refreshes
        if (response.statusCode == 401) {
          _cachedToken = null;
          _tokenExpiry = null;
        }
      }
    } catch (e) {
      debugPrint('FCM sendNotification error: $e');
    }
  }

  /// Sends an emergency alert notification to multiple users.
  /// [receiverUids] — List of Firebase UIDs to notify
  static Future<void> sendEmergencyAlert({
    required List<String> receiverUids,
    required String senderName,
    required String alertType,
    required String senderId,
  }) async {
    for (final uid in receiverUids) {
      await sendNotification(
        receiverUid: uid,
        title: '🚨 $alertType ALERT from $senderName',
        body: '$senderName has triggered an emergency alert! Check their location immediately.',
        data: {'type': 'emergency_alert', 'senderId': senderId},
      );
    }
  }
}
