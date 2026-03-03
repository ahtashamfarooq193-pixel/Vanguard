import 'dart:io';
import 'package:flutter/material.dart';
import 'package:my_app1/bottombar.dart';
import 'package:my_app1/Dashboard/homepage.dart';
import 'package:my_app1/Dashboard/chat.dart';
import 'package:my_app1/Dashboard/profile.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class Location extends StatefulWidget {
  final double? targetLat;
  final double? targetLng;
  final String? targetName;

  const Location({
    super.key,
    this.targetLat,
    this.targetLng,
    this.targetName,
  });

  @override
  State<Location> createState() => _LocationState();
}

class _LocationState extends State<Location> {
  int _selectedIndex = 2;
  final MapController _mapController = MapController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  double _currentZoom = 15.0;
  LatLng _currentLocation = const LatLng(33.6844, 73.0479); // Default Islamabad
  LatLng? _targetLocation;
  bool _isLoading = true;
  bool _isSatellite = false;

  @override
  void initState() {
    super.initState();
    if (widget.targetLat != null && widget.targetLng != null) {
      _targetLocation = LatLng(widget.targetLat!, widget.targetLng!);
      _currentLocation = _targetLocation!; // Start here
    }
    _determinePosition();
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    setState(() => _isLoading = true);

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location services are disabled.')),
        );
      }
      setState(() => _isLoading = false);
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permissions are denied')),
          );
        }
        setState(() => _isLoading = false);
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permissions are permanently denied.')),
        );
      }
      setState(() => _isLoading = false);
      return;
    }

    Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    setState(() {
      _currentLocation = LatLng(position.latitude, position.longitude);
      _isLoading = false;
    });
    
    // Fit both markers if we have a target
    if (_targetLocation != null) {
      _fitMarkers();
    } else {
      _mapController.move(_currentLocation, _currentZoom);
    }
  }

  void _fitMarkers() {
    if (_targetLocation == null) return;
    
    // Calculate the bounding box for both points
    final lat1 = _currentLocation.latitude;
    final lng1 = _currentLocation.longitude;
    final lat2 = _targetLocation!.latitude;
    final lng2 = _targetLocation!.longitude;

    // A simple way is to use fitCamera or fitBounds if available
    // For now we calculate center and reasonable zoom
    final centerLat = (lat1 + lat2) / 2;
    final centerLng = (lng1 + lng2) / 2;
    _mapController.move(LatLng(centerLat, centerLng), 13.0);
  }

  void _zoomIn() {
    setState(() {
      _currentZoom += 1;
      _mapController.move(_mapController.camera.center, _currentZoom);
    });
  }

  void _zoomOut() {
    setState(() {
      _currentZoom -= 1;
      _mapController.move(_mapController.camera.center, _currentZoom);
    });
  }

  Future<void> _sendEmergencyAlert() async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
          const SizedBox(width: 10),
          Expanded(child: Text('Emergency SOS', style: TextStyle(fontWeight: FontWeight.bold))),
        ]),
        content: const Text('Are you sure you want to send an emergency alert to all your contacts?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('Send Alert', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      // 1) Get precise position
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final mapsUrl = 'https://www.google.com/maps/search/?api=1&query=${position.latitude},${position.longitude}';
      final smsMessage = 'VANGUARD EMERGENCY! I need help. My location: $mapsUrl';

      // 2) Load contacts
      final contactsSnapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('contacts')
          .get();

      if (contactsSnapshot.docs.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No emergency contacts found.')));
        setState(() => _isLoading = false);
        return;
      }

      // 3) Log alert (Firestore)
      await _firestore.collection('alerts').add({
        'senderId': user.uid,
        'senderName': user.displayName ?? "User",
        'location': {'lat': position.latitude, 'lng': position.longitude},
        'alertType': 'SOS_LOCATION',
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'active',
      });

      // 4) Notify all (SMS/Push)
      final phoneNumbers = <String>[];
      for (final doc in contactsSnapshot.docs) {
        final contact = (doc.data()['contact'] ?? '').toString();
        if (contact.isNotEmpty && contact.contains(RegExp(r'[0-9]'))) {
          phoneNumbers.add(contact);
        }
      }

      if (phoneNumbers.isNotEmpty) {
        final separator = Platform.isAndroid ? ',' : ';';
        final smsUri = Uri(
          scheme: 'sms',
          path: phoneNumbers.join(separator),
          queryParameters: {'body': smsMessage},
        );
        if (await canLaunchUrl(smsUri)) await launchUrl(smsUri);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SOS Alert triggered!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
        ),
        title: const Text(
          'Live Tracking',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.blue),
            onPressed: _determinePosition,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isLoading)
            LinearProgressIndicator(color: Colors.blue, backgroundColor: Colors.blue.withOpacity(0.2)),
          
          // Map Container
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.3),
                    spreadRadius: 1,
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: Stack(
                  children: [
                    // Real Map Background
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _currentLocation,
                        initialZoom: _currentZoom,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: _isSatellite 
                            ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                            : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.shamii.vanguard',
                        ),
                        MarkerLayer(
                          markers: [
                            // 1. Target Location (The other person)
                            if (_targetLocation != null)
                              Marker(
                                point: _targetLocation!,
                                width: 80, height: 100,
                                child: Column(children: [
                                  Container(
                                    width: 45, height: 45,
                                    decoration: BoxDecoration(
                                      color: Colors.redAccent, shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 3),
                                      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8)],
                                    ),
                                    child: const Icon(Icons.location_on, color: Colors.white, size: 25),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.9), borderRadius: BorderRadius.circular(12)),
                                    child: Text(widget.targetName ?? 'DESTINATION', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                                  ),
                                ]),
                              ),
                            
                            // 2. My Location
                            Marker(
                              point: _currentLocation,
                              width: 80,
                              height: 100,
                              child: Column(
                                children: [
                                  Container(
                                    width: 45,
                                    height: 45,
                                    decoration: BoxDecoration(
                                      color: Colors.blue,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 3),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.3),
                                          blurRadius: 8,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.my_location,
                                      color: Colors.white,
                                      size: 25,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white24,
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                                    ),
                                    child: const Text(
                                      'YOU ARE HERE',
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    
                    // Map Controls (Zoom buttons)
                    Positioned(
                      top: 16,
                      right: 16,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.add),
                              onPressed: _zoomIn,
                            ),
                            const Divider(height: 1),
                            IconButton(
                              icon: const Icon(Icons.remove),
                              onPressed: _zoomOut,
                            ),
                            const Divider(height: 1),
                            IconButton(
                              icon: Icon(_isSatellite ? Icons.map : Icons.public, color: Colors.blue),
                              onPressed: () => setState(() => _isSatellite = !_isSatellite),
                              tooltip: 'Toggle Satellite View',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // Emergency Button Area
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 65,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _sendEmergencyAlert,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      elevation: 8,
                      shadowColor: Colors.red.withOpacity(0.5),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.warning_rounded, color: Colors.white, size: 28),
                        const SizedBox(width: 15),
                        Text(
                          _isLoading ? 'PROCESSING...' : 'SEND SOS LOCATION',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.grey, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This will notify your emergency network with a link to your precise location.',
                        style: TextStyle(color: Colors.grey[600], fontSize: 11),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ],
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
              nextScreen = const Location();
          }

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => nextScreen),
          );
        },
      ),
    );
  }
}
