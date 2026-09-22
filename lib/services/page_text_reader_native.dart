import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:marking_prokect_v2/services/recognized_text.dart';
import 'package:path_provider/path_provider.dart';

/// Page text recognition on iOS and Android: Google ML Kit, on the device,
/// with no network anywhere in it.
///
/// It reads handwriting as well as print, which is what lets the app read
/// the name beside "Name:" and know where that name ends.
class PageTextReader {
  /// ML Kit ships with the app on both mobile platforms.
  static bool get available => true;

  static OcrTrust get trust => OcrTrust.readsHandwriting;

  /// Nothing to fetch — the model is already here.
  static Future<void> warmUp() async {}

  /// Whether the reader is still fetching what it needs before it can read.
  /// Never true here; a browser has to download an engine first.
  static ValueListenable<bool> get preparing => _never;
  static final ValueNotifier<bool> _never = ValueNotifier<bool>(false);

  static Future<List<RecognizedWord>> read(Uint8List bytes) async {
    TextRecognizer? recognizer;
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/ocr_${identityHashCode(bytes)}.jpg');
      await file.writeAsBytes(bytes, flush: true);
      recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final result = await recognizer.processImage(InputImage.fromFilePath(file.path));
      final words = <RecognizedWord>[];
      var lineId = 0;
      for (final block in result.blocks) {
        for (final line in block.lines) {
          for (final el in line.elements) {
            words.add(RecognizedWord(text: el.text, rect: el.boundingBox, lineId: lineId));
          }
          lineId++;
        }
      }
      return words;
    } catch (e) {
      debugPrint('PageTextReader.read failed: $e');
      return const [];
    } finally {
      await recognizer?.close();
    }
  }
}
