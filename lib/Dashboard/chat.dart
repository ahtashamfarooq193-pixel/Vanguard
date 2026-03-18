import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:video_player/video_player.dart';
import 'package:image_picker/image_picker.dart';
import 'package:my_app1/services/cloudinary_service.dart';
import 'package:my_app1/services/fcm_service.dart';
import 'package:my_app1/services/agora_service.dart';
import 'package:my_app1/Dashboard/call_screen.dart';
import 'package:my_app1/bottombar.dart';
import 'package:my_app1/Dashboard/homepage.dart';
import 'package:my_app1/Dashboard/location.dart';
import 'package:my_app1/Dashboard/profile.dart';
import 'package:intl/intl.dart';

// ════════════════════════════════════════════════════════════════
//  DATA MODEL
// ════════════════════════════════════════════════════════════════
enum MessageStatus { sent, delivered, seen }

class ChatMessage {
  final String id;
  final String text;
  final String senderId;
  final String senderName;
  final int timestamp;
  final bool isMe;
  final String? imageUrl;
  final bool isLocation;
  final double? lat;
  final double? lng;
  final String? alertType;
  MessageStatus status;

  ChatMessage({
    required this.id,
    required this.text,
    required this.senderId,
    required this.senderName,
    required this.timestamp,
    required this.isMe,
    this.imageUrl,
    this.isLocation = false,
    this.lat,
    this.lng,
    this.alertType,
    this.status = MessageStatus.sent,
  });

  bool get isImage => imageUrl != null && imageUrl!.isNotEmpty;

  factory ChatMessage.fromMap(String id, Map<dynamic, dynamic> map, String myId) {
    MessageStatus s = MessageStatus.sent;
    final raw = map['status'];
    if (raw == 'delivered') s = MessageStatus.delivered;
    if (raw == 'seen') s = MessageStatus.seen;
    return ChatMessage(
      id: id,
      text: (map['text'] ?? '').toString(),
      senderId: (map['senderId'] ?? '').toString(),
      senderName: (map['senderName'] ?? '').toString(),
      timestamp: (map['timestamp'] is int) ? map['timestamp'] : 0,
      isMe: map['senderId'] == myId,
      imageUrl: (map['imageUrl'] ?? '').toString().isEmpty ? null : map['imageUrl'].toString(),
      isLocation: map['isLocation'] == true,
      lat: map['lat'] != null ? double.tryParse(map['lat'].toString()) : null,
      lng: map['lng'] != null ? double.tryParse(map['lng'].toString()) : null,
      alertType: map['alertType']?.toString(),
      status: s,
    );
  }

  String get formattedTime {
    if (timestamp == 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return DateFormat('hh:mm a').format(dt);
  }
}

// ════════════════════════════════════════════════════════════════
//  PRESENCE SERVICE
// ════════════════════════════════════════════════════════════════
class PresenceService {
  static late FirebaseDatabase _db;

  static void init() {
    _db = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: 'https://emergency-alert-9cff6-default-rtdb.asia-southeast1.firebasedatabase.app',
    );
  }

  static void setOnline(String uid) {
    final ref = _db.ref('presence/$uid');
    ref.set({'online': true, 'lastSeen': ServerValue.timestamp});
    ref.onDisconnect().set({'online': false, 'lastSeen': ServerValue.timestamp});
  }

  static Stream<DatabaseEvent> watchPresence(String uid) {
    return _db.ref('presence/$uid').onValue;
  }

  static String formatLastSeen(int? timestamp) {
    if (timestamp == null || timestamp == 0) return 'Offline';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('MMM d, hh:mm a').format(dt);
  }
}

// ════════════════════════════════════════════════════════════════
//  CHAT SELECTION SCREEN
// ════════════════════════════════════════════════════════════════
class ChatSelectionScreen extends StatefulWidget {
  const ChatSelectionScreen({super.key});
  @override
  State<ChatSelectionScreen> createState() => _ChatSelectionScreenState();
}

