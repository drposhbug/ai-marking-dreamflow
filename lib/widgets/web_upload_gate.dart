import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:marking_prokect_v2/services/word_locator.dart';

/// Prepares a browser to send student work, and gets out of the way.
///
/// This used to open a dialog headed "Hiding names in a browser is weaker",
/// and that was the right thing to say while it was true. It no longer is.
/// A browser reads each page on the teacher's own machine, finds the printed
/// `Name:` line, and — since `InkExtent` — measures where the writing on that
/// line actually ends and paints over exactly that. The redaction is as tight
/// as a phone's. There is no longer a weakness to warn about, so warning
/// about one would be theatre, and a blocking dialog in front of every class
/// set is an expensive place to put theatre.
///
/// Two real differences survive, and neither is a reason to stop someone:
///
///  * A browser does not read the handwriting, so it never learns the name.
///    Marks are filed by the teacher rather than automatically. That is a
///    workflow fact, said where the filing happens, not here.
///  * A page with no printed `Name:` on it has nothing to find. That is
///    caught downstream by the redaction review, which shows every page
///    before any of them is sent — something a phone cannot offer.
///
/// What this still does is the part that was always doing real work: it
/// starts the several-megabyte reader downloading the moment a teacher heads
/// for an upload, minutes before they tap Mark.
///
/// Kept as a function, with every upload route still calling it, because the
/// warm-up has to happen on all of them and because a gate is the kind of
/// thing that comes back. Always returns true; callers need no change.
Future<bool> ensureWebUploadAcknowledged(
  BuildContext context, {
  required String? teacherId,
  bool onWeb = kIsWeb,
  VoidCallback? onUseForm,
}) async {
  if (!onWeb) return true;

  // Fire and forget. A failure is not an error to show — it lands as "no
  // name was hidden on this page", which the review then puts in front of
  // the teacher with a way to fix it.
  unawaited(WordLocator.warmUp());
  return true;
}
