import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marking_prokect_v2/services/anonymizer.dart';
import 'package:marking_prokect_v2/widgets/web_upload_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pumps a bare app and runs the gate from a button press, returning whatever
/// the gate decided. Every path a teacher can take out of the dialog is a
/// different answer to "does this page go up with the name still on it".
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

  group('gating a browser upload of student work', () {
    testWidgets('off the web the teacher is never interrupted', (tester) async {
      final decision = await _runGate(tester, teacherId: 'teacher-1', onWeb: false);
      expect(find.byType(AlertDialog), findsNothing);
      expect(decision, isTrue);
    });

    testWidgets('the first browser upload has to be acknowledged', (tester) async {
      await _runGate(tester, teacherId: 'teacher-1', onWeb: true);
      expect(find.byType(AlertDialog), findsOneWidget);
      // The browser hides names now, so the old "it cannot happen here" is
      // gone. What replaces it is the limit that is still true.
      expect(find.textContaining('weaker'), findsWidgets);
      expect(find.textContaining('can\'t be hidden in a browser'), findsNothing);
    });

    testWidgets('a teacher told the old, now-untrue thing is told the new one', (tester) async {
      // They were told names go up uncovered in a browser and agreed to
      // that. That is no longer what happens, and the thing they agreed to
      // is not the thing they should be agreeing to.
      SharedPreferences.setMockInitialValues({'ai_marker.web_upload_ack.v1.teacher-1': '1'});
      expect(await const WebUploadNotice().acknowledged('teacher-1'), isFalse);
      await _runGate(tester, teacherId: 'teacher-1', onWeb: true);
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('backing out does not upload and does not count as acknowledged', (tester) async {
      bool? decision;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                decision = await ensureWebUploadAcknowledged(context, teacherId: 'teacher-1', onWeb: true);
              },
              child: const Text('pick'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('pick'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(decision, isFalse);
      expect(await const WebUploadNotice().acknowledged('teacher-1'), isFalse);
    });

    testWidgets('choosing the Form route does not upload the photo', (tester) async {
      var wentToForm = false;
      bool? decision;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                decision = await ensureWebUploadAcknowledged(
                  context,
                  teacherId: 'teacher-1',
                  onWeb: true,
                  onUseForm: () => wentToForm = true,
                );
              },
              child: const Text('pick'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('pick'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use a Google Form'));
      await tester.pumpAndSettle();

      expect(wentToForm, isTrue);
      expect(decision, isFalse);
    });

    testWidgets('accepting uploads, and is remembered so it asks only once', (tester) async {
      bool? decision;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                decision = await ensureWebUploadAcknowledged(context, teacherId: 'teacher-1', onWeb: true);
              },
              child: const Text('pick'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('pick'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Got it — upload'));
      await tester.pumpAndSettle();

      expect(decision, isTrue);
      expect(await const WebUploadNotice().acknowledged('teacher-1'), isTrue);

      // Second upload: straight through, no dialog.
      final again = await _runGate(tester, teacherId: 'teacher-1', onWeb: true);
      expect(find.byType(AlertDialog), findsNothing);
      expect(again, isTrue);
    });

    testWidgets('a teacher who accepted does not answer for the next one on a shared machine', (tester) async {
      await const WebUploadNotice().acknowledge('teacher-1');
      await _runGate(tester, teacherId: 'teacher-2', onWeb: true);
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('a signed-out session is not blocked by a gate it cannot key', (tester) async {
      final decision = await _runGate(tester, teacherId: null, onWeb: true);
      expect(find.byType(AlertDialog), findsNothing);
      expect(decision, isTrue);
    });
  });
}