class _ChatSelectionScreenState extends State<ChatSelectionScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  late final FirebaseDatabase _db;
  final int _selectedIndex = 1;
  final _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _db = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: 'https://emergency-alert-9cff6-default-rtdb.asia-southeast1.firebasedatabase.app',
    );
    final uid = _auth.currentUser?.uid;
    if (uid != null) PresenceService.setOnline(uid);
  }

  String _buildChatId(String friendId) {
    final myId = _auth.currentUser?.uid ?? '';
    final ids = [myId, friendId]..sort();
    return ids.join('_');
  }

  @override
  Widget build(BuildContext context) {
    final uid = _auth.currentUser?.uid ?? 'none';

    return Scaffold(
      backgroundColor: const Color(0xffF0F2F5),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: const Color(0xff250D57),
        elevation: 0,
        title: const Text('Vanguard Chat', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1, color: Colors.white70),
            tooltip: 'Search & Add User',
            onPressed: _showUserSearchDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            height: 125,
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: const BoxDecoration(
              color: Color(0xff250D57),
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
            ),
            child: StreamBuilder<DocumentSnapshot>(
              stream: _firestore.collection('users').doc(uid).snapshots(),
              builder: (ctx, mySnap) {
                List? myStatuses;
                String? myPhotoUrl;
                String myName = 'Me';
                Map<String, dynamic>? myUserData;

                if (mySnap.hasData && mySnap.data!.exists) {
                  final md = mySnap.data!.data() as Map<String, dynamic>;
                  myStatuses = md['statuses'] as List?;
                  myPhotoUrl = md['photoUrl'];
                  myName = md['displayName'] ?? md['name'] ?? 'Me';
                  myUserData = md;
                }

                return StreamBuilder<QuerySnapshot>(
                  stream: _firestore.collection('users').doc(uid).collection('contacts').snapshots(),
                  builder: (ctx, snap) {
                    final contacts = snap.data?.docs ?? [];
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      scrollDirection: Axis.horizontal,
                      itemCount: contacts.length + 2,
                      itemBuilder: (_, i) {
                        if (i == 0) return _addStory();
                        if (i == 1) return _recentUser(myName, myPhotoUrl, statuses: myStatuses, ownerId: uid, userData: myUserData);

                        final cDoc = contacts[i - 2];
                        return StreamBuilder<DocumentSnapshot>(
                          stream: _firestore.collection('users').doc(cDoc.id).snapshots(),
                          builder: (uCtx, uSnap) {
                            String? pUrl;
                            String name = 'User';
                            List? contactStatuses;
                            Map<String, dynamic>? contactUserData;

                            if (uSnap.hasData && uSnap.data!.exists) {
                              final ud = uSnap.data!.data() as Map<String, dynamic>;
                              pUrl = ud['photoUrl'];
                              name = ud['displayName'] ?? ud['name'] ?? 'User';
                              contactStatuses = ud['statuses'] as List?;
                              contactUserData = ud;
                            }
                            return _recentUser(name, pUrl, statuses: contactStatuses, ownerId: cDoc.id, userData: contactUserData);
                          },
                        );
                      },
                    );
                  }
                );
              }
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(top: 10),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(topLeft: Radius.circular(40), topRight: Radius.circular(40)),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(40), topRight: Radius.circular(40)),
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  children: [
                    _chatTile(
                      title: 'Vanguard AI Assistant', subtitle: 'Ask for safety help', isAi: true,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const Chat(chatType: 'ai', friendId: 'vanguard_ai'))),
                    ),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 30, vertical: 5), child: Divider(thickness: 1, color: Color(0xffF1F2F6))),
                    StreamBuilder<QuerySnapshot>(
                      stream: _firestore.collection('users').doc(uid).collection('contacts').snapshots(),
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()));
                        }
                        final docs = snap.data?.docs ?? [];
                        if (docs.isEmpty) return _emptyState();

                        return Column(
                          children: docs.map((doc) {
                            final d = doc.data() as Map<String, dynamic>;
                            final chatId = _buildChatId(doc.id);

                            return StreamBuilder<DocumentSnapshot>(
                              stream: _firestore.collection('users').doc(doc.id).snapshots(),
                              builder: (context, userSnap) {
                                String photoUrl = '';
                                String name = d['name'] ?? 'User';
                                if (userSnap.hasData && userSnap.data!.exists) {
                                  final uData = userSnap.data!.data() as Map<String, dynamic>;
                                  photoUrl = uData['photoUrl'] ?? '';
                                  name = uData['name'] ?? name;
                                }

                                return StreamBuilder<DatabaseEvent>(
                                  stream: _db.ref('chats/$chatId').onValue,
                                  builder: (context, msgSnap) {
                                    String lastMsg = 'Tap to message';
                                    String time = '';
                                    int unread = 0;

                                    if (msgSnap.hasData && msgSnap.data!.snapshot.value != null) {
                                      final chatData = msgSnap.data!.snapshot.value as Map<dynamic, dynamic>;
                                      
                                      // ── GET LAST MESSAGE ──
                                      if (chatData['lastMessage'] != null) {
                                        final m = chatData['lastMessage'] as Map<dynamic, dynamic>;
                                        lastMsg = (m['text'] ?? '').toString();
                                        if (lastMsg.length > 35) lastMsg = '${lastMsg.substring(0, 35)}...';
                                        if (m['timestamp'] is int && m['timestamp'] > 0) {
                                          time = DateFormat('hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(m['timestamp']));
                                        }
                                      }

                                      // ── GET EXACT UNREAD COUNT ──
                                      final unreadMap = chatData['unreadCount'] as Map<dynamic, dynamic>?;
                                      if (unreadMap != null && unreadMap[uid] != null) {
                                        unread = int.tryParse(unreadMap[uid].toString()) ?? 0;
                                      }
                                    }

                                    return _chatTile(
                                      title: name,
                                      subtitle: lastMsg,
                                      time: time,
                                      unread: unread,
                                      photoUrl: photoUrl.isNotEmpty ? photoUrl : null,
                                      friendId: doc.id,
                                      onTap: () => Navigator.push(context, MaterialPageRoute(
                                        builder: (_) => Chat(chatType: 'friend', friendName: name, friendId: doc.id),
                                      )),
                                    );
                                  },
                                );
                              }
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: MyBottomBar(
        selectedIndex: _selectedIndex,
        onTap: (i) {
          if (i == _selectedIndex) return;
          Widget next;
          if (i == 0) next = const HomePage();
          else if (i == 1) return;
          else if (i == 2) next = const Location();
          else next = const Profile();
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => next));
        },
      ),
    );
  }

  Widget _addStory() => Padding(
    padding: const EdgeInsets.only(right: 20),
    child: InkWell(
      onTap: _pickAndUploadStatus,
      child: Column(children: [
        Container(
          height: 60, width: 60, 
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle), 
          child: _isUploadingStatus ? const Padding(padding: EdgeInsets.all(15), child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.add, color: Colors.white, size: 30)
        ),
        const SizedBox(height: 8),
        const Text('Add Status', style: TextStyle(color: Colors.white70, fontSize: 11)),
      ]),
    ),
  );

  bool _isUploadingStatus = false;
  Future<void> _pickAndUploadStatus() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final source = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xff250D57),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 10),
        ListTile(leading: const Icon(Icons.image, color: Colors.white), title: const Text('Pick Image', style: TextStyle(color: Colors.white)), onTap: () => Navigator.pop(context, 'image')),
        ListTile(leading: const Icon(Icons.video_collection, color: Colors.white), title: const Text('Pick Video (max 3MB)', style: TextStyle(color: Colors.white)), onTap: () => Navigator.pop(context, 'video')),
        const SizedBox(height: 10),
      ]),
    );

    if (source == null) return;

    final picked = (source == 'image')
        ? await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 60)
        : await _imagePicker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: 30));

    if (picked == null) return;

    if (source == 'video') {
      final size = await File(picked.path).length();
      if (size > 3 * 1024 * 1024) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Video must be less than 3MB')));
        return;
      }
    }

    setState(() => _isUploadingStatus = true);
    try {
      final link = await CloudinaryService.uploadFile(File(picked.path));
      if (link != null) {
        // ── APPEND a new status object to the 'statuses' array ──
        // This keeps all previous statuses intact.
        await _firestore.collection('users').doc(user.uid).set({
          'statuses': FieldValue.arrayUnion([
            {
              'url': link,
              'type': source,
              'time': Timestamp.now(),    // client timestamp — server timestamp not supported in arrayUnion
              'viewers': {},
            }
          ]),
        }, SetOptions(merge: true));
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Status added! ✅')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _isUploadingStatus = false);
    }
  }

  // ── Reads the new 'statuses' array and shows the bubble ──
  Widget _recentUser(String name, String? photoUrl, {List? statuses, String? ownerId, Map<String, dynamic>? userData}) {
    final myUid = _auth.currentUser?.uid;
    final bool isMe = ownerId == myUid;

    // Filter to only statuses less than 24h old, and attach actual viewers!
    final now = DateTime.now();
    List<Map<String, dynamic>> activeStatuses = [];
    
    if (statuses != null) {
      for (int i = 0; i < statuses.length; i++) {
        final s = statuses[i] as Map;
        final t = s['time'];
        if (t != null) {
          final dt = (t is Timestamp) ? t.toDate() : DateTime.fromMillisecondsSinceEpoch(t as int);
          if (now.difference(dt).inHours < 24) {
            final sCopy = Map<String, dynamic>.from(s);
            sCopy['_origIndex'] = i;
            sCopy['_viewers'] = userData?['statusViewedBy_$i'] as Map? ?? {};
            activeStatuses.add(sCopy);
          }
        }
      }
    }

    final bool hasActiveStatus = activeStatuses.isNotEmpty;

    // Count how many of the active statuses I have NOT seen
    int unseenCount = 0;
    if (myUid != null) {
      for (final s in activeStatuses) {
        final viewers = s['_viewers'] as Map? ?? {};
        if (!viewers.containsKey(myUid)) unseenCount++;
      }
    }
    final bool isSeen = hasActiveStatus && unseenCount == 0;

    // Total views across all MY active statuses (for the owner badge)
    int totalViews = 0;
    if (isMe) {
      // Find the status with the MOST views and show that count, OR sum them.
      // Usually WhatsApp shows count for the active statuses, maybe we show aggregate
      final Set<String> uniqueViewers = {};
      for (final s in activeStatuses) {
        final viewers = s['_viewers'] as Map? ?? {};
        uniqueViewers.addAll(viewers.keys.cast<String>());
      }
      totalViews = uniqueViewers.length;
    }

    return Padding(
      padding: const EdgeInsets.only(right: 20),
      child: Column(children: [
        GestureDetector(
          onTap: () {
            if (hasActiveStatus) {
              _showMultiStatusView(activeStatuses, ownerId!, isMe);
            } else if (photoUrl != null) {
              _showFullImage(context, photoUrl);
            }
          },
          child: Stack(
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: hasActiveStatus
                        ? (isMe
                            ? Colors.greenAccent
                            : (isSeen ? Colors.grey.withOpacity(0.5) : const Color(0xff38B6FF)))
                        : Colors.transparent,
                    width: 2.5,
                  ),
                  shape: BoxShape.circle,
                ),
                child: CircleAvatar(
                  radius: 28,
                  backgroundColor: const Color(0xff38B6FF).withOpacity(0.1),
                  backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                  child: photoUrl == null ? const Icon(Icons.person, color: Colors.white, size: 20) : null,
                ),
              ),
              // Status count badge for my own bubble
              if (isMe && hasActiveStatus && totalViews > 0)
                Positioned(
                  bottom: 0, right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                    child: Text('$totalViews', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
              // Unseen indicator for other users
              if (!isMe && hasActiveStatus && unseenCount > 0)
                Positioned(
                  top: 0, right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Color(0xff38B6FF), shape: BoxShape.circle),
                    child: Text('$unseenCount', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isMe ? 'My Status' : name.split(' ').first,
          style: TextStyle(
            color: hasActiveStatus ? Colors.white : Colors.white70,
            fontSize: 11,
            fontWeight: hasActiveStatus ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ]),
    );
  }

  // ── Shows all statuses of a single viewer as a bottom sheet ──
  void _showViewersList(List activeStatuses) {
    // Aggregate all unique viewers across all active statuses
    final Map<String, dynamic> allViewers = {};
    for (final s in activeStatuses) {
      final viewers = s['_viewers'] as Map? ?? {};
      viewers.forEach((uid, time) {
        // Keep the latest time they viewed anything
        if (!allViewers.containsKey(uid.toString())) {
          allViewers[uid.toString()] = time;
        } else {
          final existing = allViewers[uid.toString()];
          if (time is Timestamp && existing is Timestamp && time.compareTo(existing) > 0) {
            allViewers[uid.toString()] = time;
          }
        }
      });
    }

    if (allViewers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No views yet.')));
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xff250D57),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20))),
      builder: (_) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(15.0),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Viewers (${allViewers.length})', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              Text('${activeStatuses.length} status${activeStatuses.length > 1 ? "es" : ""}', style: const TextStyle(color: Colors.white60, fontSize: 13)),
            ]),
          ),
          const Divider(color: Colors.white24),
          Expanded(
            child: ListView(
              children: allViewers.keys.map((uid) => StreamBuilder<DocumentSnapshot>(
                stream: _firestore.collection('users').doc(uid).snapshots(),
                builder: (_, snap) {
                  final data = snap.data?.data() as Map<String, dynamic>?;
                  final name = data?['name'] ?? 'Unknown';
                  final photo = data?['photoUrl'];
                  final timeRaw = allViewers[uid];
                  String timeStr = 'Recently';
                  if (timeRaw is Timestamp) timeStr = DateFormat('hh:mm a').format(timeRaw.toDate());
                  return ListTile(
                    leading: CircleAvatar(backgroundImage: photo != null ? NetworkImage(photo) : null, child: photo == null ? const Icon(Icons.person) : null),
                    title: Text(name, style: const TextStyle(color: Colors.white)),
                    trailing: Text(timeStr, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                  );
                },
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ── NEW: Cycles through ALL statuses of a user like WhatsApp ──
  void _showMultiStatusView(List activeStatuses, String ownerId, bool isMe) {
    final curUid = _auth.currentUser?.uid;
    if (curUid == null) return;

    showDialog(
      context: context,
      builder: (_) => _MultiStatusPlayerDialog(
        statuses: activeStatuses,
        ownerId: ownerId,
        curUid: curUid,
        isMe: isMe,
        firestore: _firestore,
      ),
    );
  }

  void _showFullImage(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(borderRadius: BorderRadius.circular(15), child: Image.network(url, fit: BoxFit.contain)),
          const SizedBox(height: 10),
          IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 30), onPressed: () => Navigator.pop(context)),
        ]),
      ),
    );
  }

  Widget _chatTile({
    required String title,
    required String subtitle,
    bool isAi = false,
    String? time,
    int unread = 0,
    String? photoUrl,
    String? friendId,
    required VoidCallback onTap,
  }) {
    // For non-AI tiles, watch real-time presence from Firebase
    if (!isAi && friendId != null) {
      return StreamBuilder<DatabaseEvent>(
        stream: _db.ref('presence/$friendId').onValue,
        builder: (context, presSnap) {
          bool isOnline = false;
          if (presSnap.hasData && presSnap.data!.snapshot.value != null) {
            final val = presSnap.data!.snapshot.value;
            if (val is Map) isOnline = val['online'] == true;
          }
          return _buildTileWidget(
            title: title, subtitle: subtitle, isAi: false, time: time,
            unread: unread, photoUrl: photoUrl, isOnline: isOnline, onTap: onTap,
          );
        },
      );
    }
    return _buildTileWidget(
      title: title, subtitle: subtitle, isAi: isAi, time: time,
      unread: unread, photoUrl: photoUrl, isOnline: false, onTap: onTap,
    );
  }

  Widget _buildTileWidget({
    required String title,
    required String subtitle,
    bool isAi = false,
    String? time,
    int unread = 0,
    String? photoUrl,
    bool isOnline = false,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 25, vertical: 8),
      leading: Stack(children: [
        GestureDetector(
          onTap: () { if (photoUrl != null) _showFullImage(context, photoUrl); },
          child: Container(
            height: 60, width: 60,
            decoration: BoxDecoration(
              gradient: isAi ? const LinearGradient(colors: [Color(0xff250D57), Color(0xff38B6FF)]) : null,
              color: isAi ? null : const Color(0xffF0F2F5),
              borderRadius: BorderRadius.circular(20)),
            child: photoUrl != null
              ? ClipRRect(borderRadius: BorderRadius.circular(20), child: Image.network(photoUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(isAi ? Icons.auto_awesome : Icons.person, color: isAi ? Colors.white : const Color(0xff250D57), size: 30)))
              : Icon(isAi ? Icons.auto_awesome : Icons.person, color: isAi ? Colors.white : const Color(0xff250D57), size: 30)),
        ),
        // ✅ Only show green dot when actually online
        if (!isAi)
          Positioned(
            bottom: 2, right: 2,
            child: Container(
              height: 14, width: 14,
              decoration: BoxDecoration(
                color: isOnline ? Colors.green : Colors.grey,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
      ]),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xff250D57))),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: unread > 0 ? const Color(0xff250D57) : Colors.grey, fontSize: 14, fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.normal)),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        if (time != null && time.isNotEmpty) Text(time, style: TextStyle(color: unread > 0 ? const Color(0xff38B6FF) : Colors.grey, fontSize: 12)),
        if (unread > 0)
          Container(margin: const EdgeInsets.only(top: 6), padding: const EdgeInsets.all(6), decoration: const BoxDecoration(color: Color(0xff38B6FF), shape: BoxShape.circle),
            child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
      ]),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  USER SEARCH & ADD CONTACT DIALOG
  // ════════════════════════════════════════════════════════════════
  void _showUserSearchDialog() {
    final searchCtrl = TextEditingController();
    List<Map<String, dynamic>> results = [];
    bool isSearching = false;
    final myUid = _auth.currentUser?.uid ?? '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          Future<void> doSearch(String query) async {
            if (query.trim().isEmpty) {
              setDlgState(() { results = []; isSearching = false; });
              return;
            }
            setDlgState(() => isSearching = true);

            // Search by name (case-insensitive via prefix range trick)
            final q = query.trim().toLowerCase();
            final byName = await _firestore
                .collection('users')
                .get();

            final found = byName.docs
                .where((d) {
                  final data = d.data();
                  final name = (data['name'] ?? data['displayName'] ?? '').toString().toLowerCase();
                  final email = (data['email'] ?? '').toString().toLowerCase();
                  return d.id != myUid && (name.contains(q) || email.contains(q));
                })
                .map((d) {
                  final data = d.data();
                  return {
                    'uid': d.id,
                    'name': data['name'] ?? data['displayName'] ?? 'Unknown',
                    'email': data['email'] ?? '',
                    'photoUrl': data['photoUrl'] ?? '',
                  };
                })
                .toList();

            setDlgState(() { results = found; isSearching = false; });
          }

          Future<void> addContact(Map<String, dynamic> user) async {
            try {
              // Add to my contacts
              await _firestore
                  .collection('users')
                  .doc(myUid)
                  .collection('contacts')
                  .doc(user['uid'])
                  .set({'name': user['name'], 'email': user['email'], 'addedAt': FieldValue.serverTimestamp()});
              // Add me to their contacts too (mutual)
              final myData = await _firestore.collection('users').doc(myUid).get();
              final myName = myData.data()?['name'] ?? myData.data()?['displayName'] ?? 'User';
              final myEmail = myData.data()?['email'] ?? '';
              await _firestore
                  .collection('users')
                  .doc(user['uid'])
                  .collection('contacts')
                  .doc(myUid)
                  .set({'name': myName, 'email': myEmail, 'addedAt': FieldValue.serverTimestamp()});

              if (mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${user['name']} ko add kar diya! ✅'),
                    backgroundColor: const Color(0xff250D57),
                  ),
                );
              }
            } catch (e) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
            }
          }

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 520),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(colors: [Color(0xff250D57), Color(0xff38B6FF)]),
                      borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.person_search, color: Colors.white, size: 26),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text('User Dhundho & Add Karo', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70),
                          onPressed: () => Navigator.pop(ctx),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),
                  // Search field
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: TextField(
                      controller: searchCtrl,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Naam ya email likho...',
                        prefixIcon: const Icon(Icons.search, color: Color(0xff250D57)),
                        suffixIcon: isSearching
                            ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                            : null,
                        filled: true,
                        fillColor: const Color(0xffF0F2F5),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onChanged: (v) => doSearch(v),
                    ),
                  ),
                  // Results
                  Flexible(
                    child: results.isEmpty && !isSearching
                        ? Padding(
                            padding: const EdgeInsets.all(30),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.people_outline, size: 60, color: Colors.grey[300]),
                                const SizedBox(height: 12),
                                Text(
                                  searchCtrl.text.isEmpty ? 'Naam ya email type karo' : 'Koi user nahi mila',
                                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: results.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final u = results[i];
                              return FutureBuilder<DocumentSnapshot>(
                                future: _firestore.collection('users').doc(myUid).collection('contacts').doc(u['uid']).get(),
                                builder: (_, snap) {
                                  final alreadyAdded = snap.data?.exists == true;
                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                    leading: CircleAvatar(
                                      radius: 24,
                                      backgroundColor: const Color(0xff250D57).withOpacity(0.1),
                                      backgroundImage: u['photoUrl'].isNotEmpty ? NetworkImage(u['photoUrl']) : null,
                                      child: u['photoUrl'].isEmpty ? const Icon(Icons.person, color: Color(0xff250D57)) : null,
                                    ),
                                    title: Text(u['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xff250D57))),
                                    subtitle: Text(u['email'], style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                    trailing: alreadyAdded
                                        ? Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: Colors.green.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(20),
                                              border: Border.all(color: Colors.green),
                                            ),
                                            child: const Text('Added ✓', style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                                          )
                                        : ElevatedButton.icon(
                                            icon: const Icon(Icons.person_add, size: 16),
                                            label: const Text('Add', style: TextStyle(fontSize: 13)),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xff250D57),
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                            ),
                                            onPressed: () => addContact(u),
                                          ),
                                  );
                                },
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _emptyState() => Padding(
    padding: const EdgeInsets.only(top: 50),
    child: Column(children: [
      Icon(Icons.chat_bubble_outline, size: 80, color: Colors.grey[300]),
      const SizedBox(height: 20),
      const Text('Upar se user dhundh kar add karo!', style: TextStyle(color: Colors.grey, fontSize: 14)),
    ]),
  );
}

// ════════════════════════════════════════════════════════════════
//  CHAT SCREEN  — INSTANT loading via onChildAdded
// ════════════════════════════════════════════════════════════════
class Chat extends StatefulWidget {
  final String chatType;
  final String? friendName;
  final String friendId;
  const Chat({super.key, required this.chatType, this.friendName, required this.friendId});
  @override
  State<Chat> createState() => _ChatState();
}

class _ChatState extends State<Chat> with WidgetsBindingObserver {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _auth = FirebaseAuth.instance;

  late final FirebaseDatabase _db;
  late final DatabaseReference _msgsRef;
  final _firestore = FirebaseFirestore.instance;

  // Messages stored in a map for O(1) lookup on update/remove
  final Map<String, ChatMessage> _messageMap = {};
  List<ChatMessage> _sortedMessages = [];

  StreamSubscription? _addSub;
  StreamSubscription? _changeSub;
  StreamSubscription? _removeSub;
  StreamSubscription? _typingSub;

  bool _aiTyping = false;
  bool _friendTyping = false;
  bool _friendOnline = false;
  int? _lastSeen;
  bool _isUploadingImage = false;
  late String _chatId;
  late String _myId;
  Timer? _typingTimer;
  final _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _db = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: 'https://emergency-alert-9cff6-default-rtdb.asia-southeast1.firebasedatabase.app',
    );

    _myId = _auth.currentUser?.uid ?? 'guest';
    PresenceService.setOnline(_myId);

    if (widget.chatType == 'ai') {
      _chatId = 'ai_$_myId';
    } else {
      final ids = [_myId, widget.friendId]..sort();
      _chatId = ids.join('_');
    }

    _msgsRef = _db.ref('chats/$_chatId/messages');

    // Keep data synced for instant offline loading
    _msgsRef.keepSynced(true);
    
    // ── CLEAR UNREAD COUNT FOR ME ──
    _db.ref('chats/$_chatId/unreadCount/$_myId').set(0);

    _listenMessages();
    _listenTyping();
    _listenPresence();
  }

  // ══════════════════════════════════════════
  //  INSTANT MESSAGE LOADING — onChildAdded
  //  Messages appear ONE BY ONE as they arrive
  //  from local cache (instant) or network.
  // ══════════════════════════════════════════
  void _listenMessages() {
    // onChildAdded fires ONCE for each existing child + new ones
    _addSub = _msgsRef.orderByChild('timestamp').onChildAdded.listen((event) {
      if (!mounted) return;
      final key = event.snapshot.key;
      final val = event.snapshot.value;
      if (key == null || val == null || val is! Map) return;

      final msg = ChatMessage.fromMap(key, val, _myId);
      _messageMap[key] = msg;
      _rebuildSorted();

      // Auto-mark as seen
      if (!msg.isMe && msg.status != MessageStatus.seen) {
        _msgsRef.child('$key/status').set('seen');
        // Also update lastMessage node so selection screen/notifications know it's seen
        _db.ref('chats/$_chatId/lastMessage/status').set('seen');
      }
    }, onError: (e) => debugPrint('onChildAdded error: $e'));

    // onChildChanged — read receipt updates etc.
    _changeSub = _msgsRef.onChildChanged.listen((event) {
      if (!mounted) return;
      final key = event.snapshot.key;
      final val = event.snapshot.value;
      if (key == null || val == null || val is! Map) return;

      _messageMap[key] = ChatMessage.fromMap(key, val, _myId);
      _rebuildSorted();
    });

    // onChildRemoved — message deleted
    _removeSub = _msgsRef.onChildRemoved.listen((event) {
      if (!mounted) return;
      final key = event.snapshot.key;
      if (key == null) return;
      _messageMap.remove(key);
      _rebuildSorted();
    });
  }

  void _rebuildSorted() {
    final list = _messageMap.values.toList();
    list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    setState(() => _sortedMessages = list);
    _scroll();
  }

  // ── LISTEN TYPING ──
  void _listenTyping() {
    if (widget.chatType == 'ai') return;
    _typingSub = _db.ref('chats/$_chatId/typing/${widget.friendId}').onValue.listen((event) {
      if (!mounted) return;
      setState(() => _friendTyping = event.snapshot.value == true);
    });
  }

  // ── LISTEN PRESENCE ──
  void _listenPresence() {
    if (widget.chatType == 'ai') {
      setState(() => _friendOnline = true);
      return;
    }
    PresenceService.watchPresence(widget.friendId).listen((event) {
      if (!mounted) return;
      final val = event.snapshot.value;
      if (val is Map) {
        setState(() {
          _friendOnline = val['online'] == true;
          _lastSeen = val['lastSeen'] as int?;
        });
      }
    });
  }

  void _setTyping(bool typing) {
    _db.ref('chats/$_chatId/typing/$_myId').set(typing);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) PresenceService.setOnline(_myId);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _addSub?.cancel();
    _changeSub?.cancel();
    _removeSub?.cancel();
    _typingSub?.cancel();
    _typingTimer?.cancel();
    _setTyping(false);
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── SEND ──
  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    _msgCtrl.clear();
    _setTyping(false);

    final user = _auth.currentUser;
    final name = user?.displayName ?? 'Me';

    try {
      final msgData = {
        'text': text,
        'senderId': _myId,
        'senderName': name,
        'timestamp': ServerValue.timestamp,
        'status': _friendOnline ? 'delivered' : 'sent',
      };
      await _msgsRef.push().set(msgData);
      await _db.ref('chats/$_chatId/lastMessage').set(msgData);

      // ── INCREMENT UNREAD COUNT FOR FRIEND ──
      if (widget.chatType != 'ai') {
        _db.ref('chats/$_chatId/unreadCount/${widget.friendId}').set(ServerValue.increment(1));
      }

      if (widget.chatType == 'ai') {
        _aiRespond(text);
      } else {
        // 🔔 Send push notification to receiver (works even when app is closed)
        FcmService.sendNotification(
          receiverUid: widget.friendId,
          title: name,
          body: text,
          data: {'chatId': _chatId},
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Send failed: $e'), backgroundColor: Colors.red));
    }
  }

  // ── DELETE MESSAGE ──
  Future<void> _deleteMessage(String msgId) async {
    try {
      await _msgsRef.child(msgId).remove();

      // Update lastMessage
      if (_sortedMessages.isNotEmpty) {
        final remaining = _sortedMessages.where((m) => m.id != msgId).toList();
        if (remaining.isNotEmpty) {
          final last = remaining.last;
          await _db.ref('chats/$_chatId/lastMessage').set({
            'text': last.text, 'senderId': last.senderId, 'senderName': last.senderName,
            'timestamp': last.timestamp, 'status': last.status.name,
          });
        } else {
          await _db.ref('chats/$_chatId/lastMessage').remove();
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e'), backgroundColor: Colors.red));
    }
  }

  // ── AI ──
  void _aiRespond(String query) {
    setState(() => _aiTyping = true);
    Future.delayed(const Duration(milliseconds: 1200), () async {
      if (!mounted) return;
      String reply;
      final q = query.toLowerCase();
      if (q.contains('help') || q.contains('emergency')) {
        reply = "🚨 Stay calm. If it's an emergency, press the alert button on Home.";
      } else if (q.contains('hello') || q.contains('hi') || q.contains('hey')) {
        reply = "Hello! 👋 I'm Vanguard AI. How can I keep you safe today?";
      } else if (q.contains('location') || q.contains('where')) {
        reply = "📍 Share your live location from the Location tab.";
      } else if (q.contains('safe')) {
        reply = "✅ Great! You can reach contacts instantly from Home.";
      } else {
        reply = "I'm monitoring your safety.\n• Type 'help' for emergency\n• Type 'location' for sharing\n• Type 'safe' for status";
      }

      final aiMsg = {
        'text': reply, 'senderId': 'vanguard_ai', 'senderName': 'Vanguard AI',
        'timestamp': ServerValue.timestamp, 'status': 'seen',
      };
      await _msgsRef.push().set(aiMsg);
      await _db.ref('chats/$_chatId/lastMessage').set(aiMsg);
      if (mounted) setState(() => _aiTyping = false);
    });
  }

  void _scroll() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  // ── START A CALL ──
  Future<void> _startCall({required bool isVideo}) async {
    if (widget.chatType == 'ai') return;
    final user = _auth.currentUser;
    if (user == null) return;

    // Get my profile photo
    final myDoc = await _firestore.collection('users').doc(_myId).get();
    final myPhoto = myDoc.data()?['photoUrl'] ?? '';
    final myName = user.displayName ?? 'User';

    // callId = chatId (unique for this pair)
    final callId = _chatId;

    // Send invite to friend via Firebase RTDB
    AgoraService.init();
    await AgoraService.sendCallInvite(
      callId: callId,
      callerId: _myId,
      callerName: myName,
      callerPhoto: myPhoto,
      receiverId: widget.friendId,
      isVideo: isVideo,
    );

    // Navigate to call screen
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AgoraCallScreen(
          channelName: callId,
          friendName: widget.friendName ?? 'Friend',
          friendPhoto: '',
          friendId: widget.friendId,
          isVideo: isVideo,
          isCaller: true,
        ),
      ),
    );
  }

  // ── BUILD ──
  @override
  Widget build(BuildContext context) {
    const theme = Color(0xff250D57);
    const accent = Color(0xff38B6FF);
    final isTyping = widget.chatType == 'ai' ? _aiTyping : _friendTyping;

    return Scaffold(
      backgroundColor: const Color(0xffF5F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 1,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: theme), onPressed: () => Navigator.pop(context)),
        title: Row(children: [
          StreamBuilder<DocumentSnapshot>(
            stream: _firestore.collection('users').doc(widget.friendId).snapshots(),
            builder: (context, snap) {
              String? pUrl;
              if (snap.hasData && snap.data!.exists) {
                pUrl = (snap.data!.data() as Map<String, dynamic>)['photoUrl'];
              }
              return Stack(children: [
                GestureDetector(
                  onTap: () { if (pUrl != null) _showFullImage(context, pUrl); },
                  child: CircleAvatar(
                    backgroundColor: accent.withOpacity(0.1),
                    backgroundImage: pUrl != null ? NetworkImage(pUrl) : null,
                    child: pUrl == null ? Icon(widget.chatType == 'ai' ? Icons.auto_awesome : Icons.person, color: theme) : null,
                  ),
                ),
                Positioned(bottom: 0, right: 0, child: Container(height: 12, width: 12, decoration: BoxDecoration(color: _friendOnline ? Colors.green : Colors.grey, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)))),
              ]);
            }
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.friendName ?? 'Vanguard AI', style: const TextStyle(color: theme, fontSize: 16, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
              if (widget.chatType != 'ai')
                Text(
                  isTyping ? 'typing...' : (_friendOnline ? 'Online' : PresenceService.formatLastSeen(_lastSeen)),
                  style: TextStyle(color: isTyping ? accent : (_friendOnline ? Colors.green : Colors.grey), fontSize: 11, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
            ]),
          ),
        ]),
        actions: widget.chatType == 'ai' ? [] : [
          // Voice Call
          IconButton(
            icon: const Icon(Icons.phone, color: theme, size: 22),
            onPressed: () => _startCall(isVideo: false),
          ),
          // Video Call
          IconButton(
            icon: const Icon(Icons.videocam, color: theme, size: 26),
            onPressed: () => _startCall(isVideo: true),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _sortedMessages.isEmpty
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.lock_outline, size: 40, color: Colors.grey[300]),
                    const SizedBox(height: 12),
                    Text('Messages are end-to-end secured\nSay Hi! 👋', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[400], fontSize: 14)),
                  ]))
                : ListView.builder(
                    controller: _scrollCtrl,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    itemCount: _sortedMessages.length,
                    itemBuilder: (_, i) => _bubble(_sortedMessages[_sortedMessages.length - 1 - i]),
                  ),
          ),
          if (isTyping)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(children: [
                _typingDots(),
                const SizedBox(width: 8),
                Text('${widget.friendName ?? "AI"} is typing...', style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey, fontSize: 12)),
              ]),
            ),
          _input(),
        ],
      ),
    );
  }

  Widget _typingDots() => SizedBox(
    width: 30, height: 14,
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: List.generate(3, (i) =>
      TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 400 + i * 200),
        builder: (_, v, __) => Opacity(opacity: v, child: Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xff38B6FF), shape: BoxShape.circle))),
      ),
    )),
  );

  Widget _bubble(ChatMessage msg) {
    final isMe = msg.isMe;
    const theme = Color(0xff250D57);
    const accent = Color(0xff38B6FF);

    Widget content;
    if (msg.isLocation) {
      content = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          height: 160, width: 230,
          decoration: BoxDecoration(
            color: isMe ? Colors.white.withOpacity(0.1) : Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(alignment: Alignment.center, children: [
            Positioned.fill(child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Opacity(opacity: 0.5, child: Icon(Icons.map, size: 80, color: isMe ? Colors.white24 : Colors.grey[300])),
            )),
            StreamBuilder<DocumentSnapshot>(
              stream: _firestore.collection('users').doc(msg.senderId).snapshots(),
              builder: (ctx, snap) {
                String? pUrl;
                if (snap.hasData && snap.data!.exists) pUrl = (snap.data!.data() as Map<String, dynamic>)['photoUrl'];
                return Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: CircleAvatar(
                    radius: 24,
                    backgroundColor: accent.withOpacity(0.1),
                    backgroundImage: pUrl != null ? NetworkImage(pUrl) : null,
                    child: pUrl == null ? Text(msg.senderName[0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, color: theme)) : null,
                  ),
                );
              }
            ),
            if (msg.alertType != null)
              Positioned(top: 8, left: 8, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(20)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  CircleAvatar(radius: 3, backgroundColor: Colors.white),
                  SizedBox(width: 4),
                  Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ]),
              )),
          ]),
        ),
        const SizedBox(height: 8),
        Text(msg.text, style: TextStyle(color: isMe ? Colors.white : theme, fontSize: 14, fontWeight: FontWeight.bold, height: 1.2)),
        const SizedBox(height: 5),
        const Divider(color: Colors.black12, height: 1),
        InkWell(
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => Location(
              targetLat: msg.lat,
              targetLng: msg.lng,
              targetName: msg.senderName,
            )));
          },
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.location_on, color: Color(0xff4CAF50), size: 16),
              SizedBox(width: 4),
              Text('View live location', style: TextStyle(color: Color(0xff4CAF50), fontWeight: FontWeight.bold, fontSize: 14)),
            ]),
          ),
        ),
      ]);
    } else if (msg.isImage) {
      content = Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        GestureDetector(
          onTap: () => _showFullImage(context, msg.imageUrl!),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              msg.imageUrl!,
              width: 200, height: 200, fit: BoxFit.cover,
              loadingBuilder: (_, child, prog) => prog == null ? child : const SizedBox(width: 200, height: 200, child: Center(child: CircularProgressIndicator())),
              errorBuilder: (_, __, ___) => Container(width: 200, height: 100, color: Colors.grey[200], child: const Icon(Icons.broken_image)),
            ),
          ),
        ),
        if (msg.text.isNotEmpty && msg.text != '📷 Photo')
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(msg.text, style: TextStyle(color: isMe ? Colors.white : theme, fontSize: 15))),
      ]);
    } else {
      content = Text(msg.text, style: TextStyle(color: isMe ? Colors.white : theme, fontSize: 15, height: 1.4));
    }

    return GestureDetector(
      onLongPress: () {
        showModalBottomSheet(
          context: context,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 8),
            Container(height: 4, width: 40, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            if (isMe) ListTile(leading: const Icon(Icons.delete_outline, color: Colors.redAccent), title: const Text('Delete Message'), onTap: () { Navigator.pop(context); _deleteMessage(msg.id); }),
            ListTile(leading: const Icon(Icons.copy, color: Colors.grey), title: const Text('Copy Text'), onTap: () { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied!'))); }),
            ListTile(leading: const Icon(Icons.reply, color: Colors.grey), title: const Text('Reply'), onTap: () => Navigator.pop(context)),
            const SizedBox(height: 8),
          ])),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isMe ? theme : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18), topRight: const Radius.circular(18),
                bottomLeft: isMe ? const Radius.circular(18) : Radius.zero,
                bottomRight: isMe ? Radius.zero : const Radius.circular(18),
              ),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                content,
                const SizedBox(height: 4),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(msg.formattedTime, style: TextStyle(color: isMe ? Colors.white54 : Colors.grey, fontSize: 10)),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    Icon(
                      msg.status == MessageStatus.seen ? Icons.done_all : (msg.status == MessageStatus.delivered ? Icons.done_all : Icons.done),
                      size: 14, 
                      color: msg.status == MessageStatus.seen ? accent : (msg.status == MessageStatus.delivered ? Colors.white70 : Colors.white38),
                    ),
                  ],
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── PICK & SEND IMAGE ──
  Future<void> _pickAndSendImage() async {
    final source = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(height: 4, width: 40, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          ListTile(leading: const Icon(Icons.camera_alt, color: Color(0xff38B6FF)), title: const Text('Camera'), onTap: () => Navigator.pop(context, 'camera')),
          ListTile(leading: const Icon(Icons.photo_library, color: Color(0xff250D57)), title: const Text('Gallery'), onTap: () => Navigator.pop(context, 'gallery')),
          ListTile(leading: const Icon(Icons.videocam, color: Colors.redAccent), title: const Text('Video (Max 3MB)'), onTap: () => Navigator.pop(context, 'video')),
          const SizedBox(height: 8),
        ]),
      ),
    );

    if (source == null) return;
    if (source == 'video') { _pickAndSendVideo(); return; }

    final picked = await _imagePicker.pickImage(source: source == 'camera' ? ImageSource.camera : ImageSource.gallery, imageQuality: 70, maxWidth: 1024);
    if (picked == null) return;

    final file = File(picked.path);
    final sizeInBytes = await file.length();
    final sizeInMb = sizeInBytes / (1024 * 1024);

    if (sizeInMb > 1.0) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Image size must be less than 1MB'), backgroundColor: Colors.red));
      return;
    }

    setState(() => _isUploadingImage = true);

    try {
      final file = File(picked.path);
      // Professional Centralized Upload
      final link = await CloudinaryService.uploadFile(file);

      if (link == null) {
        final msg = CloudinaryService.lastErrorMessage ?? 'Image upload failed. Please try again.';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: Colors.red),
          );
        }
        return;
      }

      final user = _auth.currentUser;
      final senderName = user?.displayName ?? 'Me';
      final msgData = {
        'text': '📷 Photo',
        'imageUrl': link,
        'senderId': _myId,
        'senderName': senderName,
        'timestamp': ServerValue.timestamp,
        'status': 'sent',
      };
      await _msgsRef.push().set(msgData);
      await _db.ref('chats/$_chatId/lastMessage').set(msgData);

      // ── INCREMENT UNREAD COUNT FOR FRIEND ──
      _db.ref('chats/$_chatId/unreadCount/${widget.friendId}').set(ServerValue.increment(1));

      // 🔔 Notify receiver about the photo
      FcmService.sendNotification(
        receiverUid: widget.friendId,
        title: senderName,
        body: '📷 Sent you a photo',
        data: {'chatId': _chatId},
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  Widget _input() {
    const accent = Color(0xff38B6FF);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))]),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isUploadingImage)
              const LinearProgressIndicator(color: accent, minHeight: 3),
            Row(children: [
              IconButton(
                icon: const Icon(Icons.add_circle_outline, color: Colors.grey),
                onPressed: _isUploadingImage ? null : _pickAndSendImage,
              ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  decoration: BoxDecoration(color: const Color(0xffF0F2F5), borderRadius: BorderRadius.circular(25)),
                  child: TextField(
                    controller: _msgCtrl,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    onChanged: (val) {
                      _typingTimer?.cancel();
                      if (val.trim().isNotEmpty) {
                        _setTyping(true);
                        _typingTimer = Timer(const Duration(seconds: 2), () => _setTyping(false));
                      } else {
                        _setTyping(false);
                      }
                    },
                    decoration: const InputDecoration(hintText: 'Type message...', border: InputBorder.none),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _send,
                child: Container(padding: const EdgeInsets.all(10), decoration: const BoxDecoration(color: accent, shape: BoxShape.circle), child: const Icon(Icons.send, color: Colors.white, size: 20)),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndSendVideo() async {
    final picked = await _imagePicker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return;

    final file = File(picked.path);
    final sizeInMb = (await file.length()) / (1024 * 1024);

    if (sizeInMb > 3.0) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Video size must be less than 3MB'), backgroundColor: Colors.red));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Video uploading...')));
  }

  void _showFullImage(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(borderRadius: BorderRadius.circular(15), child: Image.network(url, fit: BoxFit.contain)),
          const SizedBox(height: 10),
          IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 30), onPressed: () => Navigator.pop(context)),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  STATUS PLAYER DIALOG (Supports Video & Image)
