import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:marking_prokect_v2/services/anonymizer.dart';
import 'package:marking_prokect_v2/services/word_locator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A line of recognised words, laid out left to right the way the page
/// reader hands them over.
List<RecognizedWord> _line(String text, {required int lineId, double top = 100}) {
  final out = <RecognizedWord>[];
  var left = 40.0;
  for (final w in text.split(' ')) {
    final width = w.length * 12.0;
    out.add(RecognizedWord(text: w, rect: Rect.fromLTWH(left, top, width, 30), lineId: lineId));
    left += width + 6;
  }
  return out;
}

/// A plain white page with a black-free area we can check was painted over.
Uint8List _blankPage({int width = 400, int height = 300}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('scrubbing names out of text sent for marking', () {
    const roster = ['Ana Lopez', 'Ben Carter', 'Dev Patel'];

    test('removes a full name', () {
      expect(
        Anonymizer.scrubNames('Ana Lopez says photosynthesis needs light.', roster),
        '[name] says photosynthesis needs light.',
      );
    });

    test('removes a first name on its own', () {
      expect(Anonymizer.scrubNames('I worked with Ben on this.', roster), 'I worked with [name] on this.');
    });

    test('is case-insensitive', () {
      expect(Anonymizer.scrubNames('ana said so', roster), '[name] said so');
    });

    test('does not touch a name inside a longer word', () {
      // "Benny" and "Bennett" are not Ben; "Devon" is not Dev.
      expect(Anonymizer.scrubNames('Bennett and Devon argued', roster), 'Bennett and Devon argued');
    });

    test('leaves ordinary words alone', () {
      const text = 'The answer is 42 because the graph levels off.';
      expect(Anonymizer.scrubNames(text, roster), text);
    });

    test('replaces the longest match, not a fragment of it', () {
      // "Ana Lopez" must go as one unit, not become "[name] [name]".
      expect(Anonymizer.scrubNames('Ana Lopez', roster), '[name]');
    });

    test('ignores very short names that would match everywhere', () {
      // "Al" inside "also", "although", "already" would be carnage.
      expect(Anonymizer.scrubNames('Although it also works', ['Al']), 'Although it also works');
    });

    test('handles an empty roster and empty text', () {
      expect(Anonymizer.scrubNames('anything', const []), 'anything');
      expect(Anonymizer.scrubNames('', roster), '');
    });

    test('scrubs a name that appears more than once', () {
      expect(
        Anonymizer.scrubNames('Ana wrote it. Ana checked it.', roster),
        '[name] wrote it. [name] checked it.',
      );
    });

    test('survives punctuation around the name', () {
      expect(Anonymizer.scrubNames('(Ana), see above.', roster), '([name]), see above.');
    });
  });

  group('finding the identity line on a page', () {
    test('a "Name:" line is read and marked for covering', () {
      final found = Anonymizer.identityIn(_line('Name: Ana Lopez', lineId: 0));
      expect(found.name, 'Ana Lopez');
      expect(found.found, isTrue);
      expect(found.regions, hasLength(1));
      // The whole line goes, label included — the extent of the handwriting
      // beside it is guesswork.
      expect(found.regions.first.left, lessThanOrEqualTo(40));
      expect(found.regions.first.right, greaterThan(150));
    });

    test('a date line is not an identity line', () {
      final found = Anonymizer.identityIn(_line('Date: 3 May 2026', lineId: 0));
      expect(found.found, isFalse);
      expect(found.name, isNull);
      expect(found.regions, isEmpty);
    });

    test('only the identity line is covered, not the rest of the page', () {
      final words = [
        ..._line('Name: Ben Carter', lineId: 0, top: 40),
        ..._line('Photosynthesis needs light and water', lineId: 1, top: 120),
      ];
      final found = Anonymizer.identityIn(words);
      expect(found.name, 'Ben Carter');
      expect(found.regions, hasLength(1));
      expect(found.regions.first.top, lessThan(60));
    });

    test('a page with nothing on it has nothing to hide', () {
      final found = Anonymizer.identityIn(const []);
      expect(found.found, isFalse);
      expect(found.name, isNull);
    });
  });

  group('finding the identity line when only printed labels can be read', () {
    // What a browser has. Tesseract reads the printed "Name:" off a test
    // template; it does not read the child's handwriting beside it.

    test('the printed label on its own is enough to cover the line', () {
      final found = Anonymizer.identityIn(_line('Name:', lineId: 0), trust: OcrTrust.printedLabelsOnly);
      expect(found.found, isTrue);
      expect(found.regions, hasLength(1));
    });

    test('the cover runs edge to edge, because where the handwriting ends is unknown', () {
      // The dangerous version of this feature covers the label and leaves
      // the name beside it showing, while reporting success.
      final found = Anonymizer.identityIn(_line('Name:', lineId: 0), trust: OcrTrust.printedLabelsOnly);
      expect(found.regions.first.left, 0);
      expect(found.regions.first.right, double.infinity);
    });

    test('nothing beside the label is reported as the student\'s name', () {
      // Whatever this reader made of the scrawl is a guess, and a guessed
      // name files a result under the wrong child without saying so.
      final found = Anonymizer.identityIn(_line('Name: Ana Lopez', lineId: 0), trust: OcrTrust.printedLabelsOnly);
      expect(found.name, isNull);
      expect(found.found, isTrue);
    });

    test('a page with no label read off it is still not redacted', () {
      final found =
          Anonymizer.identityIn(_line('Photosynthesis needs light', lineId: 0), trust: OcrTrust.printedLabelsOnly);
      expect(found.found, isFalse);
      expect(found.name, isNull);
    });

    test('a reader that does read handwriting is unchanged', () {
      final found = Anonymizer.identityIn(_line('Name: Ana Lopez', lineId: 0), trust: OcrTrust.readsHandwriting);
      expect(found.name, 'Ana Lopez');
      expect(found.regions.first.right.isFinite, isTrue);
      expect(found.regions.first.left, greaterThan(0));
    });
  });

  group('blacking the name out of what is uploaded', () {
    test('the region is painted solid black and the rest is left alone', () {
      final masked = Anonymizer.maskRegions(_blankPage(), [const Rect.fromLTWH(40, 40, 120, 30)]);
      expect(masked, isNotNull);
      final out = img.decodeImage(masked!)!;
      // Inside the covered region: black. The name is gone from the bytes
      // that get uploaded, not merely flagged.
      final inside = out.getPixel(100, 55);
      expect(inside.r, lessThan(30));
      expect(inside.g, lessThan(30));
      expect(inside.b, lessThan(30));
      // Well away from it: the page the model has to mark is untouched.
      final outside = out.getPixel(350, 250);
      expect(outside.r, greaterThan(200));
    });

    test('an image that cannot be decoded reports failure instead of pretending', () {
      expect(Anonymizer.maskRegions(Uint8List.fromList([1, 2, 3, 4]), [const Rect.fromLTWH(0, 0, 5, 5)]), isNull);
    });

    test('a region with no known right edge is painted to the edge of the page', () {
      // A reader that cannot see handwriting does not know where the name
      // ends, so it asks for the rest of the line. Infinity means "to the
      // paper's edge", and only the paper knows where that is.
      final masked = Anonymizer.maskRegions(_blankPage(), [const Rect.fromLTRB(0, 40, double.infinity, 70)]);
      expect(masked, isNotNull);
      final out = img.decodeImage(masked!)!;
      expect(out.getPixel(200, 55).r, lessThan(30));
      // The far right of that line, where a name written past the label
      // would sit, is black too.
      expect(out.getPixel(398, 55).r, lessThan(30));
      // And the work below it is untouched — the model still has a page.
      expect(out.getPixel(200, 200).r, greaterThan(200));
    });
  });

  group('reporting what happened to the name', () {
    test('a page where no name field was found reports redacted false', () async {
      // Nothing recognisable on it, so nothing was covered — and the page
      // that goes up is the one that came in.
      final bytes = _blankPage();
      final page = await Anonymizer.page(bytes);
      expect(page.redacted, isFalse);
      expect(page.nameOnPaper, isNull);
      expect(page.bytes, same(bytes));
    });

    test('a paper where nothing was covered is reported as not hidden', () async {
      final set = await Anonymizer.pageSet([_blankPage()]);
      expect(set.anyRedacted, isFalse);
      expect(set.nameOnPaper, isNull);
      expect(Anonymizer.outcome(settingOn: true, anyRedacted: set.anyRedacted, available: true), NameHiding.notFound);
    });

    test('a paper where a name was covered is reported as hidden', () {
      expect(Anonymizer.outcome(settingOn: true, anyRedacted: true, available: true), NameHiding.hidden);
      expect(NameHiding.hidden.hidesTheName, isTrue);
    });

    test('every other outcome has to be said out loud', () {
      expect(NameHiding.notFound.hidesTheName, isFalse);
      expect(NameHiding.unavailable.hidesTheName, isFalse);
      expect(NameHiding.off.hidesTheName, isFalse);
      for (final h in NameHiding.values) {
        expect(h.headline, isNotEmpty);
        expect(h.detail, isNotEmpty);
      }
    });

    test('the teacher turning it off is reported as off, not as hidden', () {
      expect(Anonymizer.outcome(settingOn: false, anyRedacted: false, available: true), NameHiding.off);
    });

    test('a platform with no reader is reported as unable to hide anything, whatever the setting says', () {
      // The setting being on must never be allowed to read as "it happened".
      expect(Anonymizer.outcome(settingOn: true, anyRedacted: false, available: false), NameHiding.unavailable);
      expect(Anonymizer.outcome(settingOn: false, anyRedacted: false, available: false), NameHiding.unavailable);
      expect(NameHiding.unavailable.detail, isNotEmpty);
      // And it must no longer blame the browser for it. A browser hides
      // names now; saying otherwise would send a teacher to cover pages by
      // hand that the app already covered.
      expect(NameHiding.unavailable.detail.toLowerCase(), isNot(contains('browser')));
      expect(NameHiding.unavailable.headline.toLowerCase(), isNot(contains('browser')));
    });

    test('what will happen is said before the work is sent, not after', () {
      // The teacher has to be able to decide before they tap Mark.
      expect(Anonymizer.intent(settingOn: true, available: true), NameHiding.hidden);
      expect(Anonymizer.intent(settingOn: false, available: true), NameHiding.off);
      expect(Anonymizer.intent(settingOn: true, available: false), NameHiding.unavailable);
    });

    test('name hiding is available on this platform, and says so', () {
      // The test VM is not a browser; the browser case is covered above by
      // passing available: false, because kIsWeb cannot be faked here.
      expect(Anonymizer.available, isTrue);
    });

    test('availability is whatever the page reader on this platform says', () {
      // Not "is this a phone" any more. A browser has a reader now, so the
      // answer has to come from the reader that would actually run.
      expect(Anonymizer.available, WordLocator.available);
    });
  });

  group('telling a teacher once, in a browser, that names cannot be hidden', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('is not asked for at all off the web', () {
      expect(WebUploadNotice.needed(onWeb: false, alreadyAcknowledged: false), isFalse);
    });

    test('is asked for the first time, and not again', () async {
      const notice = WebUploadNotice();
      expect(await notice.acknowledged('teacher-1'), isFalse);
      expect(WebUploadNotice.needed(onWeb: true, alreadyAcknowledged: false), isTrue);

      await notice.acknowledge('teacher-1');
      expect(await notice.acknowledged('teacher-1'), isTrue);
      expect(WebUploadNotice.needed(onWeb: true, alreadyAcknowledged: true), isFalse);
    });

    test('one teacher acknowledging does not answer for another on the same machine', () async {
      const notice = WebUploadNotice();
      await notice.acknowledge('teacher-1');
      expect(await notice.acknowledged('teacher-2'), isFalse);
    });
  });
}
