import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationService {
  static const String _projectId = "chatbot-3bf73";
  static const String _clientEmail = "firebase-adminsdk-fbsvc@chatbot-3bf73.iam.gserviceaccount.com";
  static const String _privateKey = """-----BEGIN PRIVATE KEY-----
MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQCdhz6Wl49RwnEU
qHJZLuMQN87VAu0Sz8Zl3sPk1+C1vGuCGc+VcBbMD94aKsAC916WHE4CBacEBkJe
7HblY7/oDzH0M0bLbvaizIPZnZfwdJIRKUE6DPAcxosUDNysUrDCPV/G+P48hL+N
b66cNEdHj4AMRvrmU5ly6rGN1fnLrhoEuLkLisFxUqR+jbZYNViCQWaJBAjOyTEZ
AACQLkpqDx7LE0qoQqGHJOVm4EK9X3JKyEEW6WRbuy2t7NUen6vRQALB9aIcrrwt
2oytYBnSDTu6aSxj+5mHvREbgF9o9q6W2SXEpZQS7FgN1ZbBiDIoFwNAeSQEJoTK
nwOGU/5HAgMBAAECggEAQTdIlhfQ4cxZ/G9wR7O9lW1FV7KKa4tRW8NJ3mfxQ8vp
xkbhRcDN71VyYero61F1+zdkpDmq12Ov/pRu9LDDNlN0HuFLodUijmuU+nbf/FCG
nWEx4EIxiq8cWtQpOIZlqTEAUcs+KkYtzsh5Wb5zFFb83B94q6Uga8xRuxYWckNGw
muYiBNPiujrF7wA2we8Gq4DX/MIWfgFTTR8gheAHWjkKn6imBeH5AGactAZU87rd
ntVeweMW0P9VkTRYEeWWi+BiX77+R0vPlIG4515s3hfywEfFRt1sMb4TbZog592QZ
9ZUBjWI8bPU+846sg3nAFksQpAJ5MRYBBFzkiFvzgQKBgQDWUXKOLgj2ho1exeUK
PzuUvHSlPy2RxD4JEpuJxHnHdcnAemVm9qljRPvM9B94Bf5bR6g8mSidrBYYxqep
gFwbs5W1XAchOyIP0xAR+aF88KOTNs+UFs7gjQ6mwmbkBWEk+V+j/VEV/d5V4agn
1BnqNp6rD7NRR3JMs9P68hEPdwKBgQC8KlKJuCACQ4Y0dO42jPAsN46ZiBdsz/h7
G8TXEIpOGE9v+LX86zrTIDwRquviImC8lPHXub3I76OIcbi4STZs7K5XIdnOanWJ
en/00OigkVx3k40uZIeHxybvFyGNz3eiNOcnZzRlLjZkhORnK5HMwT6cNZMDDN/U
DU1O9H9bsQKBgQCDixA15lmH/sQMlIhlRrRqMVWjC2kL3Bh7dxlScO6SF2DSrA1L
KkCDdpbakEg0YfFh01SWhSchx7r0UBIefnOKaSqNW0PhCKt6bQCjF8Yfqo+rzuuP
qIQn3UxN3GpMsGSUzh7+x3+acOyjZ9LPR2b0k7vFoOheDe1A2OtWTndcNwKBgQCh
UT915q86gZ17N4xKpEX8Ap10ryI2HY6QLNxy7TFFhr4D5xxO+3RxML+O/hRAyOxa
gO9d3VYCAMEY5zZQeCP6+mb1OIY82zRtauJshvYJQtYdhhiR34n6NBkC/be8llOg
cu6B748R966WOwB+GvJisoH09lFVWiJC8CyJNkBB4QKBgDlplVX3cNkOb8Tz4EvQ
caXZaYZAwBqCNqXmcLsW4miEAgx256RKYzJCxvT7axWPBV5v9v668DQ4yTkYycyd
68I0eeFp1H7KSVziWednqWqRPCP7zkbOid4gFwtbktU6bAF9G+6K1yN7SED/R2wS
eBVuTMcD6ZFfSk35qQGuI5JC
-----END PRIVATE KEY-----""";

  static const List<String> _scopes = [
    'https://www.googleapis.com/auth/firebase.messaging',
  ];

  static Future<String?> getAccessToken() async {
    try {
      final accountCredentials = ServiceAccountCredentials.fromJson({
        "private_key": _privateKey,
        "client_email": _clientEmail,
        "project_id": _projectId,
        "type": "service_account",
      });

      final client = await clientViaServiceAccount(accountCredentials, _scopes);
      final accessToken = client.credentials.accessToken.data;
      client.close();
      return accessToken;
    } catch (e) {
      print("Error getting FCM access token: $e");
      return null;
    }
  }

  static Future<void> sendPushNotification({
    required String recipientUid,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      // 1. Get recipient token
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(recipientUid).get();
      if (!userDoc.exists) return;
      
      final fcmToken = userDoc.data()?['fcmToken'];
      if (fcmToken == null) {
        print("Recipient has no FCM token");
        return;
      }

      // 2. Get Access Token
      final accessToken = await getAccessToken();
      if (accessToken == null) return;

      // 3. Send Notification
      final url = 'https://fcm.googleapis.com/v1/projects/$_projectId/messages:send';
      
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({
          'message': {
            'token': fcmToken,
            'notification': {
              'title': title,
              'body': body,
            },
            'data': data ?? {},
            'android': {
              'priority': 'high',
              'notification': {
                'channel_id': 'high_importance_channel',
                'sound': 'default',
              },
            },
            'apns': {
              'payload': {
                'aps': {
                  'sound': 'default',
                },
              },
            },
          },
        }),
      );

      if (response.statusCode == 200) {
        print("Notification sent successfully");
      } else {
        print("Failed to send notification: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      print("Error sending push notification: $e");
    }
  }
}
