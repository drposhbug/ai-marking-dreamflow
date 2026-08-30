import 'package:marking_prokect_v2/models/student.dart';
import 'package:marking_prokect_v2/models/submission.dart';
import 'package:marking_prokect_v2/services/page_fingerprint.dart' show sameStudentName;

/// One student's mark, ready to leave the app.
class MarkRow {
  final String studentName;
  final String studentCode;
  final double score;
  final double maxScore;
  final DateTime markedAt;
  final String feedback;

  const MarkRow({
    required this.studentName,
    required this.studentCode,
    required this.score,
    required this.maxScore,
    required this.markedAt,
    required this.feedback,
  });

  int get percent => maxScore <= 0 ? 0 : ((score / maxScore) * 100).round();
}

/// Gets the marks OUT of Markless and into whatever the school actually
/// uses.
///
/// Marking thirty papers and then typing thirty numbers into PowerSchool by
/// hand is the step immediately after the one this app exists to remove —
/// so leaving it in place makes the whole thing feel half-finished.
///
/// Two ways out, because gradebook imports are fussy and every board runs a
/// different one:
///
///  * A plain CSV that opens in Excel or Sheets, for copying a column into
///    whatever the teacher has open.
///  * Filling a template the teacher exported FROM their gradebook, which
///    works with any system without this app having to know a thing about
///    it. Students are matched by name; anyone unmatched is reported rather
///    than quietly skipped.
class GradebookExport {
  /// Quote a field the way every spreadsheet expects: wrap when it contains
  /// a comma, quote or newline, and double any quotes inside.
  static String csvField(String value) {
    final needsQuotes = value.contains(',') || value.contains('"') || value.contains('\n') || value.contains('\r');
    final escaped = value.replaceAll('"', '""');
    return needsQuotes ? '"$escaped"' : escaped;
  }

  static String _num(double v) => v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// The straightforward export: one row per student, opens anywhere.
  static String plainCsv(List<MarkRow> rows, {String assessment = 'Assessment'}) {
    final b = StringBuffer('Student,Student ID,Assessment,Score,Out of,Percent,Marked on,Feedback\n');
    for (final r in rows) {
      b.writeln([
        csvField(r.studentName),
        csvField(r.studentCode),
        csvField(assessment),
        _num(r.score),
        _num(r.maxScore),
        '${r.percent}',
        _date(r.markedAt),
        csvField(r.feedback.replaceAll('\n', ' ').trim()),
      ].join(','));
    }
    return b.toString();
  }

  /// Builds the rows for one class from what has been marked.
  ///
  /// [since] limits it to a single assessment or a term. When a student has
  /// been marked more than once in the window the most recent mark wins —
  /// a re-mark is a correction, not a second grade.
  static List<MarkRow> rowsForClass({
    required List<Student> students,
    required List<Submission> submissions,
    required String classId,
    DateTime? since,
  }) {
    final byStudent = <String, Submission>{};
    for (final s in submissions) {
      if (s.classId != classId || s.studentId.isEmpty) continue;
      if (since != null && s.createdAt.isBefore(since)) continue;
      final existing = byStudent[s.studentId];
      if (existing == null || s.createdAt.isAfter(existing.createdAt)) {
        byStudent[s.studentId] = s;
      }
    }
    final rows = <MarkRow>[];
    for (final st in students.where((s) => s.classId == classId)) {
      final sub = byStudent[st.id];
      if (sub == null) continue;
      rows.add(MarkRow(
        studentName: st.name,
        studentCode: st.studentId,
        score: sub.score,
        maxScore: sub.maxScore,
        markedAt: sub.createdAt,
        feedback: sub.feedback,
      ));
    }
    rows.sort((a, b) => a.studentName.toLowerCase().compareTo(b.studentName.toLowerCase()));
    return rows;
  }
}

/// The result of writing marks into a gradebook's own exported file.
class TemplateFill {
  final String csv;

  /// Names in the template that no marked paper matched — reported so a
  /// teacher never uploads a file with silent gaps in it.
  final List<String> unmatched;

  /// Marked students who weren't in the template at all.
  final List<String> notInTemplate;

  final int filled;

  const TemplateFill({
    required this.csv,
    required this.unmatched,
    required this.notInTemplate,
    required this.filled,
  });
}

/// Fills a gradebook's own export with the marks.
///
/// This is what makes the feature work with PowerSchool, Aspen, MyEd,
/// Classroom or a spreadsheet a teacher made themselves: the app never has
/// to know the format, because the teacher supplies it.
class GradebookTemplate {
  /// Columns whose header suggests it holds a student's name.
  static final _nameHeader = RegExp(r'\b(student|name|last|first|surname|pupil)\b', caseSensitive: false);

