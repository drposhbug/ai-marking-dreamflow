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
