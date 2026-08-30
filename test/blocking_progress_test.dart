import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marking_prokect_v2/widgets/blocking_progress.dart';

/// Pumps a screen with a button that runs [task] behind the progress dialog.
/// The button sits on a second route so a stray pop would be visible: if the
/// helper pops the wrong thing, 'home' comes back.
Future<void> _pumpRunner(WidgetTester tester, Future<String> Function() task, {String message = 'Reading…'}) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (home) => Scaffold(
        body: ElevatedButton(
          onPressed: () => Navigator.of(home).push(MaterialPageRoute(
            builder: (_) => Builder(
              builder: (inner) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => runWithBlockingProgress<String>(inner, message: message, task: task),
                  child: const Text('go'),
                ),
              ),
            ),
          )),
          child: const Text('home'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('home'));
  await tester.pumpAndSettle();
}

void main() {
  group('a progress dialog the teacher cannot be thrown out of', () {
    testWidgets('shows the message while the work runs, and clears it after', (tester) async {
      final gate = Completer<String>();
      await _pumpRunner(tester, () => gate.future);

      await tester.tap(find.text('go'));
      await tester.pump();
      expect(find.text('Reading…'), findsOneWidget);

      gate.complete('done');
      await tester.pumpAndSettle();
      expect(find.text('Reading…'), findsNothing);
      // Still on the working screen, not thrown back to home.
      expect(find.text('go'), findsOneWidget);
    });

    testWidgets('hands back what the work returned', (tester) async {
      String? got;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                got = await runWithBlockingProgress<String>(
                  context,
                  message: 'Reading…',
                  task: () async => 'the key',
                );
              },
              child: const Text('go'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(got, 'the key');
    });

    testWidgets('the back button cannot dismiss it mid-run', (tester) async {
      final gate = Completer<String>();
      await _pumpRunner(tester, () => gate.future);
      await tester.tap(find.text('go'));
      await tester.pump();

      // A teacher pressing back because "it is taking ages". Pumped by hand
      // rather than settled: the spinner animates forever, so pumpAndSettle
      // can never return while the dialog is up.
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // The dialog is still up, and crucially the screen underneath survived.
      expect(find.text('Reading…'), findsOneWidget);
      expect(find.text('go'), findsOneWidget);

      gate.complete('done');
      await tester.pumpAndSettle();
      expect(find.text('Reading…'), findsNothing);
      expect(find.text('go'), findsOneWidget);
    });

    testWidgets('a failure closes the dialog and rethrows rather than trapping the teacher', (tester) async {
      Object? caught;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                try {
                  await runWithBlockingProgress<String>(
                    context,
                    message: 'Reading…',
                    task: () async => throw StateError('no network'),
                  );
                } catch (e) {
                  caught = e;
                }
              },
              child: const Text('go'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(caught, isA<StateError>());
      expect(find.text('Reading…'), findsNothing);
      expect(find.text('go'), findsOneWidget);
    });
  });
}
