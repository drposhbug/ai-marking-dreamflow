import 'dart:async';

import 'package:flutter/material.dart';

/// Runs [task] behind a modal progress dialog, and closes that dialog using
/// its own route rather than whatever happens to be on top.
///
/// Both halves of that matter. `barrierDismissible: false` stops a barrier
/// tap but NOT the Android back button, so a teacher pressing back during a
/// slow read used to dismiss the dialog — and the `Navigator.pop()` that ran
/// when the work finished then popped the screen underneath instead, blanking
/// the app or throwing her off the setup screen mid-flow. `PopScope` keeps
/// back from taking the dialog, and popping the captured context means the
/// close can only ever land on this dialog.
///
/// Rethrows whatever [task] threw, after closing — a failure must never leave
/// a teacher stuck behind a spinner she cannot dismiss.
Future<T> runWithBlockingProgress<T>(
  BuildContext context, {
  required String message,
  required Future<T> Function() task,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);

  // Held as a route rather than closed through the builder's context: a task
  // that finishes fast completes before the builder has ever run, leaving no
  // context to pop with and the dialog up for good.
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
            const SizedBox(width: 18),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    ),
  );
  unawaited(navigator.push(route));

  try {
    return await task();
  } finally {
    // removeRoute rather than pop: it works whether or not the dialog has
    // finished animating in, and can only ever remove this route.
    if (route.isActive) navigator.removeRoute(route);
  }
}
