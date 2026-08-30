import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:marking_prokect_v2/services/bulk_page_processor.dart';

Uint8List _b(int n) => Uint8List.fromList([n]);

List<PickedPhoto> _photos(int count) =>
    [for (var i = 0; i < count; i++) PickedPhoto(bytes: _b(i), fileName: 'p$i.jpg')];

void main() {
  group('preparing a pile of picked photos', () {
    test('processes every photo, in the order they were picked', () async {
      final result = await processPickedPages(
        _photos(3),
        process: (bytes) async => Uint8List.fromList([...bytes, 99]),
      );

      expect(result.pages.length, 3);
      expect(result.pages.map((p) => p.fileName), ['p0.jpg', 'p1.jpg', 'p2.jpg']);
      expect(result.pages.first.bytes, Uint8List.fromList([0, 99]));
      expect(result.cancelled, isFalse);
    });

    test('counts progress from one, so a teacher sees "1 of 30" not "0 of 30"', () async {
      final seen = <(int, int)>[];
      await processPickedPages(
        _photos(3),
        process: (bytes) async => bytes,
        onProgress: (done, total) => seen.add((done, total)),
      );

      expect(seen, [(1, 3), (2, 3), (3, 3)]);
    });

    test('stops as soon as the teacher cancels, and says it was cancelled', () async {
      var processed = 0;
      final result = await processPickedPages(
        _photos(30),
        process: (bytes) async {
          processed++;
          return bytes;
        },
        isCancelled: () => processed >= 4,
      );

      // Stops promptly rather than grinding through the other twenty-six.
      expect(processed, 4);
      expect(result.cancelled, isTrue);
    });

    test('a cancelled run still hands back the pages it already prepared', () async {
      var processed = 0;
      final result = await processPickedPages(
        _photos(10),
        process: (bytes) async {
          processed++;
          return bytes;
        },
        isCancelled: () => processed >= 3,
      );

      expect(result.pages.length, 3);
    });

    test('one unreadable photo does not throw away the other twenty-nine', () async {
      final result = await processPickedPages(
        _photos(5),
        process: (bytes) async {
          if (bytes.first == 2) throw Exception('corrupt photo');
          return bytes;
        },
      );

      expect(result.pages.length, 4);
      expect(result.failed, ['p2.jpg']);
      expect(result.pages.map((p) => p.fileName), ['p0.jpg', 'p1.jpg', 'p3.jpg', 'p4.jpg']);
    });

    test('nothing picked is not an error', () async {
      final result = await processPickedPages(const [], process: (b) async => b);
      expect(result.pages, isEmpty);
      expect(result.cancelled, isFalse);
    });
  });

  group('warning before a pile too big to hold', () {
    test('an ordinary class set needs no warning', () {
      expect(bulkPickWarning(30), isNull);
      expect(bulkPickWarning(kMaxGalleryPhotos), isNull);
    });

    test('past the cap the teacher is told what will happen, with the real numbers', () {
      final warning = bulkPickWarning(200);
      expect(warning, isNotNull);
      expect(warning, contains('200'));
      expect(warning, contains('$kMaxGalleryPhotos'));
    });

    test('the cap is what actually gets processed', () {
      expect(capPicked(_photos(200)).length, kMaxGalleryPhotos);
      expect(capPicked(_photos(5)).length, 5);
    });
  });
}
