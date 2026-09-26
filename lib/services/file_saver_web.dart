// The same browser-only shape web_redirect_web.dart beside it uses.
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Downloads [bytes] as [filename] — the browser's own save, no share sheet.
/// [subject] and [text] only mean something on a phone's share sheet.
Future<void> saveFile(Uint8List bytes, String filename, {required String mimeType, String? subject, String? text}) async {
  final blob = web.Blob(<JSAny>[bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body?.append(a);
  a.click();
  a.remove();
  // Revoke on the next turn, not now: some browsers start the download
  // asynchronously and a revoked URL cancels it.
  Future<void>.delayed(const Duration(seconds: 5), () => web.URL.revokeObjectURL(url));
}
