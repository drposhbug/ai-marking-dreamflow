import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Writes [bytes] to a temporary file and opens the share sheet, so the
/// teacher can send it to the copier app, Drive, email or Files.
Future<void> saveFile(Uint8List bytes, String filename, {required String mimeType, String? subject, String? text}) async {
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/$filename');
  await f.writeAsBytes(bytes, flush: true);
  await Share.shareXFiles([XFile(f.path, mimeType: mimeType)], subject: subject ?? filename, text: text);
}
