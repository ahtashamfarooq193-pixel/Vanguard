import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:my_app1/bottombar.dart';
import 'package:my_app1/Dashboard/chat.dart';
import 'package:my_app1/Dashboard/location.dart';
import 'package:my_app1/Dashboard/profile.dart';
import 'package:my_app1/Dashboard/notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:my_app1/services/fcm_service.dart';
import 'package:my_app1/services/agora_service.dart';
import 'package:my_app1/Dashboard/call_screen.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  late final FirebaseDatabase _db;
  String _currentUserName = 'Vanguard User';
  StreamSubscription<Position>? _positionStreamSubscription;
  String? _activeAlertId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initUser();
    // Init presence system
    PresenceService.init();
    _db = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: 'https://emergency-alert-9cff6-default-rtdb.asia-southeast1.firebasedatabase.app',
    );
    
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      PresenceService.setOnline(uid);
    }
  }


  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final uid = _auth.currentUser?.uid;
      if (uid != null) PresenceService.setOnline(uid);
    }
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _initUser() async {
    final user = _auth.currentUser;
    if (user == null) return;

    setState(() => _currentUserName = user.displayName ?? user.email?.split('@').first ?? 'Vanguard User');

    // Perform Firestore updates in the background with a timeout
    try {
      await Future.delayed(const Duration(seconds: 1)); // Small delay
      
      final fcmToken = await FirebaseMessaging.instance.getToken().timeout(const Duration(seconds: 4));
      
      await _firestore.collection('users').doc(user.uid).set({
        'displayName': _currentUserName,
        'email': user.email,
        'photoUrl': user.photoURL,
        'fcmToken': fcmToken,
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 4));
      
      debugPrint('✅ Background Profile & FCM Token update successful');
    } catch (e) {
      debugPrint('⚠️ Background Init Task timed out or failed (likely Firestore setup): $e');
    }
  }

  // ── GET SAFE LOCATION ──
  Future<Position?> _getSafePosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location services are disabled. Enable GPS to send precise alerts.')),
          );
        }
        return null;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission denied. Sending alert without live location.'), backgroundColor: Colors.orange),
          );
        }
        return null;
      }

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );
    } catch (e) {
      debugPrint('Location error for alert: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not get GPS. Alert will be sent without live location.'), backgroundColor: Colors.orange),
        );
      }
      return null;
    }
  }

  // ── SEND EMERGENCY ALERT (HOME QUICK BUTTONS) ──
  Future<void> _sendEmergencyAlert(String alertType) async {
    // Confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
          const SizedBox(width: 10),
          Expanded(child: Text('$alertType Alert', style: const TextStyle(fontWeight: FontWeight.bold))),
        ]),
        content: Text('Are you sure you want to send a $alertType alert to all your emergency network?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('Send Alert', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Show sending indicator
    if (mounted) {
      showGeneralDialog(
        context: context,
        barrierDismissible: false,
        pageBuilder: (_, __, ___) => const Center(child: CircularProgressIndicator()),
      );
    }

    try {
      final user = _auth.currentUser;
      if (user == null) throw 'User session expired. Please log in again.';

      // 1) Resolve current location (best-effort)
      final position = await _getSafePosition();
      final locationData = position != null
          ? {
              'lat': position.latitude,
              'lng': position.longitude,
            }
          : null;

      // 2) Load emergency contacts (for SMS + Push)
      final contactsSnapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('contacts')
          .get();

      if (contactsSnapshot.docs.isEmpty) {
        if (mounted) {
          Navigator.pop(context); // Close loading
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No emergency contacts found. Please add them first.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // 3) Create alert document in Firestore (for in-app tracking)
      final alertRef = await _firestore.collection('alerts').add({
        'senderId': user.uid,
        'senderName': _currentUserName,
        'alertType': alertType,
        'location': locationData,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'active',
      });
      _activeAlertId = alertRef.id;

      // 4) Prepare SMS data
      String mapsUrl = position != null 
        ? 'https://www.google.com/maps/search/?api=1&query=${position.latitude},${position.longitude}'
        : 'Unknown Location';
      
      final smsMessage = 'VANGUARD EMERGENCY ($alertType)! I need help. My location: $mapsUrl';
      
      // 5) Collect Contact Info (Numbers for SMS, UIDs for Push)
      final receiverUids = <String>[];
      final phoneNumbers = <String>[];
      
      for (final doc in contactsSnapshot.docs) {
        final data = doc.data();
        final uid = data['uid'];
        final contact = data['contact']?.toString() ?? "";
        
        if (uid != null && uid.toString().isNotEmpty) receiverUids.add(uid.toString());
        if (contact.isNotEmpty && contact.contains(RegExp(r'[0-9]'))) phoneNumbers.add(contact);
      }

      // 6) Fire app push notifications
      if (receiverUids.isNotEmpty) {
        await FcmService.sendEmergencyAlert(
          receiverUids: receiverUids,
          senderName: _currentUserName,
          alertType: alertType,
          senderId: user.uid,
        ).catchError((e) => debugPrint('Push error: $e'));
      }

    // 7) Automated Chat Posting (Direct share like WhatsApp but inside Vanguard)
    if (receiverUids.isNotEmpty) {
      for (String rUid in receiverUids) {
        try {
          // Build Chat ID (same logic as chat.dart)
          final ids = [user.uid, rUid]..sort();
          final chatId = ids.join('_');
          
          final autoMsg = {
            'text': '🚨 $alertType ALERT: I need help!',
            'senderId': user.uid,
            'senderName': _currentUserName,
            'timestamp': ServerValue.timestamp,
            'status': 'sent',
            'isLocation': true,
            'lat': position?.latitude,
            'lng': position?.longitude,
            'alertType': alertType,
          };

          // Post to Realtime Database
          await _db.ref('chats/$chatId/messages').push().set(autoMsg);
          await _db.ref('chats/$chatId/lastMessage').set(autoMsg);
          // Increment unread count for friend
          await _db.ref('chats/$chatId/unreadCount/$rUid').set(ServerValue.increment(1));
          
          debugPrint('Auto-shared alert to chat: $chatId');
        } catch (e) {
          debugPrint('Failed to auto-share to chat for $rUid: $e');
        }
      }
    }

      // 8) Start Real-time Tracking (Update Firestore every few seconds)
      _startRealTimeTracking(alertRef.id);

      if (mounted) Navigator.pop(context); // Close loading
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text('$alertType Alert triggered! Live tracking started.'),
              ),
            ]),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );

        // Move to Map Screen
        Navigator.push(context, MaterialPageRoute(builder: (_) => const Location()));
      }
    } catch (e) {
      if (mounted) Navigator.pop(context); // Close loading
      
      String errorMsg = e.toString();
      if (errorMsg.contains('NOT_FOUND') || errorMsg.contains('database (default) does not exist')) {
        errorMsg = "Firebase Error: Firestore Database not found! Please create it in Firebase Console (Firestore > Create Database).";
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
            action: SnackBarAction(label: 'OK', textColor: Colors.white, onPressed: () {}),
          ),
        );
      }
      debugPrint('❌ Emergency Alert Error: $e');
    }
  }

  void _startRealTimeTracking(String alertId) {
    _positionStreamSubscription?.cancel();
    
    // Configure settings for high accuracy and frequent updates
    const LocationSettings settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // Update every 10 meters
    );

    _positionStreamSubscription = Geolocator.getPositionStream(locationSettings: settings).listen(
      (Position position) {
        if (_activeAlertId == alertId) {
          _firestore.collection('alerts').doc(alertId).update({
            'location': {
              'lat': position.latitude,
              'lng': position.longitude,
            },
            'lastUpdate': FieldValue.serverTimestamp(),
          }).catchError((e) => debugPrint('Live update error: $e'));
        }
      },
      onError: (e) => debugPrint('Position stream error: $e'),
    );
    
    // Auto-stop tracking after 1 hour (safety measure)
    Timer(const Duration(hours: 1), () {
      _positionStreamSubscription?.cancel();
      if (_activeAlertId == alertId) {
         _firestore.collection('alerts').doc(alertId).update({'status': 'ended'});
      }
    });
  }

  // ── ADD CONTACT DIALOG ──
  void _addContact() {
    final searchCtrl = TextEditingController();
    bool searching = false;
    Map<String, dynamic>? foundUser;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Add Vanguard User', style: TextStyle(fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Search by exact Email to add to your safety network.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 15),
                TextField(
                  controller: searchCtrl,
                  decoration: InputDecoration(
                    labelText: 'User Email',
                    hintText: 'example@mail.com',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    suffixIcon: searching ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))) : IconButton(
                      icon: const Icon(Icons.arrow_circle_right, color: Color(0xff38B6FF)),
                      onPressed: () async {
                        final email = searchCtrl.text.trim().toLowerCase();
                        if (email.isEmpty) return;
                        setDialogState(() => searching = true);
                        try {
                          final snap = await _firestore.collection('users').where('email', isEqualTo: email).get();
                          if (snap.docs.isNotEmpty) {
                            setDialogState(() {
                              foundUser = snap.docs.first.data();
                              foundUser!['uid'] = snap.docs.first.id;
                              searching = false;
                            });
                          } else {
                            setDialogState(() { foundUser = null; searching = false; });
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User not found. Make sure they signed up!')));
                          }
                        } catch (e) {
                          setDialogState(() => searching = false);
                          debugPrint('Search error: $e');
                        }
                      },
                    ),
                  ),
                  enabled: !searching,
                ),
                if (foundUser != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xff38B6FF).withOpacity(0.1), borderRadius: BorderRadius.circular(15)),
                    child: Row(children: [
                      CircleAvatar(backgroundColor: const Color(0xff250D57), child: Text(foundUser!['name']?[0]?.toUpperCase() ?? 'U', style: const TextStyle(color: Colors.white))),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(foundUser!['name'] ?? 'Vanguard User', style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text(foundUser!['email'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ])),
                      IconButton(
                        icon: const Icon(Icons.add_task, color: Colors.green),
                        onPressed: () async {
                          final myUser = _auth.currentUser;
                          if (myUser == null || foundUser == null) return;
                          
                          setDialogState(() => searching = true);
                          try {
                            // 1. Get my own data for the reverse link
                            final myDoc = await _firestore.collection('users').doc(myUser.uid).get();
                            final myName = myDoc.data()?['name'] ?? 'Vanguard User';

                            // 2. Add them to my contacts (using their UID as doc ID)
                            await _firestore.collection('users').doc(myUser.uid).collection('contacts').doc(foundUser!['uid']).set({
                              'name': foundUser!['name'],
                              'contact': foundUser!['email'],
                              'uid': foundUser!['uid'],
                              'addedAt': FieldValue.serverTimestamp(),
                            });

                            // 3. Add me to their contacts (Bidirectional for Chat)
                            await _firestore.collection('users').doc(foundUser!['uid']).collection('contacts').doc(myUser.uid).set({
                              'name': myName,
                              'contact': myUser.email,
                              'uid': myUser.uid,
                              'addedAt': FieldValue.serverTimestamp(),
                            });

                            if (mounted) {
                              Navigator.pop(dialogCtx);
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contact linked bi-directionally for safety & chat!'), backgroundColor: Colors.green));
                            }
                          } catch (e) {
                            setDialogState(() => searching = false);
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                          }
                        },
                      )
                    ]),
                  )
                ]
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Close')),
            ],
          );
        },
      ),
    );
  }

  // ── DELETE CONTACT ──
  Future<void> _removeContact(String docId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Remove Contact?'),
        content: Text('Are you sure you want to remove $name from emergency contacts?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await _firestore.collection('users').doc(user.uid).collection('contacts').doc(docId).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$name removed'), backgroundColor: Colors.orange, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e'), backgroundColor: Colors.red));
    }
  }

  // ── BUILD ──
  @override
  Widget build(BuildContext context) {
    final uid = _auth.currentUser?.uid ?? 'none';

    return Scaffold(
      backgroundColor: const Color(0xffF5F7FB),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white, elevation: 0,
        title: Row(children: [
          Image.asset('assets/Images/logo.png', height: 40, errorBuilder: (c, e, s) => const Icon(Icons.security, color: Color(0xff250D57))),
          const SizedBox(width: 12),
          const Text('Vanguard', style: TextStyle(color: Color(0xff250D57), fontSize: 20, fontWeight: FontWeight.bold)),
          const Spacer(),
          IconButton(icon: const Icon(Icons.notifications_none_rounded, color: Colors.black87), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()))),
        ]),
      ),
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hello, $_currentUserName', style: const TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500)),
              const Text('Are you safe?', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xff2D3142))),
              const SizedBox(height: 25),

              // ── CONTACTS HEADER ──
              StreamBuilder<QuerySnapshot>(
                stream: _firestore.collection('users').doc(uid).collection('contacts').snapshots(),
                builder: (context, snapshot) {
                  final docs = snapshot.data?.docs ?? [];
                  final atLimit = docs.length >= 10;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Emergency Contacts (${docs.length}/10)',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.add_circle_outline,
                          color: atLimit ? Colors.grey : const Color(0xff38B6FF),
                          size: 28,
                        ),
                        onPressed: atLimit
                            ? () => ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Maximum 10 emergency contacts allowed.'),
                                    backgroundColor: Colors.orange,
                                  ),
                                )
                            : _addContact,
                      ),
                    ],
                  );
                },
              ),

              // ── CONTACTS LIST — HORIZONTAL SCROLL ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                child: StreamBuilder<QuerySnapshot>(
                  stream: _firestore.collection('users').doc(uid).collection('contacts').snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    if (snapshot.hasError) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            'Firestore error. Please check setup.',
                            style: TextStyle(color: Colors.red, fontSize: 12),
                          ),
                        ),
                      );
                    }

                    // Limit to max 10 contacts
                    final allDocs = snapshot.data?.docs ?? [];
                    final docs = allDocs.take(10).toList();

                    if (docs.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.people_outline, size: 40, color: Colors.grey),
                            SizedBox(height: 10),
                            Text(
                              'No contacts added yet.\nTap + to add.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey),
                            ),
                          ]),
                        ),
                      );
                    }

                    // ── HORIZONTAL SCROLL ROW ──
                    return SizedBox(
                      height: 100,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final d = doc.data() as Map<String, dynamic>;
                          final contactUid = d['uid'] ?? doc.id;
                          final nameFromDoc = d['name'] ?? 'Unknown';

                          return StreamBuilder<DocumentSnapshot>(
                            stream: _firestore
                                .collection('users')
                                .doc(contactUid)
                                .snapshots(),
                            builder: (context, userSnap) {
                              String? pUrl;
                              String name = nameFromDoc;
                              if (userSnap.hasData && userSnap.data!.exists) {
                                final uData = userSnap.data!.data()
                                    as Map<String, dynamic>;
                                pUrl = uData['photoUrl'];
                                name = uData['name'] ?? name;
                              }
                              final firstName = name.split(' ').first;

                              return GestureDetector(
                                onLongPress: () => _removeContact(doc.id, name),
                                child: Container(
                                  width: 72,
                                  margin: const EdgeInsets.symmetric(horizontal: 6),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Stack(
                                        children: [
                                          CircleAvatar(
                                            radius: 28,
                                            backgroundColor:
                                                const Color(0xffF1F2F6),
                                            backgroundImage: pUrl != null
                                                ? NetworkImage(pUrl)
                                                : null,
                                            child: pUrl == null
                                                ? Text(
                                                    name[0].toUpperCase(),
                                                    style: const TextStyle(
                                                      color: Color(0xff250D57),
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 18,
                                                    ),
                                                  )
                                                : null,
                                          ),
                                          // Delete badge
                                          Positioned(
                                            top: 0,
                                            right: 0,
                                            child: GestureDetector(
                                              onTap: () =>
                                                  _removeContact(doc.id, name),
                                              child: Container(
                                                height: 18,
                                                width: 18,
                                                decoration: const BoxDecoration(
                                                  color: Colors.redAccent,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(
                                                  Icons.close,
                                                  color: Colors.white,
                                                  size: 12,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        firstName,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xff2D3142),
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 30),
              const Text('Quick Emergency Alerts', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 15),

              GridView.count(
                shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2, crossAxisSpacing: 15, mainAxisSpacing: 15, childAspectRatio: 1.1,
                children: [
                  _alertBtn(Colors.orange, Icons.car_crash_rounded, 'Accident', () => _sendEmergencyAlert('ACCIDENT')),
                  _alertBtn(Colors.redAccent, Icons.person_off_rounded, 'Kidnap', () => _sendEmergencyAlert('KIDNAPPING')),
                  _alertBtn(Colors.green, Icons.security_rounded, 'Robbery', () => _sendEmergencyAlert('ROBBERY')),
                  _alertBtn(const Color(0xff38B6FF), Icons.campaign_rounded, 'Shout', () => _sendEmergencyAlert('SHOUT')),
                ],
              ),

              const SizedBox(height: 30),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xff250D57), Color(0xff4A148C)]), borderRadius: BorderRadius.circular(20)),
                child: const Row(children: [
                  Icon(Icons.shield_outlined, color: Colors.white, size: 30),
                  SizedBox(width: 15),
                  Expanded(child: Text('Alerts are delivered instantly to your emergency network. Stay safe with Vanguard.', style: TextStyle(color: Colors.white, fontSize: 13, height: 1.4))),
                ]),
              ),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
      bottomNavigationBar: MyBottomBar(
        selectedIndex: _selectedIndex,
        onTap: (i) {
          if (i == _selectedIndex) return;
          Widget next;
          if (i == 0) return;
          else if (i == 1) next = const ChatSelectionScreen();
          else if (i == 2) next = const Location();
          else next = const Profile();
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => next));
        },
      ),
    );
  }

  Widget _alertBtn(Color color, IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: Colors.white, borderRadius: BorderRadius.circular(20),
      elevation: 2,
      shadowColor: color.withOpacity(0.2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: color.withOpacity(0.1),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 30),
          ),
          const SizedBox(height: 12),
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ]),
      ),
    );
  }
}