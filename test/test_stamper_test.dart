import 'package:flutter_test/flutter_test.dart';
import 'package:marking_prokect_v2/services/test_stamper.dart';

void main() {
  group('the code itself', () {
    test('avoids characters that get misread off a scan', () {
      // 0/O, 1/I/L, 5/S, 8/B are the pairs that ruin a scanned code.
      for (var i = 0; i < 200; i++) {
        final code = TestStamper.newTestCode();
        expect(code.length, 4);
        expect(RegExp(r'^[ACDEFGHJKMNPQRTUVWXY234679]+$').hasMatch(code), isTrue,
            reason: 'code "$code" contains an ambiguous character');
      }
    });

    test('the stamp reads back exactly as printed', () {
      final s = TestStamper.stampFor(testCode: '7F3A', copyNumber: 7, pageNumber: 2, pageCount: 3);
      final read = TestStamper.readStamp(s);
      expect(read, isNotNull);
      expect(read!.testCode, '7F3A');
      expect(read.copyNumber, 7);
      expect(read.pageNumber, 2);
      expect(read.pageCount, 3);
    });
  });

  group('surviving what OCR does to a tiny grey footer', () {
    test('separators come back as anything', () {
      for (final sep in ['·', '•', '.', '-', ':', ' ']) {
        final read = TestStamper.readStamp('mk${sep}7F3A${sep}09 · p1/3');
        expect(read?.copyNumber, 9, reason: 'separator "$sep" defeated the reader');
      }
    });

    test('case is unreliable', () {
      expect(TestStamper.readStamp('MK·7F3A·03')?.testCode, '7F3A');
      expect(TestStamper.readStamp('mk·7f3a·03')?.testCode, '7F3A');
    });

    test('the stamp is found inside a page full of other text', () {
      const page = 'Unit Test - Energy\nName: Ana Lopez\n1. Define energy.\nmk·7F3A·12 · p2/3';
      final read = TestStamper.readStamp(page);
      expect(read?.copyNumber, 12);
      expect(read?.pageNumber, 2);
    });

    test('a page with no stamp is null, not a guess', () {
      expect(TestStamper.readStamp('Name: Ana Lopez  Page 1 of 3'), isNull);
      expect(TestStamper.readStamp(''), isNull);
    });

    test('a mangled code is rejected rather than half-read', () {
      // Three characters isn't a code — better no answer than a wrong paper.
      expect(TestStamper.readStamp('mk·7F3·02'), isNull);
    });
  });

  group('grouping a stack by its stamps', () {
    StampRead s(int copy, int page) => StampRead(testCode: '7F3A', copyNumber: copy, pageNumber: page, pageCount: 3);

    test('pages sharing a copy code are one paper', () {
      // Scanned in order: copy 1 pages 1-3, then copy 2 pages 1-3.
      final g = TestStamper.groupByStamp([s(1, 1), s(1, 2), s(1, 3), s(2, 1), s(2, 2), s(2, 3)]);
      expect(g.groups, [
        [0, 1, 2],
        [3, 4, 5],
      ]);
      expect(g.unstamped, isEmpty);
    });

    test('a shuffled stack still groups correctly', () {
      // THE case the whole feature exists for: pages interleaved.
      final g = TestStamper.groupByStamp([s(1, 1), s(2, 1), s(1, 2), s(2, 2)]);
      expect(g.groups, [
        [0, 2],
        [1, 3],
      ]);
    });

    test('a paper fed in backwards comes out reading forwards', () {
      final g = TestStamper.groupByStamp([s(1, 3), s(1, 1), s(1, 2)]);
      expect(g.groups.first, [1, 2, 0]);
    });

    test('unstamped pages are set aside, not forced into a paper', () {
      final g = TestStamper.groupByStamp([s(1, 1), null, s(1, 2)]);
      expect(g.groups, [
        [0, 2],
      ]);
      expect(g.unstamped, [1]);
    });

    test('a copy missing a page is reported', () {
      final stamps = [s(1, 1), s(1, 2), s(2, 1), s(2, 2), s(2, 3)];
      final g = TestStamper.groupByStamp(stamps);
      // Copy 1 has two of its three pages — the feeder ate one.
      expect(g.shortCopies(stamps), [1]);
    });

    test('a fully unstamped stack is simply not usable', () {
      final g = TestStamper.groupByStamp([null, null, null]);
      expect(g.isUsable, isFalse);
      expect(g.unstamped.length, 3);
    });
  });
}