  /// Finds the column most likely to hold student names.
  ///
  /// Prefers a header that says so; falls back to the first column whose
  /// values look like names rather than numbers, because plenty of exports
  /// have no useful header at all.
  static int findNameColumn(List<List<String>> rows) {
    if (rows.isEmpty) return -1;
    final header = rows.first;
    for (var c = 0; c < header.length; c++) {
      if (_nameHeader.hasMatch(header[c])) return c;
    }
    for (var c = 0; c < header.length; c++) {
      var looksLikeNames = 0;
      var seen = 0;
      for (final r in rows.skip(1)) {
        if (c >= r.length) continue;
        final v = r[c].trim();
        if (v.isEmpty) continue;
        seen++;
        if (RegExp(r'^[A-Za-z][A-Za-z .,\x27-]{2,}$').hasMatch(v)) looksLikeNames++;
      }
      if (seen >= 2 && looksLikeNames >= (seen * 0.8)) return c;
    }
    return -1;
  }

  /// Writes each student's score into [columnName], adding the column when
  /// the template doesn't already have it.
  ///
  /// Matching reuses the same forgiving name comparison the page checks
  /// use — a gradebook holding "Lopez, Ana" and a paper signed "Ana Lopez"
  /// is one student, and a teacher should not have to care.
  /// [lastNameColumn] is for gradebooks that split the name across two
  /// columns — Google Classroom's export is "Last Name, First Name" — where
  /// neither column on its own identifies a student. When it is set,
  /// [nameColumn] holds the first name and the two are joined for matching.
  static TemplateFill fill({
    required List<List<String>> template,
    required List<MarkRow> marks,
    required int nameColumn,
    int lastNameColumn = -1,
    String columnName = 'Markless',
    bool asPercent = false,
  }) {
    if (template.isEmpty || nameColumn < 0) {
      return const TemplateFill(csv: '', unmatched: [], notInTemplate: [], filled: 0);
    }
    final header = [...template.first];
    var col = header.indexWhere((h) => h.trim().toLowerCase() == columnName.toLowerCase());
    if (col < 0) {
      header.add(columnName);
      col = header.length - 1;
    }

    final used = <int>{};
    final out = <List<String>>[header];
    final unmatched = <String>[];

    for (final row in template.skip(1)) {
      final r = [...row];
      while (r.length < header.length) {
        r.add('');
      }
      final first = nameColumn < r.length ? r[nameColumn].trim() : '';
      final last = lastNameColumn >= 0 && lastNameColumn < r.length ? r[lastNameColumn].trim() : '';
      final name = lastNameColumn >= 0 ? [first, last].where((p) => p.isNotEmpty).join(' ') : first;
      if (name.isEmpty) {
        out.add(r);
        continue;
      }
      final i = _matchIndex(name, marks, used);
      if (i == null) {
        unmatched.add(name);
      } else {
        used.add(i);
        final m = marks[i];
        r[col] = asPercent ? '${m.percent}' : GradebookExport._num(m.score);
      }
      out.add(r);
    }

    final notInTemplate = [
      for (var i = 0; i < marks.length; i++)
        if (!used.contains(i)) marks[i].studentName,
    ];

    final b = StringBuffer();
    for (final r in out) {
      b.writeln(r.map(GradebookExport.csvField).join(','));
    }
    return TemplateFill(
      csv: b.toString(),
      unmatched: unmatched,
      notInTemplate: notInTemplate,
      filled: used.length,
    );
  }

