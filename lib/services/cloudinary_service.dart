import 'package:cloudinary_sdk/cloudinary_sdk.dart';

class CloudinaryService {
  static final Cloudinary _cloudinary = Cloudinary.full(
    apiKey: '313454519513523',
    apiSecret: '6POw3i5oN2FlDmB483N9kcaFPBk',
    cloudName: 'dgrsdfnzu',
  );

  /// Upload image to Cloudinary and return the URL
  static Future<String?> uploadImage(String filePath) async {
    try {
      final response = await _cloudinary.uploadResource(
        CloudinaryUploadResource(
          filePath: filePath,
          folder: 'chat_images',
          resourceType: CloudinaryResourceType.image,
        ),
      );

      if (response.isSuccessful && response.secureUrl != null) {
        print('Upload successful: ${response.secureUrl}');
        return response.secureUrl;
      } else {
        print('Upload failed: ${response.error}');
        return null;
      }
    } catch (e) {
      print('Error uploading to Cloudinary: $e');
      return null;
    }
  }

  /// Get optimized image URL
  static String getOptimizedUrl(String publicId, {int? width, int? height}) {
    return 'https://res.cloudinary.com/dgrsdfnzu/image/upload/w_${width ?? 800},h_${height ?? 600},c_limit,q_auto,f_auto/$publicId';
  }
}
