import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:my_app1/MainLayout/mainlayout.dart';
import 'package:my_app1/SignUp/countries.dart';

class NamePage extends StatefulWidget {
  const NamePage({super.key});

  @override
  State<NamePage> createState() => _NamePageState();
}

class _NamePageState extends State<NamePage> {
  final _formKey = GlobalKey<FormState>();
  TextEditingController nameController = TextEditingController();
  TextEditingController lastNameController = TextEditingController();
  bool _isLoading = false;

  Future<void> _saveName() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });
      try {
        User? user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          String fullName = "${nameController.text.trim()} ${lastNameController.text.trim()}";
          await user.updateDisplayName(fullName.trim());
          
          // Update Firestore document with full name
          await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
            'fullName': fullName.trim(),
          });
          
          await user.reload(); // Reload to ensure local user object is updated
          
          if (mounted) {
             Navigator.push(context, MaterialPageRoute(builder: (context){
                return Countries();
              }));
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error saving name: $e")),
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
    return MainLayout(content: Column(

      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        SizedBox(height: 20,),
        Text('Enter Your Name',style: TextStyle(fontSize: 22,fontWeight: FontWeight.bold),),
        SizedBox(height: 10),
        Text('Enter your name so that family and \n friends can identify you. ',style:TextStyle(fontSize: 16)
          ,),
        SizedBox(height: 35,),
        Form(key: _formKey,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal:10),
                child: TextFormField(
                  controller: nameController,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: "1st Name",
                    hintText: "First Name",
                    hintStyle: TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  validator:(value){
                    if (value == null || value.isEmpty){
                      return "Fill the 1st Name";
                    }
                    if (value.length >20){
                      return "Maximum character use 20";
                    }

                    return null;
                  },
                ),

            ),
          ],
        ),),
      SizedBox(height: 10,),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal:10),
            child: TextFormField(
              controller: lastNameController,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: "Last Name",
                hintText: "Enter Your 2nd Name",
                hintStyle: TextStyle(color: Colors.grey),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
        ),
        SizedBox(height: 20,),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal:10),
          child: SizedBox(height: 50,
            child: InkWell(
              onTap: _isLoading ? null : _saveName,
              child: Container(
                height: 60,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    Color(0xff250D57), Color(0xff38B6FF),
                  ]),borderRadius: BorderRadius.circular(30),
                ),
                child: Center(child: _isLoading ? CircularProgressIndicator(color: Colors.white) : Text("Continue",style: TextStyle(fontSize: 20,color: Colors.white),)),
              ),
            ),
          ),
        ),
      ],

    ));
  }
}
