import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:marking_prokect_v2/services/ai_grading_service.dart';
import 'package:marking_prokect_v2/services/local_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Google Drive isn't connected for this session — thrown so the UI can
/// explain that Drive export needs a Google sign-in.
class DriveAuthException implements Exception {
  @override
  String toString() => 'Google Drive isn\'t connected — sign in with Google to enable Drive export.';
}

String _esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

String _num(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 1);

/// The marked result as HTML — score, feedback, per-question notes, and
/// transcription — which Drive converts into a Google Doc on upload.
String markedResultHtml({required AiGradeResult result, required String studentName, required String date}) {
  final score = result.gradingFormat == 'levels' && result.levelDisplay != null
      ? '${result.levelDisplay} · ${result.percentageDisplay}'
      : '${result.percentageDisplay} (${_num(result.rawScore)}/${_num(result.maxScore)})';

  final b = StringBuffer()
    ..write('<h1>${_esc(studentName)} — ${_esc(result.detectedSubject)}</h1>')
    ..write('<p><b>Marked:</b> $date &nbsp; <b>Score:</b> ${_esc(score)}</p>')
    ..write('<h2>Summary</h2><p>${_esc(result.summary)}</p>');
  if (result.strengths.isNotEmpty) {
    b.write('<h2>Strengths</h2><ul>${result.strengths.map((s) => '<li>${_esc(s)}</li>').join()}</ul>');
  }
  if (result.improvements.isNotEmpty) {
    b.write('<h2>Areas to improve</h2><ul>${result.improvements.map((s) => '<li>${_esc(s)}</li>').join()}</ul>');
  }
  if (result.criteriaBreakdown.isNotEmpty) {
    b.write('<h2>Criteria</h2><ul>');
    for (final c in result.criteriaBreakdown) {
      b.write('<li><b>${_esc(c.name)}:</b> ${_num(c.score)}/${_num(c.maxScore)} — ${_esc(c.feedback)}</li>');
    }
    b.write('</ul>');
  }
  if (result.annotations.isNotEmpty) {
    b.write('<h2>Question notes</h2><ul>');
    for (final a in result.annotations) {
      b.write('<li><b>${_esc(a.questionLabel)}</b> ${_esc(a.earnedMark)}${_esc(a.outOfMark)} (${a.correct ? 'correct' : 'needs work'}): ${_esc(a.feedback)}</li>');
    }
    b.write('</ul>');
  }
  if (result.rawText.trim().isNotEmpty) {
    b.write('<h2>Transcription</h2><p>${_esc(result.rawText).replaceAll('\n', '<br>')}</p>');
  }
  return b.toString();
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

  // ── Auto-save consent (per teacher, opt-in) ─────────────────────────
  static String _autoSaveKey(String teacherId) => 'ai_marker.drive_autosave.v1.$teacherId';

  Future<bool> autoSaveEnabled(String teacherId) async =>
      (await const LocalStore().getString(_autoSaveKey(teacherId))) == '1';

  Future<void> setAutoSave(String teacherId, bool enabled) =>
      const LocalStore().setString(_autoSaveKey(teacherId), enabled ? '1' : '');

  /// Uploads a marked result as a formatted Google Doc in the Markless
  /// folder ("Marked — ‹student› — ‹date›"); returns the doc link.
  Future<String?> uploadMarkedResult({required AiGradeResult result, required String studentName}) {
    final now = DateTime.now();
    final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return uploadDoc(
      title: 'Marked — $studentName — $date',
      html: markedResultHtml(result: result, studentName: studentName, date: date),
    );
  }

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
