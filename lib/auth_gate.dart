import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:my_app1/Dashboard/homepage.dart';
import 'package:my_app1/SignUp/loginscreen.dart';
import 'package:my_app1/Splashscreen/splashscreen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SplashScreen(); 
        }
        
        if (snapshot.hasData) {
          return const HomePage();
        }
        
        return const LoginPage();
      },
    );
  }
}
