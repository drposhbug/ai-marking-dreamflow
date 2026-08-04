import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Google Drive isn't connected for this session — thrown so the UI can
/// explain that Drive export needs a Google sign-in.
class DriveAuthException implements Exception {
  @override
  String toString() => 'Google Drive isn\'t connected — sign in with Google to enable Drive export.';
}

/// Exports marked work into a "Markless" folder in the teacher's Google
/// Drive, using the Google token from their Supabase session. The app
/// requests only the drive.file scope: it can touch files it created, and
/// nothing else in the teacher's Drive.
class DriveService {
  static const _folderName = 'Markless';

  String? get _token {
    try {
      return Supabase.instance.client.auth.currentSession?.providerToken;
    } catch (_) {
      return null;
    }
  }

  /// True when the current session carries a Google access token.
  bool get isConnected => _token != null && _token!.isNotEmpty;

  Future<String> _ensureFolder(String token) async {
    final q = Uri.encodeQueryComponent(
        "name = '$_folderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false");
    final list = await http.get(
      Uri.parse('https://www.googleapis.com/drive/v3/files?q=$q&fields=files(id,name)'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (list.statusCode == 401 || list.statusCode == 403) throw DriveAuthException();
    if (list.statusCode == 200) {
      final files = (jsonDecode(list.body)['files'] as List?) ?? const [];
      if (files.isNotEmpty) return files.first['id'] as String;
    }
    final create = await http.post(
      Uri.parse('https://www.googleapis.com/drive/v3/files'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode({'name': _folderName, 'mimeType': 'application/vnd.google-apps.folder'}),
    );
    if (create.statusCode == 401 || create.statusCode == 403) throw DriveAuthException();
    if (create.statusCode >= 300) throw Exception('Could not create the Markless folder in Drive.');
    return jsonDecode(create.body)['id'] as String;
  }

  /// Uploads [html] as a Google Doc named [title] inside the Markless
  /// folder. Returns the document's link.
  Future<String?> uploadDoc({required String title, required String html}) async {
    final token = _token;
    if (token == null || token.isEmpty) throw DriveAuthException();
    final folderId = await _ensureFolder(token);

    const boundary = 'markless_upload_boundary';
    final meta = jsonEncode({
      'name': title,
      'mimeType': 'application/vnd.google-apps.document',
      'parents': [folderId],
    });
    final body = '--$boundary\r\n'
        'Content-Type: application/json; charset=UTF-8\r\n\r\n'
        '$meta\r\n'
        '--$boundary\r\n'
        'Content-Type: text/html; charset=UTF-8\r\n\r\n'
        '$html\r\n'
        '--$boundary--';
    final res = await http.post(
      Uri.parse('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,webViewLink'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'multipart/related; boundary=$boundary'},
      body: utf8.encode(body),
    );
    if (res.statusCode == 401 || res.statusCode == 403) throw DriveAuthException();
    if (res.statusCode >= 300) throw Exception('Drive upload failed (${res.statusCode}).');
    return (jsonDecode(res.body)['webViewLink'] ?? '') as String?;
  }
}
