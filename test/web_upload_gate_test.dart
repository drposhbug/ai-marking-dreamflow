import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marking_prokect_v2/widgets/web_upload_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pumps a bare app and runs the gate from a button press, returning whatever
/// the gate decided.
Future<bool?> _runGate(
  WidgetTester tester, {
  required String? teacherId,
  required bool onWeb,
  VoidCallback? onUseForm,
}) async {
  bool? decision;
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: ElevatedButton(
          onPressed: () async {
            decision = await ensureWebUploadAcknowledged(
              context,
              teacherId: teacherId,
              onWeb: onWeb,
              onUseForm: onUseForm,
            );
          },
          child: const Text('pick'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('pick'));
  await tester.pumpAndSettle();
  return decision;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('starting a browser upload of student work', () {
    // The gate used to open a dialog headed "Hiding names in a browser is
    // weaker". It does not any more, because that stopped being true: a
    // browser now measures where the writing on the Name line ends and
    // covers exactly that, as tightly as a phone does. These tests exist to
    // keep the interruption from creeping back without the weakness.

    testWidgets('a browser upload is not interrupted', (tester) async {
      final decision = await _runGate(tester, teacherId: 'teacher-1', onWeb: true);

      expect(find.byType(AlertDialog), findsNothing);
      expect(decision, isTrue);
    });

    testWidgets('the second and third uploads are not interrupted either', (tester) async {
      for (var i = 0; i < 3; i++) {
        final decision = await _runGate(tester, teacherId: 'teacher-1', onWeb: true);
        expect(find.byType(AlertDialog), findsNothing);
        expect(decision, isTrue);
      }
    });

    testWidgets('off the web nothing happens either', (tester) async {
      final decision = await _runGate(tester, teacherId: 'teacher-1', onWeb: false);

      expect(find.byType(AlertDialog), findsNothing);
      expect(decision, isTrue);
    });

    testWidgets('a signed-out teacher is let through rather than stranded', (tester) async {
      final decision = await _runGate(tester, teacherId: null, onWeb: true);

      expect(find.byType(AlertDialog), findsNothing);
      expect(decision, isTrue);
    });

    testWidgets('nothing is diverted to a Google Form behind the teacher\'s back', (tester) async {
      var divertedToForm = false;
      final decision = await _runGate(
        tester,
        teacherId: 'teacher-1',
        onWeb: true,
        onUseForm: () => divertedToForm = true,
      );

      expect(decision, isTrue);
      expect(divertedToForm, isFalse);
    });
  });
}
