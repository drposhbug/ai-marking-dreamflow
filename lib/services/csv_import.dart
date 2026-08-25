/// Parsing and analysis for imported response sheets — a Google Form's
/// exported CSV, or any spreadsheet with one row per student.
///
/// Everything here is offline and free: parsing, working out which column is
/// which, and marking the multiple-choice columns against the teacher's key.
/// Only written answers (short/paragraph) ever cost AI credits.
library;

/// One question column from the sheet.
enum ImportColumnKind { multipleChoice, shortAnswer, paragraph, skip }

class ImportColumn {
  final int index;
  final String header;
  ImportColumnKind kind;

  /// Correct answer for multiple choice (matched case-insensitively).
  String correctAnswer;

  /// Optional model answer / rubric handed to the AI for written questions.
  String keyAnswer;
  double marks;

  ImportColumn({
    required this.index,
    required this.header,
    required this.kind,
    this.correctAnswer = '',
    this.keyAnswer = '',
    this.marks = 1,
  });

  /// Distinct non-empty answers, most common first — the choices a teacher
  /// picks the right one from.
  List<String> distinctAnswers(List<List<String>> rows) {
    final counts = <String, int>{};
    for (final r in rows) {
      final v = index < r.length ? r[index].trim() : '';
      if (v.isEmpty) continue;
      counts[v] = (counts[v] ?? 0) + 1;
    }
    final keys = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return keys;
  }
}

class ParsedSheet {
  final List<String> headers;
  final List<List<String>> rows;

  /// Index of the column holding the student's name (-1 = none found).
  final int nameColumn;
  final List<ImportColumn> questions;

  const ParsedSheet({required this.headers, required this.rows, required this.nameColumn, required this.questions});

  String studentName(int row) {
    if (nameColumn < 0 || nameColumn >= rows[row].length) return 'Student ${row + 1}';
    final v = rows[row][nameColumn].trim();
    return v.isEmpty ? 'Student ${row + 1}' : v;
  }
}

