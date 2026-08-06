import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

/// One word read off the page, with the rectangle it actually occupies (in
/// image pixels).
class RecognizedWord {
  final String text;
  final Rect rect;
  final int lineId;
  const RecognizedWord({required this.text, required this.rect, required this.lineId});
}

/// Anchors AI error marks to the real words on the page.
///
/// A vision model can say roughly where an error is, but never precisely —
/// its coordinates drift by a line or two, which reads as sloppy marking.
/// On-device text recognition gives exact word rectangles, so the AI's
/// estimate is downgraded to a hint that only picks WHICH occurrence of a
/// repeated word ("familys" four times) the mark belongs to.
class WordLocator {
  /// Reads every word on the page. Returns an empty list when recognition
  /// isn't possible (web, unreadable handwriting, missing model) — callers
  /// fall back to the AI's estimated positions.
  static Future<List<RecognizedWord>> recognize(Uint8List bytes) async {
    if (kIsWeb) return const [];
    TextRecognizer? recognizer;
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/ocr_${identityHashCode(bytes)}.jpg');
      await file.writeAsBytes(bytes, flush: true);
      recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final result = await recognizer.processImage(InputImage.fromFilePath(file.path));
      final words = <RecognizedWord>[];
      var lineId = 0;
      for (final block in result.blocks) {
        for (final line in block.lines) {
          for (final el in line.elements) {
            words.add(RecognizedWord(text: el.text, rect: el.boundingBox, lineId: lineId));
          }
          lineId++;
        }
      }
      return words;
    } catch (e) {
      debugPrint('WordLocator.recognize failed: $e');
      return const [];
    } finally {
      await recognizer?.close();
    }
  }

  /// The text an error label points at: "dont → don't" yields "dont".
  /// Labels without an arrow ("run-on sentence") have no anchor word.
  static String? targetOf(String feedback) {
    final m = RegExp(r'^(.{1,48}?)\s*(?:→|->|=>|:)\s*\S').firstMatch(feedback.trim());
    final t = m?.group(1)?.trim();
    if (t == null || t.isEmpty) return null;
    // Guard against labels like "missing apostrophe: students freedom" where
    // the left side is a category rather than the student's actual words.
    return t.length > 40 ? null : t;
  }

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r"[^a-z0-9']"), '');

  /// Rectangle of [target] on the page, choosing the occurrence closest to
  /// the AI's estimate ([hintX]/[hintY] as 0–1 page fractions).
  static Rect? locate({
    required List<RecognizedWord> words,
    required String target,
    required double hintX,
    required double hintY,
    required Size imageSize,
  }) {
    final tokens = target.split(RegExp(r'\s+')).map(_norm).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty || words.isEmpty) return null;

    final matches = <Rect>[];
    for (var i = 0; i < words.length; i++) {
      if (_norm(words[i].text) != tokens.first) continue;
      var rect = words[i].rect;
      var ok = true;
      for (var t = 1; t < tokens.length; t++) {
        final j = i + t;
        if (j >= words.length || words[j].lineId != words[i].lineId || _norm(words[j].text) != tokens[t]) {
          ok = false;
          break;
        }
        rect = rect.expandToInclude(words[j].rect);
      }
      if (ok) matches.add(rect);
    }
    if (matches.isEmpty) return null;

    double distance(Rect r) {
      final cx = r.center.dx / imageSize.width;
      final cy = r.center.dy / imageSize.height;
      // Vertical agreement matters most — the AI is far better at "which
      // line" than "how far along the line".
      final dx = (cx - hintX).abs();
      final dy = (cy - hintY).abs();
      return dy * 3 + dx;
    }

    matches.sort((a, b) => distance(a).compareTo(distance(b)));
    return matches.first;
  }
}
