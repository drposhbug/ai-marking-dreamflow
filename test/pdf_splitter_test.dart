import 'package:flutter_test/flutter_test.dart';
import 'package:marking_prokect_v2/services/pdf_splitter.dart';

PageSignals first({String? name}) => PageSignals(firstPageScore: 1.5, sawText: true, studentName: name);
PageSignals cont() => const PageSignals(firstPageScore: 0, sawText: true);
PageSignals blind() => const PageSignals(firstPageScore: 0, sawText: false);

void main() {
  _stackWarningTests();
  group('fixed-length splitting', () {
    test('divides a stack evenly', () {
      expect(PdfSplitter.groupByFixed(9, 3), [
        [0, 1, 2],
        [3, 4, 5],
        [6, 7, 8],
      ]);
    });

    test('keeps a short final paper instead of dropping pages', () {
      final groups = PdfSplitter.groupByFixed(8, 3);
      expect(groups.length, 3);
      expect(groups.last, [6, 7]);
      // Every page must land somewhere — losing one loses a student's work.
      expect(groups.expand((g) => g).toList(), List.generate(8, (i) => i));
    });

    test('a nonsense page count never loses pages', () {
      expect(PdfSplitter.groupByFixed(4, 0).expand((g) => g).length, 4);
    });
  });

  group('detected splitting', () {
    test('starts a paper at each detected cover page', () {
      final signals = [first(name: 'Ana'), cont(), cont(), first(name: 'Ben'), cont()];
      expect(PdfSplitter.groupBySignals(signals), [
        [0, 1, 2],
        [3, 4],
      ]);
    });

    test('page 0 always starts a paper even if it scored nothing', () {
      final signals = [cont(), cont(), first(), cont()];
      final groups = PdfSplitter.groupBySignals(signals);
      expect(groups.first, [0, 1]);
      expect(groups.expand((g) => g).toList(), [0, 1, 2, 3]);
    });

    test('handles papers of different lengths', () {
      final signals = [first(), cont(), first(), cont(), cont(), cont(), first()];
      expect(PdfSplitter.groupBySignals(signals).map((g) => g.length).toList(), [2, 4, 1]);
    });
  });

  group('suggested pages per paper', () {
    test('reads the common gap between cover pages', () {
      final signals = [first(), cont(), cont(), first(), cont(), cont(), first(), cont(), cont()];
      expect(PdfSplitter.suggestPagesPerStudent(signals), 3);
    });

    test('refuses to guess when the stack is ragged', () {
      final signals = [first(), cont(), first(), cont(), cont(), cont(), cont(), first()];
      expect(PdfSplitter.suggestPagesPerStudent(signals), isNull);
    });

    test('needs at least two cover pages', () {
      expect(PdfSplitter.suggestPagesPerStudent([first(), cont()]), isNull);
    });
  });

  group('knowing when detection cannot be trusted', () {
    test('an unreadable scan is unusable', () {
      expect(PdfSplitter.detectionUnusable([blind(), blind(), blind()]), isTrue);
    });

    test('one detected start is not a split', () {
      expect(PdfSplitter.detectionUnusable([first(), cont(), cont()]), isTrue);
    });

    test('a header on every page is meaningless', () {
      expect(PdfSplitter.detectionUnusable([first(), first(), first(), first()]), isTrue);
    });

    test('a real class set is usable', () {
      final signals = [first(), cont(), first(), cont(), first(), cont()];
      expect(PdfSplitter.detectionUnusable(signals), isFalse);
    });
  });
}

// ── The copier's quiet failure ────────────────────────────────────────────
// A double-feed pulls two sheets through as one. Nothing errors; a page is
// simply gone and every boundary after it shifts. Arithmetic is the only
// way to notice, so these cases matter more than the happy path.
void _stackWarningTests() {
  group('stack sanity check', () {
    test('says nothing when a clean stack matches the class size', () {
      expect(
        PdfSplitter.stackWarning(groupLengths: [3, 3, 3, 3], expectedStudents: 4),
        isNull,
      );
    });

    test('says nothing about a tidy stack with no expectation given', () {
      expect(PdfSplitter.stackWarning(groupLengths: [3, 3, 3]), isNull);
    });

    test('flags a missing paper against the expected count', () {
      final w = PdfSplitter.stackWarning(groupLengths: [3, 3, 3], expectedStudents: 4);
      expect(w, contains('Only 3 papers'));
      expect(w, contains('two sheets through at once'));
    });

    test('flags too many papers as a boundary problem, not a missing page', () {
      final w = PdfSplitter.stackWarning(groupLengths: [3, 3, 2, 1], expectedStudents: 3);
      expect(w, contains('split in two'));
    });

    test('spots the one paper that came out short', () {
      final w = PdfSplitter.stackWarning(groupLengths: [3, 3, 2, 3, 3]);
      expect(w, contains('Most papers are 3 pages'));
      expect(w, contains('1 is not'));
    });

    test('stays quiet when lengths genuinely vary, with no normal length', () {
      // An essay task where everyone wrote a different amount: there is no
      // majority length, so "most papers are N" would be a lie.
      expect(PdfSplitter.stackWarning(groupLengths: [1, 2, 3, 4]), isNull);
    });

    test('does not cry wolf on a two-paper stack', () {
      expect(PdfSplitter.stackWarning(groupLengths: [3, 2]), isNull);
    });

    test('an explicit expectation beats the ragged-length check', () {
      final w = PdfSplitter.stackWarning(groupLengths: [3, 3, 2], expectedStudents: 3);
      // Count matches, so it falls through to the short-paper warning.
      expect(w, contains('Most papers are 3 pages'));
    });

    test('handles an empty stack', () {
      expect(PdfSplitter.stackWarning(groupLengths: []), isNull);
    });
  });
}
