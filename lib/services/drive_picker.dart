import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:marking_prokect_v2/app/app_state.dart' show ScannedPage;
import 'package:marking_prokect_v2/services/document_processor.dart';

/// The Google Drive app isn't installed (or can't handle the pick intent) —
/// callers fall back to the generic system file picker.
class DrivePickerUnavailable implements Exception {}

/// Outcome of a Drive import — carries what was skipped or unreadable so
/// the UI can explain itself instead of silently doing nothing.
class DriveImport {
  final List<ScannedPage> pages;
  final int pickedCount;
  final int skippedNonImage;
  final int failedReads;

  const DriveImport({
    required this.pages,
    required this.pickedCount,
    required this.skippedNonImage,
    required this.failedReads,
  });

  bool get cancelled => pickedCount == 0;
  int get unusable => skippedNonImage + failedReads;
}

/// Opens the Google Drive app's OWN picker (via a native intent targeted at
/// the Drive package) so "From Drive" lands the teacher directly in their
/// Drive. Downloads the picked files and runs each image through the
/// scanner pipeline.
class DrivePicker {
  static const _channel = MethodChannel('markless/drive_picker');

  static bool _looksLikeImage(String name, String mime) {
    if (mime.startsWith('image/')) return true;
    if (mime.isNotEmpty) return false;
    final n = name.toLowerCase();
    return const ['.jpg', '.jpeg', '.png', '.webp', '.heic', '.heif', '.bmp'].any(n.endsWith);
  }

  static Future<DriveImport> importScannedPages() async {
    Map<String, dynamic> raw;
    try {
      raw = (await _channel.invokeMapMethod<String, dynamic>('pickFromDrive')) ?? const {};
    } on PlatformException catch (e) {
      if (e.code == 'no_drive' || e.code == 'busy') throw DrivePickerUnavailable();
      rethrow;
    } on MissingPluginException {
      throw DrivePickerUnavailable();
    }

    final picked = (raw['picked'] as num?)?.toInt() ?? 0;
    final files = (raw['files'] as List? ?? const []).whereType<Map>().toList();

    final pages = <ScannedPage>[];
    var skipped = 0;
    for (final f in files) {
      final name = (f['name'] ?? 'drive_image.jpg').toString();
      final mime = (f['mime'] ?? '').toString();
      final bytes = f['bytes'];
      if (bytes is! Uint8List || !_looksLikeImage(name, mime)) {
        skipped++;
        continue;
      }
      final processed = await DocumentProcessor.processPage(bytes);
      pages.add(ScannedPage(bytes: processed, fileName: name));
    }
    return DriveImport(
      pages: pages,
      pickedCount: picked,
      skippedNonImage: skipped,
      failedReads: (picked - files.length).clamp(0, picked),
    );
  }
}
