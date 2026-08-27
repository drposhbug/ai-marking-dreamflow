import 'package:flutter_test/flutter_test.dart';
import 'package:marking_prokect_v2/services/page_fingerprint.dart';

/// Builds a fingerprint from a 16-hex-char string with enough detail to be
/// taken seriously.
PageFingerprint fp(String hex, {int detail = 20}) => PageFingerprint(hex, detail);

void main() {
  _mixedNameTests();
  group('telling pages apart', () {
    test('identical pages match', () {
      expect(fp('a1b2c3d4e5f60718').matches(fp('a1b2c3d4e5f60718')), isTrue);
    });

    test('a rescan of the same sheet still matches', () {
      // One bit of scanner noise.
      expect(fp('a1b2c3d4e5f60718').matches(fp('a1b2c3d4e5f60719')), isTrue);
    });

    test('different pages do not match', () {
      expect(fp('0000000000000000').matches(fp('ffffffffffffffff')), isFalse);
    });

    test('blank pages never match anything', () {
      // Every test has a blank back page; if those matched, every paper
      // would look like it contained a duplicate.
      final blank = fp('0000000000000000', detail: 1);
      expect(blank.matches(fp('0000000000000000', detail: 1)), isFalse);
      expect(blank.matches(fp('a1b2c3d4e5f60718')), isFalse);
    });

    test('distance is symmetric and zero for a match', () {
      final a = fp('a1b2c3d4e5f60718');
      final b = fp('a1b2c3d4e5f60719');
      expect(a.distanceTo(a), 0);
      expect(a.distanceTo(b), b.distanceTo(a));
    });
  });

  group('catching a wrong split before credits are spent', () {
    final clean = [fp('1111111111111111'), fp('2222222222222222'), fp('3333333333333333'), fp('4444444444444444')];

    test('a clean two-paper stack raises nothing', () {
      final check = StackCheck.run(
        groups: [
          [0, 1],
          [2, 3],
        ],
        fingerprints: clean,
        coverPage: [true, false, true, false],
      );
      expect(check.anySuspect, isFalse);
      expect(check.wholeStackLooksWrong, isFalse);
    });

    test('the same sheet twice in one paper is caught', () {
      final check = StackCheck.run(
        groups: [
          [0, 1],
          [2, 3],
        ],
        fingerprints: [fp('1111111111111111'), fp('1111111111111111'), fp('3333333333333333'), fp('4444444444444444')],
        coverPage: [true, false, true, false],
      );
      expect(check.papers[0].faults, contains(PaperFault.duplicatePage));
      expect(check.papers[1].isSuspect, isFalse);
    });

    test('two cover pages in one paper means a boundary was missed', () {
      final check = StackCheck.run(
        groups: [
          [0, 1, 2, 3],
        ],
        fingerprints: clean,
        coverPage: [true, false, true, false],
      );
      expect(check.papers[0].faults, contains(PaperFault.twoCoverPages));
    });

    test('the same paper appearing twice in a stack is caught', () {
      final check = StackCheck.run(
        groups: [
          [0, 1],
          [2, 3],
        ],
        fingerprints: [fp('1111111111111111'), fp('9999999999999999'), fp('1111111111111111'), fp('8888888888888888')],
        coverPage: [true, false, true, false],
      );
      expect(check.papers[1].faults, contains(PaperFault.duplicateOfAnotherPaper));
    });

    test('when most of the stack is suspect, the ORDER is wrong', () {
      // Three papers, two of them carrying two cover pages each.
      final check = StackCheck.run(
        groups: [
          [0, 1],
          [2, 3],
          [4, 5],
        ],
        fingerprints: [
          fp('1111111111111111'), fp('2222222222222222'),
          fp('3333333333333333'), fp('4444444444444444'),
          fp('5555555555555555'), fp('6666666666666666'),
        ],
        coverPage: [true, true, true, true, true, false],
      );
      expect(check.suspects.length, 2);
      expect(check.wholeStackLooksWrong, isTrue);
    });

    test('one bad paper in a big stack is not the whole stack', () {
      final groups = [for (var i = 0; i < 10; i++) [i * 2, i * 2 + 1]];
      // Well-separated hashes: a repeated byte per page, so two different
      // pages are ~8+ bits apart the way real pages are. Sequential hex
      // strings would differ by one bit and all look like the same sheet.
      // Nibbles chosen to be >=2 bits apart, so any two pages sit >=16 bits
      // apart — comfortably outside the 8-bit same-sheet threshold.
      const codes = ['0', '3', '5', '6', '9', 'a', 'c', 'f'];
      String distinct(int i) => codes[i % 8] * 8 + codes[(i ~/ 8) % 8] * 8;
      final fps = [for (var i = 0; i < 20; i++) fp(distinct(i))];
      final covers = [for (var i = 0; i < 20; i++) i.isEven];
      covers[3] = true; // paper 1 has a second cover page
      final check = StackCheck.run(groups: groups, fingerprints: fps, coverPage: covers);
      expect(check.suspects.length, 1);
      expect(check.wholeStackLooksWrong, isFalse);
    });

    test('an empty stack is not an error', () {
      final check = StackCheck.run(groups: const [], fingerprints: const [], coverPage: const []);
      expect(check.anySuspect, isFalse);
      expect(check.wholeStackLooksWrong, isFalse);
    });
  });
}