// ════════════════════════════════════════════════════════════════

class _StatusPlayerDialog extends StatefulWidget {
  final String url;
  final String type;
  final String ownerId;
  final String curUid;
  final Map viewersMap;

  const _StatusPlayerDialog({
    required this.url, 
    required this.type, 
    required this.ownerId, 
    required this.curUid,
    required this.viewersMap,
  });

  @override
  State<_StatusPlayerDialog> createState() => _StatusPlayerDialogState();
}

class _StatusPlayerDialogState extends State<_StatusPlayerDialog> {
  VideoPlayerController? _videoController;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    if (widget.type == 'video') {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(widget.url))
        ..initialize().then((_) {
          setState(() => _isInitialized = true);
          _videoController?.play();
          _videoController?.setLooping(true);
        });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  void _showViewerList() {
    final viewerIds = widget.viewersMap.keys.toList();
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Viewed by', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xff250D57))),
            const SizedBox(height: 15),
            if (viewerIds.isEmpty)
              const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('No views yet', style: TextStyle(color: Colors.grey))))
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: viewerIds.length,
                  itemBuilder: (_, i) {
                    final uid = viewerIds[i];
                    return StreamBuilder<DocumentSnapshot>(
                      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
                      builder: (context, snap) {
                        String name = 'Loading...';
                        String? photoUrl;
                        if (snap.hasData && snap.data!.exists) {
                          final d = snap.data!.data() as Map<String, dynamic>;
                          name = d['displayName'] ?? d['name'] ?? 'User';
                          photoUrl = d['photoUrl'];
                        }
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                            child: photoUrl == null ? const Icon(Icons.person) : null,
                          ),
                          title: Text(name),
                          subtitle: Text(DateFormat('hh:mm a').format((widget.viewersMap[uid] as Timestamp).toDate())),
                        );
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: EdgeInsets.zero,
      child: Stack(children: [
        Center(
          child: widget.type == 'video'
              ? (_isInitialized
                  ? AspectRatio(
                      aspectRatio: _videoController!.value.aspectRatio,
                      child: VideoPlayer(_videoController!),
                    )
                  : const CircularProgressIndicator(color: Colors.white))
              : InteractiveViewer(
                  child: Image.network(widget.url, fit: BoxFit.contain, width: double.infinity,
                    errorBuilder: (_, __, ___) => const Center(child: Text('Failed to load image', style: TextStyle(color: Colors.white)))),
                ),
        ),
        Positioned(top: 40, right: 20, child: IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 30), onPressed: () => Navigator.pop(context))),
        Positioned(
          bottom: 30, left: 0, right: 0, 
          child: GestureDetector(
            onTap: widget.ownerId == widget.curUid ? _showViewerList : null,
            child: Column(children: [
              Icon(widget.type == 'video' ? Icons.play_circle_outline : Icons.visibility, color: Colors.white, size: 24),
              const SizedBox(height: 4),
              Text(
                widget.ownerId == widget.curUid ? '${widget.viewersMap.length} views' : 'Watching ${widget.type}',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)
              ),
              if (widget.ownerId == widget.curUid)
                const Text('Tap to see who viewed', style: TextStyle(color: Colors.white70, fontSize: 10)),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  MULTI-STATUS PLAYER  —  WhatsApp-style story viewer
//  Cycles through all statuses of a user automatically.
//  Records per-status view in Firestore.
// ════════════════════════════════════════════════════════════════
class _MultiStatusPlayerDialog extends StatefulWidget {
  final List statuses;
  final String ownerId;
  final String curUid;
  final bool isMe;
  final FirebaseFirestore firestore;

  const _MultiStatusPlayerDialog({
    required this.statuses,
    required this.ownerId,
    required this.curUid,
    required this.isMe,
    required this.firestore,
  });

  @override
  State<_MultiStatusPlayerDialog> createState() => _MultiStatusPlayerDialogState();
}

class _MultiStatusPlayerDialogState extends State<_MultiStatusPlayerDialog>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  late AnimationController _progressCtrl;
  VideoPlayerController? _videoCtrl;
  bool _videoReady = false;

  @override
  void initState() {
    super.initState();
    _progressCtrl = AnimationController(vsync: this);
    _progressCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _nextStatus();
      }
    });
    _loadStatus(_currentIndex);
  }

  Future<void> _loadStatus(int index) async {
    _progressCtrl.stop();
    _videoCtrl?.dispose();
    _videoCtrl = null;
    _videoReady = false;

    final s = widget.statuses[index];
    final type = s['type'] ?? 'image';
    final url  = s['url']  ?? '';
    final duration = type == 'video' ? const Duration(seconds: 30) : const Duration(seconds: 5);

    if (type == 'video' && url.isNotEmpty) {
      _videoCtrl = VideoPlayerController.networkUrl(Uri.parse(url));
      await _videoCtrl!.initialize();
      _videoCtrl!.play();
      if (mounted) setState(() => _videoReady = true);
    }

    _progressCtrl.duration = duration;
    _progressCtrl.forward(from: 0);

    // Record view for this specific status (not if owner is viewing own)
    if (!widget.isMe) {
      _recordView(index);
    }
  }

  void _recordView(int index) {
    // Get the _origIndex that we attached earlier directly to point to the correct DB sub-document
    final s = widget.statuses[index];
    final origIndex = s['_origIndex'] ?? index;

    // Use dot notation to merge the specific viewer UID into the nested map
    // This prevents overwriting other viewers of the same status!
    widget.firestore.collection('users').doc(widget.ownerId).update({
      'statusViewedBy_$origIndex.${widget.curUid}': FieldValue.serverTimestamp(),
    }).catchError((e) {
      if (e.toString().contains('not-found') || e.toString().contains('no document')) {
       // fallback if update fails (though doc should exist)
       widget.firestore.collection('users').doc(widget.ownerId).set({
         'statusViewedBy_$origIndex': {widget.curUid: FieldValue.serverTimestamp()},
       }, SetOptions(merge: true));
      }
    });
  }

  Future<void> _deleteStatus() async {
    _progressCtrl.stop();
    _videoCtrl?.pause();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Status?'),
        content: const Text('Are you sure you want to delete this status?'),
        actions: [
          TextButton(onPressed: () {
            Navigator.pop(ctx, false);
            _progressCtrl.forward();
            _videoCtrl?.play();
          }, child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      )
    );

    if (confirm != true) return;

    try {
      final s = widget.statuses[_currentIndex];
      final origIndex = s['_origIndex'] ?? _currentIndex;
      
      final userDoc = await widget.firestore.collection('users').doc(widget.ownerId).get();
      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>;
        List allStatuses = data['statuses'] ?? [];
        if (origIndex < allStatuses.length) {
          allStatuses.removeAt(origIndex);
          await widget.firestore.collection('users').doc(widget.ownerId).update({
            'statuses': allStatuses,
          });
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Status deleted')));
          if (mounted) Navigator.pop(context); // Close dialog to let UI refresh
        }
      }
    } catch (e) {
      debugPrint('Delete error: $e');
      _progressCtrl.forward();
      _videoCtrl?.play();
    }
  }

  void _showViewerList(Map viewersMap) {
    _progressCtrl.stop();
    _videoCtrl?.pause();

    final viewerIds = viewersMap.keys.toList();
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Viewed by', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xff250D57))),
            const SizedBox(height: 15),
            if (viewerIds.isEmpty)
              const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('No views yet', style: TextStyle(color: Colors.grey))))
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: viewerIds.length,
                  itemBuilder: (_, i) {
                    final uid = viewerIds[i];
                    return StreamBuilder<DocumentSnapshot>(
                      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
                      builder: (context, snap) {
                        String name = 'Loading...';
                        String? photoUrl;
                        if (snap.hasData && snap.data!.exists) {
                          final d = snap.data!.data() as Map<String, dynamic>;
                          name = d['displayName'] ?? d['name'] ?? 'User';
                          photoUrl = d['photoUrl'];
                        }
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                            child: photoUrl == null ? const Icon(Icons.person) : null,
                          ),
                          title: Text(name),
                          subtitle: Text(DateFormat('hh:mm a').format((viewersMap[uid] as Timestamp).toDate())),
                        );
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    ).then((_) {
      if (mounted) {
        _progressCtrl.forward();
        _videoCtrl?.play();
      }
    });
  }

  void _nextStatus() {
    if (_currentIndex < widget.statuses.length - 1) {
      setState(() => _currentIndex++);
      _loadStatus(_currentIndex);
    } else {
      Navigator.pop(context);
    }
  }

  void _prevStatus() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      _loadStatus(_currentIndex);
    }
  }

  @override
  void dispose() {
    _progressCtrl.dispose();
    _videoCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s    = widget.statuses[_currentIndex];
    final type = s['type'] ?? 'image';
    final url  = s['url']  ?? '';
    final total = widget.statuses.length;

    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: EdgeInsets.zero,
      child: SizedBox.expand(
        child: Stack(children: [
          // ── Media ──
          Center(
            child: type == 'video'
                ? (_videoReady && _videoCtrl != null
                    ? AspectRatio(
                        aspectRatio: _videoCtrl!.value.aspectRatio,
                        child: VideoPlayer(_videoCtrl!),
                      )
                    : const CircularProgressIndicator(color: Colors.white))
                : InteractiveViewer(
                    child: Image.network(
                      url, fit: BoxFit.contain, width: double.infinity,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Text('Failed to load', style: TextStyle(color: Colors.white))),
                    ),
                  ),
          ),

          // ── Progress bars (one per status) ──
          Positioned(
            top: 40, left: 12, right: 12,
            child: Row(
              children: List.generate(total, (i) {
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    height: 3,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: i < _currentIndex
                        ? Container(color: Colors.white)
                        : i == _currentIndex
                            ? AnimatedBuilder(
                                animation: _progressCtrl,
                                builder: (_, __) => FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: _progressCtrl.value,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                  ),
                );
              }),
            ),
          ),

          // ── Status index label ──
          Positioned(
            top: 55, left: 16,
            child: Text(
              '${_currentIndex + 1} / $total',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),

          // ── Close button ──
          Positioned(
            top: 45, right: 12,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // ── Tap left half = prev, right half = next ──
          Positioned.fill(
            child: Row(children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _prevStatus,
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _nextStatus,
                ),
              ),
            ]),
          ),

          // ── Bottom: status info and actions ──
          Positioned(
            bottom: 30, left: 20, right: 20,
            child: Column(
              children: [
                if (widget.isMe) ...[
                  GestureDetector(
                    onTap: () => _showViewerList(s['_viewers'] as Map? ?? {}),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.keyboard_arrow_up, color: Colors.white, size: 24),
                        const SizedBox(height: 4),
                        Text(
                          '${(s['_viewers'] as Map? ?? {}).length} views',
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 15),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Type and Count indicator
                    Row(
                      children: [
                        Icon(
                          type == 'video' ? Icons.videocam : Icons.image,
                          color: Colors.white54, size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Status ${_currentIndex + 1} of $total',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                    
                    // Delete Button
                    if (widget.isMe)
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.white70, size: 24),
                        onPressed: _deleteStatus,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
