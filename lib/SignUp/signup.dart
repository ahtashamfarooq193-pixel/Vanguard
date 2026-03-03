import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:my_app1/MainLayout/mainlayout.dart';
import 'package:my_app1/SignUp/loginscreen.dart';
import 'package:my_app1/SignUp/privacyterm.dart';
import 'package:my_app1/Dashboard/homepage.dart';
import 'package:my_app1/auth_gate.dart';

class SignUp extends StatefulWidget {
  const SignUp({super.key});

  @override
  State<SignUp> createState() => _SignUpState();
}

class _SignUpState extends State<SignUp> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _agreeToTerms = false;

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.red));
  }

  Future<void> _handleSignUp() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreeToTerms) {
      _showError("Please agree to the Privacy Policy & Terms");
      return;
    }

    setState(() => _isLoading = true);
    try {
      // Create user in Firebase
      final UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // Update Display Name if user provided username here
      if (userCredential.user != null) {
        final user = userCredential.user!;
        final name = _usernameController.text.trim();
        await user.updateDisplayName(name);

        // Save to Firestore
        final token = await FirebaseMessaging.instance.getToken();
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'name': name,
          'email': user.email,
          'photoUrl': user.photoURL, // Cloudinary or Google photoUrl
          'fcmToken': token,
          'createdAt': FieldValue.serverTimestamp(),
          'lastTokenUpdate': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      if (mounted) {
        // Proceed directly to AuthGate (frictionless sign-up flow)
        Navigator.pushAndRemoveUntil(
          context, 
          MaterialPageRoute(builder: (_) => const AuthGate()),
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? "Registration failed");
    } catch (e) {
      _showError("An unexpected error occurred: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = const Color(0xff250D57);
    final accentColor = const Color(0xff38B6FF);

    return MainLayout(
      content: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            const SizedBox(height: 30),
            const Text("Create Your Account", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text("Sign up to send alerts and stay protected anytime", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 40),
            
            Form(
              key: _formKey,
              child: Column(
                children: [
                  _buildTextField(_usernameController, "User Name", Icons.person_outline),
                  const SizedBox(height: 15),
                  _buildTextField(_emailController, "Email", Icons.email_outlined, isEmail: true),
                  const SizedBox(height: 15),
                  _buildTextField(
                    _passwordController, 
                    "Password", 
                    Icons.lock_outline, 
                    isPassword: true,
                    obscure: _obscurePassword,
                    onToggle: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 10),
            
            Row(
              children: [
                Checkbox(value: _agreeToTerms, onChanged: (v) => setState(() => _agreeToTerms = v ?? false)),
                const Text("I Agree to your "),
                GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyTerm())),
                  child: const Text("Privacy Policy & Terms", style: TextStyle(fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
                ),
              ],
            ),
            
            const SizedBox(height: 30),
            
            _isLoading 
              ? const CircularProgressIndicator()
              : ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                  ),
                  onPressed: _handleSignUp,
                  child: Ink(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [themeColor, accentColor]),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Container(
                      height: 55,
                      alignment: Alignment.center,
                      child: const Text("GET STARTED", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                ),
            
            const SizedBox(height: 25),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("Already have an account?"),
                TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage())),
                  child: const Text("Sign In", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {bool isPassword = false, bool isEmail = false, bool obscure = false, VoidCallback? onToggle}) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: isEmail ? TextInputType.emailAddress : TextInputType.text,
      validator: (value) {
        if (value == null || value.isEmpty) return "Please enter your $label";
        if (isEmail && !value.contains('@')) return "Enter a valid email";
        if (isPassword && value.length < 6) return "Password must be at least 6 characters";
        return null;
      },
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.grey),
        suffixIcon: isPassword 
            ? IconButton(icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, color: Colors.grey), onPressed: onToggle)
            : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.symmetric(vertical: 18),
      ),
    );
  }
}
