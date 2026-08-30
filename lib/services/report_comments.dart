import 'package:marking_prokect_v2/models/student.dart';
import 'package:marking_prokect_v2/models/submission.dart';
import 'package:marking_prokect_v2/services/anonymizer.dart';

/// The stretch of the year a report card covers.
///
/// Held as a half-open range because a teacher picks two dates off a
/// calendar and means both of them: a paper marked at 3pm on the last day
/// of term is inside that term. Comparing against the raw end date would
/// drop every paper marked after midnight on it — which is all of them —
/// and the teacher would see an empty term with no clue why.
class TermWindow {
  final String label;

  /// Local midnight on the first day, inclusive.
  final DateTime start;

  /// Local midnight on the day AFTER the last day, exclusive.
  final DateTime end;

  const TermWindow({required this.label, required this.start, required this.end});

  /// A window from the two dates a teacher tapped.
  ///
  /// They arrive in whichever order they were picked. Sorting them beats
  /// returning an empty term: a teacher who taps the end date first has
  /// made no mistake worth punishing.
  factory TermWindow.between(DateTime from, DateTime to, {String label = 'This term'}) {
    final a = DateTime(from.year, from.month, from.day);
    final b = DateTime(to.year, to.month, to.day);
    final lo = a.isAfter(b) ? b : a;
    final hi = a.isAfter(b) ? a : b;
    // Day + 1 rather than Duration(days: 1): DateTime normalises the
    // overflow (Dec 32 is Jan 1) AND lands on local midnight, where adding
    // 24 hours across a daylight-saving change lands at 23:00 or 01:00 and
    // silently moves the term boundary by a day.
    return TermWindow(label: label, start: lo, end: DateTime(hi.year, hi.month, hi.day + 1));
  }

  /// The last [days] days of marking, ending at the end of today.
  factory TermWindow.lastDays(int days, {DateTime? now, String? label}) {
    final t = now ?? DateTime.now();
    return TermWindow(
      label: label ?? 'Last $days days',
      start: DateTime(t.year, t.month, t.day + 1 - days),
      end: DateTime(t.year, t.month, t.day + 1),
    );
  }

  bool contains(DateTime t) => !t.isBefore(start) && t.isBefore(end);
}

/// One rubric line on one piece of work.
class CriterionEvidence {
  final String name;
  final double score;
  final double maxScore;

  const CriterionEvidence({required this.name, required this.score, required this.maxScore});

  int get percent => maxScore <= 0 ? 0 : ((score / maxScore) * 100).round();
}

/// One marked piece of work, reduced to what a report comment can be built
/// on. No page images, no raw transcription — those are both enormous and
/// full of the student's handwriting, name included.
class AssessmentEvidence {
  final DateTime markedAt;
  final String subject;
  final String title;
  final double score;
  final double maxScore;
  final List<CriterionEvidence> criteria;
  final List<String> strengths;
  final List<String> improvements;

  const AssessmentEvidence({
    required this.markedAt,
    required this.subject,
    required this.title,
    required this.score,
    required this.maxScore,
    required this.criteria,
    required this.strengths,
    required this.improvements,
  });

  int get percent => maxScore <= 0 ? 0 : ((score / maxScore) * 100).round();
}

/// A criterion seen across several pieces of work — the thing a defensible
/// comment is actually made of ("unit conversion, three times, averaging
/// 45%") rather than a single bad afternoon.
class CriterionTrend {
  final String name;
  final int averagePercent;
  final int seen;

  const CriterionTrend({required this.name, required this.averagePercent, required this.seen});
}

/// Everything the app knows about one student's term.
///
/// [studentId] and [studentName] stay on the device. Only what
/// [ReportComments.anonymousPayload] emits ever leaves it, and that is keyed
/// by position in the request — see the class comment there.
class StudentEvidence {
  final String studentId;
  final String studentName;

  /// Oldest first, so a reader (human or model) sees the term unfold.
  final List<AssessmentEvidence> assessments;

  const StudentEvidence({
    required this.studentId,
    required this.studentName,
    required this.assessments,
  });

  int get pieces => assessments.length;

  /// Null when nothing in the window carried a mark — an average of no
  /// marks is 0%, which reads as a failing student rather than an empty
  /// window, and that is the kind of mistake a parent phones about.
  int? get averagePercent {
    final scored = assessments.where((a) => a.maxScore > 0).toList();
    if (scored.isEmpty) return null;
    return (scored.map((a) => a.percent).reduce((a, b) => a + b) / scored.length).round();
  }

