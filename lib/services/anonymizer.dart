import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:marking_prokect_v2/services/word_locator.dart';

/// A page prepared for marking, with the student's identity kept behind.
class AnonymizedPage {
  /// What actually gets uploaded.
  final Uint8List bytes;

  /// The name read off the paper — read HERE, on the phone, and never sent
  /// anywhere. It is what links the result to the right student locally.
  final String? nameOnPaper;

  /// True when something was actually covered up. False means no name field
  /// was found, so the page went up unchanged.
  final bool redacted;

  const AnonymizedPage({required this.bytes, required this.nameOnPaper, required this.redacted});
}

/// Keeps student identity out of what gets sent for marking.
///
/// The marking model never needs to know whose paper it is — it grades the
/// work. So the name is read on the device, blacked out of the image, and
/// only the anonymous page is uploaded. The name stays on the phone and is
/// what files the result under the right student.
///
/// This is better than it sounds for accuracy too: reading the name locally
/// is free and exact, where asking the model to read it costs tokens and
/// gets misread handwriting wrong.
class Anonymizer {
  /// Labels that introduce a student's identity on a school paper.
  static final _identityLabel = RegExp(
    r'^\s*(?:student\s+)?(?:name|nom|full\s+name|student|pupil|student\s*(?:id|number|#))\s*[:.\-]',
    caseSensitive: false,
  );

  /// Not a name, even when it follows a "Name:"-shaped label.
  static final _notAName = RegExp(
    r'^(?:date|class|period|block|section|grade|teacher|subject|score|mark|total|page)\b',
    caseSensitive: false,
  );

  /// Reads and hides the identity on one page.
  ///
  /// Falls back to the untouched page whenever recognition or redaction
  /// fails — a marking run must never be blocked by this, but the caller is
  /// told via [AnonymizedPage.redacted] so the UI can be honest about it.
  static Future<AnonymizedPage> page(Uint8List bytes) async {
    if (kIsWeb) return AnonymizedPage(bytes: bytes, nameOnPaper: null, redacted: false);
    try {
      final words = await WordLocator.recognize(bytes);
      if (words.isEmpty) return AnonymizedPage(bytes: bytes, nameOnPaper: null, redacted: false);

      final byLine = <int, List<RecognizedWord>>{};
      for (final w in words) {
        (byLine[w.lineId] ??= <RecognizedWord>[]).add(w);
      }

      String? name;
      final toCover = <Rect>[];
      for (final entry in byLine.entries) {
        final lineWords = entry.value..sort((a, b) => a.rect.left.compareTo(b.rect.left));
        final text = lineWords.map((w) => w.text).join(' ').trim();
        if (text.isEmpty || !_identityLabel.hasMatch(text)) continue;

        final value = _valueAfterLabel(text);
        // Cover the whole line: the label alone identifies nobody, but the
        // handwriting beside it does, and its exact extent is guesswork.
        toCover.add(_lineBounds(lineWords));
        name ??= value;
      }
      if (toCover.isEmpty) return AnonymizedPage(bytes: bytes, nameOnPaper: null, redacted: false);

      final redacted = await compute(_maskRegions, _MaskJob(bytes, toCover));
      return AnonymizedPage(
        bytes: redacted ?? bytes,
        nameOnPaper: name,
        redacted: redacted != null,
      );
    } catch (e) {
      debugPrint('Anonymizer.page failed: $e');
      return AnonymizedPage(bytes: bytes, nameOnPaper: null, redacted: false);
    }
  }

  /// Runs [page] across a whole paper, keeping the first name found.
  static Future<(List<Uint8List>, String?)> pages(List<Uint8List> pages) async {
    final out = <Uint8List>[];
    String? name;
    for (final p in pages) {
      final a = await page(p);
      out.add(a.bytes);
      name ??= a.nameOnPaper;
    }
    return (out, name);
  }

  static Rect _lineBounds(List<RecognizedWord> words) {
    var left = double.infinity, top = double.infinity, right = 0.0, bottom = 0.0;
    for (final w in words) {
      if (w.rect.left < left) left = w.rect.left;
      if (w.rect.top < top) top = w.rect.top;
      if (w.rect.right > right) right = w.rect.right;
      if (w.rect.bottom > bottom) bottom = w.rect.bottom;
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  static String? _valueAfterLabel(String line) {
    final m = RegExp(r'[:.\-]\s*(.+)$').firstMatch(line);
    var rest = (m?.group(1) ?? '').trim();
    if (rest.isEmpty) return null;
    final cut = RegExp(r'\s{2,}|\s(?=(?:date|class|period|block|section|grade)\s*[:.\-])', caseSensitive: false).firstMatch(rest);
    if (cut != null) rest = rest.substring(0, cut.start).trim();
    rest = rest.replaceAll(RegExp(r'[_\.]{2,}'), ' ').trim();
    if (rest.isEmpty || _notAName.hasMatch(rest)) return null;
    if (rest.length < 2 || rest.length > 40) return null;
    if (!RegExp(r'[A-Za-z]').hasMatch(rest)) return null;
    return rest;
  }

  /// Removes names the teacher already knows from free text before it is
  /// sent for marking — a student who signed their essay, or wrote a
  /// classmate's name in an answer.
  ///
  /// Whole-word, case-insensitive, longest names first so "Ana Lopez" is
  /// replaced before the bare "Ana" inside it.
  static String scrubNames(String text, Iterable<String> names) {
    if (text.isEmpty) return text;
    final parts = <String>{};
    for (final full in names) {
      final n = full.trim();
      if (n.length < 3) continue; // "Al", "Jo" — too short to match safely
      parts.add(n);
      for (final piece in n.split(RegExp(r'\s+'))) {
        if (piece.length >= 3) parts.add(piece);
      }
    }
    if (parts.isEmpty) return text;
    final ordered = parts.toList()..sort((a, b) => b.length.compareTo(a.length));
    var out = text;
    for (final p in ordered) {
      out = out.replaceAll(
        RegExp('(?<![A-Za-z])${RegExp.escape(p)}(?![A-Za-z])', caseSensitive: false),
        '[name]',
      );
    }
    return out;
  }
}

class _MaskJob {
  final Uint8List bytes;
  final List<Rect> regions;
  const _MaskJob(this.bytes, this.regions);
}

/// Paints solid black over each region. Runs in a background isolate — a
/// full-page decode/encode would jank the UI on a class set.
Uint8List? _maskRegions(_MaskJob job) {
  try {
    final image = img.decodeImage(job.bytes);
    if (image == null) return null;
    for (final r in job.regions) {
      // A little padding: recognition boxes hug the glyphs, and a descender
      // or a long tail on handwriting can sit outside them.
      final pad = (image.height * 0.006).round().clamp(2, 14);
      final x = (r.left - pad).round().clamp(0, image.width - 1);
      final y = (r.top - pad).round().clamp(0, image.height - 1);
      final w = (r.width + pad * 2).round().clamp(1, image.width - x);
      final h = (r.height + pad * 2).round().clamp(1, image.height - y);
      img.fillRect(image, x1: x, y1: y, x2: x + w, y2: y + h, color: img.ColorRgb8(0, 0, 0));
    }
    return Uint8List.fromList(img.encodeJpg(image, quality: 88));
  } catch (e) {
    debugPrint('_maskRegions failed: $e');
    return null;
  }
}
