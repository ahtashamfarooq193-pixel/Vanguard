import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:my_app1/auth_gate.dart';
import 'package:my_app1/services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await Firebase.initializeApp();
    debugPrint('✅ Firebase Initialized');

    // Enable Realtime Database disk persistence
    final db = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: 'https://emergency-alert-9cff6-default-rtdb.asia-southeast1.firebasedatabase.app',
    );
    db.setPersistenceEnabled(true);
    
    // Background init for notifications
    NotificationService.initialize().catchError((e) => debugPrint('❌ Notification Error: $e'));
  } catch (e) {
    debugPrint('❌ Critical App Init Error: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Vanguard',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff250D57)),
      ),
      // THE PROFESSIONAL WAY: Use AuthGate to handle auth state globally
      home: const AuthGate(),
    );
  }
}