  /// Change in percentage points between the first half of the term and the
  /// second. Null under [_minPiecesForTrend] pieces: two marks apart is
  /// noise, and "has improved this term" is a claim a teacher has to defend.
  static const int _minPiecesForTrend = 3;

  int? get trendPoints {
    final scored = assessments.where((a) => a.maxScore > 0).toList();
    if (scored.length < _minPiecesForTrend) return null;
    final split = scored.length ~/ 2;
    final first = scored.take(split);
    final second = scored.skip(scored.length - split);
    final a = first.map((e) => e.percent).reduce((x, y) => x + y) / first.length;
    final b = second.map((e) => e.percent).reduce((x, y) => x + y) / second.length;
    return (b - a).round();
  }

  /// Rubric lines averaged across the term, strongest first. Only lines
  /// seen more than once are worth naming in a report — one criterion on
  /// one test is an anecdote.
  List<CriterionTrend> get criteriaTrends {
    final byKey = <String, List<CriterionEvidence>>{};
    final display = <String, String>{};
    for (final a in assessments) {
      for (final c in a.criteria) {
        final key = c.name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
        if (key.isEmpty || c.maxScore <= 0) continue;
        (byKey[key] ??= <CriterionEvidence>[]).add(c);
        display[key] ??= c.name.trim();
      }
    }
    final out = <CriterionTrend>[];
    byKey.forEach((key, list) {
      out.add(CriterionTrend(
        name: display[key] ?? key,
        averagePercent: (list.map((c) => c.percent).reduce((a, b) => a + b) / list.length).round(),
        seen: list.length,
      ));
    });
    out.sort((a, b) => b.averagePercent.compareTo(a.averagePercent));
    return out;
  }

  /// Whether there is enough here to write anything defensible. A single
  /// piece of work is not a term.
  bool get isThin => pieces < 2;
}

/// A draft comment as it comes back, before the teacher has touched it.
class ReportDraft {
  /// Position in the request — the only thing the model is given to
  /// identify a student by, and what reattaches the name locally.
  final int index;

  /// Written with a `{{name}}` placeholder where the student's name goes.
  final String comment;

  /// The evidence the model says it leaned on, in its own words. Shown to
  /// the teacher so a claim can be checked against a real mark rather than
  /// taken on trust.
  final List<String> grounds;

  const ReportDraft({required this.index, required this.comment, required this.grounds});
}

/// Turns a term of marked work into report card comments.
///
/// The whole reason this can be done well here and nowhere else is that the
/// evidence already exists: every mark, every rubric line, every strength
/// and next step, per student, across a term. A comment built on that is
/// defensible to a parent; a comment built on a blank prompt is the generic
/// filler teachers already resent writing.
///
/// Two rules run through everything below.
///
///  1. NO NAMES LEAVE THE DEVICE. The model is sent an array of anonymous
///     evidence and answers by array position. It writes `{{name}}` where a
///     name belongs and [personalise] fills it in here. Free text written
///     during marking is scrubbed against the class roster on the way out,
///     because a student who signed their essay can end up quoted in their
///     own feedback.
///  2. NOTHING BUT THE EVIDENCE. A fabricated claim about a child is the
///     worst thing this feature could produce — worse than no comment at
///     all, because the teacher will not know to check it. The prompt says
///     to write less rather than invent, and [suspectFigures] gives the
///     teacher a second look at any number that is not in the evidence.
class ReportComments {
  /// Pieces of work sent per student. A term is rarely longer than this,
  /// and a student with two years of history would otherwise push the
  /// prompt past what a class-sized request can carry.
  static const int maxAssessments = 12;

  /// Strengths / next steps carried from each piece. Marking writes up to
  /// three or four; the later ones repeat the earlier ones.
  static const int maxNotesPerAssessment = 3;

  /// Rubric lines carried per piece.
  static const int maxCriteriaPerAssessment = 8;

  /// Longest note kept. Marking feedback is a sentence; anything past this
  /// is a transcription that leaked into the wrong field.
  static const int maxNoteChars = 220;

