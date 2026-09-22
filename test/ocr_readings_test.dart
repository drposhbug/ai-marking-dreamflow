import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:marking_prokect_v2/services/recognized_text.dart';

OcrReading _r(String text, {double confidence = 92, int lineId = 0, Rect? rect}) => OcrReading(
      text: text,
      rect: rect ?? const Rect.fromLTWH(40, 100, 60, 28),
      lineId: lineId,
      confidence: confidence,
    );

void main() {
  group('deciding which OCR readings to act on', () {
    // A browser reads a page with Tesseract, which will hand back a guess
    // for anything ink-shaped. Acting on a guess is how a name field gets
    // "found" in the wrong place and the real one left showing.

    test('a confident printed label is kept, with its box and its line', () {
      final words = believableWords([_r('Name:', confidence: 94, lineId: 3)]);
      expect(words, hasLength(1));
      expect(words.single.text, 'Name:');
      expect(words.single.lineId, 3);
      expect(words.single.rect, const Rect.fromLTWH(40, 100, 60, 28));
    });

    test('a reading the engine is unsure of is dropped, not downgraded', () {
      expect(believableWords([_r('Nom2', confidence: 21)]), isEmpty);
    });

    test('the threshold can be moved but defaults to something defensible', () {
      expect(believableWords([_r('smudge', confidence: 40)]), isEmpty);
      expect(believableWords([_r('smudge', confidence: 40)], minConfidence: 30), hasLength(1));
    });

    test('blank and whitespace readings are dropped', () {
      expect(believableWords([_r(''), _r('   '), _r('\n')]), isEmpty);
    });

    test('a box with no area is dropped, because nothing can be covered by it', () {
      expect(believableWords([_r('Name:', rect: const Rect.fromLTWH(10, 10, 0, 20))]), isEmpty);
      expect(believableWords([_r('Name:', rect: const Rect.fromLTWH(10, 10, 30, 0))]), isEmpty);
    });

    test('order and line grouping survive, so a line can be rebuilt from them', () {
      final words = believableWords([
        _r('Name:', lineId: 0, rect: const Rect.fromLTWH(40, 40, 60, 28)),
        _r('scrawl', lineId: 0, confidence: 12, rect: const Rect.fromLTWH(110, 40, 90, 28)),
        _r('Photosynthesis', lineId: 1, rect: const Rect.fromLTWH(40, 120, 180, 28)),
      ]);
      expect(words.map((w) => w.text).toList(), ['Name:', 'Photosynthesis']);
      expect(words.map((w) => w.lineId).toList(), [0, 1]);
    });
  });
}
