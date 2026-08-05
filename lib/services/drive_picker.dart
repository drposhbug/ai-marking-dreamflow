import 'dart:typed_data';

import 'package:flutter/services.dart';

/// The Google Drive app isn't installed (or can't handle the pick intent) —
/// callers fall back to the generic system file picker.
class DrivePickerUnavailable implements Exception {}

class PickedDriveFile {
  final String name;
  final Uint8List bytes;
  const PickedDriveFile({required this.name, required this.bytes});
}

/// Opens the Google Drive app's OWN picker (via a native intent targeted at
/// the Drive package) so "From Drive" lands the teacher directly in their
/// Drive instead of the system Files UI. Multi-select supported.
class DrivePicker {
  static const _channel = MethodChannel('markless/drive_picker');

  static Future<List<PickedDriveFile>> pickImages() async {
    try {
      final res = await _channel.invokeMethod<List<dynamic>>('pickFromDrive');
      return (res ?? const [])
          .whereType<Map>()
          .map((m) => PickedDriveFile(
                name: (m['name'] ?? 'drive_image.jpg').toString(),
                bytes: m['bytes'] as Uint8List,
              ))
          .toList(growable: false);
    } on PlatformException catch (e) {
      if (e.code == 'no_drive' || e.code == 'busy') throw DrivePickerUnavailable();
      rethrow;
    } on MissingPluginException {
      throw DrivePickerUnavailable();
    }
  }
}
