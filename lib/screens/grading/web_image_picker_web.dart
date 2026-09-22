import 'dart:async';
import 'dart:typed_data';

import 'dart:html' as html;

class WebPickedImage {
  final Uint8List bytes;
  final String name;
  const WebPickedImage({required this.bytes, required this.name});
}

Future<WebPickedImage?> pickWebImage({required bool captureEnvironmentCamera}) {
  final completer = Completer<WebPickedImage?>();

  try {
    final input = html.FileUploadInputElement();
    input.accept = 'image/*';

    // Mobile-web camera hint. Many browsers will show “Take Photo / Photo Library”.
    if (captureEnvironmentCamera) {
      input.setAttribute('capture', 'environment');
    }

    input.multiple = false;

    StreamSubscription<html.Event>? sub;
    sub = input.onChange.listen((_) async {
      sub?.cancel();
      final files = input.files;
      if (files == null || files.isEmpty) {
        if (!completer.isCompleted) completer.complete(null);
        return;
      }

      final file = files.first;
      final reader = html.FileReader();

      reader.onError.listen((_) {
        if (!completer.isCompleted) completer.completeError(StateError('Failed to read file.'));
      });

      reader.onLoadEnd.listen((_) {
        if (completer.isCompleted) return;
        // readAsArrayBuffer hands back a ByteBuffer on some Dart web SDKs and
        // an already-wrapped Uint8List on others. Insisting on one of them
        // meant every gallery pick in a browser failed with "Unexpected
        // FileReader result type" — take whichever arrives.
        final result = reader.result;
        final bytes = switch (result) {
          final ByteBuffer b => Uint8List.view(b),
          final Uint8List b => b,
          final List<int> b => Uint8List.fromList(b),
          _ => null,
        };
        if (bytes != null) {
          completer.complete(WebPickedImage(bytes: bytes, name: file.name));
        } else {
          completer.completeError(StateError('Unexpected FileReader result type: ${result.runtimeType}'));
        }
      });

      reader.readAsArrayBuffer(file);
    });

    // Must be triggered by a user gesture; caller should call from onTap.
    input.click();
  } catch (e) {
    if (!completer.isCompleted) completer.completeError(e);
  }

  return completer.future;
}
