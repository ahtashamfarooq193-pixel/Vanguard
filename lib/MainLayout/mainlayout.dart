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
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xff6A5ACD).withValues(alpha: 0.5),
              Color(0xff9B59B6).withValues(alpha: 0.6),
              Color(0xffF4A261).withValues(alpha: 0.6),
            ],
          ),
        ),
        child: Column(
          children: [
            Expanded(
              flex: 5,
              child: Container(
                width: double.infinity,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      "assets/Images/logo.png",
                      scale: 2.5,
                    ),
                    const Text(
                      "Let family & friends know \n you're safe!",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 21,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 6,
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