import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:marking_prokect_v2/app/app_state.dart' show ScannedPage;
import 'package:marking_prokect_v2/services/document_processor.dart';
import 'package:pdfx/pdfx.dart';

/// The Google Drive app isn't installed (or can't handle the pick intent) —
/// callers fall back to the generic system file picker.
class DrivePickerUnavailable implements Exception {}

/// How many PDF pages get imported at most — keeps a 200-page textbook from
/// becoming 200 marks. The UI mentions when a PDF was cut off.
const int kMaxPdfPages = 15;

bool looksLikeImageFile(String name, String mime) {
  if (mime.startsWith('image/')) return true;
  if (mime.isNotEmpty && mime != 'application/octet-stream') return false;
  final n = name.toLowerCase();
  return const ['.jpg', '.jpeg', '.png', '.webp', '.heic', '.heif', '.bmp'].any(n.endsWith);
}

bool looksLikePdfFile(String name, String mime) =>
    mime == 'application/pdf' || name.toLowerCase().endsWith('.pdf');

/// Renders a PDF's pages to JPEG images sized for the marking pipeline
/// (~1600px long side) using the platform's built-in PDF engine — no API
/// cost. Throws when the bytes aren't a readable PDF.
Future<List<Uint8List>> renderPdfPages(Uint8List bytes, {int maxPages = kMaxPdfPages}) async {
  final doc = await PdfDocument.openData(bytes);
  try {
    final out = <Uint8List>[];
    final count = math.min(doc.pagesCount, maxPages);
    for (var i = 1; i <= count; i++) {
      final page = await doc.getPage(i);
      try {
        final scale = 1600 / math.max(page.width, page.height);
        final rendered = await page.render(
          width: page.width * scale,
          height: page.height * scale,
          format: PdfPageImageFormat.jpeg,
          backgroundColor: '#FFFFFF',
        );
        if (rendered != null) out.add(rendered.bytes);
      } finally {
        await page.close();
      }
    }
    return out;
  } finally {
    await doc.close();
  }
}

/// A picked file (image OR pdf) → scanner-processed pages. Empty when the
/// file can't be read as either.
Future<List<ScannedPage>> pagesFromPickedFile({
  required String name,
  required String mime,
  required Uint8List bytes,
}) async {
  try {
    if (looksLikePdfFile(name, mime)) {
      final images = await renderPdfPages(bytes);
      final pages = <ScannedPage>[];
      for (var i = 0; i < images.length; i++) {
        // Rendered PDF pages are already flat and clean — the scanner pass
        // is still safe (downscale/contrast are no-ops on digital pages).
        final processed = await DocumentProcessor.processPage(images[i]);
        pages.add(ScannedPage(bytes: processed, fileName: '$name (page ${i + 1})'));
      }
      return pages;
    }
    if (looksLikeImageFile(name, mime)) {
      final processed = await DocumentProcessor.processPage(bytes);
      return [ScannedPage(bytes: processed, fileName: name)];
    }
  } catch (e) {
    debugPrint('pagesFromPickedFile failed for $name: $e');
  }
  return const [];
}

/// Whether a PDF would be truncated by the page cap (for honest messaging).
Future<bool> pdfExceedsPageCap(String name, String mime, Uint8List bytes) async {
  if (!looksLikePdfFile(name, mime)) return false;
  try {
    final doc = await PdfDocument.openData(bytes);
    final n = doc.pagesCount;
    await doc.close();
    return n > kMaxPdfPages;
  } catch (_) {
    return false;
  }
}

/// Outcome of a Drive import — carries what was skipped or unreadable so
/// the UI can explain itself instead of silently doing nothing.
class DriveImport {
  final List<ScannedPage> pages;

  /// Pages grouped by source file — a batch of PDFs (one per student) can
  /// be marked as separate submissions instead of one merged pile.
  final List<List<ScannedPage>> fileGroups;
  final int pickedCount;
  final int unreadable;
  final bool pdfTruncated;

  const DriveImport({
    required this.pages,
    required this.fileGroups,
    required this.pickedCount,
    required this.unreadable,
    required this.pdfTruncated,
  });

  bool get cancelled => pickedCount == 0;
}

/// Opens the Google Drive app's OWN picker (via a native intent targeted at
/// the Drive package) so "From Drive" lands the teacher directly in their
/// Drive. Downloads the picked files and turns images AND PDFs into
/// scanner-processed pages.
class DrivePicker {
  static const _channel = MethodChannel('markless/drive_picker');

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
    final groups = <List<ScannedPage>>[];
    var unreadable = picked - files.length; // entries the native side couldn't stream
    var truncated = false;
    for (final f in files) {
      final name = (f['name'] ?? 'drive_file').toString();
      final mime = (f['mime'] ?? '').toString();
      final bytes = f['bytes'];
      if (bytes is! Uint8List) {
        unreadable++;
        continue;
      }
      final got = await pagesFromPickedFile(name: name, mime: mime, bytes: bytes);
      if (got.isEmpty) {
        unreadable++;
        continue;
      }
      if (await pdfExceedsPageCap(name, mime, bytes)) truncated = true;
      pages.addAll(got);
      groups.add(got);
    }
    return DriveImport(
      pages: pages,
      fileGroups: groups,
      pickedCount: picked,
      unreadable: unreadable.clamp(0, picked),
      pdfTruncated: truncated,
    );
  }
}
