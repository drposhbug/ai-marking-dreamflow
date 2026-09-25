import 'package:image/image.dart' as img;

/// Finds where the writing on a line actually stops.
///
/// This exists because of one gap. A phone's reader sees the child's
/// handwriting, so it knows the rectangle the name occupies and covers
/// exactly that. A browser's reader sees the printed `Name:` label and not
/// the handwriting beside it, so it has never known where the name ends —
/// and the only honest answer was to paint from the label to the paper's
/// edge, destroying whatever else sat on that line.
///
/// But finding where the ink ends is not a reading problem. It does not
/// matter what the name says; it matters which columns of pixels have marks
/// in them. That is ordinary image work, it needs no model and no download,
/// and it runs in a millisecond or two on the band of a single line.
///
/// So the browser keeps its weaker *reader* and stops needing a weaker
/// *redaction*: it covers the name and not the rest of the line.
///
/// What it deliberately does not do is guess the name. Knowing where ink is
/// is not knowing what it says, and a guessed name files a result under the
/// wrong child. Identity stays a separate question.
class InkExtent {
  /// A column counts as written-on once this many pixels in the band are
  /// darker than the paper. One dark pixel is dust or a speck of toner.
  static const int _minDarkPixels = 2;

  /// How far past the last mark to keep looking before calling it the end,
  /// as a fraction of page width. Wide enough to step over the gap between
  /// a first and last name; narrow enough not to walk into the `Date:`
  /// field that so often shares the line.
  static const double _gapFraction = 0.055;

  /// Ink found right at the edge of the search window means the line runs
  /// on past it, so the caller should fall back to covering everything.
  static const double _edgeTolerance = 0.02;

  /// The x where writing on this line stops, searching right from [fromX].
  ///
  /// Returns null when nothing conclusive was found — no ink at all, an
  /// unreadable band, or ink still going at the right-hand edge. Null means
  /// "keep doing the safe thing", which is covering the rest of the line.
  ///
  /// [top] and [bottom] bound the line in image pixels. [fromX] is normally
  /// the right edge of the printed label.
  static double? endOfWriting(
    img.Image image, {
    required double top,
    required double bottom,
    required double fromX,
  }) {
    final y0 = top.floor().clamp(0, image.height - 1);
    final y1 = bottom.ceil().clamp(0, image.height - 1);
    if (y1 <= y0) return null;

    final x0 = fromX.floor().clamp(0, image.width - 1);
    if (x0 >= image.width - 1) return null;

    final threshold = _paperThreshold(image, y0, y1);
    if (threshold == null) return null;

    final gap = (image.width * _gapFraction).round().clamp(8, 400);
    var lastInk = -1;
    var blankRun = 0;

    for (var x = x0; x < image.width; x++) {
      var dark = 0;
      for (var y = y0; y <= y1; y++) {
        if (_luminance(image, x, y) < threshold) {
          dark++;
          if (dark >= _minDarkPixels) break;
        }
      }
      if (dark >= _minDarkPixels) {
        lastInk = x;
        blankRun = 0;
      } else {
        blankRun++;
        // Only start counting the gap once something has been seen. A wide
        // blank between the label and where the child began writing is not
        // the end of anything.
        if (lastInk >= 0 && blankRun > gap) break;
      }
    }

    if (lastInk < 0) return null;

    // Still inky at the far edge: the line genuinely runs off the page, or
    // the band is a rule line. Either way this has learnt nothing useful.
    if (lastInk >= image.width - 1 - (image.width * _edgeTolerance)) return null;

    return lastInk.toDouble();
  }

  /// A darkness threshold for this band, from the paper it is printed on.
  ///
  /// Scanned paper is overwhelmingly background, so the bright end of the
  /// band is the paper itself whatever the exposure. Thresholding a fixed
  /// fraction below it adapts to a grey photocopy and a bright scan alike,
  /// which a fixed cutoff does not.
  ///
  /// Returns null for a band with no usable contrast — a black bar, or a
  /// blank strip — so the caller does not act on noise.
  static int? _paperThreshold(img.Image image, int y0, int y1) {
    // A sample rather than every pixel: enough for a histogram, cheap on a
    // 300dpi page.
    const targetSamples = 4000;
    final rows = y1 - y0 + 1;
    final step = ((image.width * rows) / targetSamples).round().clamp(1, 64);

    final histogram = List<int>.filled(256, 0);
    var count = 0;
    for (var y = y0; y <= y1; y++) {
      for (var x = 0; x < image.width; x += step) {
        histogram[_luminance(image, x, y)]++;
        count++;
      }
    }
    if (count == 0) return null;

    // The paper is the brightest bulk of the band, not the single brightest
    // pixel, which could be a scanner flare.
    final paper = _percentile(histogram, count, 0.90);
    final darkest = _percentile(histogram, count, 0.02);
    if (paper - darkest < 28) return null; // nothing but paper, or nothing but ink

    // Two-thirds of the way down from paper toward the darkest ink: past the
    // grey of a photocopy's background, short of faint pencil.
    return (paper - (paper - darkest) * 0.45).round().clamp(1, 254);
  }

  static int _percentile(List<int> histogram, int total, double p) {
    final target = (total * p).round().clamp(1, total);
    var seen = 0;
    for (var v = 0; v < histogram.length; v++) {
      seen += histogram[v];
      if (seen >= target) return v;
    }
    return 255;
  }

  static int _luminance(img.Image image, int x, int y) {
    final px = image.getPixel(x, y);
    // Rec. 601, the weighting scanners and cameras are built around.
    return (px.r * 0.299 + px.g * 0.587 + px.b * 0.114).round().clamp(0, 255);
  }
}
