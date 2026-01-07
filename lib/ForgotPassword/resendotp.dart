import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:my_app1/ForgotPassword/newpassword.dart';
import 'package:my_app1/MainLayout/mainlayout.dart';

class ResendOtp extends StatefulWidget {
  final String email;
  const ResendOtp({super.key, required this.email});

  @override
  State<ResendOtp> createState() => _ResendOtpState();
}

class _ResendOtpState extends State<ResendOtp> {
  TextEditingController codeController = TextEditingController();
  bool _isLoading = false;

  Future<void> _resendOtp() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final sendOtp = FirebaseFunctions.instanceFor(region: 'asia-south1').httpsCallable('sendOtp');
      await sendOtp.call(<String, dynamic>{
        'email': widget.email,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('OTP resent successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to resend OTP: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(content: Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        SizedBox(height: 10,),
        Text("Verify Email",style: TextStyle(fontSize: 20,fontWeight: FontWeight.bold),),
        SizedBox(height: 10,),
        Text("We sent a code to ${widget.email}. \n Check your email to get started!",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16),
        ),
        SizedBox(height: 60,),
        Container(
          width: 200,
          child: TextFormField(
            obscureText: false,
            controller: codeController,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            maxLength: 4,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: 16,
            ),
            decoration:InputDecoration(
              hintText: '____',
              counterText: '',
              hintStyle: TextStyle(letterSpacing: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              )
            ),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
            ],
          ),
        ),
        SizedBox(height: 15),
        Row(
          children: [
            SizedBox(width: 20),
            Text("Didn't receive OTP"),
            SizedBox(width: 10),
            InkWell(
              onTap: _isLoading ? null : _resendOtp,
              child: Text(
                _isLoading ? "Sending..." : "Resend",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.underline,
                  color: Colors.blue,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 25),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: SizedBox(
            height: 50,
            child: InkWell(
              onTap: () {
                if (codeController.text.length == 4) {
                   Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => NewPassword(
                        email: widget.email,
                        otp: codeController.text,
                      ),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a 4-digit code')),
                  );
                }
              },
              child: Container(
                height: 60,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xff250D57), Color(0xff38B6FF)],
                  ),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Center(
                  child: Text(
                    "Verify",
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ));
  }
}