  /// Builds one student's evidence out of what has been marked.
  ///
  /// Work that could not be graded is left out entirely: its score is a
  /// placeholder, and averaging a placeholder into a report comment invents
  /// a bad term out of a bad photograph. Work flagged for review is kept —
  /// it has a real mark, and the teacher has already seen it flagged.
  static StudentEvidence forStudent({
    required Student student,
    required List<Submission> submissions,
    required TermWindow window,
    String? classId,
    Map<String, String> presetNames = const {},
  }) {
    final mine = submissions.where((s) {
      if (s.studentId != student.id) return false;
      if (classId != null && classId.isNotEmpty && s.classId != classId) return false;
      if (s.triageStatus == TriageStatus.unableToGrade) return false;
      return window.contains(s.createdAt);
    }).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    // Keep the most recent when there are too many, but hand them back in
    // term order — a trend read backwards is a trend inverted.
    final kept = mine.length > maxAssessments ? mine.sublist(mine.length - maxAssessments) : mine;

    return StudentEvidence(
      studentId: student.id,
      studentName: student.name,
      assessments: kept.map((s) => _assessmentOf(s, presetNames)).toList(growable: false),
    );
  }

  /// Every student in a class, including those with nothing marked.
  ///
  /// The empty ones are deliberately kept: a teacher scanning a list of
  /// thirty needs to see that three have no work this term, not silently
  /// get twenty-seven comments and wonder later who is missing.
  static List<StudentEvidence> forClass({
    required List<Student> students,
    required List<Submission> submissions,
    required String classId,
    required TermWindow window,
    Map<String, String> presetNames = const {},
  }) {
    final roster = students.where((s) => s.classId == classId).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return roster
        .map((s) => forStudent(
              student: s,
              submissions: submissions,
              window: window,
              classId: classId,
              presetNames: presetNames,
            ))
        .toList(growable: false);
  }

  static AssessmentEvidence _assessmentOf(Submission s, Map<String, String> presetNames) {
    final result = s.resultJson ?? const <String, dynamic>{};
    final criteria = <CriterionEvidence>[];
    for (final raw in (result['criteriaBreakdown'] as List? ?? const []).whereType<Map>()) {
      final name = (raw['name'] ?? '').toString().trim();
      final max = (raw['maxScore'] as num?)?.toDouble() ?? 0;
      if (name.isEmpty || max <= 0) continue;
      criteria.add(CriterionEvidence(
        name: name,
        score: (raw['score'] as num?)?.toDouble() ?? 0,
        maxScore: max,
      ));
      if (criteria.length >= maxCriteriaPerAssessment) break;
    }
    return AssessmentEvidence(
      markedAt: s.createdAt,
      subject: s.subject,
      title: (presetNames[s.presetId] ?? '').trim().isNotEmpty ? presetNames[s.presetId]!.trim() : s.subject,
      score: s.score,
      maxScore: s.maxScore,
      criteria: criteria,
      strengths: _notes(result['strengths']),
      improvements: _notes(result['improvements']),
    );
  }

  static List<String> _notes(Object? raw) => (raw as List? ?? const [])
      .map((e) => e.toString().trim())
      .where((e) => e.isNotEmpty)
      .take(maxNotesPerAssessment)
      .map((e) => e.length > maxNoteChars ? '${e.substring(0, maxNoteChars).trimRight()}…' : e)
      .toList(growable: false);

  /// What actually goes over the wire for one student.
  ///
  /// Keyed by [index] and nothing else. No id, no name, no code — an id is
  /// as identifying as a name once it is paired with a roster, and the
  /// server has no need for either.
  ///
  /// [scrub] is the class roster: free text written during marking runs
  /// through it, because a student who signed their essay, or wrote a
  /// classmate's name in an answer, can end up quoted back in the feedback
  /// the marker generated.
  static Map<String, dynamic> anonymousPayload(
    StudentEvidence e, {
    required int index,
    Iterable<String> scrub = const [],
    String pronoun = 'they',
  }) {
    String clean(String t) => scrub.isEmpty ? t : Anonymizer.scrubNames(t, scrub);
    return {
      'i': index,
      'pronoun': pronoun,
      'pieces': e.pieces,
      if (e.averagePercent != null) 'averagePercent': e.averagePercent,
      if (e.trendPoints != null) 'trendPoints': e.trendPoints,
      'criteria': [
        for (final c in e.criteriaTrends)
          {'name': clean(c.name), 'averagePercent': c.averagePercent, 'seen': c.seen},
      ],
      'work': [
        for (final a in e.assessments)
          {
            'on': _isoDate(a.markedAt),
            'subject': clean(a.subject),
            'title': clean(a.title),
            'score': a.score,
            'outOf': a.maxScore,
            'percent': a.percent,
            if (a.criteria.isNotEmpty)
              'criteria': [
                for (final c in a.criteria) {'name': clean(c.name), 'percent': c.percent},
              ],
            if (a.strengths.isNotEmpty) 'didWell': [for (final s in a.strengths) clean(s)],
            if (a.improvements.isNotEmpty) 'nextSteps': [for (final s in a.improvements) clean(s)],
          },
      ],
    };
  }

