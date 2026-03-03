import 'dart:async';
import 'dart:io';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:mime/mime.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GoogleDriveService {
  static const _scopes = <String>[
    drive.DriveApi.driveFileScope,
  ];

  static const _prefsFolderIdKey = 'google_drive_vanguard_folder_id';
  static String? _autoFolderId;
  static String? _lastErrorMessage;

  static String? get lastErrorMessage => _lastErrorMessage;
  static void _setError(String message, [Object? err]) {
    _lastErrorMessage = message;
    if (err != null) debugPrint('❌ Google Drive: $message ($err)');
  }

  static final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: _scopes);

  static Future<drive.DriveApi?> _getDriveApi() async {
    try {
      _lastErrorMessage = null;
      final account = await _googleSignIn.signInSilently() ?? await _googleSignIn.signIn();
      if (account == null) {
        _setError('Google account connection cancelled. Please try again.');
        return null;
      }

      final headers = await account.authHeaders;
      final client = _GoogleAuthClient(headers);
      return drive.DriveApi(client);
    } catch (e) {
      _setError('Unable to connect to Google Drive. Check internet and try again.', e);
      return null;
    }
  }

  static Future<String?> _getOrCreateFolder(drive.DriveApi api) async {
    if (_autoFolderId != null) return _autoFolderId;
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedId = prefs.getString(_prefsFolderIdKey);
      if (savedId != null && savedId.isNotEmpty) {
        _autoFolderId = savedId;
        return _autoFolderId;
      }

      // With `driveFileScope`, listing all folders may not be permitted. Instead,
      // create a dedicated folder once and persist its id.
      final folder = drive.File()
        ..name = 'Vanguard_Media'
        ..mimeType = 'application/vnd.google-apps.folder';
      final result = await api.files.create(folder, $fields: 'id').timeout(const Duration(seconds: 15));
      _autoFolderId = result.id;
      if (_autoFolderId != null) {
        await prefs.setString(_prefsFolderIdKey, _autoFolderId!);
      }
      return _autoFolderId;
    } catch (e) {
      _setError('Could not prepare Drive folder. Please try again.', e);
      return null;
    }
  }

  static Future<String?> uploadFile(File file) async {
    _lastErrorMessage = null;
    if (!await file.exists()) {
      _setError('Selected file was not found. Please pick it again.');
      return null;
    }

    final api = await _getDriveApi();
    if (api == null) return null;

    Future<String?> attempt() async {
      final folderId = await _getOrCreateFolder(api);
      final fileName = p.basename(file.path);
      final mimeType = lookupMimeType(file.path) ?? 'image/jpeg';

      final driveFile = drive.File()
        ..name = 'V_IMG_${DateTime.now().millisecondsSinceEpoch}_$fileName'
        ..parents = folderId != null ? [folderId] : null;

      final media = drive.Media(file.openRead(), file.lengthSync(), contentType: mimeType);
      final created = await api.files
          .create(driveFile, uploadMedia: media, $fields: 'id')
          .timeout(const Duration(seconds: 45));

      final id = created.id;
      if (id == null || id.isEmpty) {
        _setError('Upload failed: missing file id from Google Drive.');
        return null;
      }

      // Make the file public so it can be displayed in-app.
      await api.permissions
          .create(
            drive.Permission()
              ..role = 'reader'
              ..type = 'anyone',
            id,
          )
          .timeout(const Duration(seconds: 15));

      final viewLink = 'https://drive.google.com/uc?export=view&id=$id';
      debugPrint('✅ Drive upload ok: $viewLink');
      return viewLink;
    }

    try {
      return await _withRetry<String?>(
        attempt,
        attempts: 3,
        baseDelay: const Duration(milliseconds: 700),
        shouldRetry: (e) {
          if (e is TimeoutException || e is SocketException) return true;
          return false;
        },
      );
    } catch (e) {
      if (_lastErrorMessage == null) {
        _setError('Failed to upload. Please check your connection and try again.', e);
      }
      return null;
    }
  }
}

class _GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();
  _GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }

  @override
  void close() {
    _client.close();
    super.close();
  }
}

Future<T> _withRetry<T>(
  Future<T> Function() fn, {
  required int attempts,
  required Duration baseDelay,
  required bool Function(Object e) shouldRetry,
}) async {
  Object? lastErr;
  for (var i = 0; i < attempts; i++) {
    try {
      return await fn();
    } catch (e) {
      lastErr = e;
      if (i == attempts - 1 || !shouldRetry(e)) rethrow;
      final delay = baseDelay * (1 << i);
      await Future.delayed(delay);
    }
  }
  // unreachable, but keeps analyzer happy
  throw lastErr ?? Exception('Retry failed');
}
