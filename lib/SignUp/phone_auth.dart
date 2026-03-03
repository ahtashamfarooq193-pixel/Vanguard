import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:my_app1/Dashboard/homepage.dart';
import 'package:my_app1/MainLayout/mainlayout.dart';

class PhoneAuthPage extends StatefulWidget {
  const PhoneAuthPage({super.key});

  @override
  State<PhoneAuthPage> createState() => _PhoneAuthPageState();
}

class _PhoneAuthPageState extends State<PhoneAuthPage> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String _verificationId = "";
  bool _isOTPSent = false;
  bool _isLoading = false;

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  // Step 1: Request OTP
  Future<void> _verifyPhoneNumber() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty || !phone.startsWith('+')) {
      _showError("Please enter phone number with country code (e.g. +92...)");
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Auto-resolution (on some Android devices)
          await _auth.signInWithCredential(credential);
          if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HomePage()));
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() => _isLoading = false);
          _showError(e.message ?? "Verification failed");
        },
        codeSent: (String verId, int? resendToken) {
          setState(() {
            _verificationId = verId;
            _isOTPSent = true;
            _isLoading = false;
          });
        },
        codeAutoRetrievalTimeout: (String verId) {
          _verificationId = verId;
        },
      );
    } catch (e) {
      setState(() => _isLoading = false);
      _showError("An error occurred: $e");
    }
  }

  // Step 2: Verify OTP
  Future<void> _signInWithOTP() async {
    final otp = _otpController.text.trim();
    if (otp.isEmpty || otp.length < 6) {
      _showError("Enter valid 6-digit OTP");
      return;
    }

    setState(() => _isLoading = true);

    try {
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: otp,
      );

      await _auth.signInWithCredential(credential);
      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HomePage()));
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showError("Invalid OTP code!");
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      content: Padding(
        padding: const EdgeInsets.all(25.0),
        child: Column(
          children: [
            const SizedBox(height: 30),
            Icon(Icons.phone_android_rounded, size: 80, color: Color(0xff250D57)),
            const SizedBox(height: 20),
            Text(
              _isOTPSent ? "Verify Code" : "Phone Registration",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              _isOTPSent 
                ? "Enter the 6-digit code sent to your phone" 
                : "Enter your phone number to receive a secure code",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 40),

            if (!_isOTPSent) ...[
              // Phone Input
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: "Phone Number",
                  hintText: "+92 300 1234567",
                  prefixIcon: Icon(Icons.phone),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                ),
              ),
              const SizedBox(height: 30),
              _isLoading 
                ? CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _verifyPhoneNumber,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xff250D57),
                      minimumSize: Size(double.infinity, 55),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: Text("GET CODE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
            ] else ...[
              // OTP Input
              TextFormField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, letterSpacing: 10, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  counterText: "",
                  hintText: "000000",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                ),
              ),
              const SizedBox(height: 30),
              _isLoading 
                ? CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _signInWithOTP,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xff38B6FF),
                      minimumSize: Size(double.infinity, 55),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: Text("VERIFY & SIGN UP", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
              TextButton(
                onPressed: () => setState(() => _isOTPSent = false),
                child: Text("Change Number", style: TextStyle(color: Colors.grey)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
