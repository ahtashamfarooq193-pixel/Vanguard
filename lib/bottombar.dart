import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';

class MyBottomBar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onTap;

  const MyBottomBar({
    super.key,
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final db = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: 'https://emergency-alert-9cff6-default-rtdb.asia-southeast1.firebasedatabase.app',
    );

    return BottomNavigationBar(
      currentIndex: selectedIndex,
      selectedItemColor: const Color(0xff38B6FF),
      unselectedItemColor: Colors.grey,
      type: BottomNavigationBarType.fixed,
      onTap: onTap,
      items: [
        const BottomNavigationBarItem(
          icon: Icon(Icons.home),
          label: 'Home',
        ),
        BottomNavigationBarItem(
          icon: StreamBuilder<DatabaseEvent>(
            stream: db.ref('chats').onValue,
            builder: (context, snapshot) {
              int totalUnread = 0;
              if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
                final allChats = snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
                allChats.forEach((chatId, chatData) {
                  if (chatData is Map && chatData['unreadCount'] != null) {
                    final counts = chatData['unreadCount'] as Map<dynamic, dynamic>;
                    if (counts.containsKey(uid)) {
                      totalUnread += (counts[uid] as int? ?? 0);
                    }
                  }
                });
              }

              return Badge(
                label: Text(totalUnread.toString()),
                isLabelVisible: totalUnread > 0,
                child: const Icon(Icons.chat_bubble_outline),
              );
            },
          ),
          label: 'Chat',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.location_on),
          label: 'Location',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.person),
          label: 'Profile',
        ),
      ],
    );
  }
}