// ── The mistake a page-number footer would HIDE ───────────────────────────
// "Name: ___  MATH9-U3 · p1/3" printed on every page means a shuffled page
// still reads 1, 2, 3 — the sequence looks perfect while one page belongs
// to somebody else. The name on each page is the only thing that catches
// it, so these cases matter more than the tidy ones.
void _mixedNameTests() {
  group('recognising the same student across pages', () {
    test('identical names are the same student', () {
      expect(sameStudentName('Ana Lopez', 'Ana Lopez'), isTrue);
    });

    test('case and punctuation do not matter', () {
      expect(sameStudentName('ANA LOPEZ', 'ana lopez.'), isTrue);
    });

    test('a shortened name is the same student', () {
      expect(sameStudentName('Ana Lopez', 'Ana'), isTrue);
      expect(sameStudentName('Ana', 'Ana Lopez'), isTrue);
    });

    test('one misread letter is forgiven', () {
      expect(sameStudentName('Ana Lopez', 'Anq Lopez'), isTrue);
    });

    test('a missing name is no evidence, not a mismatch', () {
      expect(sameStudentName('', 'Ana Lopez'), isTrue);
      expect(sameStudentName('Ana Lopez', ''), isTrue);
    });

    test('genuinely different students are different', () {
      expect(sameStudentName('Ana Lopez', 'Ben Carter'), isFalse);
      expect(sameStudentName('Ana', 'Ben'), isFalse);
    });
  });

  group('a shuffled page inside a valid-looking paper', () {
    final fps = [
      PageFingerprint('1111111111111111', 20),
      PageFingerprint('2222222222222222', 20),
      PageFingerprint('3333333333333333', 20),
    ];

    test('is caught when the pages name different students', () {
      final check = StackCheck.run(
        groups: [
          [0, 1, 2],
        ],
        fingerprints: fps,
        // Page numbering would read 1, 2, 3 — perfectly valid looking.
        coverPage: [true, false, false],
        names: ['Ana Lopez', 'Ben Carter', 'Ana Lopez'],
      );
      expect(check.papers[0].faults, contains(PaperFault.mixedNames));
    });

    test('is not raised when only some pages carry a name', () {
      final check = StackCheck.run(
        groups: [
          [0, 1, 2],
        ],
        fingerprints: fps,
        coverPage: [true, false, false],
        names: ['Ana Lopez', null, ''],
      );
      expect(check.papers[0].isSuspect, isFalse);
    });

    test('is not raised for the same student written two ways', () {
      final check = StackCheck.run(
        groups: [
          [0, 1, 2],
        ],
        fingerprints: fps,
        coverPage: [true, false, false],
        names: ['Ana Lopez', 'Ana', 'ANA LOPEZ'],
      );
      expect(check.papers[0].isSuspect, isFalse);
    });

    test('still works when no names were read at all', () {
      final check = StackCheck.run(
        groups: [
          [0, 1, 2],
        ],
        fingerprints: fps,
        coverPage: [true, false, false],
      );
      expect(check.papers[0].isSuspect, isFalse);
    });
  });
}
