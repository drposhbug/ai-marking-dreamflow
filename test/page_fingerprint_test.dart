import 'package:flutter_test/flutter_test.dart';
import 'package:marking_prokect_v2/services/page_fingerprint.dart';

/// Builds a fingerprint from a 16-hex-char string with enough detail to be
/// taken seriously.
PageFingerprint fp(String hex, {int detail = 20}) => PageFingerprint(hex, detail);

void main() {
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
