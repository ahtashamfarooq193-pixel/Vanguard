import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:my_app1/ForgotPassword/newpassword.dart';
import 'package:my_app1/ForgotPassword/resendotp.dart';
import 'package:my_app1/MainLayout/mainlayout.dart';


class Varification extends StatefulWidget {
  final String email;
  const Varification({super.key, required this.email});

  @override
  State<Varification> createState() => _VarificationState();
}

class _VarificationState extends State<Varification> {
  TextEditingController codeController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      content: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          SizedBox(height: 10),
          Text(
            "Verify Email",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              "We sent a code to ${widget.email}. \n Check your email to get started!",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
          ),
          SizedBox(height: 60),
          Container(
            width: 200,
            child: TextFormField(
              obscureText: false, // OTP is usually visible or obscured based on preference, removed fixed true
              controller: codeController,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              maxLength: 4,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 28,
                letterSpacing: 16,
              ),
              decoration: InputDecoration(
                counterText: '',
                hintText: '----',
                hintStyle: TextStyle(letterSpacing: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          ),

          SizedBox(height: 15),
          Row(
            children: [
              SizedBox(width: 20),
              Text("Didn't receive OTP"),
              SizedBox(width: 10),
              InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) {
                        return ResendOtp(email: widget.email);
                      },
                    ),
                  );
                },
                child: Text(
                  "Resend",
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
      ),
    );
  }
}
