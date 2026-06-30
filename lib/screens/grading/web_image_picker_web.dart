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
        final result = reader.result;
        if (result is ByteBuffer) {
          completer.complete(WebPickedImage(bytes: Uint8List.view(result), name: file.name));
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
