import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marking_prokect_v2/models/grading_preset.dart';
import 'package:marking_prokect_v2/models/submission.dart';
import 'package:marking_prokect_v2/screens/reports/report_comments_screen.dart';
import 'package:marking_prokect_v2/services/classes_service.dart';
import 'package:marking_prokect_v2/services/local_store.dart';
import 'package:marking_prokect_v2/services/presets_service.dart';
import 'package:marking_prokect_v2/services/students_service.dart';
import 'package:marking_prokect_v2/services/submissions_service.dart';
import 'package:provider/provider.dart';

/// Keeps one test's classes and students out of the next one's. The real
/// store is SharedPreferences, whose cached instance outlives a test, so
/// every case after the first was drafting against a roster built up by the
/// ones before it.
class _MemoryStore implements LocalStore {
  final _data = <String, String>{};
  @override
  Future<String?> getString(String key) async => _data[key];
  @override
  Future<void> setString(String key, String value) async => _data[key] = value;
  @override
  Future<void> clear() async => _data.clear();
}

// The screen itself, with real services and no network.
//
// Drafting is not exercised here — that needs a signed-in teacher and the
// edge function. What IS exercised is the part a teacher notices first and
// that no unit test can see: a student with nothing marked is still on the
// list, saying so, instead of quietly missing.
void main() {
  Future<void> show(WidgetTester tester, {required bool withMarkedWork}) async {
    // Tall enough that the whole list is laid out — the draft button and the
    // student cards sit well below one screen, and a lazy ListView never
    // builds what it cannot show.
    tester.view.physicalSize = const Size(1000, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = _MemoryStore();
    final classes = ClassesService(store: store);
    final students = StudentsService(store: store);
    final submissions = SubmissionsService(store: store);
    final presets = PresetsService(store: store);

    final klass = await classes.create(
      teacherId: 't1',
      name: 'Year 10 Science',
      subject: 'Science',
      period: 'P2',
    );
    final ana = await students.create(
      teacherId: 't1',
      classId: klass.id,
      name: 'Ana Lopez',
      studentId: 'AL1',
    );
    await students.create(teacherId: 't1', classId: klass.id, name: 'Ben Carter', studentId: 'BC1');

    if (withMarkedWork) {
      final at = DateTime.now().subtract(const Duration(days: 3));
      await submissions.create(Submission(
        id: 'sub1',
        teacherId: 't1',
        studentId: ana.id,
        classId: klass.id,
        presetId: 'p1',
        subject: 'Science',
        gradingMode: GradingMode.testQuiz,
        score: 15,
        maxScore: 20,
        feedback: '',
        triageStatus: TriageStatus.graded,
        overrideUsed: false,
        triageFlags: const [],
        confidence: 90,
        createdAt: at,
        updatedAt: at,
        resultJson: const {
          'criteriaBreakdown': [
            {'name': 'Unit conversion', 'score': 4.0, 'maxScore': 10.0},
          ],
          'strengths': ['Clear working'],
          'improvements': ['Watch the units'],
        },
      ));
    }

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: classes),
        ChangeNotifierProvider.value(value: students),
        ChangeNotifierProvider.value(value: submissions),
        ChangeNotifierProvider.value(value: presets),
      ],
      child: const MaterialApp(home: ReportCommentsScreen()),
    ));
    await tester.pumpAndSettle();

    // Pick the class.
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Year 10 Science · P2').last);
    await tester.pumpAndSettle();
  }

  testWidgets('the teacher is told these are drafts before anything else', (tester) async {
    await show(tester, withMarkedWork: false);
    expect(find.textContaining('These are drafts'), findsOneWidget);
  });

  testWidgets('a student with nothing marked is shown, and says so', (tester) async {
    await show(tester, withMarkedWork: true);
    expect(find.text('Ana Lopez'), findsOneWidget);
    expect(find.text('Ben Carter'), findsOneWidget);
    expect(find.textContaining('Nothing marked in this period'), findsOneWidget);
  });

  testWidgets('the evidence is on screen before any comment is drafted', (tester) async {
    await show(tester, withMarkedWork: true);
    expect(find.text('1 piece'), findsOneWidget);
    expect(find.text('avg 75%'), findsOneWidget);
    expect(find.text('thin evidence'), findsOneWidget);
    expect(find.textContaining('Unit conversion 40%'), findsOneWidget);
    // Nothing to edit until a draft exists — an empty box invites a
    // teacher to write the comment by hand, which is the job they came
    // here to avoid.
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('the draft button counts only the students there is evidence for', (tester) async {
    await show(tester, withMarkedWork: true);
    expect(find.text('Draft 1 comment'), findsOneWidget);
  });

  testWidgets('an empty class cannot be drafted at all', (tester) async {
    await show(tester, withMarkedWork: false);
    expect(find.text('Draft 0 comments'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.ancestor(of: find.text('Draft 0 comments'), matching: find.byType(FilledButton)),
    );
    expect(button.onPressed, isNull);
  });
}
