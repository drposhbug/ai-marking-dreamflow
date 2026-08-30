import 'package:flutter_test/flutter_test.dart';
import 'package:marking_prokect_v2/services/csv_import.dart';
import 'package:marking_prokect_v2/services/gradebook_export.dart';

MarkRow mark(String name, double score, {double outOf = 20, String code = '', String feedback = ''}) => MarkRow(
      studentName: name,
      studentCode: code,
      score: score,
      maxScore: outOf,
      markedAt: DateTime(2026, 8, 27),
      feedback: feedback,
    );

void main() {
  _classroomSheet();
  group('a CSV every spreadsheet can open', () {
    test('quotes fields that would otherwise break the file', () {
      expect(GradebookExport.csvField('plain'), 'plain');
      expect(GradebookExport.csvField('Lopez, Ana'), '"Lopez, Ana"');
      expect(GradebookExport.csvField('said "hi"'), '"said ""hi"""');
      expect(GradebookExport.csvField('two\nlines'), '"two\nlines"');
    });

    test('a comma in a name cannot shift every later column', () {
      final csv = GradebookExport.plainCsv([mark('Lopez, Ana', 17)]);
      // Round-trip through the parser: the row must still have 8 fields.
      final rows = CsvImport.parse(csv);
      expect(rows.length, 2);
      expect(rows[1].length, 8);
      expect(rows[1][0], 'Lopez, Ana');
      expect(rows[1][3], '17');
    });

    test('scores keep half marks but drop pointless decimals', () {
      final csv = GradebookExport.plainCsv([mark('A', 17), mark('B', 17.5)]);
      final rows = CsvImport.parse(csv);
      expect(rows[1][3], '17');
      expect(rows[2][3], '17.50');
    });

    test('percent is rounded, not truncated', () {
      expect(mark('A', 17, outOf: 20).percent, 85);
      expect(mark('A', 0, outOf: 0).percent, 0); // never divide by zero
    });
  });

  group('filling a gradebook the teacher exported', () {
    List<List<String>> template(String csv) => CsvImport.parse(csv);

    test('finds the name column from its header', () {
      final t = template('Student Name,Term 1\nAna Lopez,\nBen Carter,\n');
      expect(GradebookTemplate.findNameColumn(t), 0);
    });

    test('finds a name column even with a useless header', () {
      final t = template('A,B\nAna Lopez,12\nBen Carter,15\nCara Diaz,9\n');
      expect(GradebookTemplate.findNameColumn(t), 0);
    });

    test('writes each mark against the right student', () {
      final t = template('Student,Term 1\nAna Lopez,\nBen Carter,\n');
      final f = GradebookTemplate.fill(
        template: t,
        marks: [mark('Ben Carter', 12), mark('Ana Lopez', 18)],
        nameColumn: 0,
      );
      final rows = CsvImport.parse(f.csv);
      expect(rows.first.last, 'Markless');
      expect(rows[1][0], 'Ana Lopez');
      expect(rows[1].last, '18');
      expect(rows[2][0], 'Ben Carter');
      expect(rows[2].last, '12');
      expect(f.filled, 2);
    });

    test('handles a gradebook that writes names surname-first', () {
      final t = template('Student,Mark\n"Lopez, Ana",\n');
      final f = GradebookTemplate.fill(template: t, marks: [mark('Ana Lopez', 18)], nameColumn: 0);
      expect(f.filled, 1);
      expect(CsvImport.parse(f.csv)[1].last, '18');
    });

    test('reports students it could not match instead of silently skipping', () {
      final t = template('Student,Mark\nAna Lopez,\nSomebody Else,\n');
      final f = GradebookTemplate.fill(template: t, marks: [mark('Ana Lopez', 18)], nameColumn: 0);
      expect(f.filled, 1);
      expect(f.unmatched, ['Somebody Else']);
    });

    test('reports marked students missing from the template', () {
      final t = template('Student,Mark\nAna Lopez,\n');
      final f = GradebookTemplate.fill(
        template: t,
        marks: [mark('Ana Lopez', 18), mark('Ben Carter', 12)],
        nameColumn: 0,
      );
      expect(f.notInTemplate, ['Ben Carter']);
    });

    test('never gives the same mark to two rows', () {
      // Two students who share a first name — the forgiving matcher must
      // not hand Ana's mark to both rows.
      final t = template('Student,Mark\nAna Lopez,\nAna Lopez,\n');
      final f = GradebookTemplate.fill(template: t, marks: [mark('Ana Lopez', 18)], nameColumn: 0);
      expect(f.filled, 1);
      expect(f.unmatched.length, 1);
    });

    test('writes into an existing column rather than adding a duplicate', () {
      final t = template('Student,Markless\nAna Lopez,old\n');
      final f = GradebookTemplate.fill(template: t, marks: [mark('Ana Lopez', 18)], nameColumn: 0);
      final rows = CsvImport.parse(f.csv);
      expect(rows.first.length, 2, reason: 'a second Markless column was added');
      expect(rows[1][1], '18');
    });

    test('can write percentages instead of raw scores', () {
      final t = template('Student,Mark\nAna Lopez,\n');
      final f = GradebookTemplate.fill(
        template: t,
        marks: [mark('Ana Lopez', 17, outOf: 20)],
        nameColumn: 0,
        asPercent: true,
      );
      expect(CsvImport.parse(f.csv)[1].last, '85');
    });

    test('an empty template produces nothing rather than crashing', () {
      final f = GradebookTemplate.fill(template: const [], marks: [mark('A', 1)], nameColumn: 0);
      expect(f.csv, isEmpty);
      expect(f.filled, 0);
    });
  });
}

