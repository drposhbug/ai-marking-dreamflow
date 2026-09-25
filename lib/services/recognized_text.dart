import 'dart:ui' show Rect;

/// One word read off the page, with the rectangle it actually occupies (in
/// image pixels).
class RecognizedWord {
  final String text;
  final Rect rect;
  final int lineId;
  const RecognizedWord({required this.text, required this.rect, required this.lineId});
}

/// How much of a page the reader on this platform can actually read.
///
/// This is not a quality score. It changes what the app is allowed to
/// conclude from a reading, so it has to travel with the reading.
enum OcrTrust {
  /// On-device recognition that reads handwriting as well as print — ML Kit
  /// on iOS and Android. The words beside a "Name:" label are the student's
  /// name, and the box around them is where the name is.
  readsHandwriting,

  /// A reader that is reliable on printed text and is not reading the
  /// child's handwriting — Tesseract in a browser. It finds the printed
  /// "Name:" on a test template; what it makes of the writing beside it is
  /// a guess, so no name is reported from it.
  ///
  /// Where that writing *ends* is no longer a guess: `InkExtent` measures it
  /// off the pixels, which needs no reading. So a redaction here is as tight
  /// as one from a reader that sees handwriting. What is still missing is
  /// the name itself, which is why results from this reader cannot file
  /// themselves.
  printedLabelsOnly,
}

/// One word as an OCR engine reported it, before anything decides whether to
/// believe it.
///
/// Tesseract returns a guess for anything ink-shaped, with a confidence
/// attached. Acting on the low-confidence ones is how a "Name:" field gets
/// found in the wrong place while the real one stays on the page.
class OcrReading {
  final String text;

  /// In image pixels.
  final Rect rect;

  /// Words the engine grouped onto one line share this.
  final int lineId;

  /// 0–100, as the engine reports it.
  final double confidence;

  const OcrReading({
    required this.text,
    required this.rect,
    required this.lineId,
    required this.confidence,
  });
}

/// Below this, a reading is a shape the engine tried to name, not a word.
///
/// Printed labels on a school test template come back in the high 80s and
/// 90s; handwriting and paper noise come back well under this. Set low
/// enough that a faint photocopy still yields its "Name:", high enough that
/// a smudge does not become one.
const double kMinOcrConfidence = 55;

/// Keeps only the readings solid enough to act on.
///
/// Dropping a real word costs a redaction that does not happen, and the app
/// says so. Keeping a false one costs a black box in the wrong place and a
/// name left showing under a green tick. The second is the one to avoid.
List<RecognizedWord> believableWords(
  Iterable<OcrReading> readings, {
  double minConfidence = kMinOcrConfidence,
}) {
  final out = <RecognizedWord>[];
  for (final r in readings) {
    if (r.text.trim().isEmpty) continue;
    if (r.confidence < minConfidence) continue;
    // A zero-area box covers nothing, and would anchor a mark nowhere.
    if (r.rect.width <= 0 || r.rect.height <= 0) continue;
    out.add(RecognizedWord(text: r.text, rect: r.rect, lineId: r.lineId));
  }
  return out;
}