  static String _isoDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Puts the student's name back into a draft.
  ///
  /// Only the first name: report comments read as "Ana has grown in
  /// confidence", never as "Ana Lopez has". A roster stored surname-first
  /// ("Lopez, Ana") is handled, because plenty of schools export them that
  /// way and "Lopez, has grown in confidence" is not a comment anyone can
  /// send home.
  static String personalise(String comment, String name) {
    final first = firstName(name);
    if (first.isEmpty) return comment.replaceAll('{{name}}', 'This student');
    return comment.replaceAll('{{name}}', first);
  }

  /// Whether a draft run should write over this student's comment.
  ///
  /// A teacher who has edited a comment has done work the model cannot
  /// redo, so a bulk run ([only] null) leaves edited comments alone and
  /// fills in the rest. Naming a student ([only]) is the teacher asking for
  /// that one specifically, and it replaces whatever is there.
  static bool shouldDraft({
    required String studentId,
    required bool edited,
    String? only,
  }) =>
      only != null ? studentId == only : !edited;

  static String firstName(String name) {
    final n = name.trim();
    if (n.isEmpty) return '';
    if (n.contains(',')) {
      final after = n.split(',').skip(1).join(' ').trim();
      if (after.isNotEmpty) return after.split(RegExp(r'\s+')).first;
    }
    return n.split(RegExp(r'\s+')).first;
  }

  /// Numbers in a draft that do not appear anywhere in the evidence.
  ///
  /// Not a verdict — a second look. A model asked for grounded prose will
  /// occasionally round "82%" to "over 80%" (fine) or produce a figure from
  /// nowhere (not fine), and the difference matters more here than
  /// anywhere else in the app. Flagging the figure lets the teacher check
  /// one number rather than re-read the whole term.
  ///
  /// Deliberately forgiving: anything within a point of a real figure
  /// passes, since a comment that rounds is not a comment that invents.
  static List<String> suspectFigures(String comment, StudentEvidence e) {
    final allowed = <double>{
      e.pieces.toDouble(),
      if (e.averagePercent != null) e.averagePercent!.toDouble(),
      if (e.trendPoints != null) e.trendPoints!.abs().toDouble(),
    };
    for (final a in e.assessments) {
      allowed.addAll([a.percent.toDouble(), a.score, a.maxScore]);
      for (final c in a.criteria) {
        allowed.addAll([c.percent.toDouble(), c.score, c.maxScore]);
      }
    }
    for (final c in e.criteriaTrends) {
      allowed.addAll([c.averagePercent.toDouble(), c.seen.toDouble()]);
    }

    final out = <String>[];
    for (final m in RegExp(r'\d+(?:\.\d+)?').allMatches(comment)) {
      final text = m.group(0)!;
      final v = double.tryParse(text);
      if (v == null) continue;
      if (allowed.any((a) => (a - v).abs() <= 1)) continue;
      if (!out.contains(text)) out.add(text);
    }
    return out;
  }
}

/// How the teacher wants the comments to read.
///
/// Length is a word target rather than a "short/long" word because the
/// model needs a number and the teacher needs a limit — many boards cap
/// report comments at a character count, and a comment that has to be cut
/// by hand has not saved anybody anything.
class ReportOptions {
  final String tone; // warm | balanced | formal
  final int words;
  final bool includeNextStep;

  const ReportOptions({this.tone = 'warm', this.words = 70, this.includeNextStep = true});

  static const tones = ['warm', 'balanced', 'formal'];
  static const lengths = [45, 70, 110];

  Map<String, dynamic> toJson() => {'tone': tone, 'words': words, 'includeNextStep': includeNextStep};
}
