import 'dart:async';

// The same conditional-import shape web_image_picker_web.dart beside it
// already uses: this file only ever compiles for the browser, and a second
// style here would be one more thing to keep in step for no gain.
import 'dart:js_interop';

import 'package:web/web.dart' as web;

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

  bool carriesFiles(web.DataTransfer? dt) {
    if (dt == null) return false;
    // Dragging selected text or a link across the window must not put the
    // page into "drop your scans here" — it promises something that would
    // not work.
    return dt.types.toDart.any((t) => t.toDart == 'Files');
  }

  final subs = <StreamSubscription<web.Event>>[];

  subs.add(web.EventStreamProviders.dragEnterEvent.forTarget(web.document).listen((e) {
    if (!carriesFiles((e as web.DragEvent).dataTransfer)) return;
    e.preventDefault();
    depth++;
    if (depth == 1) onHover(true);
  }));

  subs.add(web.EventStreamProviders.dragOverEvent.forTarget(web.document).listen((e) {
    if (!carriesFiles((e as web.DragEvent).dataTransfer)) return;
    // Without this the browser refuses the drop and then navigates away to
    // the dropped file, losing whatever the teacher was in the middle of.
    e.preventDefault();
    e.dataTransfer?.dropEffect = 'copy';
  }));

  subs.add(web.EventStreamProviders.dragLeaveEvent.forTarget(web.document).listen((e) {
    if (depth == 0) return;
    depth--;
    if (depth == 0) onHover(false);
  }));

  subs.add(web.EventStreamProviders.dropEvent.forTarget(web.document).listen((e) {
    e.preventDefault();
    setHover(false);
    final files = _listOf((e as web.DragEvent).dataTransfer?.files);
    if (files.isEmpty) return;
    unawaited(_readAll(files, pasted: false).then((read) {
      if (read.isNotEmpty) onDropped(read);
    }));
  }));

  // The drag can also end outside the window entirely (escape, or dropped on
  // the desktop), which fires neither leave nor drop reliably.
  subs.add(web.EventStreamProviders.dragEndEvent.forTarget(web.window).listen((_) => setHover(false)));
  subs.add(web.EventStreamProviders.blurEvent.forTarget(web.window).listen((_) => setHover(false)));

  void onPaste(web.Event event) {
    final data = (event as web.ClipboardEvent).clipboardData;
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
  // and a paste aimed at the page can land there first. One JS function, so
  // the same one can be removed again.
  final pasteListener = onPaste.toJS;
  web.window.addEventListener('paste', pasteListener, true.toJS);

  return BrowserIntake._([
    for (final s in subs) s.cancel,
    () => web.window.removeEventListener('paste', pasteListener, true.toJS),
  ]);
}

List<web.File> _listOf(web.FileList? list) => [
      for (var i = 0; i < (list?.length ?? 0); i++)
        if (list!.item(i) case final web.File f) f,
    ];

/// A pasted image sometimes arrives as a file and sometimes only as a
/// clipboard item, depending on the browser and on where it was copied from.
List<web.File> _clipboardFiles(web.DataTransfer data) {
  final direct = _listOf(data.files);
  if (direct.isNotEmpty) return direct;
  final items = data.items;
  final out = <web.File>[];
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    if (item.kind != 'file') continue;
    final file = item.getAsFile();
    if (file != null) out.add(file);
  }
  return out;
}

Future<List<DroppedFile>> _readAll(List<web.File> files, {required bool pasted}) async {
  final out = <DroppedFile>[];
  for (final file in files) {
    final read = await _readOne(file, pasted: pasted);
    // One unreadable file must not cost the teacher the other twenty-nine —
    // the same promise the rest of the pipeline makes.
    if (read != null) out.add(read);
  }
  return out;
}

Future<DroppedFile?> _readOne(web.File file, {required bool pasted}) async {
  try {
    // Blob.arrayBuffer() is a promise of the whole file: one result type in
    // every browser, where FileReader's differed between Dart web SDKs and
    // made dropped or pasted scans vanish without a word.
    final bytes = (await file.arrayBuffer().toDart).toDart.asUint8List();
    // Every browser calls a pasted screenshot "image.png"; named for the
    // moment it arrived, it can be told apart in a list of marks.
    final name = pasted ? pastedFileName(file.type, DateTime.now()) : file.name;
    return DroppedFile(name: name, mime: file.type, bytes: bytes);
  } catch (e) {
    debugPrint('Could not read dropped file "${file.name}": $e');
    return null;
  }
}
