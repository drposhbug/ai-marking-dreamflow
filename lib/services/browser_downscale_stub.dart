import 'dart:typed_data';

/// Phones decode photos in a background isolate already; nothing to do.
Future<Uint8List?> browserDownscale(Uint8List bytes, {int maxSide = 1600}) async => null;
