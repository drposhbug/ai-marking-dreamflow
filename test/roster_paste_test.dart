import 'package:flutter_test/flutter_test.dart';
import 'package:marking_prokect_v2/services/roster_paste.dart';

/// A pasted class list is the first thing a teacher does with the app, and
/// it has to cope with whatever their school system copied out — headers,
/// numbering, emails, "Last, First", trailing blank rows.
///
/// The rule these tests hold to: never mangle a real name to make a line
/// tidier. Dropping a child, or filing them under a chopped-up name, is
/// worse than leaving an odd row for the teacher to fix.
void main() {
  group('the ordinary paste', () {
    test('one name per line', () {
      expect(RosterPaste.parse('Ana Ruiz\nBen Cole\nCara Diaz'), ['Ana Ruiz', 'Ben Cole', 'Cara Diaz']);
    });

    test('blank lines and stray spacing are dropped', () {
      expect(RosterPaste.parse('  Ana Ruiz  \n\n\n   \nBen Cole\n'), ['Ana Ruiz', 'Ben Cole']);
    });

    test('double spaces inside a name are collapsed', () {
      expect(RosterPaste.parse('Ana   Ruiz'), ['Ana Ruiz']);
    });

    test('the pasted order is kept', () {
      // Teachers check the list against their register by eye.
      expect(RosterPaste.parse('Zoe Adams\nAlan Beck'), ['Zoe Adams', 'Alan Beck']);
    });
  });

  group('name order', () {
    test('"Last, First" becomes "First Last"', () {
      expect(RosterPaste.parse('Ruiz, Ana'), ['Ana Ruiz']);
    });

    test('a whole list in "Last, First" is flipped', () {
      expect(RosterPaste.parse('Ruiz, Ana\nCole, Ben'), ['Ana Ruiz', 'Ben Cole']);
    });

    test('"First Last" is left exactly as it is', () {
      expect(RosterPaste.parse('Ana Ruiz'), ['Ana Ruiz']);
    });

    test('a two-part surname survives the flip', () {
      expect(RosterPaste.parse('van der Berg, Sofie'), ['Sofie van der Berg']);
    });

    test('a middle name is not rearranged', () {
      expect(RosterPaste.parse('Ana Maria Ruiz'), ['Ana Maria Ruiz']);
    });

    test('two commas are left alone rather than guessed at', () {
      // "Ruiz, Ana, Jr" could be several things. Better an odd row the
      // teacher can see and fix than a silently wrong name.
      expect(RosterPaste.parse('Ruiz, Ana, Jr'), ['Ruiz, Ana, Jr']);
    });
  });

  group('what a copy-paste drags in', () {
    test('a header row is not a student', () {
      expect(RosterPaste.parse('Name\nAna Ruiz'), ['Ana Ruiz']);
    });

    test('spreadsheet headers of every usual spelling are dropped', () {
      expect(RosterPaste.parse('Student Name\nEmail Address\nAna Ruiz'), ['Ana Ruiz']);
    });

    test('numbered lists lose their numbering', () {
      expect(RosterPaste.parse('1. Ana Ruiz\n2) Ben Cole\n10. Cara Diaz'),
          ['Ana Ruiz', 'Ben Cole', 'Cara Diaz']);
    });

    test('bulleted lists lose their bullets', () {
      expect(RosterPaste.parse('- Ana Ruiz\n• Ben Cole\n* Cara Diaz'),
          ['Ana Ruiz', 'Ben Cole', 'Cara Diaz']);
    });

    test('a trailing email is stripped off', () {
      expect(RosterPaste.parse('Ana Ruiz <ana.ruiz@school.org>'), ['Ana Ruiz']);
      expect(RosterPaste.parse('Ben Cole ben@school.org'), ['Ben Cole']);
    });

    test('a row with no letters at all is not a child', () {
      expect(RosterPaste.parse('Ana Ruiz\n42\n---\n87%'), ['Ana Ruiz']);
    });

    test('quotes from a spreadsheet cell are removed', () {
      expect(RosterPaste.parse('"Ana Ruiz"'), ['Ana Ruiz']);
    });

    test('tab-separated columns split like lines', () {
      expect(RosterPaste.parse('Ana Ruiz\tBen Cole'), ['Ana Ruiz', 'Ben Cole']);
    });
  });

  group('duplicates', () {
    test('the same name twice is one student', () {
      expect(RosterPaste.parse('Ana Ruiz\nAna Ruiz'), ['Ana Ruiz']);
    });

    test('duplicates differing only by case or spacing are one student', () {
      expect(RosterPaste.parse('Ana Ruiz\nana  ruiz\nANA RUIZ'), ['Ana Ruiz']);
    });

    test('the first spelling is the one kept', () {
      expect(RosterPaste.parse('Ana Ruiz\nANA RUIZ').first, 'Ana Ruiz');
    });

    test('two genuinely different students both survive', () {
      // Same first name is not the same child.
      expect(RosterPaste.parse('Ana Ruiz\nAna Diaz').length, 2);
    });
  });

  group('one line holding several names', () {
    test('a comma list of three or more is split', () {
      expect(RosterPaste.parse('Ana Ruiz, Ben Cole, Cara Diaz'),
          ['Ana Ruiz', 'Ben Cole', 'Cara Diaz']);
    });

    test('a single "Last, First" is NOT split into two students', () {
      // The case that would quietly turn one child into two.
      expect(RosterPaste.parse('Ruiz, Ana'), ['Ana Ruiz']);
    });

    test('two full names on one line are split', () {
      expect(RosterPaste.parse('Ana Ruiz, Ben Cole'), ['Ana Ruiz', 'Ben Cole']);
    });
  });

  group('topping up a class instead of doubling it', () {
    test('names the class already has are reported', () {
      final pasted = RosterPaste.parse('Ana Ruiz\nBen Cole');
      expect(RosterPaste.alreadyPresent(pasted, ['ana ruiz']), ['Ana Ruiz']);
    });

    test('nothing is reported when the class is new', () {
      expect(RosterPaste.alreadyPresent(['Ana Ruiz'], const []), isEmpty);
    });
  });

  group('student codes', () {
    test('initials become the code', () {
      expect(RosterPaste.codeFor('Ana Ruiz', <String>{}), 'AR1');
    });

    test('two students with the same initials get different codes', () {
      final taken = <String>{};
      expect(RosterPaste.codeFor('Ana Ruiz', taken), 'AR1');
      expect(RosterPaste.codeFor('Alan Reid', taken), 'AR2');
    });

    test('a one-word name still gets a code', () {
      expect(RosterPaste.codeFor('Prince', <String>{}), 'P1');
    });
  });

  test('an empty paste yields nothing rather than a blank student', () {
    expect(RosterPaste.parse('   \n\n  '), isEmpty);
  });
}
