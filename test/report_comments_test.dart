import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:marking_prokect_v2/models/grading_preset.dart';
import 'package:marking_prokect_v2/models/student.dart';
import 'package:marking_prokect_v2/models/submission.dart';
import 'package:marking_prokect_v2/services/report_comments.dart';

Student student(String id, String name, {String classId = 'c1'}) => Student(
      id: id,
      teacherId: 't1',
      classId: classId,
      name: name,
      studentId: id.toUpperCase(),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

Submission sub({
  required String studentId,
  required DateTime at,
  String classId = 'c1',
  double score = 15,
  double max = 20,
  TriageStatus status = TriageStatus.graded,
  String subject = 'Science',
  String presetId = 'p1',
  List<Map<String, dynamic>> criteria = const [],
  List<String> strengths = const [],
  List<String> improvements = const [],
}) =>
    Submission(
      id: 'sub_${studentId}_${at.millisecondsSinceEpoch}',
      teacherId: 't1',
      studentId: studentId,
      classId: classId,
      presetId: presetId,
      subject: subject,
      gradingMode: GradingMode.testQuiz,
      score: score,
      maxScore: max,
      feedback: '',
      triageStatus: status,
      overrideUsed: false,
      triageFlags: const [],
      confidence: 90,
      createdAt: at,
      updatedAt: at,
      resultJson: {
        'criteriaBreakdown': criteria,
        'strengths': strengths,
        'improvements': improvements,
      },
    );

Map<String, dynamic> crit(String name, double score, double max) => {'name': name, 'score': score, 'maxScore': max};

StudentEvidence evidenceOf(List<Submission> subs, {TermWindow? window}) => ReportComments.forStudent(
      student: student('s1', 'Ana Lopez'),
      submissions: subs,
      window: window ?? TermWindow.between(DateTime(2026, 1, 1), DateTime(2026, 12, 31)),
    );

void main() {
  _editProtection();
  group('the term a report covers', () {
    test('the last day of term is inside the term', () {
      final w = TermWindow.between(DateTime(2026, 4, 1), DateTime(2026, 6, 30));
      // The failure this guards: comparing against the raw end date drops
      // everything marked after midnight on it, which is every paper.
      expect(w.contains(DateTime(2026, 6, 30, 15, 40)), isTrue);
      expect(w.contains(DateTime(2026, 6, 30, 23, 59, 59)), isTrue);
      expect(w.contains(DateTime(2026, 7, 1)), isFalse);
    });

    test('the first day of term is inside it, the day before is not', () {
      final w = TermWindow.between(DateTime(2026, 4, 1), DateTime(2026, 6, 30));
      expect(w.contains(DateTime(2026, 4, 1)), isTrue);
      expect(w.contains(DateTime(2026, 3, 31, 23, 59)), isFalse);
    });

    test('dates picked in the wrong order still make a term', () {
      final w = TermWindow.between(DateTime(2026, 6, 30), DateTime(2026, 4, 1));
      expect(w.contains(DateTime(2026, 5, 12)), isTrue);
      expect(w.start, DateTime(2026, 4, 1));
    });

    test('a term ending on the last day of a month or year does not wrap', () {
      expect(TermWindow.between(DateTime(2026, 12, 20), DateTime(2026, 12, 31)).end, DateTime(2027, 1, 1));
      expect(TermWindow.between(DateTime(2026, 1, 5), DateTime(2026, 1, 31)).end, DateTime(2026, 2, 1));
    });

    test('a one-day term contains that day and nothing else', () {
      final w = TermWindow.between(DateTime(2026, 5, 5), DateTime(2026, 5, 5));
      expect(w.contains(DateTime(2026, 5, 5, 9)), isTrue);
      expect(w.contains(DateTime(2026, 5, 4, 23, 59)), isFalse);
      expect(w.contains(DateTime(2026, 5, 6)), isFalse);
    });

    test('"last 30 days" includes work marked earlier today', () {
      final now = DateTime(2026, 3, 15, 8);
      final w = TermWindow.lastDays(30, now: now);
      expect(w.contains(DateTime(2026, 3, 15, 22, 30)), isTrue, reason: 'tonight\'s marking must count');
      expect(w.contains(DateTime(2026, 2, 14, 12)), isTrue);
      expect(w.contains(DateTime(2026, 2, 13, 12)), isFalse);
    });

    test('"last 30 days" crossing a year boundary counts back correctly', () {
      final w = TermWindow.lastDays(30, now: DateTime(2026, 1, 10));
      expect(w.start, DateTime(2025, 12, 12));
      expect(w.contains(DateTime(2025, 12, 24)), isTrue);
      expect(w.contains(DateTime(2025, 12, 11, 23)), isFalse);
    });
  });

  group('what counts as evidence', () {
    final window = TermWindow.between(DateTime(2026, 4, 1), DateTime(2026, 6, 30));

    test('work that could not be graded is left out entirely', () {
      // Its score is a placeholder. Averaging it in turns a bad photograph
      // into a bad term, and the parent never hears about the photograph.
      final e = evidenceOf(
        [
          sub(studentId: 's1', at: DateTime(2026, 5, 1), score: 18),
          sub(studentId: 's1', at: DateTime(2026, 5, 2), score: 0, status: TriageStatus.unableToGrade),
        ],
        window: window,
      );
      expect(e.pieces, 1);
      expect(e.averagePercent, 90);
    });

    test('work flagged for review is kept — it has a real mark', () {
      final e = evidenceOf(
        [sub(studentId: 's1', at: DateTime(2026, 5, 1), score: 10, status: TriageStatus.needsReview)],
        window: window,
      );
      expect(e.pieces, 1);
    });

    test('another student\'s work never lands in this student\'s evidence', () {
      final e = evidenceOf(
        [
          sub(studentId: 's2', at: DateTime(2026, 5, 1), score: 20),
          sub(studentId: 's1', at: DateTime(2026, 5, 2), score: 10),
        ],
        window: window,
      );
      expect(e.pieces, 1);
      expect(e.assessments.single.score, 10);
    });

    test('another class\'s work is left out when a class is named', () {
      final e = ReportComments.forStudent(
        student: student('s1', 'Ana Lopez'),
        submissions: [
          sub(studentId: 's1', at: DateTime(2026, 5, 1), classId: 'c2'),
          sub(studentId: 's1', at: DateTime(2026, 5, 2), classId: 'c1'),
        ],
        window: window,
        classId: 'c1',
      );
      expect(e.pieces, 1);
    });

    test('work outside the term is left out', () {
      final e = evidenceOf(
        [
          sub(studentId: 's1', at: DateTime(2026, 3, 31, 23, 59)),
          sub(studentId: 's1', at: DateTime(2026, 7, 1)),
        ],
        window: window,
      );
      expect(e.pieces, 0);
      expect(e.averagePercent, isNull);
    });

    test('a long history is cut to the most recent, still in term order', () {
      final subs = [
        for (var d = 1; d <= 20; d++) sub(studentId: 's1', at: DateTime(2026, 4, d), score: d.toDouble(), max: 20),
      ];
      final e = evidenceOf(subs, window: window);
      expect(e.pieces, ReportComments.maxAssessments);
      // Most recent kept...
      expect(e.assessments.last.score, 20);
      // ...but handed over oldest-first, or a trend reads backwards.
      expect(e.assessments.first.markedAt.isBefore(e.assessments.last.markedAt), isTrue);
    });

    test('a class list keeps students with nothing marked', () {
      // Silently dropping them is how a teacher discovers in June that
      // three children never got a comment.
      final roster = [student('s2', 'Ben Carter'), student('s1', 'Ana Lopez'), student('s3', 'Cara Diaz')];
      final all = ReportComments.forClass(
        students: roster,
        submissions: [sub(studentId: 's1', at: DateTime(2026, 5, 1))],
        classId: 'c1',
        window: window,
      );
      expect(all.length, 3);
      expect(all.map((e) => e.studentName), ['Ana Lopez', 'Ben Carter', 'Cara Diaz']);
      expect(all.where((e) => e.pieces == 0).length, 2);
    });

    test('a class list ignores students in another class', () {
      final all = ReportComments.forClass(
        students: [student('s1', 'Ana Lopez'), student('s9', 'Zed Other', classId: 'c9')],
        submissions: const [],
        classId: 'c1',
        window: window,
      );
      expect(all.length, 1);
    });
  });

  group('reading a term out of the marks', () {
    test('an unscored piece never divides by zero', () {
      final e = evidenceOf([sub(studentId: 's1', at: DateTime(2026, 5, 1), score: 0, max: 0)]);
      expect(e.assessments.single.percent, 0);
      expect(e.averagePercent, isNull, reason: 'no marks is not the same as zero marks');
    });

    test('an average ignores the unscored pieces rather than counting them as zero', () {
      final e = evidenceOf([
        sub(studentId: 's1', at: DateTime(2026, 5, 1), score: 18, max: 20),
        sub(studentId: 's1', at: DateTime(2026, 5, 2), score: 0, max: 0),
      ]);
      expect(e.averagePercent, 90);
    });

    test('no trend is claimed off two marks', () {
      final e = evidenceOf([
        sub(studentId: 's1', at: DateTime(2026, 5, 1), score: 4, max: 20),
        sub(studentId: 's1', at: DateTime(2026, 5, 8), score: 18, max: 20),
      ]);
      expect(e.trendPoints, isNull, reason: '"has improved" is a claim a teacher has to defend');
    });

    test('a fall in marks comes back negative, not as an absolute', () {
      final e = evidenceOf([
        sub(studentId: 's1', at: DateTime(2026, 5, 1), score: 18, max: 20),
        sub(studentId: 's1', at: DateTime(2026, 5, 8), score: 14, max: 20),
        sub(studentId: 's1', at: DateTime(2026, 5, 15), score: 8, max: 20),
      ]);
      expect(e.trendPoints, -50);
    });

    test('rubric lines merge across pieces despite casing and spacing', () {
      final e = evidenceOf([
        sub(studentId: 's1', at: DateTime(2026, 5, 1), criteria: [crit('Unit Conversion', 2, 10)]),
        sub(studentId: 's1', at: DateTime(2026, 5, 2), criteria: [crit('unit  conversion', 6, 10)]),
      ]);
      final t = e.criteriaTrends.single;
      expect(t.seen, 2);
      expect(t.averagePercent, 40);
      expect(t.name, 'Unit Conversion', reason: 'first spelling seen is the one shown to the teacher');
    });

    test('a rubric line worth nothing is not averaged in', () {
      final e = evidenceOf([
        sub(studentId: 's1', at: DateTime(2026, 5, 1), criteria: [crit('Presentation', 0, 0), crit('Method', 5, 10)]),
      ]);
      expect(e.criteriaTrends.map((c) => c.name), ['Method']);
    });

    test('rubric lines come back strongest first', () {
      final e = evidenceOf([
        sub(studentId: 's1', at: DateTime(2026, 5, 1), criteria: [crit('Weak', 1, 10), crit('Strong', 9, 10)]),
      ]);
      expect(e.criteriaTrends.map((c) => c.name), ['Strong', 'Weak']);
    });

    test('one piece of work is flagged as thin evidence', () {
      expect(evidenceOf([sub(studentId: 's1', at: DateTime(2026, 5, 1))]).isThin, isTrue);
      expect(
        evidenceOf([
          sub(studentId: 's1', at: DateTime(2026, 5, 1)),
          sub(studentId: 's1', at: DateTime(2026, 5, 2)),
        ]).isThin,
        isFalse,
      );
    });
  });

  group('nothing identifying leaves the device', () {
    const roster = ['Ana Lopez', 'Ben Carter'];

    Map<String, dynamic> payload({List<String> strengths = const [], List<String> improvements = const []}) {
      final e = evidenceOf([
        sub(
          studentId: 's1',
          at: DateTime(2026, 5, 1),
          criteria: [crit('Method', 5, 10)],
          strengths: strengths,
          improvements: improvements,
        ),
      ]);
      return ReportComments.anonymousPayload(e, index: 3, scrub: roster);
    }

    test('the student\'s own name is nowhere in the payload', () {
      final json = jsonEncode(payload());
      expect(json.toLowerCase(), isNot(contains('ana')));
      expect(json.toLowerCase(), isNot(contains('lopez')));
      expect(json, isNot(contains('s1')), reason: 'an id is as identifying as a name once paired with a roster');
    });

    test('a name that leaked into marking feedback is scrubbed out', () {
      // The real case: a student signed their essay, so the marker quoted
      // the signature back in the strengths it wrote.
      final json = jsonEncode(payload(strengths: ['Ana Lopez explained the method clearly.']));
      expect(json, isNot(contains('Ana')));
      expect(json, contains('explained the method clearly'));
    });

    test('a classmate named in the work is scrubbed too', () {
      final json = jsonEncode(payload(improvements: ['Copied Ben\'s working rather than showing their own.']));
      expect(json, isNot(contains('Ben')));
    });

    test('the payload is keyed by the index given, not by list position', () {
      expect(payload()['i'], 3);
    });

    test('the payload carries marks and rubric lines, and no page images', () {
      final p = payload();
      expect(p['pieces'], 1);
      expect(p['averagePercent'], 75);
      expect((p['work'] as List).single, containsPair('percent', 75));
      final json = jsonEncode(p);
      expect(json, isNot(contains('image')));
      expect(json, isNot(contains('rawText')));
    });

    test('an empty roster still produces a payload rather than throwing', () {
      final e = evidenceOf([sub(studentId: 's1', at: DateTime(2026, 5, 1))]);
      expect(ReportComments.anonymousPayload(e, index: 0)['pieces'], 1);
    });

    test('a note long enough to be a transcription is cut short', () {
      final long = 'x' * 400;
      final e = evidenceOf([sub(studentId: 's1', at: DateTime(2026, 5, 1), strengths: [long])]);
      final note = ((ReportComments.anonymousPayload(e, index: 0)['work'] as List).single
          as Map)['didWell'] as List;
      expect((note.single as String).length, lessThanOrEqualTo(ReportComments.maxNoteChars + 1));
    });

    test('only the first few notes per piece are sent', () {
      final e = evidenceOf([
        sub(studentId: 's1', at: DateTime(2026, 5, 1), strengths: ['a', 'b', 'c', 'd', 'e']),
      ]);
      final note = ((ReportComments.anonymousPayload(e, index: 0)['work'] as List).single
          as Map)['didWell'] as List;
      expect(note.length, ReportComments.maxNotesPerAssessment);
    });
  });

  group('putting the name back', () {
    test('the placeholder becomes the first name only', () {
      expect(
        ReportComments.personalise('{{name}} has grown in confidence. {{name}} should keep it up.', 'Ana Lopez'),
        'Ana has grown in confidence. Ana should keep it up.',
      );
    });

    test('a roster stored surname-first still reads as a person', () {
      // "Lopez, has grown in confidence" is not a comment anyone can send.
      expect(ReportComments.personalise('{{name}} improved.', 'Lopez, Ana'), 'Ana improved.');
    });

    test('a nameless student gets neutral wording, not a hole in the sentence', () {
      expect(ReportComments.personalise('{{name}} improved.', '   '), 'This student improved.');
    });

    test('a draft that forgot the placeholder is left exactly as written', () {
      expect(ReportComments.personalise('The work improved steadily.', 'Ana Lopez'), 'The work improved steadily.');
    });

    test('a single-word name works', () {
      expect(ReportComments.firstName('Ana'), 'Ana');
      expect(ReportComments.firstName(''), '');
    });
  });

  group('catching a figure that is not in the evidence', () {
    final e = evidenceOf([
      sub(studentId: 's1', at: DateTime(2026, 5, 1), score: 15, max: 20, criteria: [crit('Method', 4, 10)]),
      sub(studentId: 's1', at: DateTime(2026, 5, 8), score: 17, max: 20),
    ]);

    test('a number from nowhere is flagged', () {
      expect(ReportComments.suspectFigures('Ana averaged 92% this term.', e), ['92']);
    });

    test('a real average is not flagged', () {
      expect(e.averagePercent, 80);
      expect(ReportComments.suspectFigures('Ana averaged 80% this term.', e), isEmpty);
    });

    test('rounding is not invention', () {
      // 85% rounded from 84 is a comment doing its job, not making things up.
      expect(ReportComments.suspectFigures('Scored 76% on the first piece.', e), isEmpty);
    });

    test('a rubric percentage the teacher can check is allowed', () {
      expect(ReportComments.suspectFigures('The method criterion sat at 40%.', e), isEmpty);
    });

    test('the number of pieces is allowed', () {
      expect(ReportComments.suspectFigures('Across 2 assessments the work was steady.', e), isEmpty);
    });

    test('each bad figure is reported once, in the order it appears', () {
      expect(
        ReportComments.suspectFigures('Scored 92% then 92% again, and 5 out of 300.', e),
        ['92', '300'],
      );
    });

    test('a comment with no numbers is never flagged', () {
      expect(ReportComments.suspectFigures('Steady work on the written explanations.', e), isEmpty);
    });

    test('a student with no evidence flags any figure at all', () {
      final empty = evidenceOf(const []);
      expect(ReportComments.suspectFigures('Averaged 70% this term.', empty), ['70']);
    });
  });
}

void _editProtection() {
  group('a bulk draft never overwrites what the teacher typed', () {
    test('untouched comments are redrafted', () {
      expect(ReportComments.shouldDraft(studentId: 's1', edited: false), isTrue);
    });

    test('an edited comment is left alone', () {
      // The hour a teacher spends editing thirty comments is not
      // recoverable, and tapping Draft to fill two blanks must not cost it.
      expect(ReportComments.shouldDraft(studentId: 's1', edited: true), isFalse);
    });

    test('naming a student replaces even an edited comment', () {
      expect(
        ReportComments.shouldDraft(studentId: 's1', edited: true, only: 's1'),
        isTrue,
      );
    });

    test('naming a student leaves everyone else alone', () {
      expect(
        ReportComments.shouldDraft(studentId: 's2', edited: false, only: 's1'),
        isFalse,
      );
    });
  });
}