class CsvImport {
  /// RFC-4180-ish parse: quoted fields, "" escapes, commas and newlines
  /// inside quotes, CRLF or LF, and a UTF-8 BOM. Semicolon sheets (some
  /// locales export those) are detected off the header row.
  static List<List<String>> parse(String raw) {
    var text = raw;
    if (text.startsWith('﻿')) text = text.substring(1);
    final sep = _detectSeparator(text);

    final rows = <List<String>>[];
    var field = StringBuffer();
    var row = <String>[];
    var inQuotes = false;
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(c);
        }
        continue;
      }
      if (c == '"') {
        inQuotes = true;
      } else if (c == sep) {
        row.add(field.toString());
        field = StringBuffer();
      } else if (c == '\n' || c == '\r') {
        if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        row.add(field.toString());
        field = StringBuffer();
        if (row.any((f) => f.trim().isNotEmpty)) rows.add(row);
        row = <String>[];
      } else {
        field.write(c);
      }
    }
    row.add(field.toString());
    if (row.any((f) => f.trim().isNotEmpty)) rows.add(row);
    return rows;
  }

  static String _detectSeparator(String text) {
    final firstLine = text.split(RegExp(r'[\r\n]')).firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    // Count separators outside quotes on the header row only.
    var commas = 0, semis = 0, tabs = 0, inQ = false;
    for (final ch in firstLine.split('')) {
      if (ch == '"') inQ = !inQ;
      if (inQ) continue;
      if (ch == ',') commas++;
      if (ch == ';') semis++;
      if (ch == '\t') tabs++;
    }
    if (tabs > commas && tabs > semis) return '\t';
    if (semis > commas) return ';';
    return ',';
  }

  // Columns a Google Form adds that are never questions.
  static final _metaHeaders = RegExp(r'^(timestamp|score|total\s*score|email\s*(address)?|username)$', caseSensitive: false);
  static final _nameHeaders = RegExp(r'\b(name|student)\b', caseSensitive: false);

  /// Works out which column is the student and which are questions, and
  /// guesses each question's type from what the class actually typed —
  /// a handful of repeated short answers reads as multiple choice, a column
  /// of long prose as paragraphs. Every guess is editable on screen.
  static ParsedSheet analyze(List<List<String>> allRows) {
    if (allRows.isEmpty) return const ParsedSheet(headers: [], rows: [], nameColumn: -1, questions: []);
    final headers = allRows.first.map((h) => h.trim()).toList();
    final rows = allRows.skip(1).toList();

    var nameColumn = -1;
    var emailColumn = -1;
    final questions = <ImportColumn>[];

    for (var c = 0; c < headers.length; c++) {
      final h = headers[c];
      if (h.isEmpty) continue;
      final isMeta = _metaHeaders.hasMatch(h.trim());
      if (isMeta) {
        if (emailColumn < 0 && h.toLowerCase().contains('email')) emailColumn = c;
        continue;
      }
      if (nameColumn < 0 && _nameHeaders.hasMatch(h)) {
        nameColumn = c;
        continue;
      }

      final values = <String>[];
      for (final r in rows) {
        final v = c < r.length ? r[c].trim() : '';
        if (v.isNotEmpty) values.add(v);
      }
      if (values.isEmpty) continue;
      final distinct = values.toSet().length;
      final lengths = values.map((v) => v.length).toList()..sort();
      final avgLen = lengths.reduce((a, b) => a + b) / lengths.length;
      final longest = lengths.last;
      // 75th percentile: what a student who actually answered wrote.
      final p75 = lengths[((lengths.length - 1) * 0.75).round()];

      ImportColumnKind kind;
      double marks;
      if (distinct <= 8 && avgLen <= 30 && values.length >= 3) {
        kind = ImportColumnKind.multipleChoice;
        marks = 1;
      } else if (longest >= 150 || p75 >= 100) {
        // ~150 chars is about 25 words — past a "short answer" by any
        // reading. Judge by the students who actually wrote something, not
        // the average: two one-line answers must not demote an essay
        // question to "short" and mark the whole class out of 2, not 5.
        kind = ImportColumnKind.paragraph;
        marks = 5;
      } else {
        kind = ImportColumnKind.shortAnswer;
        marks = 2;
      }
      questions.add(ImportColumn(index: c, header: h, kind: kind, marks: marks));
    }

    // A form that only asked for email still needs a student label.
    if (nameColumn < 0) nameColumn = emailColumn;
    return ParsedSheet(headers: headers, rows: rows, nameColumn: nameColumn, questions: questions);
  }

  /// Marks one multiple-choice answer. Free, local, and forgiving of the
  /// junk that surrounds form answers: case, whitespace, a trailing period,
  /// and "B) 42" matching a key of "42" (or of "B").
  static bool mcCorrect(String answer, String correct) {
    String norm(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'[.\s]+$'), '').replaceAll(RegExp(r'\s+'), ' ');
    final a = norm(answer);
    final k = norm(correct);
    if (a.isEmpty || k.isEmpty) return false;
    if (a == k) return true;
    // "b) 42" / "b. 42" / "(b) 42" — match on either the letter or the body.
    final lead = RegExp(r'^\(?([a-e])[).:]\s*(.*)$');
    final am = lead.firstMatch(a);
    final km = lead.firstMatch(k);
    final aLetter = am?.group(1), aBody = am?.group(2)?.trim();
    final kLetter = km?.group(1), kBody = km?.group(2)?.trim();
    if (aLetter != null && (aLetter == k || aLetter == kLetter)) return true;
    if (kLetter != null && (a == kLetter || a == kBody)) return true;
    if (aBody != null && aBody.isNotEmpty && (aBody == k || (kBody != null && aBody == kBody))) return true;
    return false;
  }
}
