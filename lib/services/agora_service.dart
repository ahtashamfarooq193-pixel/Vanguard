// ════════════════════════════════════════════════════════════════
//  AGORA SERVICE  — handles call signaling via Firebase RTDB
// ════════════════════════════════════════════════════════════════
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:my_app1/services/fcm_service.dart';

class AgoraService {
  // ── REPLACE WITH YOUR AGORA APP ID ──
  static const String appId = 'aa83f01259d146d7b6766fd0242aa6d6';

  // For testing without a token server, use '' (empty string).
  // For production, generate a token from your backend.
  static const String token = '';

  static late FirebaseDatabase _db;

  static void init() {
    _db = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          'https://emergency-alert-9cff6-default-rtdb.asia-southeast1.firebasedatabase.app',
    );
  }

  // ── Send call invite to receiver ──
  static Future<void> sendCallInvite({
    required String callId,
    required String callerId,
    required String callerName,
    required String callerPhoto,
    required String receiverId,
    required bool isVideo,
  }) async {
    await _db.ref('calls/$receiverId').set({
      'callId': callId,
      'callerId': callerId,
      'callerName': callerName,
      'callerPhoto': callerPhoto,
      'isVideo': isVideo,
      'status': 'ringing',
      'timestamp': ServerValue.timestamp,
    });

    // 🔔 Send High-Priority Push Notification to wake up/notify the receiver
    await FcmService.sendNotification(
      receiverUid: receiverId,
      title: isVideo ? 'Video Call' : 'Voice Call',
      body: '$callerName is calling you...',
      data: {
        'type': 'incoming_call',
        'callId': callId,
        'callerId': callerId,
        'callerName': callerName,
        'callerPhoto': callerPhoto,
        'isVideo': isVideo.toString(),
      },
    );
  }

  // ── Cancel / end call invite ──
  static Future<void> endCall(String receiverId) async {
    await _db.ref('calls/$receiverId').remove();
  }

  // ── Accept call ──
  static Future<void> acceptCall(String receiverId) async {
    await _db.ref('calls/$receiverId/status').set('accepted');
  }

  // ── Reject call ──
  static Future<void> rejectCall(String receiverId) async {
    await _db.ref('calls/$receiverId/status').set('rejected');
  }

  // ── Watch incoming calls for this user ──
  static Stream<DatabaseEvent> watchIncomingCall(String myUid) {
    return _db.ref('calls/$myUid').onValue;
  }
}
