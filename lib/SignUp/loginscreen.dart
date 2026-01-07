import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:my_app1/Dashboard/homepage.dart';
import 'package:my_app1/ForgotPassword/forgotpasswordscreen.dart';
import 'package:my_app1/MainLayout/mainlayout.dart';

import 'package:my_app1/SignUp/signup.dart';


class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState(); // Note: kept original state class
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _rememberMe = false;
  bool _obscurePassword = true;
  @override
  Widget build(BuildContext context) {
    return MainLayout(
      content: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          SizedBox(height: 20),
          Center(
            child: Text(
              "WELCOME",
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ),
          SizedBox(height: 05),
          Center(
            child: Text(
              "Stay safe and connected as your \n quick alert starts here",
              style: TextStyle(fontSize: 16),
            ),
          ),
          SizedBox(height: 20),
             Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: TextFormField(
                textInputAction: TextInputAction.next,
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: "Email",
                  hintText: " Enter Email",
                  prefixIcon: Icon(Icons.email,color: Colors.grey,),
                  hintStyle: TextStyle(color: Colors.grey),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
          SizedBox(height: 10),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  hintText: "Password",
                  labelText: "Password",
                  prefixIcon: Icon(Icons.lock,color: Colors.grey,),
                  hintStyle: TextStyle(color: Colors.grey),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: Colors.grey,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),

          SizedBox(height: 3),
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Checkbox(
                value: _rememberMe,
                onChanged: (value) {
                  setState(() {
                    _rememberMe = value ?? false;
                  });
                },
              ),
              Text("Remember Me"),
              SizedBox(width: 83),
              InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) {
                        return Forgotpass();
                      },
                    ),
                  );
                },
                child: Text("Forgot Password",style: TextStyle(color: Colors.blue,fontWeight: FontWeight.bold),),
              ),
            ],
          ),
          SizedBox(height: 20),
          InkWell(
            onTap: () async {
              if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
                 ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Please fill in all fields")),
                 );
                 return;
              }
              try {
                await FirebaseAuth.instance.signInWithEmailAndPassword(
                  email: _emailController.text.trim(),
                  password: _passwordController.text.trim(),
                );
                if (context.mounted) {
                  Navigator.pushReplacement( // Use pushReplacement to prevent going back to login
                    context,
                    MaterialPageRoute(
                      builder: (context) {
                        return HomePage();
                      },
                    ),
                  );
                }
              } on FirebaseAuthException catch (e) {
                 String message = "Login Failed";
                 if (e.code == 'user-not-found') {
                    message = 'No user found for that email.';
                 } else if (e.code == 'wrong-password') {
                    message = 'Wrong password provided.';
                 } else if (e.code == 'invalid-email') {
                    message = "Invalid email format.";
                 } else if (e.code == 'invalid-credential') {
                    message = "Invalid credentials.";
                 }
                 if (context.mounted) {
                   ScaffoldMessenger.of(context).showSnackBar(
                     SnackBar(content: Text(message)),
                   );
                 }
              } catch (e) {
                  if (context.mounted) {
                   ScaffoldMessenger.of(context).showSnackBar(
                     SnackBar(content: Text("Error: ${e.toString()}")),
                   );
                 }
              }
            },
            child: SizedBox(
              height: 50,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Container(
                  height: 60,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(25),
                    gradient: LinearGradient(
                      colors: [Color(0xff250D57), Color(0xff38B6FF)],
                    ),
                  ),
                  child: Center(
                    child: Text(
                      "Log IN",
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text("Don't have an account?"),
              SizedBox(width: 10),
              InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) {
                        return SignUp();
                      },
                    ),
                  );
                },
                child: Text(
                  "Sign Up",
                  style: TextStyle(fontWeight: FontWeight.bold,decoration: TextDecoration.underline,color: Colors.blue),
                ),
              ),
            ],
          ),
          SizedBox(height: 30),
        ],
      ),
    );
  }
}
