import 'package:flutter_test/flutter_test.dart';
import 'package:marking_prokect_v2/services/anonymizer.dart';

void main() {
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
}
