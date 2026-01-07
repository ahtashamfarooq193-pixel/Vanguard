import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:my_app1/Dashboard/notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:my_app1/bottombar.dart';
import 'package:my_app1/Dashboard/chat.dart';
import 'package:my_app1/Dashboard/location.dart';
import 'package:my_app1/Dashboard/profile.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:my_app1/services/notification_service.dart';

class HomePage extends StatefulWidget {
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  List<Map<String, String>> _emergencyContacts = [];
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String? _currentUserId;
  String? _currentUserName;
  StreamSubscription<QuerySnapshot>? _chatsSubscription;
  DateTime? _lastNotificationCheck;

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _initUser();
    _setupNotificationListener();
    _lastNotificationCheck = DateTime.now();
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
                        // Navigate to Chat Selection
                        setState(() { _selectedIndex = 1; });
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const ChatSelectionScreen()));
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
    final user = _auth.currentUser;
    if (user != null) {
      String name = user.displayName ?? 'Emergency User';
      try {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (userDoc.exists) {
          final data = userDoc.data();
          name = data?['fullName'] ?? data?['username'] ?? name;
        }

        // Save FCM Token
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null) {
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
            'fcmToken': token,
            'lastActive': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }

      } catch (e) {
        print('Error fetching user name: $e');
      }
      setState(() {
        _currentUserId = user.uid;
        _currentUserName = name;
      });
    }
  }

  String _getChatId(String otherUid) {
    if (_currentUserId == null) return '';
    List<String> ids = [_currentUserId!, otherUid];
    ids.sort();
    return ids.join('_');
  }

  Future<void> _sendEmergencyAlert(String alertType) async {
    if (_currentUserId == null || _emergencyContacts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add emergency contacts first!')),
      );
      return;
    }

    // Show sending dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final messageText = "🚨 EMERGENCY ALERT: $alertType! I need help. My last known location is being shared.";
      int sentCount = 0;

      for (var contact in _emergencyContacts) {
        final friendUid = contact['uid'];
        if (friendUid == null) continue;

        final chatId = _getChatId(friendUid);

        // Send to Firestore
        await FirebaseFirestore.instance
            .collection('chats')
            .doc(chatId)
            .collection('messages')
            .add({
          'text': messageText,
          'senderId': _currentUserId,
          'senderName': _currentUserName,
          'timestamp': FieldValue.serverTimestamp(),
          'isAlert': true,
        });
        
        // Update chat document metadata for notifications and "Recent" list
        await FirebaseFirestore.instance.collection('chats').doc(chatId).set({
          'lastMessage': '🚨 EMERGENCY: $alertType',
          'lastTimestamp': FieldValue.serverTimestamp(),
          'lastSenderId': _currentUserId,
          'lastSenderName': _currentUserName,
          'participantNames': {
            _currentUserId: _currentUserName,
            friendUid: contact['name'] ?? 'User',
          },
          'participants': [_currentUserId, friendUid],
        }, SetOptions(merge: true));

        // Add to notifications collection for the friend
        await FirebaseFirestore.instance.collection('notifications').add({
          'userId': friendUid,
          'title': '🚨 EMERGENCY ALERT',
          'body': '$_currentUserName triggered a $alertType alert!',
          'time': FieldValue.serverTimestamp(),
          'icon': 'emergency',
          'timestamp': FieldValue.serverTimestamp(),
        });

        // Update last message in chat document
        await FirebaseFirestore.instance.collection('chats').doc(chatId).set({
          'lastMessage': messageText,
          'lastTimestamp': FieldValue.serverTimestamp(),
          'participants': [_currentUserId, friendUid],
        }, SetOptions(merge: true));

        // SEND PUSH NOTIFICATION
        NotificationService.sendPushNotification(
          recipientUid: friendUid,
          title: '🚨 EMERGENCY ALERT',
          body: '$_currentUserName triggered a $alertType alert!',
          data: {
            'click_action': 'FLUTTER_NOTIFICATION_CLICK',
            'type': 'emergency',
            'senderId': _currentUserId,
          },
        );
        
        sentCount++;
      }

      if (context.mounted) Navigator.pop(context); // Remove loading

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Alert sent to $sentCount contact(s)!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) Navigator.pop(context); // Remove loading
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sending alert: $e')),
        );
      }
    }
  }

  Future<void> _loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final String? contactsJson = prefs.getString('emergency_contacts');
    if (contactsJson != null) {
      setState(() {
        _emergencyContacts = List<Map<String, String>>.from(
          (json.decode(contactsJson) as List).map((item) => Map<String, String>.from(item))
        );
      });
    }
  }

  Future<void> _saveContacts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('emergency_contacts', json.encode(_emergencyContacts));
  }

  void _addContact() {
    final nameController = TextEditingController();
    final emailController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Emergency Contact', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: 'Registered Email or Phone', hintText: 'Enter email or phone (+92...)'),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (emailController.text.isNotEmpty) {
                final input = emailController.text.trim().toLowerCase();
                
                // Show loading
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => const Center(child: CircularProgressIndicator()),
                );

                try {
                  // Search for user by email
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
                      // Check if already in list
                      bool exists = _emergencyContacts.any((c) => c['uid'] == friendUid || c['email'] == friendEmail);
                      if (!exists) {
                        _emergencyContacts.add({
                          'name': friendName!,
                          'email': friendEmail!,
                          'uid': friendUid!,
                        });
                      }
                    });

                    // Add notification for the friend
                    try {
                      await FirebaseFirestore.instance.collection('notifications').add({
                        'userId': friendUid,
                        'title': 'New Contact Request',
                        'body': '${_currentUserName ?? "A user"} added you as an emergency contact.',
                        'time': FieldValue.serverTimestamp(),
                        'icon': 'person_add',
                        'timestamp': FieldValue.serverTimestamp(),
                      });

                      // SEND PUSH NOTIFICATION
                      NotificationService.sendPushNotification(
                        recipientUid: friendUid,
                        title: 'New Emergency Contact',
                        body: '${_currentUserName ?? "A user"} added you as an emergency contact.',
                        data: {
                          'click_action': 'FLUTTER_NOTIFICATION_CLICK',
                          'type': 'contact_add',
                          'senderId': _currentUserId,
                        },
                      );

                    } catch (e) {
                      print('Error sending notification: $e');
                    }

                    _saveContacts();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Contact added successfully!'), duration: Duration(seconds: 1)),
                      );
                      Navigator.pop(context); // Close add dialog
                    }
                  } else {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Account not found with this email or phone.')),
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
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff38B6FF)),
            child: const Text('Add', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _removeContact(int index) {
    setState(() {
      _emergencyContacts.removeAt(index);
    });
    _saveContacts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],

      // Top app bar
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        title: Row(
          children: [
            Image.asset('assets/Images/logo.png', height: 40),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Emergency Alert',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.notifications_outlined, color: Colors.black),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const NotificationsScreen()),
                );
              },
            ),
          ],
        ),

      ),

      // Main content
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Accounts/Contacts Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Emergency Accounts',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  TextButton.icon(
                    onPressed: _addContact,
                    icon: const Icon(Icons.add, size: 20, color: Color(0xff38B6FF)),
                    label: const Text('Add', style: TextStyle(color: Color(0xff38B6FF))),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: _emergencyContacts.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                          child: Text('No emergency contacts added yet.', style: TextStyle(color: Colors.grey)),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _emergencyContacts.length,
                        itemBuilder: (context, index) {
                          final contact = _emergencyContacts[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: Colors.blue.withValues(alpha: 0.1),
                              child: const Icon(Icons.person, color: Colors.blue),
                            ),
                            title: Text(contact['name']!, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(contact['email']!),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                              onPressed: () => _removeContact(index),
                            ),
                          );
                        },
                      ),
              ),

              SizedBox(height: 20),

              // Description text
              Text(
                'By pressing any of the following alerts, you\'ll be notifying all your emergency contacts of your last known location.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[700]),
              ),

              SizedBox(height: 20),

              // Accident Alert Button
              _buildAlertButton(
                color: Colors.orange,
                icon: Icons.car_crash,
                text: 'Accident Alert',
                onPressed: () => _sendEmergencyAlert('ACCIDENT'),
              ),

              SizedBox(height: 15),

              // Kidnapping Alert Button
              _buildAlertButton(
                color: Colors.red,
                icon: Icons.person_off,
                text: 'Kidnapping Alert',
                onPressed: () => _sendEmergencyAlert('KIDNAPPING'),
              ),

              SizedBox(height: 15),

              // Robbery Alert Button
              _buildAlertButton(
                color: Colors.green,
                icon: Icons.warning,
                text: 'Robbery Alert',
                onPressed: () => _sendEmergencyAlert('ROBBERY'),
              ),

              SizedBox(height: 20),

              // OR text
              Text(
                'OR',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              ),

              SizedBox(height: 20),

              // Shout Alert Button
              _buildAlertButton(
                color: Colors.blue,
                icon: Icons.campaign,
                text: 'Shout Alert',
                onPressed: () => _sendEmergencyAlert('SHOUT'),
              ),

              SizedBox(height: 10),

              // Audio record text
              Text(
                'Hold to send a 5 second audio record',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),

              SizedBox(height: 20),

              const SizedBox(height: 20),
              // Tips Section (instead of second ads)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xff250D57), Color(0xff38B6FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lightbulb_outline, color: Colors.white, size: 30),
                    const SizedBox(width: 15),
                    const Expanded(
                      child: Text(
                        'Tip: Long-press any alert to see more options or cancel.',
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 80), // Bottom bar ke liye space
            ],
          ),
        ),
      ),

      // Apka bottom bar yahan!
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
              nextScreen = HomePage();
          }

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => nextScreen),
          );
        },
      ),
    );
  }

  // Yeh function alert buttons banata hai
  Widget _buildAlertButton({
    required Color color,
    required IconData icon,
    required String text,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: () async {
        onPressed();
        
        // Add notification for the button click
        if (_currentUserId != null) {
          try {
            await FirebaseFirestore.instance.collection('notifications').add({
              'userId': _currentUserId,
              'title': 'Alert Triggered',
              'body': 'You have successfully triggered the $text.',
              'time': FieldValue.serverTimestamp(),
              'icon': 'emergency',
              'timestamp': FieldValue.serverTimestamp(),
            });
          } catch (e) {
            print('Error adding notification: $e');
          }
        }
      },
      child: Container(
        height: 60,
        width: double.infinity,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 28),
            SizedBox(width: 12),
            Text(
              text,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}