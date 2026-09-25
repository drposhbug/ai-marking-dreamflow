import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:marking_prokect_v2/services/anonymizer.dart';
import 'package:marking_prokect_v2/services/ink_extent.dart';

/// A scanned-looking page: near-white paper rather than pure white, so the
/// threshold has to be derived rather than assumed.
img.Image _page({int width = 1000, int height = 400, int paper = 246}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(paper, paper, paper));
  return image;
}

/// Lays down a block of dark pixels, the way a word sits on a line.
void _ink(img.Image image, {required int x0, required int x1, required int y0, required int y1, int value = 40}) {
  img.fillRect(image, x1: x0, y1: y0, x2: x1, y2: y1, color: img.ColorRgb8(value, value, value));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('finding where the writing on a line stops', () {
    test('stops at the end of the name, not the edge of the paper', () {
      final image = _page();
      // "Name:" label, then a handwritten name, then nothing.
      _ink(image, x0: 40, x1: 120, y0: 100, y1: 130);
      _ink(image, x0: 150, x1: 300, y0: 100, y1: 130);

      final end = InkExtent.endOfWriting(image, top: 100, bottom: 130, fromX: 0);

      expect(end, isNotNull);
      expect(end, closeTo(300, 4));
    });

    test('steps over the gap between a first and last name', () {
      final image = _page();
      _ink(image, x0: 40, x1: 120, y0: 100, y1: 130); // Name:
      _ink(image, x0: 150, x1: 240, y0: 100, y1: 130); // Ana
      _ink(image, x0: 268, x1: 390, y0: 100, y1: 130); // Lopez

      final end = InkExtent.endOfWriting(image, top: 100, bottom: 130, fromX: 0);

      expect(end, closeTo(390, 4), reason: 'a 28px word gap is not the end of the writing');
    });

    test('does not run on into the Date field sharing the line', () {
      final image = _page();
      _ink(image, x0: 40, x1: 120, y0: 100, y1: 130); // Name:
      _ink(image, x0: 150, x1: 320, y0: 100, y1: 130); // the name
      _ink(image, x0: 700, x1: 900, y0: 100, y1: 130); // Date: 4 Mar

      final end = InkExtent.endOfWriting(image, top: 100, bottom: 130, fromX: 0);

      expect(end, closeTo(320, 4));
      expect(end! < 700, isTrue, reason: 'the date is on the same line and is not the student');
    });

    test('gives up when ink runs to the edge, so the caller covers it all', () {
      final image = _page();
      _ink(image, x0: 40, x1: 995, y0: 100, y1: 130);

      expect(InkExtent.endOfWriting(image, top: 100, bottom: 130, fromX: 0), isNull);
    });

    test('gives up on a blank band rather than inventing an end', () {
      expect(InkExtent.endOfWriting(_page(), top: 100, bottom: 130, fromX: 0), isNull);
    });

    test('reads a grey photocopy, where paper is far from white', () {
      final image = _page(paper: 188);
      _ink(image, x0: 40, x1: 120, y0: 100, y1: 130, value: 96);
      _ink(image, x0: 150, x1: 300, y0: 100, y1: 130, value: 96);

      final end = InkExtent.endOfWriting(image, top: 100, bottom: 130, fromX: 0);

      expect(end, closeTo(300, 4), reason: 'the threshold comes from this page, not a constant');
    });

    test('ignores a speck of dust', () {
      final image = _page();
      _ink(image, x0: 40, x1: 200, y0: 100, y1: 130);
      image.setPixel(600, 115, img.ColorRgb8(20, 20, 20)); // one stray pixel

      final end = InkExtent.endOfWriting(image, top: 100, bottom: 130, fromX: 0);

      expect(end, closeTo(200, 4));
    });
  });

  group('what actually gets painted over', () {
    /// True when the column is black across the band.
    bool blackAt(img.Image image, int x, int y) {
      final p = image.getPixel(x, y);
      return p.r < 24 && p.g < 24 && p.b < 24;
    }

    test('an open-ended region covers the name and spares the rest of the line', () {
      final page = _page();
      _ink(page, x0: 40, x1: 120, y0: 100, y1: 130); // Name:
      _ink(page, x0: 150, x1: 300, y0: 100, y1: 130); // the name
      // A question sitting further along the same line, which the old
      // edge-to-edge redaction destroyed.
      _ink(page, x0: 700, x1: 950, y0: 100, y1: 130);

      final masked = Anonymizer.maskRegions(
        Uint8List.fromList(img.encodePng(page)),
        [const Rect.fromLTRB(0, 100, double.infinity, 130)],
      );
      expect(masked, isNotNull);
      final out = img.decodeImage(masked!)!;

      expect(blackAt(out, 200, 115), isTrue, reason: 'the name must be covered');
      expect(blackAt(out, 290, 115), isTrue, reason: 'to the end of the name');
      expect(blackAt(out, 800, 115), isFalse, reason: 'the rest of the line must survive');
    });

    test('falls back to the full width when the ink gives no answer', () {
      final page = _page();
      _ink(page, x0: 40, x1: 995, y0: 100, y1: 130);

      final masked = Anonymizer.maskRegions(
        Uint8List.fromList(img.encodePng(page)),
        [const Rect.fromLTRB(0, 100, double.infinity, 130)],
      );
      final out = img.decodeImage(masked!)!;

      expect(blackAt(out, 950, 115), isTrue, reason: 'covering everything is still the safe answer');
    });

    test('a measured region is left exactly as the reader measured it', () {
      final page = _page();
      _ink(page, x0: 150, x1: 300, y0: 100, y1: 130);
      _ink(page, x0: 700, x1: 950, y0: 100, y1: 130);

      final masked = Anonymizer.maskRegions(
        Uint8List.fromList(img.encodePng(page)),
        [const Rect.fromLTRB(150, 100, 300, 130)],
      );
      final out = img.decodeImage(masked!)!;

      expect(blackAt(out, 200, 115), isTrue);
      expect(blackAt(out, 800, 115), isFalse, reason: 'a phone reading must not be widened by this');
    });
  });
}
