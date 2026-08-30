import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:marking_prokect_v2/services/anonymizer.dart';

/// Tells a teacher, once, that a page they upload in a browser goes up with
/// the student's name still on it.
///
/// On a phone the name is read on the device and blacked out first. That needs
/// on-device text recognition, which a browser does not have, so the honest
/// moment is before the upload rather than after it. Every route that can send
/// student work from a browser has to come through here — a gate on one screen
/// and not the next is the same as no gate.
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
      title: const Text('Names can\'t be hidden in a browser'),
      content: SingleChildScrollView(
        child: Text(
          'On a phone or tablet, Markless reads the name off each page here on the device and blacks it out before the page is sent for marking. That needs on-device text recognition, and a browser does not have it.\n\n'
          'A page you upload here is sent exactly as you picked it — name and all. Cover the name first, or mark from a Google Form or CSV instead: that route sends answers keyed by row number and never sends the name column.',
          style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(height: 1.45),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, 'form'), child: const Text('Use a Google Form')),
        FilledButton(onPressed: () => Navigator.pop(ctx, 'ok'), child: const Text('I\'ll cover names myself')),
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