/// Google Classroom's grade export, which the app can't push marks into
/// (that needs Google's review plus each district's IT admin) but can at
/// least fill in one tap instead of asking which column is which.
void _classroomSheet() {
  MarkRow mark(String name, double score) => MarkRow(
        studentName: name,
        studentCode: '',
        score: score,
        maxScore: 100,
        markedAt: DateTime(2026, 6, 1),
        feedback: '',
      );

  // The real shape: name split in two, an email column, and a "Points"
  // row under the header that is not a student.
  List<List<String>> sheet() => [
        ['Last Name', 'First Name', 'Email Address', 'Essay 1'],
        ['', '', 'Points', '100'],
        ['Ruiz', 'Ana', 'ana@school.org', ''],
        ['Cole', 'Ben', 'ben@school.org', ''],
      ];

  group('spotting the file', () {
    test('a Classroom export is recognised', () {
      final shape = ClassroomSheet.detect(sheet());
      expect(shape, isNotNull);
      expect(shape!.firstNameColumn, 1);
      expect(shape.lastNameColumn, 0);
      expect(shape.emailColumn, 2);
    });

    test('an ordinary one-name-column spreadsheet is not mistaken for one', () {
      expect(ClassroomSheet.detect([
        ['Student', 'Mark'],
        ['Ana Ruiz', ''],
      ]), isNull);
    });

    test('a half-matching file goes to the manual mapper instead', () {
      // First/Last but no email: not Classroom's shape, so don't guess.
      expect(ClassroomSheet.detect([
        ['Last Name', 'First Name', 'Homeroom'],
        ['Ruiz', 'Ana', '9B'],
      ]), isNull);
    });

    test('an empty file is not a Classroom sheet', () {
      expect(ClassroomSheet.detect(const []), isNull);
    });
  });

  group('filling it', () {
    test('a split name matches a student marked as "First Last"', () {
      final shape = ClassroomSheet.detect(sheet())!;
      final filled = GradebookTemplate.fill(
        template: sheet(),
        marks: [mark('Ana Ruiz', 88)],
        nameColumn: shape.firstNameColumn,
        lastNameColumn: shape.lastNameColumn,
      );
      expect(filled.filled, 1);
      expect(filled.csv, contains('88'));
    });

    test('two students sharing a first name each get their own mark', () {
      // Why the second column matters. The name matcher is forgiving
      // enough to match "Ana" to "Ana Ruiz" on its own, which is fine
      // until a class has two Anas — and then a first-name-only match can
      // hand Ana Diaz's mark to Ana Ruiz. Reading both columns removes
      // the ambiguity instead of relying on row order.
      final twoAnas = [
        ['Last Name', 'First Name', 'Email Address', 'Essay 1'],
        ['Ruiz', 'Ana', 'ana.r@school.org', ''],
        ['Diaz', 'Ana', 'ana.d@school.org', ''],
      ];
      final shape = ClassroomSheet.detect(twoAnas)!;
      final filled = GradebookTemplate.fill(
        template: twoAnas,
        marks: [mark('Ana Diaz', 71), mark('Ana Ruiz', 88)],
        nameColumn: shape.firstNameColumn,
        lastNameColumn: shape.lastNameColumn,
      );
      expect(filled.filled, 2);
      final rows = filled.csv.trim().split('\n');
      expect(rows[1], contains('88')); // Ruiz
      expect(rows[2], contains('71')); // Diaz
    });

    test('the Points row never receives a mark', () {
      final shape = ClassroomSheet.detect(sheet())!;
      final filled = GradebookTemplate.fill(
        template: sheet(),
        marks: [mark('Ana Ruiz', 88), mark('Ben Cole', 71)],
        nameColumn: shape.firstNameColumn,
        lastNameColumn: shape.lastNameColumn,
      );
      final rows = filled.csv.trim().split('\n');
      // Header, Points, Ana, Ben — and the Points row keeps its own values.
      expect(rows[1], startsWith(',,Points,100'));
      expect(filled.filled, 2);
    });

    test('the teacher\'s own columns are all still there', () {
      final shape = ClassroomSheet.detect(sheet())!;
      final filled = GradebookTemplate.fill(
        template: sheet(),
        marks: [mark('Ana Ruiz', 88)],
        nameColumn: shape.firstNameColumn,
        lastNameColumn: shape.lastNameColumn,
      );
      expect(filled.csv, contains('Email Address'));
      expect(filled.csv, contains('ana@school.org'));
      expect(filled.csv, contains('Essay 1'));
    });

    test('a student in the sheet with no mark is reported, not guessed', () {
      final shape = ClassroomSheet.detect(sheet())!;
      final filled = GradebookTemplate.fill(
        template: sheet(),
        marks: [mark('Ana Ruiz', 88)],
        nameColumn: shape.firstNameColumn,
        lastNameColumn: shape.lastNameColumn,
      );
      expect(filled.unmatched, contains('Ben Cole'));
    });
  });

  group('the Points row helper', () {
    test('the points row is spotted', () {
      final shape = ClassroomSheet.detect(sheet())!;
      expect(ClassroomSheet.isPointsRow(['', '', 'Points', '100'], shape), isTrue);
    });

    test('a real student is not', () {
      final shape = ClassroomSheet.detect(sheet())!;
      expect(ClassroomSheet.isPointsRow(['Ruiz', 'Ana', 'ana@school.org', ''], shape), isFalse);
    });
  });
}
