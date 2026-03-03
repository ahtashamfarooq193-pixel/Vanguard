import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        height: double.infinity,
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xff250D57),
              Color(0xff38B6FF),
            ],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Safe image loading
            Image.asset("assets/Images/logo.png", height: 200, errorBuilder: (c, e, s) => const Icon(Icons.security, size: 100, color: Colors.white)),
            const SizedBox(height: 30),
            const Text(
              "VANGUARD",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 28, letterSpacing: 2),
            ),
            const SizedBox(height: 10),
            const Text(
              "Let family & friends know you're safe!",
              style: TextStyle(color: Colors.white70, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 50),
            const CircularProgressIndicator(color: Colors.white70),
          ],
        ),
      ),
    );
  }
}
