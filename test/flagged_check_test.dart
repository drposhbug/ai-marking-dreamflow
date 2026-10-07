import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marking_prokect_v2/app/app_state.dart';
import 'package:marking_prokect_v2/services/ai_grading_service.dart';
import 'package:marking_prokect_v2/services/local_store.dart';
import 'package:marking_prokect_v2/widgets/flagged_check.dart';
import 'package:provider/provider.dart';

class _MemoryStore implements LocalStore {
  final Map<String, String> values = {};
  @override
  Future<String?> getString(String key) async => values[key];
  @override
  Future<void> setString(String key, String value) async => values[key] = value;
  @override
  Future<void> clear() async => values.clear();
}

QuestionAnnotation q(String earned, {bool check = false}) => QuestionAnnotation(
      questionLabel: 'Q1',
      earnedMark: earned,
      outOfMark: '/2',
      correct: false,
      feedback: '',
      positionTop: 0.5,
      positionLeft: 0.5,
      teacherCheck: check,
    );

/// Drawings the AI marked as a best guess are flagged, and leaving a paper
/// with any asks first — unless the teacher chose to skip that for the batch.
void main() {
  test('drawings marked as a best guess and "?" marks both count as flagged', () {
    expect(flaggedCount([q('1'), q('1', check: true), q('?')]), 2);
    expect(flaggedCount([q('2')]), 0);
  });

  testWidgets('asks before going on; "Skip for this batch" stops asking', (tester) async {
    final app = AppState(store: _MemoryStore());
    final answers = <bool>[];
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: app,
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => answers.add(await confirmFlagged(context, [q('1', check: true)])),
            child: const Text('next'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('next'));
    await tester.pumpAndSettle();
    expect(find.text('1 flagged question'), findsOneWidget);
    await tester.tap(find.text('Check them'));
    await tester.pumpAndSettle();
    expect(answers, [false]);

    await tester.tap(find.text('next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip for this batch'));
    await tester.pumpAndSettle();
    expect(answers, [false, true]);

    // The rest of the batch goes straight through.
    await tester.tap(find.text('next'));
    await tester.pumpAndSettle();
    expect(find.text('1 flagged question'), findsNothing);
    expect(answers, [false, true, true]);
  });
}
