import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marking_prokect_v2/models/grading_preset.dart';
import 'package:marking_prokect_v2/models/submission.dart';
import 'package:marking_prokect_v2/screens/classes/class_analysis_screen.dart';
import 'package:marking_prokect_v2/services/class_analysis.dart';
import 'package:marking_prokect_v2/services/classes_service.dart';
import 'package:marking_prokect_v2/services/local_store.dart';
import 'package:marking_prokect_v2/services/students_service.dart';
import 'package:marking_prokect_v2/services/submissions_service.dart';
import 'package:provider/provider.dart';

/// Keeps one test's class and roster out of the next one's — the real store
/// is SharedPreferences, whose cached instance outlives a single test.
class _MemoryStore implements LocalStore {
  final _data = <String, String>{};
  @override
  Future<String?> getString(String key) async => _data[key];
  @override
  Future<void> setString(String key, String value) async => _data[key] = value;
  @override
  Future<void> clear() async => _data.clear();
}

/// One annotation as the marker returns it — see QuestionAnnotation.toJson.
Map<String, dynamic> q(
  String label, {
  String earned = '1',
  String outOf = '/1',
  bool correct = true,
  String feedback = '',
  int chosenOption = 0,
}) =>
    {
      'questionLabel': label,
      'earnedMark': earned,
      'outOfMark': outOf,
      'correct': correct,
      'feedback': feedback,
      'methodNote': '',
      'chosenOption': chosenOption,
      'pageIndex': 0,
      'positionTop': 0.5,
      'positionLeft': 0.5,
    };

/// A question that was answered fully correctly.
Map<String, dynamic> right(String label, {String outOf = '/2', String? feedback}) =>
    q(label, earned: outOf.replaceAll('/', ''), outOf: outOf, correct: true, feedback: feedback ?? 'Correct');

/// A question that lost every mark, with the marker's note on why.
Map<String, dynamic> wrong(String label, {String outOf = '/2', String feedback = '', int chosenOption = 0}) =>
    q(label, earned: '0', outOf: outOf, correct: false, feedback: feedback, chosenOption: chosenOption);

/// A question the marker refused to judge — the teacher marks it by hand.
Map<String, dynamic> teacherOnly(String label, {String outOf = '/2'}) =>
    q(label, earned: '?', outOf: outOf, correct: false, feedback: 'Listening task — no key');

Map<String, dynamic> crit(String name, double score, double max) =>
    {'name': name, 'score': score, 'maxScore': max, 'level': null, 'feedback': ''};

