import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_app1/MainLayout/mainlayout.dart';
import 'package:my_app1/SignUp/loginscreen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:my_app1/bottombar.dart';
import 'package:my_app1/Dashboard/homepage.dart';
import 'package:my_app1/Dashboard/chat.dart';
import 'package:my_app1/Dashboard/location.dart';
import 'package:my_app1/ForgotPassword/forgotpasswordscreen.dart';
import 'package:my_app1/Dashboard/privacypolicy.dart';
import 'package:my_app1/services/cloudinary_service.dart';

class Profile extends StatefulWidget {
  const Profile({super.key});

  @override
  State<Profile> createState() => _ProfileState();
}

class _ProfileState extends State<Profile> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ImagePicker _picker = ImagePicker();
  int _selectedIndex = 3;
  String _bio = "Add a bio...";
  String _phone = "Add phone number";
  String? _localImagePath;
  String? _profilePictureUrl; // Cloudinary URL
  bool _notificationsEnabled = true;
  bool _isUploading = false; // Track upload state

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _bio = prefs.getString('user_bio') ?? "Software Developer at TechCorp";
      _phone = prefs.getString('user_phone') ?? "+92 300 1234567";
      _localImagePath = prefs.getString('profile_image_path');
      _profilePictureUrl = prefs.getString('profile_image_url'); // Load Cloudinary URL
      _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
    });
  }

  Future<void> _saveProfileData(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is String) {
      await prefs.setString(key, value);
    } else if (value is bool) {
      await prefs.setBool(key, value);
    }

    // Sync with Firestore if user is logged in
    final user = _auth.currentUser;
    if (user != null) {
      final updateData = <String, dynamic>{};
      if (key == 'user_bio') updateData['bio'] = value;
      if (key == 'user_phone') updateData['phone'] = value;
      if (key == 'display_name') updateData['fullName'] = value;
      if (key == 'notifications_enabled') updateData['notificationsEnabled'] = value;
      if (key == 'profile_image_path') updateData['profileImagePath'] = value;

      if (updateData.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set(updateData, SetOptions(merge: true));
      }
    }
  }

  Future<void> _updateProfilePicture() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1080,
        maxHeight: 1080,
        imageQuality: 85,
      );
      if (image == null) return;

      setState(() {
        _isUploading = true;
        _localImagePath = image.path; // Show preview immediately
      });

      // Upload to Cloudinary
      final imageUrl = await CloudinaryService.uploadImage(image.path);

      if (imageUrl != null) {
        setState(() {
          _profilePictureUrl = imageUrl;
          _isUploading = false;
        });
        
        // Save URL to Firestore and local storage
        await _saveProfileData('profile_image_url', imageUrl);
        _showSnackBar('Profile picture updated successfully!');
      } else {
        setState(() {
          _isUploading = false;
          _localImagePath = null;
        });
        _showSnackBar('Failed to upload image');
      }
    } catch (e) {
      setState(() {
        _isUploading = false;
        _localImagePath = null;
      });
      _showSnackBar('Error updating image: $e');
    }
  }

  Future<void> _editField(String title, String currentVal, String key) async {
    TextEditingController controller = TextEditingController(text: currentVal);
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Update $title", style: TextStyle(color: Color(0xff250D57), fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: "Enter $title",
            filled: true,
            fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancel", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () async {
              String newValue = controller.text.trim();
              if (newValue.isEmpty) return;

              if (key == 'user_phone') {
                Navigator.pop(context); // Close edit dialog
                _startPhoneVerification(newValue);
              } else {
                setState(() {
                  if (key == 'user_bio') _bio = newValue;
                  if (key == 'display_name') {
                    _auth.currentUser?.updateDisplayName(newValue);
                  }
                });
                await _saveProfileData(key, newValue);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("$title updated successfully"), duration: const Duration(seconds: 1)),
                  );
                  Navigator.pop(context); // Close dialog
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xff38B6FF),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text("Save", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _startPhoneVerification(String phoneNumber) async {
    // Ensure phone number is in international format
    if (!phoneNumber.startsWith('+')) {
      _showSnackBar('Please enter phone number with country code (e.g., +92...)');
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (PhoneAuthCredential credential) async {
        Navigator.pop(context); // Close loading
        await _auth.currentUser?.updatePhoneNumber(credential);
        _onPhoneVerified(phoneNumber);
      },
      verificationFailed: (FirebaseAuthException e) {
        Navigator.pop(context); // Close loading
        _showSnackBar('Verification failed: ${e.message}');
      },
      codeSent: (String verificationId, int? resendToken) {
        Navigator.pop(context); // Close loading
        _showOtpDialog(phoneNumber, verificationId);
      },
      codeAutoRetrievalTimeout: (String verificationId) {},
    );
  }

  void _showOtpDialog(String phoneNumber, String verificationId) {
    TextEditingController otpController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Enter OTP"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Verification code sent to $phoneNumber"),
            TextField(
              controller: otpController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(hintText: "6-digit code"),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              String smsCode = otpController.text.trim();
              if (smsCode.length == 6) {
                try {
                  PhoneAuthCredential credential = PhoneAuthProvider.credential(
                    verificationId: verificationId,
                    smsCode: smsCode,
                  );
                  Navigator.pop(context); // Close OTP dialog
                  
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) => const Center(child: CircularProgressIndicator()),
                  );

                  await _auth.currentUser?.updatePhoneNumber(credential);
                  Navigator.pop(context); // Close loading
                  _onPhoneVerified(phoneNumber);
                } catch (e) {
                  Navigator.pop(context); // Close loading
                  _showSnackBar('Invalid OTP or Verification Failed');
                }
              }
            },
            child: const Text("Verify"),
          ),
        ],
      ),
    );
  }

  void _onPhoneVerified(String phoneNumber) async {
    setState(() {
      _phone = phoneNumber;
    });
    await _saveProfileData('user_phone', phoneNumber);
    _showSnackBar('Phone number verified and updated successfully!');
  }

  Future<void> _changePassword() async {
    final user = _auth.currentUser;
    if (user != null && user.email != null) {
      // Navigate to Forgotpass screen to trigger OTP flow
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const Forgotpass()),
      );
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      content: StreamBuilder<User?>(
        stream: _auth.userChanges(),
        builder: (context, snapshot) {
          final user = snapshot.data;
          
          return SingleChildScrollView(
            child: Column(
              children: [
                _buildHeader(user),
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      _buildInfoSection(user),
                      SizedBox(height: 25),
                      _buildSettingsSection(),
                      SizedBox(height: 30),
                      _buildSignOutButton(),
                      SizedBox(height: 40),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: MyBottomBar(
        selectedIndex: _selectedIndex,
        onTap: (index) {
          if (index == _selectedIndex) return;
          
          Widget nextScreen;
          switch (index) {
            case 0:
              nextScreen = HomePage();
              break;
            case 1:
              nextScreen = const ChatSelectionScreen();
              break;
            case 2:
              nextScreen = const Location();
              break;
            case 3:
              nextScreen = const Profile();
              break;
            default:
              nextScreen = HomePage();
          }

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => nextScreen),
          );
        },
      ),
    );
  }

  Widget _buildHeader(User? user) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(top: 40, bottom: 30),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xff250D57), Color(0xff4A148C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(40),
          bottomRight: Radius.circular(40),
        ),
      ),
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                padding: EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 2),
                ),
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 60,
                      backgroundColor: Colors.white24,
                      backgroundImage: _profilePictureUrl != null
                          ? NetworkImage(_profilePictureUrl!) // Cloudinary URL
                          : (_localImagePath != null 
                              ? FileImage(File(_localImagePath!)) 
                              : (user?.photoURL != null ? NetworkImage(user!.photoURL!) : null)) as ImageProvider?,
                      child: (_profilePictureUrl == null && _localImagePath == null && user?.photoURL == null) 
                        ? Icon(Icons.person, size: 70, color: Colors.white) 
                        : null,
                    ),
                    // Loading indicator during upload
                    if (_isUploading)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withValues(alpha: 0.5),
                          ),
                          child: Center(
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Positioned(
                bottom: 5,
                right: 5,
                child: GestureDetector(
                  onTap: _isUploading ? null : _updateProfilePicture, // Disable during upload
                  child: Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _isUploading ? Colors.grey : Color(0xff38B6FF),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                    ),
                    child: Icon(
                      _isUploading ? Icons.hourglass_empty : Icons.edit_rounded, 
                      color: Colors.white, 
                      size: 20
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 15),
          Text(
            user?.displayName ?? "User Name",
            style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 1),
          ),
          SizedBox(height: 5),
          Text(
            user?.email ?? "email@example.com",
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(User? user) {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15, offset: Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Personal Info", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xff250D57))),
              TextButton(
                onPressed: () => _editField("Name", user?.displayName ?? "", 'display_name'),
                child: Text("Edit", style: TextStyle(color: Color(0xff38B6FF))),
              ),
            ],
          ),
          Divider(),
          _buildInfoRow(Icons.person_outline, "Full Name", user?.displayName ?? "Not set"),
          _buildInfoRow(Icons.phone_outlined, "Phone", _phone, onTap: () => _editField("Phone", _phone, 'user_phone')),
          _buildInfoRow(Icons.info_outline, "Bio", _bio, onTap: () => _editField("Bio", _bio, 'user_bio')),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, {VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(color: Color(0xff38B6FF).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: Color(0xff38B6FF), size: 22),
            ),
            SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(color: Colors.grey, fontSize: 12)),
                  Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xff250D57))),
                ],
              ),
            ),
            if (onTap != null) Icon(Icons.chevron_right, color: Colors.grey, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsSection() {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15, offset: Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Account Settings", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xff250D57))),
          Divider(),
          _buildSettingTile(Icons.lock_outline, "Change Password", _changePassword),
          _buildSettingTile(
            Icons.notifications_none_outlined, 
            "Notifications", 
            () {}, 
            trailing: Switch.adaptive(
              value: _notificationsEnabled, 
              activeThumbColor: Color(0xff38B6FF),
              onChanged: (val) {
                setState(() => _notificationsEnabled = val);
                _saveProfileData('notifications_enabled', val);
              },
            ),
          ),
          _buildSettingTile(Icons.privacy_tip_outlined, "Privacy Policy", () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const PrivacyPolicyScreen()),
            );
          }),
          _buildSettingTile(Icons.help_outline, "Help & Support", () {}),
        ],
      ),
    );
  }

  Widget _buildSettingTile(IconData icon, String title, VoidCallback onTap, {Widget? trailing}) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: Color(0xff250D57), size: 22),
      ),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w500, color: Color(0xff250D57))),
      trailing: trailing ?? Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
      onTap: onTap,
    );
  }

  Widget _buildSignOutButton() {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        onPressed: () => _auth.signOut().then((_) => Navigator.pushAndRemoveUntil(
          context, MaterialPageRoute(builder: (context) => LoginPage()), (route) => false)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red.shade50,
          foregroundColor: Colors.red,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: Colors.red.shade100)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.logout_rounded),
            SizedBox(width: 10),
            Text("Sign Out", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
