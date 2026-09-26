// The same browser-only shape web_redirect_web.dart beside it uses.
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';

/// Downloads [bytes] as [filename] — the browser's own save, no share sheet.
/// [subject] and [text] only mean something on a phone's share sheet.
Future<void> saveFile(Uint8List bytes, String filename, {required String mimeType, String? subject, String? text}) async {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final a = html.AnchorElement(href: url)
    ..download = filename
    ..style.display = 'none';
  html.document.body?.append(a);
  a.click();
  a.remove();
  // Revoke on the next turn, not now: some browsers start the download
  // asynchronously and a revoked URL cancels it.
  Future<void>.delayed(const Duration(seconds: 5), () => html.Url.revokeObjectUrl(url));
}
