import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_app1/bottombar.dart';
import 'package:my_app1/Dashboard/homepage.dart';
import 'package:my_app1/Dashboard/location.dart';
import 'package:my_app1/Dashboard/profile.dart';
import 'package:image_picker/image_picker.dart';
import 'package:my_app1/services/cloudinary_service.dart';
import 'package:my_app1/services/notification_service.dart';

class ChatMessage {
  final String text;
  final String senderId;
  final String senderName;
  final DateTime timestamp;
  final bool isMe;
  final bool isRead;
  final String? imageUrl;
  final String? senderProfileUrl;

  ChatMessage({
    required this.text,
    required this.senderId,
    required this.senderName,
    required this.timestamp,
    required this.isMe,
    this.isRead = true,
    this.imageUrl,
    this.senderProfileUrl,
  });

  // storage
  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'senderId': senderId,
      'senderName': senderName,
      'timestamp': timestamp.toIso8601String(),
      'isMe': isMe,
      'imageUrl': imageUrl,
      'senderProfileUrl': senderProfileUrl,
    };
  }

  // Create from Firestore
  factory ChatMessage.fromFirestore(DocumentSnapshot doc, String currentUserId) {
    final data = doc.data() as Map<String, dynamic>;
    final senderId = data['senderId'] ?? '';
    return ChatMessage(
      text: data['text'] ?? '',
      senderId: senderId,
      senderName: data['senderName'] ?? '',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isMe: senderId == currentUserId,
      isRead: data['isRead'] ?? false,
      imageUrl: data['imageUrl'],
      senderProfileUrl: data['senderProfileUrl'] ?? data['senderPhotoUrl'],
    );
  }

  // Create from JSON (for local storage)
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      text: json['text'] ?? '',
      senderId: json['senderId'] ?? '',
      senderName: json['senderName'] ?? '',
      timestamp: json['timestamp'] != null 
          ? DateTime.parse(json['timestamp']) 
          : DateTime.now(),
      isMe: json['isMe'] ?? false,
      isRead: json['isRead'] ?? true,
      imageUrl: json['imageUrl'],
      senderProfileUrl: json['senderProfileUrl'],
    );
  }
}

// Chat Selection Screen - Shows when clicking chat icon
class ChatSelectionScreen extends StatefulWidget {
  const ChatSelectionScreen({super.key});

  @override
  State<ChatSelectionScreen> createState() => _ChatSelectionScreenState();
}

class _ChatSelectionScreenState extends State<ChatSelectionScreen> {
  List<Map<String, dynamic>> _friends = []; // Friends list with UID and name
  int _selectedIndex = 1; // Chat is selected (index 1)
  String _currentUserId = '';
  String _currentUserName = 'User';
  final Map<String, String> _userNames = {}; // Cache for participant names (uid -> name)
  final Map<String, String?> _userProfiles = {}; // Cache for participant profiles (uid -> url)
  StreamSubscription<QuerySnapshot>? _chatsSubscription;
  DateTime? _lastNotificationCheck;

  @override
  void initState() {
    super.initState();
    _initUser();
    _loadFriends();
    _setupNotificationListener();
    _lastNotificationCheck = DateTime.now();
    _initializeUnreadCounts(); // Fix all existing chats
  }
  
  // Initialize unreadCounts for all chats that don't have it
  Future<void> _initializeUnreadCounts() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      
      print('DEBUG - Initializing unreadCounts for all chats...');
      
      final chatsSnapshot = await FirebaseFirestore.instance
          .collection('chats')
          .where('participants', arrayContains: user.uid)
          .get();
      
      for (var chatDoc in chatsSnapshot.docs) {
        final data = chatDoc.data();
        
        // Check if unreadCounts exists
        if (data['unreadCounts'] == null) {
          print('DEBUG - Chat ${chatDoc.id} missing unreadCounts, initializing...');
          
          final participants = List<String>.from(data['participants'] ?? []);
          Map<String, int> initialCounts = {};
          
          // Initialize all participants with 0
          for (var participantId in participants) {
            initialCounts[participantId] = 0;
          }
          
          await chatDoc.reference.update({
            'unreadCounts': initialCounts,
          });
          
          print('DEBUG - Initialized unreadCounts for chat ${chatDoc.id}');
        }
      }
      
