import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

class WebPickedImage {
  final Uint8List bytes;
  final String name;
  const WebPickedImage({required this.bytes, required this.name});
}

Future<WebPickedImage?> pickWebImage({required bool captureEnvironmentCamera}) {
  final completer = Completer<WebPickedImage?>();

  try {
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..accept = 'image/*'
      ..multiple = false;

    // Mobile-web camera hint. Many browsers will show “Take Photo / Photo Library”.
    if (captureEnvironmentCamera) {
      input.setAttribute('capture', 'environment');
    }

    StreamSubscription<web.Event>? sub;
    sub = input.onChange.listen((_) async {
      await sub?.cancel();
      final file = input.files?.item(0);
      if (file == null) {
        if (!completer.isCompleted) completer.complete(null);
        return;
      }
      try {
        // Blob.arrayBuffer() is a promise of the whole file — no FileReader
        // callbacks, and one result type on every browser.
        final buffer = await file.arrayBuffer().toDart;
        if (!completer.isCompleted) {
          completer.complete(WebPickedImage(bytes: buffer.toDart.asUint8List(), name: file.name));
        }
      } catch (e) {
        if (!completer.isCompleted) completer.completeError(StateError('Failed to read file: $e'));
      }
    });

    // Must be triggered by a user gesture; caller should call from onTap.
    input.click();
  } catch (e) {
    if (!completer.isCompleted) completer.completeError(e);
  }

  return completer.future;
}
