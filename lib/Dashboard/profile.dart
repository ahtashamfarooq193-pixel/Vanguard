import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:my_app1/services/cloudinary_service.dart';
import 'package:my_app1/bottombar.dart';
import 'package:my_app1/Dashboard/homepage.dart';
import 'package:my_app1/Dashboard/chat.dart';
import 'package:my_app1/Dashboard/location.dart';
import 'package:my_app1/Dashboard/privacypolicy.dart';
import 'package:my_app1/SignUp/loginscreen.dart';
import 'package:my_app1/auth_gate.dart';

class Profile extends StatefulWidget {
  const Profile({super.key});

  @override
  State<Profile> createState() => _ProfileState();
}

class _ProfileState extends State<Profile> {
  final ImagePicker _picker = ImagePicker();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  int _selectedIndex = 3;
  
  // Profile Data
  String _name = "Safe User";
  String _email = "user@vanguard.com";
  String _phone = "+92 300 1234567";
  String _bio = "Your safety is our priority.";
  String? _localImagePath;
  String? _firebasePhotoUrl;
  
  // Settings
  bool _notificationsEnabled = true;
  bool _locationSharing = true;
  int _contactCount = 0;
  bool _isUploadingPic = false;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    final user = _auth.currentUser;

    setState(() {
      // Priority: Firebase User Data > SharedPreferences > Default
      _name = user?.displayName ?? prefs.getString('display_name') ?? "Safe User";
      _email = user?.email ?? "user@vanguard.com";
      _phone = user?.phoneNumber ?? prefs.getString('user_phone') ?? "+92 300 1234567";
      _firebasePhotoUrl = user?.photoURL;
      
      _bio = prefs.getString('user_bio') ?? "Your safety is our priority.";
      _localImagePath = prefs.getString('profile_image_path');
      _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
      _locationSharing = prefs.getBool('location_sharing') ?? true;
      
      final contactsList = prefs.getStringList('emergency_contacts_list');
      _contactCount = contactsList?.length ?? 0;
    });
  }

  Future<void> _handleLogout() async {
    try {
      // 1. Sign out from Firebase and Google securely
      // Added catchError to prevent failure if Google wasn't used to sign in
      await _googleSignIn.signOut().catchError((e) => null);
      await _googleSignIn.disconnect().catchError((e) => null);
      await _auth.signOut();
      
      if (!mounted) return;

      // 2. FORCE reset the entire app to the AuthGate
      // It will automatically check Firebase and show LoginPage
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const AuthGate()),
        (route) => false,
      );
      
      debugPrint("✅ Logged out successfully and stack cleared");
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Logout failed: $e")));
    }
  }

  Future<void> _updateField(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
    
    // Also update Firebase display name if name is changed
    if (key == 'display_name') {
      await _auth.currentUser?.updateDisplayName(value);
    }
    
    _loadProfileData();
  }

  Future<void> _updateProfilePicture() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 50, maxWidth: 512);
    if (image != null) {
      setState(() => _isUploadingPic = true);
      
      try {
        final file = File(image.path);
        // Upload to Cloudinary to get public link
        final link = await CloudinaryService.uploadFile(file);
        
        if (link != null) {
          final user = _auth.currentUser;
          if (user != null) {
            // Update Auth Profile
            await user.updatePhotoURL(link);
            
            // Update Firestore Profile
            await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
              'photoUrl': link,
            }, SetOptions(merge: true));
            
            setState(() {
              _firebasePhotoUrl = link;
              _localImagePath = image.path;
            });
            
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile picture updated successfully!")));
          }
        } else {
          final msg = CloudinaryService.lastErrorMessage ?? "Failed to upload image to Cloudinary.";
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(msg), backgroundColor: Colors.red),
            );
          }
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
      }
      
      setState(() => _isUploadingPic = false);
    }
  }

  void _showEditDialog(String title, String currentVal, String key) {
    TextEditingController controller = TextEditingController(text: currentVal);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Edit $title", style: const TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          maxLines: key == 'user_bio' ? 3 : 1,
          decoration: InputDecoration(
            hintText: "Enter $title",
            filled: true,
            fillColor: const Color(0xffF1F2F6),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xff250D57),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              _updateField(key, controller.text.trim());
              Navigator.pop(context);
            },
            child: const Text("Save Changes"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xff250D57);
    const Color accentColor = Color(0xff38B6FF);

    return Scaffold(
      backgroundColor: const Color(0xffF8F9FE),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildSliverAppBar(primaryColor, accentColor),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  const SizedBox(height: 25),
                  _buildQuickActionCard(accentColor),
                  const SizedBox(height: 25),
                  _buildSectionTitle("Identity Details"),
                  const SizedBox(height: 12),
                  _buildInfoCard([
                    _buildInfoTile(Icons.person_outline, "Name", _name, () => _showEditDialog("Name", _name, 'display_name')),
                    _buildInfoTile(Icons.phone_outlined, "Mobile", _phone, () => _showEditDialog("Phone", _phone, 'user_phone')),
                    _buildInfoTile(Icons.email_outlined, "Email", _email, null),
                  ]),
                  const SizedBox(height: 25),
                  _buildSectionTitle("Safety Preferences"),
                  const SizedBox(height: 12),
                  _buildInfoCard([
                    _buildSwitchTile(Icons.notifications_active_outlined, "Notifications", _notificationsEnabled, (val) {
                      setState(() => _notificationsEnabled = val);
                      SharedPreferences.getInstance().then((p) => p.setBool('notifications_enabled', val));
                    }),
                    _buildSwitchTile(Icons.my_location_outlined, "Location Sharing", _locationSharing, (val) {
                      setState(() => _locationSharing = val);
                      SharedPreferences.getInstance().then((p) => p.setBool('location_sharing', val));
                    }),
                    _buildInfoTile(Icons.lock_outline, "Security", "Password & Security", () {}),
                  ]),
                  const SizedBox(height: 25),
                  _buildSectionTitle("Legal & Info"),
                  const SizedBox(height: 12),
                  _buildInfoCard([
                    _buildInfoTile(Icons.article_outlined, "Privacy Policy", "Data Protection", () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()));
                    }),
                    _buildInfoTile(Icons.help_center_outlined, "Support Center", "Contact us", () {}),
                  ]),
                  const SizedBox(height: 35),
                  _buildLogoutButton(),
                  const SizedBox(height: 60),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: MyBottomBar(
        selectedIndex: _selectedIndex,
        onTap: (index) {
          if (index == _selectedIndex) return;
          Widget next;
          if (index == 0) next = HomePage();
          else if (index == 1) next = const ChatSelectionScreen();
          else if (index == 2) next = const Location();
          else next = const Profile();
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => next));
        },
      ),
    );
  }

  Widget _buildSliverAppBar(Color primary, Color accent) {
    return SliverAppBar(
      expandedHeight: 250,
      pinned: true,
      elevation: 0,
      backgroundColor: primary,
      automaticallyImplyLeading: false,
      title: const Text("", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      centerTitle: true,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [primary, const Color(0xff1A093D)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              Stack(
                children: [
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.15), width: 4),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 5))
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircleAvatar(
                          radius: 55,
                          backgroundColor: Colors.white10,
                          backgroundImage: _firebasePhotoUrl != null 
                            ? NetworkImage(_firebasePhotoUrl!) as ImageProvider
                            : (_localImagePath != null ? FileImage(File(_localImagePath!)) : null),
                          child: (_firebasePhotoUrl == null && _localImagePath == null) ? const Icon(Icons.person, size: 60, color: Colors.white) : null,
                        ),
                        if (_isUploadingPic)
                          const CircularProgressIndicator(color: Colors.white),
                      ],
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: _updateProfilePicture,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: accent, shape: BoxShape.circle, border: Border.all(color: primary, width: 2)),
                        child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Text(_name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(_bio, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActionCard(Color accent) {
    final user = _auth.currentUser;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          StreamBuilder<QuerySnapshot>(
            stream: _firestore.collection('users').doc(user?.uid).collection('contacts').snapshots(),
            builder: (context, snapshot) {
              final count = snapshot.data?.docs.length ?? 0;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Emergency Contacts", style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 5),
                  Text("$count Registered", style: const TextStyle(color: Color(0xff2D3142), fontSize: 18, fontWeight: FontWeight.w800)),
                ],
              );
            }
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xff250D57),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
            ),
            onPressed: () {
               Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HomePage()));
            },
            child: const Text("Manage List", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xff9DA3B4), letterSpacing: 1.5),
      ),
    );
  }

  Widget _buildInfoCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildInfoTile(IconData icon, String label, String value, VoidCallback? onTap) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        height: 45,
        width: 45,
        decoration: BoxDecoration(color: const Color(0xffF5F7FB), borderRadius: BorderRadius.circular(15)),
        child: Icon(icon, color: const Color(0xff250D57), size: 22),
      ),
      title: Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
      subtitle: Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xff2D3142))),
      trailing: onTap != null ? const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xffD1D5DB)) : null,
    );
  }

  Widget _buildSwitchTile(IconData icon, String label, bool value, Function(bool) onChanged) {
    return ListTile(
      leading: Container(
        height: 45,
        width: 45,
        decoration: BoxDecoration(color: const Color(0xffF5F7FB), borderRadius: BorderRadius.circular(15)),
        child: Icon(icon, color: const Color(0xff250D57), size: 22),
      ),
      title: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xff2D3142))),
      trailing: Switch.adaptive(
        value: value,
        onChanged: onChanged,
        activeColor: const Color(0xff38B6FF),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: InkWell(
        onTap: _handleLogout,
        child: Container(
          height: 55,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.red.withOpacity(0.1)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.logout_rounded, color: Colors.red, size: 20),
              SizedBox(width: 12),
              Text("Logout Securely", style: TextStyle(color: Colors.red, fontWeight: FontWeight.w800, fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }
}