      print('DEBUG - Finished initializing unreadCounts');
    } catch (e) {
      print('Error initializing unreadCounts: $e');
    }
  }

  @override
  void dispose() {
    _chatsSubscription?.cancel();
    super.dispose();
  }

  void _setupNotificationListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _chatsSubscription = FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: user.uid)
        .snapshots()
        .listen((snapshot) {
      if (_lastNotificationCheck == null) return;

      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.modified || change.type == DocumentChangeType.added) {
          final data = change.doc.data() as Map<String, dynamic>;
          final lastSenderId = data['lastSenderId'];
          final lastTimestamp = data['lastTimestamp'] as Timestamp?;
          
          if (lastSenderId != null && lastSenderId != user.uid && lastTimestamp != null) {
            final msgTime = lastTimestamp.toDate();
            if (msgTime.isAfter(_lastNotificationCheck!)) {
              _lastNotificationCheck = msgTime;
              final senderName = data['lastSenderName'] ?? 'Someone';
              final message = data['lastMessage'] ?? 'sent a message';
              
              if (mounted) {
                // Clear previous snackbar first
                ScaffoldMessenger.of(context).clearSnackBars();
                
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$senderName: $message'),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: const Color(0xff250D57),
                    duration: const Duration(seconds: 2),
                    dismissDirection: DismissDirection.horizontal, // Enable swipe to dismiss
                    margin: EdgeInsets.only(
                      bottom: MediaQuery.of(context).size.height - 100,
                      left: 10,
                      right: 10,
                    ),
                    action: SnackBarAction(
                      label: 'View',
                      textColor: const Color(0xff38B6FF),
                      onPressed: () {
                        // Optional: Navigate to chat if not already there
                      },
                    ),
                  ),
                );
              }
            }
          }
        }
      }
    });
  }

  Future<void> _initUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      String name = user.displayName ?? 'User';
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (doc.exists) {
          name = doc.data()?['fullName'] ?? doc.data()?['username'] ?? name;
        }
      } catch (e) {
        print('Error fetching current user name: $e');
      }
      if (mounted) {
        setState(() {
          _currentUserId = user.uid;
          _currentUserName = name;
        });
      }
    }
  }

  // Load friends from local storage
  Future<void> _loadFriends() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final friendsJson = prefs.getString('friends_list');

      List<Map<String, dynamic>> loadedFriends = [];
      if (friendsJson != null) {
        final List<dynamic> friendsList = json.decode(friendsJson);
        loadedFriends = friendsList.map((f) => Map<String, dynamic>.from(f)).toList();
      }

      // Automatically add Shamii if not present
      const shamiiEmail = 'shamii9145@gmail.com';
      bool hasShamii = loadedFriends.any((f) => f['email'] == shamiiEmail);

      if (!hasShamii) {
        // Try to fetch Shamii's UID from Firestore
        try {
          final querySnapshot = await FirebaseFirestore.instance
              .collection('users')
              .where('email', isEqualTo: shamiiEmail)
              .get();
          
          if (querySnapshot.docs.isNotEmpty) {
            final userData = querySnapshot.docs.first.data();
            loadedFriends.add({
              'name': userData['fullName'] ?? userData['username'] ?? 'Shamii',
              'uid': userData['uid'],
              'email': shamiiEmail,
            });
          } else {
            // Default Shamii if user is not in Firestore yet
            loadedFriends.add({
              'name': 'Shamii',
              'uid': 'shamii_default_uid', // This will be updated once they register
              'email': shamiiEmail,
            });
          }
        } catch (e) {
          print('Error fetching Shamii from Firestore: $e');
        }
      }

      setState(() {
        _friends = loadedFriends;
      });
      
      // Save updated list
      if (!hasShamii) {
        await _saveFriends();
      }
    } catch (e) {
      print('Error loading friends: $e');
    }
  }

  Future<void> _saveFriends() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final friendsJson = json.encode(_friends);
      await prefs.setString('friends_list', friendsJson);
    } catch (e) {
      print('Error saving friends: $e');
    }
  }



  Future<void> _fetchAndSetUserInfo(String uid) async {
    if (_userNames.containsKey(uid) && _userProfiles.containsKey(uid)) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists && mounted) {
        setState(() {
          _userNames[uid] = doc.data()?['fullName'] ?? doc.data()?['username'] ?? 'User';
          _userProfiles[uid] = doc.data()?['profileImageUrl'] ?? doc.data()?['photoURL'];
        });
      }
    } catch (e) {
      print('Error fetching info for $uid: $e');
    }
  }

  Widget _buildChatTile(BuildContext context, String uid, String name, String lastMessage, DateTime? time, {int? unreadCount, String? profileUrl}) {
    name = _userNames[uid] ?? name;
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => Chat(
              chatType: 'friend',
              friendName: name,
              friendUid: uid,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: Colors.grey.withOpacity(0.1), spreadRadius: 1, blurRadius: 3, offset: const Offset(0, 1)),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.grey[300],
              backgroundImage: profileUrl != null ? NetworkImage(profileUrl) : null,
              child: profileUrl == null 
                  ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87))
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(lastMessage, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            ),
            if (time != null || (unreadCount != null && unreadCount > 0))
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (time != null)
                    Text(
                      "${time.hour}:${time.minute.toString().padLeft(2, '0')}",
                      style: TextStyle(fontSize: 10, color: Colors.grey[400]),
                    ),
                  if (unreadCount != null && unreadCount > 0)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        unreadCount.toString(),
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        automaticallyImplyLeading: false,
        title: const Text(
          'Chat',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add, color: Colors.black),
            onPressed: _showAddFriendDialog,
            tooltip: 'Add Friend',
          ),
        ],
      ),
      body: Container(
        color: Colors.grey[100],
        child: Column(
          children: [
            // Chat with AI option
            InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const Chat(chatType: 'ai'),
                  ),
                );
              },
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.2),
                      spreadRadius: 1,
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xff250D57), Color(0xff38B6FF)],
                        ),
                      ),
                      child: const Icon(
                        Icons.smart_toy,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Chat with AI',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Get instant AI assistance',
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.grey,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),

            // Friends section (Horizontal or vertical)
            if (_friends.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Friends & Contacts',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    TextButton(
                      onPressed: _showAddFriendDialog,
                      child: const Text(
                        'Add New',
                        style: TextStyle(
                          color: Color(0xff250D57),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _friends.length,
                  itemBuilder: (context, index) {
                    final friend = _friends[index];
                    final name = friend['name'] ?? 'User';
                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => Chat(
                              chatType: 'friend',
                              friendName: name,
                              friendUid: friend['uid'],
                            ),
                          ),
                        );
                      },
                      child: Container(
                        width: 80,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 28,
                              backgroundColor: Colors.white,
                              child: CircleAvatar(
                                radius: 26,
                                backgroundColor: const Color(0xff38B6FF).withOpacity(0.2),
                                child: friend['profileUrl'] != null || friend['photoURL'] != null
                                    ? ClipOval(child: Image.network(friend['profileUrl'] ?? friend['photoURL']!, fit: BoxFit.cover, width: 52, height: 52))
                                    : Text(
                                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                                        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xff250D57)),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              name.split(' ')[0],
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const Divider(height: 32, thickness: 1, indent: 16, endIndent: 16),
            ] else ...[
               Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Friends',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    TextButton(
                      onPressed: _showAddFriendDialog,
                      child: const Text('Add Friend', style: TextStyle(color: Color(0xff250D57), fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ],

            // Recent Conversations header
            const Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Recent Conversations',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),

            // Active Chats from Firestore
            Expanded(
              child: FirebaseAuth.instance.currentUser == null
                  ? const Center(child: CircularProgressIndicator())
                  : StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('chats')
                          .where('participants', arrayContains: FirebaseAuth.instance.currentUser!.uid)
                          .orderBy('lastTimestamp', descending: true)
                          .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final chatDocs = snapshot.data?.docs ?? [];

                  if (chatDocs.isEmpty && _friends.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          const Text('No conversations yet', style: TextStyle(fontSize: 18, color: Colors.grey, fontWeight: FontWeight.bold)),
                          Text('Add a friend or wait for a message!', style: TextStyle(color: Colors.grey[500])),
                        ],
                      ),
                    );
                  }

                  // Merge Firestore chats with local friends to ensure names are shown correctly
                  return ListView.builder(
                    itemCount: chatDocs.length,
                    itemBuilder: (context, index) {
                      final chatData = chatDocs[index].data() as Map<String, dynamic>;
                      final participants = List<String>.from(chatData['participants'] ?? []);
                      final currentUid = FirebaseAuth.instance.currentUser?.uid;
                      final otherUid = participants.firstWhere((id) => id != currentUid, orElse: () => '');
                      
                      if (otherUid.isEmpty) return const SizedBox.shrink();

                      // Try to find the name from local friends or Firestore participants info
                      // In a real app, we might store participant names in the chat doc or fetch them
                      String otherName = 'User';
                      final localFriend = _friends.firstWhere((f) => f['uid'] == otherUid, orElse: () => {});
                      final participantNames = chatData['participantNames'] as Map<String, dynamic>?;
                      final participantProfiles = chatData['participantProfiles'] as Map<String, dynamic>?;

                      if (localFriend.isNotEmpty) {
                        otherName = localFriend['name'] ?? 'User';
                      } else if (participantNames != null && participantNames.containsKey(otherUid)) {
                        otherName = participantNames[otherUid].toString();
                      } else if (_userNames.containsKey(otherUid)) {
                        otherName = _userNames[otherUid]!;
                      } else {
                        otherName = 'Chat User';
                        _fetchAndSetUserInfo(otherUid);
                      }

                      String? otherProfile = participantProfiles?[otherUid]?.toString();
                      if (otherProfile == null && _userProfiles.containsKey(otherUid)) {
                        otherProfile = _userProfiles[otherUid];
                      }

                      final unreadCounts = chatData['unreadCounts'] as Map<String, dynamic>?;
                      final unreadCount = (unreadCounts?[currentUid] as num?)?.toInt() ?? 0;
                      
                      // DEBUG: Print to see what's happening
                      print('DEBUG Chat Tile - Other UID: $otherUid, Current UID: $currentUid');
                      print('DEBUG UnreadCounts Map: $unreadCounts');
                      print('DEBUG Extracted Count for $currentUid: $unreadCount');

                      return _buildChatTile(
                        context,
                        otherUid,
                        otherName,
                        chatData['lastMessage'] ?? 'No messages yet',
                        (chatData['lastTimestamp'] as Timestamp?)?.toDate(),
                        unreadCount: unreadCount,
                        profileUrl: otherProfile,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: MyBottomBar(
        selectedIndex: _selectedIndex,
        onTap: (index) {
          if (index == _selectedIndex) return;
          
          Widget nextScreen;
          switch (index) {
            case 0:
              nextScreen = HomePage();
              break;
            case 1:
              nextScreen = const ChatSelectionScreen();
              break;
            case 2:
              nextScreen = const Location();
              break;
            case 3:
              nextScreen = const Profile();
              break;
            default:
              nextScreen = const ChatSelectionScreen();
          }

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => nextScreen),
          );
        },
      ),
    );
  }

  void _showAddFriendDialog() {
    final friendController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Friend'),
        content: TextField(
          controller: friendController,
          decoration: const InputDecoration(
            hintText: 'Enter email or phone (+92...)',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final input = friendController.text.trim().toLowerCase();
              if (input.isNotEmpty) {
                // Show loading
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => const Center(child: CircularProgressIndicator()),
                );

                try {
                  // Search by Email first
                  var querySnapshot = await FirebaseFirestore.instance
                      .collection('users')
                      .where('email', isEqualTo: input)
                      .get();

                  // If not found, try searching by Phone
                  if (querySnapshot.docs.isEmpty) {
                    querySnapshot = await FirebaseFirestore.instance
                        .collection('users')
                        .where('phone', isEqualTo: input)
                        .get();
                  }

                  if (context.mounted) Navigator.pop(context); // Remove loading

                  String? friendName;
                  String? friendEmail;
                  String? friendUid;

                  // Standardized Shamii Fallback
                  const shamiiEmail = 'shamii9145@gmail.com';
                  bool isShamii = input == shamiiEmail;

                  if (querySnapshot.docs.isNotEmpty) {
                    final userData = querySnapshot.docs.first.data();
                    friendName = (userData['fullName'] ?? userData['username'] ?? userData['email']).toString();
                    friendEmail = userData['email']?.toString() ?? input;
                    friendUid = userData['uid']?.toString();
                  } else if (isShamii) {
                    // Fallback for Shamii
                    friendName = 'Shamii';
                    friendEmail = shamiiEmail;
                    friendUid = 'shamii_default_uid';
                  }

                  if (friendUid != null) {
                    setState(() {
                      // Check if already in friends by UID or Email
                      bool alreadyExists = _friends.any((f) => f['uid'] == friendUid || f['email'] == friendEmail);
                      if (!alreadyExists) {
                        _friends.add({
                          'name': friendName!,
                          'uid': friendUid!,
                          'email': friendEmail!,
                        });
                      }
                    });
                    await _saveFriends();
                    
                    // Notify the friend that they have been added
                    try {
                      await FirebaseFirestore.instance.collection('notifications').add({
                        'userId': friendUid,
                        'title': 'New Friend',
                        'body': '${_currentUserName ?? "A user"} added you as a friend.',
                        'time': FieldValue.serverTimestamp(),
                        'icon': 'person_add',
                        'timestamp': FieldValue.serverTimestamp(),
                      });
                    } catch (e) {
                      print('Error notifying friend: $e');
                    }

                    if (context.mounted) {
                      Navigator.pop(context); // Close dialog
                      // Navigate directly to chat
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => Chat(
                            chatType: 'friend',
                            friendName: friendName,
                            friendUid: friendUid,
                          ),
                        ),
                      );
                    }
                  } else {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Account not found.')),
                      );
                    }
                  }
                } catch (e) {
                  if (context.mounted) Navigator.pop(context); // Remove loading
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

// Main Chat Screen
class Chat extends StatefulWidget {
  final String chatType; // 'ai' or 'friend'
  final String? friendName; // Name of friend if chatType is 'friend'
  final String? friendUid; // UID of friend if chatType is 'friend'

  const Chat({super.key, required this.chatType, this.friendName, this.friendUid});

  @override
  State<Chat> createState() => _ChatState();
}

class _ChatState extends State<Chat> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  String _currentUserId = '';
  String _currentUserName = '';
  bool _isTyping = false;
  bool _isUploading = false; // Track image upload state
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ImagePicker _imagePicker = ImagePicker(); // Image picker instance

  // AI responses that sound human
  final List<Map<String, dynamic>> _aiResponses = [
    {
      'patterns': [
        'hello',
        'hi',
        'hey',
        'good morning',
        'good afternoon',
        'good evening',
      ],
      'responses': [
        'Hey there! How can I help you today?',
        'Hello! What\'s on your mind?',
        'Hi! Nice to chat with you!',
        'Hey! How are you doing?',
      ],
    },
    {
      'patterns': ['how are you', 'how do you do', 'what\'s up'],
      'responses': [
        'I\'m doing great, thanks for asking! How about you?',
        'I\'m good! Just here to help. How can I assist you?',
        'Doing well! What can I do for you today?',
      ],
    },
    {
      'patterns': ['thank', 'thanks', 'appreciate'],
      'responses': [
        'You\'re welcome! Happy to help!',
        'No problem at all! Anything else?',
        'My pleasure! Feel free to ask if you need anything.',
      ],
    },
    {
      'patterns': ['help', 'assist', 'support'],
      'responses': [
        'Of course! I\'m here to help. What do you need?',
        'Sure thing! What can I help you with?',
        'I\'d be happy to help! Tell me what you need.',
      ],
    },
    {
      'patterns': ['bye', 'goodbye', 'see you', 'later'],
      'responses': [
        'See you later! Take care!',
        'Goodbye! Have a great day!',
        'Bye! Chat with you soon!',
      ],
    },
    {
      'patterns': ['name', 'who are you', 'developer', 'creator', 'made you'],
      'responses': [
        'I\'m your AI assistant! I was created by Shamii to help you stay protected and connected.',
        'My creator is Shamii. I\'m here to assist you with anything you need!',
        'I\'m a helpful AI assistant developed by Shamii. How can I help you today?',
      ],
    },
  ];

  @override
  void initState() {
    super.initState();
    _initUser();
    _resetUnreadCount();
    _markMessagesAsRead();
    
    // Listen for new messages while chat is open to mark them as read immediately
    if (widget.chatType == 'friend') {
      final chatId = _getChatId();
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        FirebaseFirestore.instance
            .collection('chats')
            .doc(chatId)
            .collection('messages')
            .where('receiverId', isEqualTo: user.uid)
            .where('isRead', isEqualTo: false)
            .snapshots()
            .listen((snapshot) {
              if (mounted) { // Only if screen is still active
                for (var doc in snapshot.docs) {
                  doc.reference.update({'isRead': true});
                }
              }
            });
      }
    }
  }

  void _resetUnreadCount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || widget.chatType != 'friend') return;
    
    final chatId = _getChatId();
    await FirebaseFirestore.instance.collection('chats').doc(chatId).update({
      'unreadCounts.${user.uid}': 0,
    }).catchError((e) => print('Error resetting unread count: $e'));
  }

  void _markMessagesAsRead() async {
    final user = _auth.currentUser;
    if (user == null || widget.chatType != 'friend') return;

    final chatId = _getChatId();
    final batch = FirebaseFirestore.instance.batch();
    
    final unreadMessages = await FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('receiverId', isEqualTo: user.uid)
        .where('isRead', isEqualTo: false)
        .get();

    if (unreadMessages.docs.isEmpty) return;

    for (var doc in unreadMessages.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    
    await batch.commit();
    print('DEBUG: Marked ${unreadMessages.docs.length} messages as read');
  }

  Future<void> _initUser() async {
    final user = _auth.currentUser;
    if (user != null) {
      String name = user.displayName ?? 'You';
      
      // Attempt to get name from Firestore if Auth name is missing
      try {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (userDoc.exists) {
          final data = userDoc.data();
          name = data?['fullName'] ?? data?['username'] ?? name;
        }
      } catch (e) {
        print('Error fetching user name: $e');
      }

      setState(() {
        _currentUserId = user.uid;
        _currentUserName = name;
      });
      _loadMessages();
    }
  }

  // Get unique ID for this chat
  String _getChatId() {
    if (widget.chatType == 'ai') {
      return 'ai_${_currentUserId}';
    } else {
      // Create a deterministic ID from two UIDs
      List<String> ids = [_currentUserId, widget.friendUid ?? ''];
      ids.sort();
      return ids.join('_');
    }
  }

  // Load messages
  Future<void> _loadMessages() async {
    if (widget.chatType == 'ai') {
      // AI messages are still local for now as per simple simulation, 
      // but we could sync them too if needed.
      _loadLocalMessages();
    }
  }

  Future<void> _loadLocalMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final chatId = _getChatId();
      final messagesJson = prefs.getString('local_chat_$chatId');

      if (messagesJson != null) {
        final List<dynamic> messagesList = json.decode(messagesJson);
        setState(() {
          _messages.clear();
          _messages.addAll(
            messagesList.map((msg) => ChatMessage.fromJson(msg)).toList(),
          );
        });
        _scrollToBottom();
      } else {
        if (widget.chatType == 'ai') {
          _addWelcomeMessage();
          _saveLocalMessages();
        }
      }
    } catch (e) {
      print('Error loading local messages: $e');
    }
  }

  // Save messages locally
  Future<void> _saveLocalMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final chatId = _getChatId();
      final messagesJson = json.encode(
        _messages.map((msg) => msg.toJson()).toList(),
      );
      await prefs.setString('local_chat_$chatId', messagesJson);
    } catch (e) {
      print('Error saving local messages: $e');
    }
  }

  void _addWelcomeMessage() {
    _messages.add(
      ChatMessage(
        text:
            'Hello! I\'m your AI assistant. Feel free to ask me anything or chat with me!',
        senderId: 'ai',
        senderName: 'AI Assistant',
        timestamp: DateTime.now(),
        isMe: false,
      ),
    );
  }

  String _getAIResponse(String userMessage) {
    final lowerMessage = userMessage.toLowerCase();

    // Check for pattern matches
    for (var responseSet in _aiResponses) {
      for (var pattern in responseSet['patterns'] as List<String>) {
        if (lowerMessage.contains(pattern)) {
          final responses = responseSet['responses'] as List<String>;
          return responses[Random().nextInt(responses.length)];
        }
      }
    }

    // Default contextual responses
    final defaultResponses = [
      'That\'s interesting! Tell me more about that.',
      'I see what you mean. Can you elaborate?',
      'Hmm, that\'s a good point. What do you think about it?',
      'I understand. Is there anything specific you\'d like to know?',
      'Got it! Anything else you want to discuss?',
      'That makes sense. How can I help you with that?',
      'Interesting perspective! What else is on your mind?',
      'I hear you. Feel free to share more details if you\'d like.',
    ];

    // Add some variety based on message length
    if (userMessage.length < 10) {
      return 'Could you tell me a bit more?';
    } else if (userMessage.length > 50) {
      return 'Wow, that\'s a lot of information! Let me think about that...';
    }

    return defaultResponses[Random().nextInt(defaultResponses.length)];
  }

  String _getFriendResponse(String userMessage) {
    // Simulate friend responses
    final friendResponses = [
      'That sounds great!',
      'I agree with you on that.',
      'Haha, that\'s funny!',
      'Really? Tell me more!',
      'I understand what you mean.',
      'Thanks for sharing that with me.',
      'That\'s interesting!',
      'I see, that makes sense.',
    ];
    return friendResponses[Random().nextInt(friendResponses.length)];
  }

  Future<void> _showImageSourceDialog() async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Select Image Source",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildSourceOption(
                  icon: Icons.camera_alt,
                  label: "Camera",
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndUploadImage(ImageSource.camera);
                  },
                ),
                _buildSourceOption(
                  icon: Icons.photo_library,
                  label: "Gallery",
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndUploadImage(ImageSource.gallery);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceOption({required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: const Color(0xff38B6FF).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: const Color(0xff38B6FF), size: 30),
          ),
          const SizedBox(height: 8),
          Text(label),
        ],
      ),
    );
  }

  Future<void> _pickAndUploadImage(ImageSource source) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1080,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (image == null) return;

      setState(() {
        _isUploading = true;
      });

      // Upload to Cloudinary
      final imageUrl = await CloudinaryService.uploadImage(image.path);

      if (imageUrl != null) {
        _sendImageMessage(imageUrl);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to upload image')),
          );
        }
      }
    } catch (e) {
      print('Error picking/uploading image: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  void _sendImageMessage(String imageUrl) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final friendUid = widget.friendUid;
    final chatId = _getChatId();
    final profileUrl = user.photoURL;

    final newMessage = {
      'text': '',
      'imageUrl': imageUrl,
      'senderId': _currentUserId,
      'senderName': _currentUserName,
      'senderProfileUrl': profileUrl,
      'receiverId': friendUid,
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': false,
    };

    if (widget.chatType == 'ai') {
      setState(() {
        _messages.add(
          ChatMessage(
            text: '',
            imageUrl: imageUrl,
            senderId: _currentUserId,
            senderName: _currentUserName,
            senderProfileUrl: profileUrl,
            timestamp: DateTime.now(),
            isMe: true,
          ),
        );
      });
      await _saveLocalMessages();
      _scrollToBottom();
      _handleAIResponse("System: User sent an image.");
    } else {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add(newMessage);

      await FirebaseFirestore.instance.collection('chats').doc(chatId).set({
        'lastMessage': '📷 Image',
        'lastTimestamp': FieldValue.serverTimestamp(),
        'lastSenderId': _currentUserId,
        'participantProfiles': {
          _currentUserId: profileUrl,
          friendUid: widget.friendName != null ? null : null, // We might not have friend's profile here, but we can update it if we find it
        },
        'unreadCounts.$friendUid': FieldValue.increment(1),
      }, SetOptions(merge: true));

      _scrollToBottom();
      if (friendUid != null) {
        NotificationService.sendPushNotification(
          recipientUid: friendUid,
          title: _currentUserName,
          body: "📷 Image",
          data: {
            'click_action': 'FLUTTER_NOTIFICATION_CLICK',
            'type': 'chat',
            'senderId': _currentUserId,
          },
        );
      }
    }
  }

  void _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final messageText = _messageController.text.trim();
    _messageController.clear();

    if (widget.chatType == 'ai') {
      setState(() {
        _messages.add(
          ChatMessage(
            text: messageText,
            senderId: _currentUserId,
            senderName: _currentUserName,
            senderProfileUrl: _auth.currentUser?.photoURL,
            timestamp: DateTime.now(),
            isMe: true,
          ),
        );
      });
      await _saveLocalMessages();
      _scrollToBottom();
      _handleAIResponse(messageText);
    } else {
      // Send to Firestore
      final friendUid = widget.friendUid;
      if (friendUid == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: Friend ID missing')),
        );
        return;
      }

      final chatId = _getChatId();
      final newMessage = {
        'text': messageText,
        'senderId': _currentUserId,
        'senderName': _currentUserName,
        'senderProfileUrl': _auth.currentUser?.photoURL,
        'receiverId': friendUid,
        'timestamp': FieldValue.serverTimestamp(),
      };

      // Send to Firestore
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add({
            ...newMessage,
            'isRead': false,
          });
      
      // Update last message, names, and increment unread count for friend
      print('DEBUG _sendMessage - Incrementing unread for friend: $friendUid');
      print('DEBUG _sendMessage - Chat ID: $chatId');
      
      // First ensure the chat document exists with proper structure
      final chatDoc = await FirebaseFirestore.instance.collection('chats').doc(chatId).get();
      
      Map<String, dynamic> updateData = {
        'lastMessage': messageText,
        'lastTimestamp': FieldValue.serverTimestamp(),
        'lastSenderId': _currentUserId,
        'lastSenderName': _currentUserName,
        'participantNames': {
          _currentUserId: _currentUserName,
          friendUid: widget.friendName ?? 'User',
        },
        'participantProfiles': {
          _currentUserId: _auth.currentUser?.photoURL,
        },
        'participants': [_currentUserId, friendUid],
      };
      
      // Initialize or increment unread count
      if (!chatDoc.exists || chatDoc.data()?['unreadCounts'] == null) {
        // First time - initialize the map
        print('DEBUG - Initializing unreadCounts map');
        updateData['unreadCounts'] = {
          _currentUserId: 0,
          friendUid: 1, // Friend has 1 unread
        };
      } else {
        // Already exists - just increment
        updateData['unreadCounts.$friendUid'] = FieldValue.increment(1);
      }
      
      await FirebaseFirestore.instance.collection('chats').doc(chatId).set(
        updateData,
        SetOptions(merge: true),
      );
      
      print('DEBUG _sendMessage - Unread count updated for $friendUid');

      // SEND PUSH NOTIFICATION
      NotificationService.sendPushNotification(
        recipientUid: friendUid, // friendUid is checked for null at line 1352
        title: _currentUserName,
        body: messageText,
        data: {
          'click_action': 'FLUTTER_NOTIFICATION_CLICK',
          'type': 'chat',
          'senderId': _currentUserId,
        },
      );

      _scrollToBottom();
    }
  }

  void _handleAIResponse(String messageText) {
    // Show typing indicator
    setState(() {
      _isTyping = true;
    });

    // Respond after a delay (simulating thinking time)
    final responseDelay = Duration(milliseconds: 1000 + Random().nextInt(2000));
    Future.delayed(responseDelay, () async {
      if (mounted) {
        setState(() {
          _isTyping = false;
          final responseText = _getAIResponse(messageText);

          _messages.add(
            ChatMessage(
              text: responseText,
              senderId: 'ai',
              senderName: 'AI Assistant',
              timestamp: DateTime.now(),
              isMe: false,
            ),
          );
        });
        // Save messages after receiving response
        await _saveLocalMessages();
        _scrollToBottom();
      }
    });
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatTitle = widget.chatType == 'ai'
        ? 'AI Assistant'
        : (widget.friendName ?? 'Friend');

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: widget.chatType == 'ai'
                    ? const LinearGradient(
                        colors: [Color(0xff250D57), Color(0xff38B6FF)],
                      )
                    : null,
                color: widget.chatType == 'friend' ? Colors.grey[300] : null,
              ),
              child: widget.chatType == 'ai'
                  ? const Icon(Icons.smart_toy, color: Colors.white, size: 20)
                  : Center(
                      child: Text(
                        chatTitle.isNotEmpty ? chatTitle[0].toUpperCase() : '?',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  chatTitle,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  widget.chatType == 'ai' ? 'Online' : 'Last seen recently',
                  style: const TextStyle(color: Colors.green, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.black),
            onPressed: () {
              // Add menu options here if needed
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages List
          Expanded(
            child: Container(
              color: Colors.grey[100],
              child: _currentUserId.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : widget.chatType == 'ai'
                  ? (_messages.isEmpty
                      ? const Center(
                          child: Text(
                            'No messages yet.\nStart a conversation!',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey, fontSize: 16),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16.0),
                          itemCount: _messages.length + (_isTyping ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == _messages.length && _isTyping) {
                              return _buildTypingIndicator();
                            }
                            final message = _messages[index];
                            return _buildMessageBubble(message, index);
                          },
                        ))
                  : StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('chats')
                          .doc(_getChatId())
                          .collection('messages')
                          .orderBy('timestamp', descending: false)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Center(child: Text('Error: ${snapshot.error}'));
                        }
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        final docs = snapshot.data?.docs ?? [];
                        if (docs.isEmpty) {
                          return const Center(
                            child: Text(
                              'No messages yet.\nStart a conversation!',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey, fontSize: 16),
                            ),
                          );
                        }

                        // Scroll to bottom when new messages arrive
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _scrollToBottom();
                        });

                        return ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16.0),
                          itemCount: docs.length,
                          itemBuilder: (context, index) {
                            final doc = docs[index];
                            final chatMsg = ChatMessage.fromFirestore(doc, _currentUserId);
                            return _buildMessageBubble(chatMsg, index, messageId: doc.id);
                          },
                        );
                      },
                    ),
            ),
          ),

          // Typing indicator
          if (_isTyping)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              alignment: Alignment.centerLeft,
              child: Text(
                '${chatTitle} is typing...',
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),

          // Message Input
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2),
                  spreadRadius: 1,
                  blurRadius: 5,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8.0,
                  vertical: 8.0,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: TextField(
                          controller: _messageController,
                          decoration: const InputDecoration(
                            hintText: 'Type a message...',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 10,
                            ),
                          ),
                          maxLines: null,
                          textCapitalization: TextCapitalization.sentences,
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // File attach button before send button
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(
                          Icons.attach_file,
                          color: Colors.black87,
                        ),
                        onPressed: _isUploading ? null : _showImageSourceDialog,
                        tooltip: 'Attach Image',
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Send button with app gradient colors
                    Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xff250D57), Color(0xff38B6FF)],
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.send, color: Colors.white),
                        onPressed: _sendMessage,
                        tooltip: 'Send',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, left: 0, right: 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.2),
              spreadRadius: 1,
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message, int index, {String? messageId}) {
    return GestureDetector(
      onLongPress: () {
        _showDeleteMessageDialog(index, messageId: messageId);
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: message.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!message.isMe) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.grey[300],
              backgroundImage: message.senderProfileUrl != null 
                  ? NetworkImage(message.senderProfileUrl!) 
                  : null,
              child: message.senderProfileUrl == null 
                  ? Text(message.senderName.isNotEmpty ? message.senderName[0].toUpperCase() : '?', 
                      style: const TextStyle(fontSize: 12, color: Colors.black87)) 
                  : null,
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.7,
              ),
              padding: const EdgeInsets.all(3), // Padding for border/shadow if needed
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    spreadRadius: 0,
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(message.isMe ? 20 : 4),
                  bottomRight: Radius.circular(message.isMe ? 4 : 20),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: message.isMe 
                        ? const LinearGradient(
                            colors: [Color(0xff250D57), Color(0xff38B6FF)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: message.isMe ? null : Colors.white,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!message.isMe)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            message.senderName,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: message.senderId == 'ai'
                                  ? const Color(0xff250D57)
                                  : Colors.grey[600],
                            ),
                          ),
                        ),
                      if (message.imageUrl != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              message.imageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => 
                                  const Icon(Icons.broken_image, size: 50, color: Colors.grey),
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return const Center(child: CircularProgressIndicator());
                              },
                            ),
                          ),
                        ),
                      if (message.text.isNotEmpty)
                        Text(
                          message.text,
                          style: TextStyle(
                            fontSize: 15, 
                            color: message.isMe ? Colors.white : Colors.black87,
                            height: 1.3,
                          ),
                        ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _formatTimestamp(message.timestamp),
                              style: TextStyle(
                                fontSize: 10, 
                                color: message.isMe ? Colors.white.withValues(alpha: 0.7) : Colors.grey[500],
                              ),
                            ),
                            if (message.isMe) ...[
                              const SizedBox(width: 4),
                              Icon(
                                Icons.done_all,
                                size: 14,
                                color: message.isRead ? const Color(0xff38B6FF) : Colors.white70,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteMessageDialog(int index, {String? messageId}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Message'),
        content: const Text('Are you sure you want to delete this message?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (widget.chatType == 'ai') {
                setState(() {
                  _messages.removeAt(index);
                });
                await _saveLocalMessages();
              } else if (messageId != null) {
                final chatId = _getChatId();
                await FirebaseFirestore.instance
                    .collection('chats')
                    .doc(chatId)
                    .collection('messages')
                    .doc(messageId)
                    .delete();
              }
              if (mounted) Navigator.pop(context);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Message deleted'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays == 0) {
      // Today - show time
      final hour = timestamp.hour;
      final minute = timestamp.minute.toString().padLeft(2, '0');
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      return '$displayHour:$minute $period';
    } else if (difference.inDays == 1) {
      // Yesterday
      final hour = timestamp.hour;
      final minute = timestamp.minute.toString().padLeft(2, '0');
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      return 'Yesterday $displayHour:$minute $period';
    } else {
      // Older
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
  }

  // Legacy sendPushNotification removed in favor of NotificationService
}
