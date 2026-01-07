import 'package:flutter/material.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Privacy Policy',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 30),
            _buildSection(
              '1. Data Collection',
              'We collect minimal data required to keep you safe, including your email, full name, and emergency contacts. This information is stored securely in our encrypted database.',
            ),
            _buildSection(
              '2. Location Sharing',
              'Your location is ONLY shared with your designated emergency contacts and ONLY when you trigger an emergency alert. We do not track you in the background for any other purpose.',
            ),
            _buildSection(
              '3. Emergency Alerts',
              'By using this app, you acknowledge that alerts are sent via the internet. While we strive for 100% reliability, message delivery depends on your network provider.',
            ),
            _buildSection(
              '4. User Responsibility',
              'Users are responsible for keeping their emergency contact list updated. False alerts should be avoided to ensure that the system remains effective for real emergencies.',
            ),
            _buildSection(
              '5. Chat Privacy',
              'All chats between users and with the AI assistant are private. We do not share your conversations with third parties.',
            ),
            const SizedBox(height: 40),
            _buildFooter(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xff250D57), Color(0xff38B6FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: const [
          Icon(Icons.privacy_tip_outlined, color: Colors.white, size: 50),
          SizedBox(height: 15),
          Text(
            'Your Security, Our Priority',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 5),
          Text(
            'Last Updated: Jan 2026',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 25.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xff250D57),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            content,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black87,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Center(
      child: Text(
        'Thank you for trusting us with your safety.',
        style: TextStyle(
          fontSize: 14,
          fontStyle: FontStyle.italic,
          color: Colors.grey[600],
        ),
      ),
    );
  }
}
