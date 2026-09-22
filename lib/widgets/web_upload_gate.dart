import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:marking_prokect_v2/services/anonymizer.dart';
import 'package:marking_prokect_v2/services/word_locator.dart';

/// Tells a teacher, once, what hiding names in a browser actually does.
///
/// It used to say it did nothing, because it did. A browser now reads each
/// page on the teacher's own machine, finds the printed `Name:` line and
/// blacks that line out before anything is sent. What is left to say is the
/// part that is still true and still matters: browser reading is weaker than
/// a phone's, it works off the printed label rather than the handwriting,
/// and on a page where it finds no label nothing is covered.
///
/// Every route that can send student work from a browser comes through here —
/// a gate on one screen and not the next is the same as no gate — which also
/// makes this the right place to start the engine downloading, minutes before
/// the teacher taps Mark.
///
/// Remembered per teacher: it is a fact worth one dialog, not one every time
/// they mark a class set. Returns false when they back out, so the caller
/// abandons the upload.
Future<bool> ensureWebUploadAcknowledged(
  BuildContext context, {
  required String? teacherId,
  bool onWeb = kIsWeb,
  WebUploadNotice notice = const WebUploadNotice(),
  VoidCallback? onUseForm,
}) async {
  if (!onWeb) return true;

  // Fire and forget, on every browser upload and not only the first: the
  // reader is a several-megabyte download the first time, and starting it
  // here means it is usually finished before the page is ready to send.
  // A failure is not an error to show — it lands as "no name was hidden on
  // this page", which the app already says out loud.
  unawaited(WordLocator.warmUp());

  // Signed out there is nothing to key the acknowledgement to, and blocking
  // would strand the teacher rather than protect anyone.
  if (teacherId == null) return true;

  final already = await notice.acknowledged(teacherId);
  if (!WebUploadNotice.needed(onWeb: onWeb, alreadyAcknowledged: already)) return true;
  if (!context.mounted) return false;

  final choice = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Hiding names in a browser is weaker'),
      // Short on purpose. This is read once, by someone holding a stack of
      // papers who wants to get on with it, and a teacher who skims three
      // paragraphs has been told nothing. What survives is the only part
      // that changes what she would do: a page with no printed label goes up
      // with the name on it. The rest — that redaction is local, that a Form
      // avoids the question — is in Settings and on the button beside this.
      content: SingleChildScrollView(
        child: Text(
          'Markless blacks out the "Name:" line on your own machine before a page is sent, here and on a phone.\n\n'
          'A browser reads the printed label rather than the handwriting, so it covers the whole line. If a page has no printed "Name:" on it, nothing is covered — Markless says so on the page, so you can cover it yourself.',
          style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(height: 1.45),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, 'form'), child: const Text('Use a Google Form')),
        FilledButton(onPressed: () => Navigator.pop(ctx, 'ok'), child: const Text('Got it — upload')),
      ],
    ),
  );

  if (choice == 'form') {
    onUseForm?.call();
    return false;
  }
  if (choice != 'ok') return false;
  // Only a deliberate "I know" is remembered. Backing out must leave the
  // teacher to be asked again next time.
  await notice.acknowledge(teacherId);
  return true;
}
