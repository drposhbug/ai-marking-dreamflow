import 'dart:async';
import 'dart:typed_data';

// The same conditional-import shape web_image_picker_web.dart beside it
// already uses: this file only ever compiles for the browser, and a second
// style here would be one more thing to keep in step for no gain.
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:marking_prokect_v2/services/dropped_intake.dart';

/// Drag-and-drop and paste, on the browser side.
///
/// On a desktop a teacher with a folder of scans expects to drag them onto
/// the page, and a teacher looking at a submission in a marking portal
/// expects to screenshot it and press Ctrl-V. Neither existed, so every page
/// meant a trip through a file dialog. The listeners sit on the document so
/// the whole window is the target — a teacher aiming at a small rectangle
/// and missing would just watch the browser open her student's JPEG.
class BrowserIntake {
  final List<void Function()> _stop;
  BrowserIntake._(this._stop);

  void dispose() {
    for (final off in _stop) {
      off();
    }
    _stop.clear();
  }
}

BrowserIntake? startBrowserIntake({
  required void Function(bool hovering) onHover,
  required void Function(List<DroppedFile> files) onDropped,
  required void Function(List<DroppedFile> files) onPasted,
}) {
  // Drag enter and leave also fire as the pointer crosses every element
  // inside the page, so a plain on/off flickers the whole way across. Depth
  // counting is what keeps the drop target steady.
  var depth = 0;

  void setHover(bool hovering) {
    if (!hovering) depth = 0;
    onHover(hovering);
  }

  bool carriesFiles(html.DataTransfer? dt) {
    final types = dt?.types;
    if (types == null) return false;
    // Dragging selected text or a link across the window must not put the
    // page into "drop your scans here" — it promises something that would
    // not work.
    return types.contains('Files');
  }

  final subs = <StreamSubscription<html.Event>>[];

  subs.add(html.document.onDragEnter.listen((e) {
    if (!carriesFiles(e.dataTransfer)) return;
    e.preventDefault();
    depth++;
    if (depth == 1) onHover(true);
  }));

  subs.add(html.document.onDragOver.listen((e) {
    if (!carriesFiles(e.dataTransfer)) return;
    // Without this the browser refuses the drop and then navigates away to
    // the dropped file, losing whatever the teacher was in the middle of.
    e.preventDefault();
    e.dataTransfer.dropEffect = 'copy';
  }));

  subs.add(html.document.onDragLeave.listen((e) {
    if (depth == 0) return;
    depth--;
    if (depth == 0) onHover(false);
  }));

  subs.add(html.document.onDrop.listen((e) {
    e.preventDefault();
    setHover(false);
    final files = e.dataTransfer.files;
    if (files == null || files.isEmpty) return;
    unawaited(_readAll(files, pasted: false).then((read) {
      if (read.isNotEmpty) onDropped(read);
    }));
  }));

  // The drag can also end outside the window entirely (escape, or dropped on
  // the desktop), which fires neither leave nor drop reliably.
  subs.add(html.window.onDragEnd.listen((_) => setHover(false)));
  subs.add(html.window.onBlur.listen((_) => setHover(false)));

  void onPaste(html.Event event) {
    final data = event is html.ClipboardEvent ? event.clipboardData : null;
    if (data == null) return;
    final files = _clipboardFiles(data);
    // Pasting text — a student's name into the search box — must fall
    // through to the field that has focus, untouched.
    if (files.isEmpty) return;
    event.preventDefault();
    unawaited(_readAll(files, pasted: true).then((read) {
      if (read.isNotEmpty) onPasted(read);
    }));
  }

  // Capture phase: Flutter puts a hidden input under the focused text field
  // and a paste aimed at the page can land there first.
  html.window.addEventListener('paste', onPaste, true);

  return BrowserIntake._([
    for (final s in subs) s.cancel,
    () => html.window.removeEventListener('paste', onPaste, true),
  ]);
}

/// A pasted image sometimes arrives as a file and sometimes only as a
/// clipboard item, depending on the browser and on where it was copied from.
List<html.File> _clipboardFiles(html.DataTransfer data) {
  final direct = data.files;
  if (direct != null && direct.isNotEmpty) return direct;
  final items = data.items;
  final count = items?.length ?? 0;
  if (items == null || count == 0) return const [];
  final out = <html.File>[];
  for (var i = 0; i < count; i++) {
    final item = items[i];
    if (item.kind != 'file') continue;
    final file = item.getAsFile();
    if (file != null) out.add(file);
  }
  return out;
}

Future<List<DroppedFile>> _readAll(List<html.File> files, {required bool pasted}) async {
  final out = <DroppedFile>[];
  for (final file in files) {
    final read = await _readOne(file, pasted: pasted);
    // One unreadable file must not cost the teacher the other twenty-nine —
    // the same promise the rest of the pipeline makes.
    if (read != null) out.add(read);
  }
  return out;
}

Future<DroppedFile?> _readOne(html.File file, {required bool pasted}) {
  final done = Completer<DroppedFile?>();
  final reader = html.FileReader();
  final mime = file.type;

  void finish(DroppedFile? value) {
    if (!done.isCompleted) done.complete(value);
  }

  reader.onError.listen((_) {
    debugPrint('Could not read dropped file "${file.name}"');
    finish(null);
  });
  reader.onLoadEnd.listen((_) {
    // readAsArrayBuffer hands back a ByteBuffer on some Dart web SDKs and an
    // already-wrapped Uint8List on others. Insisting on one of them made
    // every dropped or pasted scan vanish without a word.
    final result = reader.result;
    final bytes = switch (result) {
      final ByteBuffer b => Uint8List.view(b),
      final Uint8List b => b,
      final List<int> b => Uint8List.fromList(b),
      _ => null,
    };
    if (bytes == null) {
      debugPrint('Unexpected FileReader result type: ${result.runtimeType}');
      finish(null);
      return;
    }
    // Every browser calls a pasted screenshot "image.png"; named for the
    // moment it arrived, it can be told apart in a list of marks.
    final name = pasted ? pastedFileName(mime, DateTime.now()) : file.name;
    finish(DroppedFile(name: name, mime: mime, bytes: bytes));
  });

  try {
    reader.readAsArrayBuffer(file);
  } catch (e) {
    debugPrint('Could not read dropped file "${file.name}": $e');
    finish(null);
  }
  return done.future;
}
