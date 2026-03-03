// lib/widgets/main_layout.dart

import 'package:flutter/material.dart';

class MainLayout extends StatelessWidget {
  final Widget content;
  final Widget? bottomNavigationBar;

  const MainLayout({required this.content, this.bottomNavigationBar, super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xff250D57), // Deep Violet/Navy
              Color(0xff38B6FF), // Bright Blue
            ],
          ),
        ),
        child: Column(
          children: [
            Expanded(
              flex: 1, // 25% of the screen
              child: Container(
                width: double.infinity,
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Vanguard",
                      style: TextStyle(
                        fontSize: 34, // Slightly smaller font to fit well
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 1.2,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      "Let family & friends know you're safe!",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 3, // 75% of the screen
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(30),
                    topRight: Radius.circular(30),
                  ),
                ),
                child: SingleChildScrollView(
                  child: content,
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}