  /// Index of the mark belonging to [name], or null.
  ///
  /// Handles "Lopez, Ana" as well as "Ana Lopez", and never hands the same
  /// mark to two rows.
  ///
  /// Confidence order matters, and it is the difference between a right
  /// and a wrong mark on a child's record. [sameStudentName] is forgiving
  /// on purpose — it treats a shared first name as a match, which is the
  /// right call when checking whether two pages came from one paper.
  /// Writing into a gradebook is not that: a class with two Anas would
  /// give the first Ana whichever mark came first in the list, and report
  /// nothing wrong, because both names "matched". So an exact match is
  /// taken wherever it sits in the list, and the loose rule only decides
  /// when nothing better exists anywhere.
  static int? _matchIndex(String name, List<MarkRow> marks, Set<int> used) {
    final candidates = <String>[name];
    if (name.contains(',')) {
      final parts = name.split(',');
      if (parts.length >= 2) candidates.add('${parts[1].trim()} ${parts[0].trim()}');
    }

    final wanted = candidates.map(_normName).where((c) => c.isNotEmpty).toList(growable: false);

    // Pass one: the same name, exactly. Accents are folded rather than
    // stripped, so a gradebook holding "Ana Ruiz" and a register holding
    // "Ana Ruíz" are one student and match here instead of falling through
    // to the guessing pass.
    for (var i = 0; i < marks.length; i++) {
      if (used.contains(i)) continue;
      if (wanted.contains(_normName(marks[i].studentName))) return i;
    }

    // Pass two: everything else sameStudentName is willing to accept —
    // but only when exactly one mark accepts it. Two students called Ana
    // both answer to a first-name match, and picking whichever came first
    // writes one child's mark onto the other's row without a word. An
    // ambiguous name is left for the teacher, who is told about it.
    var found = -1;
    for (var i = 0; i < marks.length; i++) {
      if (used.contains(i)) continue;
      final hit = candidates.any((c) => sameStudentName(c, marks[i].studentName));
      if (!hit) continue;
      if (found >= 0) return null; // more than one: do not guess
      found = i;
    }
    return found < 0 ? null : found;
  }

  /// Lower-cased, accent-folded, punctuation-free, single-spaced.
  static String _normName(String s) {
    const from = 'àáâãäåāăąèéêëēĕėęěìíîïĩīĭįòóôõöøōŏőùúûüũūŭůçćĉċčñńņňýÿŷ';
    const to = 'aaaaaaaaaeeeeeeeeeiiiiiiiiooooooooouuuuuuuucccccnnnnyyy';
    final b = StringBuffer();
    for (final ch in s.toLowerCase().split('')) {
      final i = from.indexOf(ch);
      b.write(i >= 0 ? to[i] : ch);
    }
    return b.toString().replaceAll(RegExp(r'[^a-z ]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

/// Recognises a Google Classroom grade export.
///
/// Classroom is the one gradebook whose export shape is predictable, and
/// it is also the one this app can't talk to directly — pushing marks into
/// Classroom needs Google's review plus every district's IT admin. So the
/// next best thing is to make its downloaded file land in one tap instead
/// of asking the teacher which column is which.
///
/// The file looks like:
///
///     Last Name,First Name,Email Address,Essay 1,Quiz 2
///     ,,Points,100,20
///     Ruiz,Ana,ana@school.org,88,18
///
/// Two things make it awkward, and both are handled here: the name is
/// split across two columns, and there is often a "Points" row under the
/// header that is not a student.
class ClassroomSheet {
  final int firstNameColumn;
  final int lastNameColumn;
  final int emailColumn;

  const ClassroomSheet({
    required this.firstNameColumn,
    required this.lastNameColumn,
    required this.emailColumn,
  });

  static final _first = RegExp(r'^first\s*name$', caseSensitive: false);
  static final _last = RegExp(r'^last\s*name$', caseSensitive: false);
  static final _email = RegExp(r'^email(\s*address)?$', caseSensitive: false);

  /// The Classroom shape, or null if this is some other file.
  ///
  /// Deliberately strict: both name columns AND the email column must be
  /// there. A file that only half matches goes to the manual mapper, which
  /// is never wrong — guessing here would silently mark the wrong column.
  static ClassroomSheet? detect(List<List<String>> rows) {
    if (rows.isEmpty) return null;
    final header = rows.first;
    var first = -1;
    var last = -1;
    var email = -1;
    for (var c = 0; c < header.length; c++) {
      final h = header[c].trim();
      if (first < 0 && _first.hasMatch(h)) first = c;
      if (last < 0 && _last.hasMatch(h)) last = c;
      if (email < 0 && _email.hasMatch(h)) email = c;
    }
    if (first < 0 || last < 0 || email < 0) return null;
    return ClassroomSheet(firstNameColumn: first, lastNameColumn: last, emailColumn: email);
  }

  /// True for Classroom's "Points" row — the one under the header holding
  /// the marks each assignment is out of. It has no name, so filling a
  /// mark into it would put a student's score on a row that isn't a
  /// student.
  static bool isPointsRow(List<String> row, ClassroomSheet shape) {
    final f = shape.firstNameColumn < row.length ? row[shape.firstNameColumn].trim() : '';
    final l = shape.lastNameColumn < row.length ? row[shape.lastNameColumn].trim() : '';
    if (f.isNotEmpty || l.isNotEmpty) return false;
    final e = shape.emailColumn < row.length ? row[shape.emailColumn].trim() : '';
    return e.toLowerCase() == 'points' || e.isEmpty;
  }
}
