import 'package:flutter/material.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final List<Map<String, String>> _mockNotifications = [
    {
      'title': 'Welcome to Vanguard',
      'body': 'Thank you for joining us. Stay safe!',
      'time': 'Just now',
      'icon': 'notifications'
    },
    {
      'title': 'App Update',
      'body': 'Version 2.0.1 is now available for local testing.',
      'time': '2 hours ago',
      'icon': 'system_update'
    },
    {
      'title': 'Safety Tip',
      'body': 'Remember to add emergency contacts for alert features.',
      'time': 'Yesterday',
      'icon': 'security'
    }
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _mockNotifications.isEmpty
          ? const Center(child: Text('No notifications yet.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _mockNotifications.length,
              separatorBuilder: (context, index) => const Divider(),
              itemBuilder: (context, index) {
                final data = _mockNotifications[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xff38B6FF).withOpacity(0.1),
                    child: Icon(_getIcon(data['icon'] ?? 'notifications'), color: const Color(0xff38B6FF)),
                  ),
                  title: Text(data['title']!, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(data['body']!),
                      const SizedBox(height: 4),
                      Text(
                        data['time']!,
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  IconData _getIcon(String iconName) {
    switch (iconName) {
      case 'system_update':
        return Icons.system_update_alt;
      case 'security':
        return Icons.security_rounded;
      case 'emergency':
        return Icons.emergency_share;
      case 'person_add':
        return Icons.person_add;
      default:
        return Icons.notifications;
    }
  }
}
