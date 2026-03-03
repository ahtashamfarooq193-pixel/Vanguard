import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';

class CloudinaryService {
  // ── CONFIGURATION ──
  // TODO: Replace these with your real Cloudinary credentials
  static const String _cloudName = "dujhxsxnt"; 
  static const String _uploadPreset = "vanguard_preset"; 

  static String? _lastErrorMessage;
  static String? get lastErrorMessage => _lastErrorMessage;

  /// Uploads a file to Cloudinary using an Unsigned Upload Preset.
  /// Returns the secure URL of the uploaded image or null on failure.
  static Future<String?> uploadFile(File file) async {
    _lastErrorMessage = null;

    if (!await file.exists()) {
      _lastErrorMessage = "File does not exist.";
      return null;
    }

    try {
      // Use 'auto/upload' to let Cloudinary detect Image vs Video
      final url = Uri.parse("https://api.cloudinary.com/v1_1/$_cloudName/auto/upload");

      // We use MultipartRequest for file uploads
      final request = http.MultipartRequest("POST", url)
        ..fields['upload_preset'] = _uploadPreset
        ..files.add(await http.MultipartFile.fromPath('file', file.path));

      final response = await request.send().timeout(const Duration(seconds: 30));
      final responseData = await response.stream.bytesToString();

      if (response.statusCode == 200 || response.statusCode == 201) {
        final Map<String, dynamic> data = jsonDecode(responseData);
        final String secureUrl = data['secure_url'];
        debugPrint('✅ Cloudinary Upload Success: $secureUrl');
        return secureUrl;
      } else {
        final Map<String, dynamic> errorData = jsonDecode(responseData);
        _lastErrorMessage = errorData['error']?['message'] ?? "Upload failed with status: ${response.statusCode}";
        debugPrint('❌ Cloudinary Error: $_lastErrorMessage');
        return null;
      }
    } catch (e) {
      _lastErrorMessage = "Cloudinary connection error: $e";
      debugPrint('❌ Cloudinary Catch: $e');
      return null;
    }
  }
}
