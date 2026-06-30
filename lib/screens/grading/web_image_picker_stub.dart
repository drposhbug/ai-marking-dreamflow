import 'dart:typed_data';

/// Web-only image picker based on `<input type="file">`.
///
/// This stub is used for non-web builds.
class WebPickedImage {
  final Uint8List bytes;
  final String name;
  const WebPickedImage({required this.bytes, required this.name});
}

Future<WebPickedImage?> pickWebImage({required bool captureEnvironmentCamera}) async => throw UnsupportedError('pickWebImage is only supported on web.');