Submission paper({
  required String studentId,
  List<Map<String, dynamic>> questions = const [],
  List<Map<String, dynamic>> criteria = const [],
  DateTime? at,
  String classId = 'c1',
  String presetId = 'p1',
  String subject = 'Science',
  TriageStatus status = TriageStatus.graded,
  double? score,
  double? max,
}) {
  final when = at ?? DateTime(2026, 5, 4, 16, 30);
  double earnedOf(Map<String, dynamic> a) => double.tryParse((a['earnedMark'] as String).replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
  double outOf(Map<String, dynamic> a) => double.tryParse((a['outOfMark'] as String).replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
  final scored = questions.where((a) => (a['earnedMark'] as String).trim() != '?').toList();
  final raw = score ?? scored.fold<double>(0, (t, a) => t + earnedOf(a));
  final out = max ?? scored.fold<double>(0, (t, a) => t + outOf(a));
  return Submission(
    id: 'sub_${studentId}_${when.millisecondsSinceEpoch}',
    teacherId: 't1',
    studentId: studentId,
    classId: classId,
    presetId: presetId,
    subject: subject,
    gradingMode: GradingMode.testQuiz,
    score: raw,
    maxScore: out,
    feedback: '',
    triageStatus: status,
    overrideUsed: false,
    triageFlags: const [],
    confidence: 90,
    createdAt: when,
    updatedAt: when,
    resultJson: {
      'annotations': questions,
      'criteriaBreakdown': criteria,
      'rawScore': raw,
      'maxScore': out,
    },
  );
}

QuestionInsight named(ClassInsight insight, String label) =>
    insight.questions.firstWhere((x) => x.label == label);

void main() {
  group('finding the class set a teacher just marked', () {
    test('one afternoon of marking is one set', () {
      final subs = [
        paper(studentId: 's1', at: DateTime(2026, 5, 4, 16, 30)),
        paper(studentId: 's2', at: DateTime(2026, 5, 4, 16, 33)),
        paper(studentId: 's3', at: DateTime(2026, 5, 4, 16, 41)),
      ];
      final sets = ClassAnalysis.setsFor(submissions: subs, classId: 'c1');
      expect(sets.length, 1);
      expect(sets.first.papers.length, 3);
    });

    test('last week\'s test and this week\'s are separate sets, newest first', () {
      final subs = [
        paper(studentId: 's1', at: DateTime(2026, 5, 4, 16, 30)),
        paper(studentId: 's2', at: DateTime(2026, 5, 4, 16, 33)),
        paper(studentId: 's1', at: DateTime(2026, 4, 27, 15, 0)),
      ];
      final sets = ClassAnalysis.setsFor(submissions: subs, classId: 'c1');
      expect(sets.length, 2);
      expect(sets.first.papers.length, 2);
      expect(sets.first.markedAt, DateTime(2026, 5, 4, 16, 33));
    });

    test('two subjects marked the same afternoon do not merge', () {
      final subs = [
        paper(studentId: 's1', subject: 'Science', presetId: 'p1', at: DateTime(2026, 5, 4, 16, 30)),
        paper(studentId: 's2', subject: 'French', presetId: 'p2', at: DateTime(2026, 5, 4, 16, 35)),
      ];
      expect(ClassAnalysis.setsFor(submissions: subs, classId: 'c1').length, 2);
    });

    test('another class is not in this class\'s sets', () {
      final subs = [
        paper(studentId: 's1', classId: 'c1'),
        paper(studentId: 's9', classId: 'c2'),
      ];
      final sets = ClassAnalysis.setsFor(submissions: subs, classId: 'c1');
      expect(sets.length, 1);
      expect(sets.first.papers.single.studentId, 's1');
    });

    test('a paper that could not be graded is left out', () {
      final subs = [
        paper(studentId: 's1'),
        paper(studentId: 's2', status: TriageStatus.unableToGrade),
      ];
      final sets = ClassAnalysis.setsFor(submissions: subs, classId: 'c1');
      expect(sets.single.papers.length, 1);
    });
  });

  group('how the class went, question by question', () {
    ClassInsight threeStudents() => ClassAnalysis.analyse([
          paper(studentId: 's1', questions: [right('Q1'), wrong('Q2', feedback: 'Forgot to convert cm to m'), right('Q3')]),
          paper(studentId: 's2', questions: [right('Q1'), wrong('Q2', feedback: 'forgot to convert cm to m'), wrong('Q3', feedback: 'No units')]),
          paper(studentId: 's3', questions: [right('Q1'), q('Q2', earned: '1', outOf: '/2', correct: false, feedback: 'Units dropped halfway'), right('Q3')]),
        ]);

    test('percent correct counts full marks only', () {
      final insight = threeStudents();
      expect(named(insight, 'Q1').percentCorrect, 100);
      expect(named(insight, 'Q2').percentCorrect, 0);
      expect(named(insight, 'Q3').percentCorrect, 67);
    });

    test('average score is the marks actually earned on that question', () {
      final insight = threeStudents();
      final q2 = named(insight, 'Q2');
      expect(q2.outOf, 2);
      expect(q2.averageMark, closeTo(1 / 3, 0.001));
      expect(q2.averagePercent, 17);
    });

    test('questions are ranked worst first', () {
      final insight = threeStudents();
      expect(insight.questions.map((x) => x.label).toList(), ['Q2', 'Q3', 'Q1']);
    });

    test('the most repeated marker note becomes the one-line what went wrong', () {
      final q2 = named(threeStudents(), 'Q2');
      expect(q2.commonErrorCount, 2);
      expect(q2.commonError, 'Forgot to convert cm to m');
      expect(q2.whatWentWrong, contains('Forgot to convert cm to m'));
    });

    test('the class average across the whole paper is reported', () {
      // 5/6, 2/6 and 4/6 of the marks available.
      expect(threeStudents().averagePercent, 61);
    });

    test('every student who lost marks on a question is listed, and every student who did not', () {
      final insight = threeStudents();
      expect(named(insight, 'Q2').missedBy, ['s1', 's2', 's3']);
      expect(named(insight, 'Q3').missedBy, ['s2']);
      expect(named(insight, 'Q3').gotBy, ['s1', 's3']);
    });
  });

  group('the KTCA category behind a question', () {
    test('the category is read off the label the marker wrote', () {
      final insight = ClassAnalysis.analyse([
        paper(studentId: 's1', questions: [wrong('Thinking 2'), right('Knowledge 1'), right('Application 3')]),
      ]);
      expect(named(insight, 'Thinking 2').category, 'Thinking');
      expect(named(insight, 'Knowledge 1').category, 'Knowledge');
      expect(named(insight, 'Application 3').category, 'Application');
    });

    test('a plain numbered question has no category rather than a guessed one', () {
      final insight = ClassAnalysis.analyse([
        paper(studentId: 's1', questions: [wrong('Q4')]),
      ]);
      expect(named(insight, 'Q4').category, isNull);
    });

    test('a category section with a single question is still categorised', () {
      final insight = ClassAnalysis.analyse([
        paper(studentId: 's1', questions: [wrong('Communication')]),
      ]);
      expect(named(insight, 'Communication').category, 'Communication');
    });
  });

  group('multiple choice', () {
    test('the wrong option most of the class picked is surfaced', () {
      final insight = ClassAnalysis.analyse([
        paper(studentId: 's1', questions: [wrong('Q5', outOf: '/1', chosenOption: 3)]),
        paper(studentId: 's2', questions: [wrong('Q5', outOf: '/1', chosenOption: 3)]),
        paper(studentId: 's3', questions: [wrong('Q5', outOf: '/1', chosenOption: 2)]),
        paper(studentId: 's4', questions: [right('Q5', outOf: '/1')]),
      ]);
      final q5 = named(insight, 'Q5');
      expect(q5.commonWrongOption, 3);
      expect(q5.commonWrongOptionCount, 2);
      expect(q5.whatWentWrong, contains('option 3'));
    });

    test('a right answer\'s option is never counted as the common wrong one', () {
      final insight = ClassAnalysis.analyse([
        paper(studentId: 's1', questions: [q('Q5', earned: '1', outOf: '/1', correct: true, chosenOption: 4)]),
        paper(studentId: 's2', questions: [q('Q5', earned: '1', outOf: '/1', correct: true, chosenOption: 4)]),
        paper(studentId: 's3', questions: [wrong('Q5', outOf: '/1', chosenOption: 1)]),
      ]);
      expect(named(insight, 'Q5').commonWrongOption, 1);
    });
  });

  group('edge cases that would otherwise put a wrong number in front of a teacher', () {
    test('a batch of one paper still analyses', () {
      final insight = ClassAnalysis.analyse([
        paper(studentId: 's1', questions: [right('Q1'), wrong('Q2', feedback: 'Slope formula inverted')]),
      ]);
      expect(insight.papers, 1);
      expect(insight.questions.length, 2);
      expect(named(insight, 'Q2').percentCorrect, 0);
      expect(named(insight, 'Q1').percentCorrect, 100);
    });

    test('a question the whole class got right is 100 percent and needs no reteach', () {
      final insight = ClassAnalysis.analyse([
        paper(studentId: 's1', questions: [right('Q1')]),
        paper(studentId: 's2', questions: [right('Q1')]),
      ]);
      final q1 = named(insight, 'Q1');
      expect(q1.percentCorrect, 100);
      expect(q1.missedBy, isEmpty);
      expect(q1.reteach, isEmpty);
      expect(insight.weakest, isEmpty);
    });

    test('a question the whole class got wrong is 0 percent, not an empty average', () {
      final insight = ClassAnalysis.analyse([
        paper(studentId: 's1', questions: [wrong('Q7', feedback: 'Balanced the equation wrong')]),
        paper(studentId: 's2', questions: [wrong('Q7', feedback: 'Balanced the equation wrong')]),
      ]);
      final q7 = named(insight, 'Q7');
      expect(q7.percentCorrect, 0);
      expect(q7.averagePercent, 0);
      expect(q7.attempted, 2);
      expect(q7.reteach, isNotEmpty);
    });

    test('a student who skipped the last page is not counted wrong on it', () {
      final insight = ClassAnalysis.analyse([
        paper(studentId: 's1', questions: [right('Q1'), right('Q2')]),
        paper(studentId: 's2', questions: [right('Q1'), right('Q2')]),
        paper(studentId: 's3', questions: [right('Q1')]),
      ]);
      final q2 = named(insight, 'Q2');
      // The failure this guards: treating a missing question as a zero
      // reports a question the class actually aced as 67% and sends the
      // teacher to reteach it.
      expect(q2.attempted, 2);
      expect(q2.percentCorrect, 100);
      expect(q2.notSeen, 1);
      expect(q2.missedBy, isEmpty);
    });

    test('a question flagged for teacher marking is excluded, not counted as zero', () {
      final insight = ClassAnalysis.analyse([
        paper(studentId: 's1', questions: [right('Q1'), teacherOnly('Q2')]),
        paper(studentId: 's2', questions: [right('Q1'), teacherOnly('Q2')]),
        paper(studentId: 's3', questions: [right('Q1'), right('Q2')]),
      ]);
      final q2 = named(insight, 'Q2');
      expect(q2.teacherMarked, 2);
      expect(q2.attempted, 1);
      expect(q2.percentCorrect, 100);
      expect(q2.averagePercent, 100);
      expect(q2.missedBy, isEmpty);
      expect(q2.reteach, isEmpty);
    });

    test('a question every paper left to the teacher reports no percentage at all', () {
      final insight = ClassAnalysis.analyse([
        paper(studentId: 's1', questions: [teacherOnly('Q2')]),
        paper(studentId: 's2', questions: [teacherOnly('Q2')]),
      ]);
      final q2 = named(insight, 'Q2');
      expect(q2.attempted, 0);
      expect(q2.hasMarks, isFalse);
      expect(q2.teacherMarked, 2);
      expect(q2.whatWentWrong, contains('teacher'));
    });

    test('the same question written two ways is one question', () {
      final insight = ClassAnalysis.analyse([
        paper(studentId: 's1', questions: [wrong('Q3')]),
        paper(studentId: 's2', questions: [wrong('Question 3')]),
        paper(studentId: 's3', questions: [wrong('q 3')]),
      ]);
      expect(insight.questions.length, 1);
      expect(insight.questions.single.attempted, 3);
    });

    test('writing error marks are not questions', () {
      // Essay error marks carry no marks of their own — counting them as
      // questions puts thirty 0% "Grammar" rows at the top of the ranking.
      final insight = ClassAnalysis.analyse([
        paper(studentId: 's1', questions: [
          right('Q1'),
          q('Grammar', earned: '', outOf: '', correct: false, feedback: 'dont -> don\'t'),
        ], criteria: const []),
      ]);
      expect(insight.questions.map((x) => x.label).toList(), ['Q1']);
    });

    test('nothing marked yet is an empty analysis, not a crash', () {
      final insight = ClassAnalysis.analyse(const []);
      expect(insight.papers, 0);
      expect(insight.questions, isEmpty);
      expect(insight.averagePercent, isNull);
    });
  });

  group('an essay set falls back to the rubric sections', () {
    test('sections are ranked like questions when there are no numbered ones', () {
      final insight = ClassAnalysis.analyse([
        paper(studentId: 's1', criteria: [crit('Grammar', 2, 5), crit('Content', 5, 5)]),
        paper(studentId: 's2', criteria: [crit('Grammar', 3, 5), crit('Content', 4, 5)]),
      ]);
      expect(insight.questions.map((x) => x.label).toList(), ['Grammar', 'Content']);
      expect(named(insight, 'Grammar').averagePercent, 50);
      expect(named(insight, 'Content').percentCorrect, 50);
    });

    test('numbered questions win over the rubric when both are present', () {
      final insight = ClassAnalysis.analyse([
        paper(studentId: 's1', questions: [wrong('Q1')], criteria: [crit('Knowledge', 2, 5)]),
      ]);
      expect(insight.questions.map((x) => x.label).toList(), ['Q1']);
    });
  });

  group('the reteach note a teacher can use or ignore', () {
    String noteFor(List<Submission> papers, String label) => named(ClassAnalysis.analyse(papers), label).reteach;

    test('it names the question, the numbers, and the repeated slip', () {
      final note = noteFor([
        paper(studentId: 's1', questions: [wrong('Q4', feedback: 'Forgot to convert cm to m')]),
        paper(studentId: 's2', questions: [wrong('Q4', feedback: 'Forgot to convert cm to m')]),
        paper(studentId: 's3', questions: [right('Q4')]),
      ], 'Q4');
      expect(note, contains('Q4'));
      expect(note, contains('2 of 3'));
      expect(note, contains('Forgot to convert cm to m'));
    });

    test('a question nobody got sends the teacher to check the question first', () {
      final note = noteFor([
        paper(studentId: 's1', questions: [wrong('Q8')]),
        paper(studentId: 's2', questions: [wrong('Q8')]),
        paper(studentId: 's3', questions: [wrong('Q8')]),
      ], 'Q8');
      expect(note.toLowerCase(), contains('nobody'));
    });

    test('a question only a couple of students missed suggests a pull-aside, not a reteach', () {
      final papers = [
        for (var i = 0; i < 10; i++) paper(studentId: 's$i', questions: [right('Q2')]),
        paper(studentId: 's10', questions: [wrong('Q2')]),
      ];
      expect(noteFor(papers, 'Q2').toLowerCase(), contains('pull-aside'));
    });

    test('the category changes the advice, because Thinking marks do not come back like Knowledge marks', () {
      final knowledge = noteFor([
        paper(studentId: 's1', questions: [wrong('Knowledge 1')]),
        paper(studentId: 's2', questions: [wrong('Knowledge 1')]),
        paper(studentId: 's3', questions: [right('Knowledge 1')]),
      ], 'Knowledge 1');
      final thinking = noteFor([
        paper(studentId: 's1', questions: [wrong('Thinking 1')]),
        paper(studentId: 's2', questions: [wrong('Thinking 1')]),
        paper(studentId: 's3', questions: [right('Thinking 1')]),
      ], 'Thinking 1');
      expect(knowledge, isNot(thinking));
      expect(thinking.toLowerCase(), contains('reasoning'));
    });

    test('part marks everywhere reads as a finishing problem, not a starting one', () {
      final note = noteFor([
        for (var i = 0; i < 4; i++)
          paper(studentId: 's$i', questions: [q('Q6', earned: '3', outOf: '/4', correct: false, feedback: 'Missing units')]),
      ], 'Q6');
      expect(note.toLowerCase(), contains('finish'));
    });
  });

  group('what one student missed that the class did not', () {
    ClassInsight classOfFive() => ClassAnalysis.analyse([
          paper(studentId: 's1', questions: [right('Q1'), wrong('Q2'), wrong('Q3')]),
          paper(studentId: 's2', questions: [right('Q1'), right('Q2'), wrong('Q3')]),
          paper(studentId: 's3', questions: [right('Q1'), right('Q2'), wrong('Q3')]),
          paper(studentId: 's4', questions: [right('Q1'), right('Q2'), wrong('Q3')]),
          paper(studentId: 's5', questions: [right('Q1'), right('Q2'), right('Q3')]),
        ]);

    test('a question this student missed that most of the class got', () {
      final gaps = ClassAnalysis.gapsFor(classOfFive(), 's1');
      expect(gaps.missedWhatClassGot.map((x) => x.label).toList(), ['Q2']);
    });

    test('a question this student got that most of the class missed', () {
      final gaps = ClassAnalysis.gapsFor(classOfFive(), 's5');
      expect(gaps.gotWhatClassMissed.map((x) => x.label).toList(), ['Q3']);
    });

    test('a question the whole class missed is not held against the student', () {
      final gaps = ClassAnalysis.gapsFor(classOfFive(), 's2');
      expect(gaps.missedWhatClassGot, isEmpty);
      expect(gaps.gotWhatClassMissed, isEmpty);
    });

    test('a student whose paper is not in the set has no gaps rather than every question', () {
      final gaps = ClassAnalysis.gapsFor(classOfFive(), 's99');
      expect(gaps.missedWhatClassGot, isEmpty);
      expect(gaps.gotWhatClassMissed, isEmpty);
    });

    test('a question this student never saw is not a gap', () {
      final insight = ClassAnalysis.analyse([
        paper(studentId: 's1', questions: [right('Q1')]),
        paper(studentId: 's2', questions: [right('Q1'), right('Q2')]),
        paper(studentId: 's3', questions: [right('Q1'), right('Q2')]),
      ]);
      expect(ClassAnalysis.gapsFor(insight, 's1').missedWhatClassGot, isEmpty);
    });
  });

  // The screen over the top of all of it, with real services and no
  // network. What a unit test cannot see is whether the worst question is
  // the one a teacher's eye lands on first.
  group('the class summary screen', () {
    Future<void> show(WidgetTester tester, {required bool marked}) async {
      // Tall enough that the lazy list lays out every question card.
      tester.view.physicalSize = const Size(1000, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final store = _MemoryStore();
      final classes = ClassesService(store: store);
      final students = StudentsService(store: store);
      final submissions = SubmissionsService(store: store);

      final klass = await classes.create(teacherId: 't1', name: 'Year 10 Science', subject: 'Science', period: 'P2');
      final ana = await students.create(teacherId: 't1', classId: klass.id, name: 'Ana Lopez', studentId: 'AL1');
      final ben = await students.create(teacherId: 't1', classId: klass.id, name: 'Ben Carter', studentId: 'BC1');

      if (marked) {
        final at = DateTime(2026, 5, 4, 16);
        await submissions.create(paper(
          studentId: ana.id,
          classId: klass.id,
          at: at,
          questions: [right('Knowledge 1'), wrong('Thinking 2', feedback: 'Forgot to convert cm to m')],
        ));
        await submissions.create(paper(
          studentId: ben.id,
          classId: klass.id,
          at: at.add(const Duration(minutes: 3)),
          questions: [right('Knowledge 1'), wrong('Thinking 2', feedback: 'Forgot to convert cm to m')],
        ));
      }

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: classes),
          ChangeNotifierProvider.value(value: students),
          ChangeNotifierProvider.value(value: submissions),
        ],
        child: MaterialApp(home: ClassAnalysisScreen(classId: klass.id)),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('an unmarked class says what would fill it in, rather than showing zeros', (tester) async {
      await show(tester, marked: false);
      expect(find.textContaining('Nothing to break down yet'), findsOneWidget);
    });

    testWidgets('the question to start with is named at the top', (tester) async {
      await show(tester, marked: true);
      expect(find.textContaining('Start with Thinking 2'), findsOneWidget);
    });

    testWidgets('the KTCA category and the one-line what went wrong are on the question', (tester) async {
      await show(tester, marked: true);
      expect(find.text('Thinking'), findsOneWidget);
      expect(find.text('Forgot to convert cm to m'), findsWidgets);
    });

    testWidgets('the reteach idea is folded away until the teacher asks for it', (tester) async {
      await show(tester, marked: true);
      expect(find.text('Reteach idea'), findsNothing);
      await tester.tap(find.text('Thinking 2'));
      await tester.pumpAndSettle();
      expect(find.text('Reteach idea'), findsOneWidget);
    });
  });
}
