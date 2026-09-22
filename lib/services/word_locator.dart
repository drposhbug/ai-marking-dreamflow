import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:marking_prokect_v2/services/page_text_reader.dart';
import 'package:marking_prokect_v2/services/recognized_text.dart';

export 'package:marking_prokect_v2/services/recognized_text.dart' show RecognizedWord, OcrTrust;

/// Anchors AI error marks to the real words on the page, and finds the line
/// a student's name is written on.
///
/// A vision model can say roughly where an error is, but never precisely —
/// its coordinates drift by a line or two, which reads as sloppy marking.
/// Text recognition gives exact word rectangles, so the AI's estimate is
/// downgraded to a hint that only picks WHICH occurrence of a repeated word
/// ("familys" four times) the mark belongs to.
///
/// Which recogniser runs is a platform question answered by
/// `page_text_reader.dart`. How much it can be trusted is a different
/// question, answered by [trust], and callers have to ask it: a browser
/// reads the printed `Name:` on a test template but not the handwriting
/// beside it.
class WordLocator {
  /// Whether this platform can read a page at all.
  static bool get available => PageTextReader.available;

  /// How much of a page the reader here can actually read.
  static OcrTrust get trust => PageTextReader.trust;

  /// True while the reader is fetching what it needs. Only a browser ever
  /// has to, and only once.
  static ValueListenable<bool> get preparing => PageTextReader.preparing;

  /// Gets the reader ready before it is needed, so the teacher does not wait
  /// on a download at the moment they tap Mark. Cheap and idempotent
  /// everywhere; fire and forget.
  static Future<void> warmUp() => PageTextReader.warmUp();

  /// Reads every word on the page. Returns an empty list when recognition
  /// isn't possible (unreadable handwriting, a missing model, an engine that
  /// would not load) — callers fall back to the AI's estimated positions,
  /// and anything that was going to redact a name reports that it did not.
  static Future<List<RecognizedWord>> recognize(Uint8List bytes) => PageTextReader.read(bytes);

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
