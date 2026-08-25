import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:marking_prokect_v2/services/csv_import.dart';

void main() {
  final raw = File(r'C:\Users\tyler\AppData\Local\Temp\sample_form.csv').readAsStringSync();

  test('parses a Google Form export, quoted commas and all', () {
    final rows = CsvImport.parse(raw);
    expect(rows.length, 5); // header + 4 students
    expect(rows[1][2], 'Ana Lopez');
    // The long answer contains commas inside quotes — must stay one field.
    expect(rows[1][5], contains('LEDs use about 75% less electricity'));
    expect(rows[1].length, rows[0].length);
  });

  test('finds the name column and skips form metadata', () {
    final sheet = CsvImport.analyze(CsvImport.parse(raw));
    expect(sheet.headers[sheet.nameColumn], 'Full Name');
    // Timestamp, Email Address and Score are never questions.
    final headers = sheet.questions.map((q) => q.header).toList();
    expect(headers.any((h) => h.contains('Timestamp')), isFalse);
    expect(headers.any((h) => h.contains('Score')), isFalse);
    expect(headers.length, 3);
  });

  test('guesses question types from what the class actually typed', () {
    final sheet = CsvImport.analyze(CsvImport.parse(raw));
    expect(sheet.questions[0].kind, ImportColumnKind.multipleChoice);
    expect(sheet.questions[2].kind, ImportColumnKind.paragraph);
  });

  test('multiple choice marking forgives case, spacing and letter prefixes', () {
    expect(CsvImport.mcCorrect('liquid', 'Liquid'), isTrue);
    expect(CsvImport.mcCorrect(' Liquid ', 'Liquid'), isTrue);
    expect(CsvImport.mcCorrect('Liquid.', 'Liquid'), isTrue);
    expect(CsvImport.mcCorrect('B) Liquid', 'Liquid'), isTrue);
    expect(CsvImport.mcCorrect('b', 'B) Liquid'), isTrue);
    expect(CsvImport.mcCorrect('Solid', 'Liquid'), isFalse);
    expect(CsvImport.mcCorrect('', 'Liquid'), isFalse);
  });

  test('a blank answer is not silently treated as correct', () {
    final sheet = CsvImport.analyze(CsvImport.parse(raw));
    final mc = sheet.questions[0];
    // Cara answered "liquid" lowercase; nobody left the MC blank here, so
    // check the empty-string path directly.
    expect(CsvImport.mcCorrect(sheet.rows[2][mc.index], 'Liquid'), isTrue);
    expect(CsvImport.mcCorrect('', 'Liquid'), isFalse);
  });
}
