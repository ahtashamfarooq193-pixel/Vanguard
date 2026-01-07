import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:my_app1/MainLayout/mainlayout.dart';
import 'package:my_app1/SignUp/loginscreen.dart';

class NewPassword extends StatefulWidget {
  final String email;
  final String otp;
  const NewPassword({super.key, required this.email, required this.otp});

  @override
  State<NewPassword> createState() => _NewPasswordState();
}

class _NewPasswordState extends State<NewPassword> {
  final _formKey = GlobalKey<FormState>();
  TextEditingController _passwordController = TextEditingController();
  TextEditingController _confirmpasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  Future<void> _resetPassword() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        final resetPassword = FirebaseFunctions.instanceFor(region: 'asia-south1').httpsCallable('resetPasswordWithOtp');
        await resetPassword.call(<String, dynamic>{
          'email': widget.email,
          'otp': widget.otp,
          'newPassword': _passwordController.text.trim(),
        });

        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Password successfully changed!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (context) => LoginPage(),
            ),
            (route) => false,
          );
        }
      } catch (e) {
        if (mounted) {
           String message = "Failed to reset password.";
           if (e is FirebaseFunctionsException) {
             message = e.message ?? message;
           }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
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
  }

  @override
  Widget build(BuildContext context) {
    return
    MainLayout(
      content: Padding(
        padding: const EdgeInsets.all(10),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              SizedBox(height: 10),
              Text(
                "Set a New Password",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
              ),
              SizedBox(height: 05),
              Text(
                "Create a strong password to secure your \n account",
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 30),
              Row(
                children: [
                  SizedBox(width: 15),
                  Text("New Password:", style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              SizedBox(height: 5),
              TextFormField(
                obscureText: _obscurePassword,
                controller: _passwordController,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  hintText: "Enter Password",
                  prefixIcon: Icon(Icons.lock, color: Colors.grey),
                  hintStyle: TextStyle(color: Colors.grey),
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    color: Colors.grey,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return "Enter the Password";
                  }
                  if (value.length < 8) {
                    return 'Choose minimum 8 character Password';
                  }
                  return null;
                },
              ),
              SizedBox(height: 10),
              Row(
                children: [
                  SizedBox(width: 15),
                  Text(
                    'Confirm Password:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              SizedBox(height: 5),
              TextFormField(
                controller: _confirmpasswordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  hintText: 'Confirm Your Password',
                  hintStyle: TextStyle(color: Colors.grey),
                  prefixIcon: Icon(Icons.lock, color: Colors.grey),
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: Colors.grey,
                    ),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Confirm Your Password';
                  }
                  if (value != _passwordController.text) {
                    return 'Password does not match';
                  }
                  return null;
                },
              ),
              SizedBox(height: 25),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: SizedBox(
                  height: 50,
                  child: InkWell(
                    onTap: _isLoading ? null : _resetPassword,
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
                        child: _isLoading 
                          ? CircularProgressIndicator(color: Colors.white)
                          : Text(
                            "Reset Password", // Corrected text
                            style: TextStyle(color: Colors.white, fontSize: 18),
                          ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
