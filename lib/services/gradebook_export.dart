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
  static TemplateFill fill({
    required List<List<String>> template,
    required List<MarkRow> marks,
    required int nameColumn,
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
      final name = nameColumn < r.length ? r[nameColumn].trim() : '';
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
  static int? _matchIndex(String name, List<MarkRow> marks, Set<int> used) {
    final candidates = <String>[name];
    if (name.contains(',')) {
      final parts = name.split(',');
      if (parts.length >= 2) candidates.add('${parts[1].trim()} ${parts[0].trim()}');
    }
    for (var i = 0; i < marks.length; i++) {
      if (used.contains(i)) continue;
      for (final c in candidates) {
        if (sameStudentName(c, marks[i].studentName)) return i;
      }
    }
    return null;
  }
}
