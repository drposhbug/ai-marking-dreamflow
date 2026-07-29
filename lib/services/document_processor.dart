import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// A processed capture plus the verdict on whether it actually shows a page.
class ProcessedPage {
  final Uint8List bytes;

  /// False when the photo doesn't look like a document at all (desk, floor,
  /// lap...) — the scanner uses this to refuse to save junk auto-captures.
  final bool isDocument;

  const ProcessedPage(this.bytes, this.isDocument);
}

/// Post-processes captured document photos like a document scanner:
/// straightens pages shot at an angle (perspective correction), stretches
/// contrast so paper reads white and ink reads dark, and sharpens the text.
class DocumentProcessor {
  /// Runs in a background isolate; falls back to the original bytes if
  /// anything about the photo defeats the processing.
  static Future<Uint8List> processPage(Uint8List jpegBytes) async =>
      (await processPageDetailed(jpegBytes)).bytes;

  /// Like [processPage] but also reports whether the photo looks like an
  /// actual document. Fails open (isDocument = true) so a processing crash
  /// never blocks a legitimate scan.
  static Future<ProcessedPage> processPageDetailed(Uint8List jpegBytes) async {
    try {
      final (bytes, isDoc) = await compute(processPageSync, jpegBytes);
      return ProcessedPage(bytes, isDoc);
    } catch (e) {
      debugPrint('DocumentProcessor failed: $e');
      return ProcessedPage(jpegBytes, true);
    }
  }
}

@visibleForTesting
(Uint8List, bool) processPageSync(Uint8List jpegBytes) {
  var image = img.decodeImage(jpegBytes);
  if (image == null) return (jpegBytes, false);

  // Respect the EXIF orientation flag — gallery photos shot sideways come
  // in rotated on disk and would otherwise stay sideways.
  image = img.bakeOrientation(image);

  final corners = _findPageCorners(image);
  final isDocument = corners != null || _looksLikeDocument(image);

  if (corners != null) {
    image = img.copyRectify(
      image,
      topLeft: corners[0],
      topRight: corners[1],
      bottomRight: corners[2],
      bottomLeft: corners[3],
      interpolation: img.Interpolation.linear,
    );
  }

  // Page photographed sideways (text lines running vertically) → rotate
  // upright so the teacher and the marker both read it normally.
  image = _autoRotateForText(image);

  // Perspective correction rarely lands perfectly square — measure the
  // residual tilt of the text lines and take out the last few degrees.
  image = _deskewSmallAngle(image);

  _stretchContrast(image);
  image = _sharpen(image);
  return (Uint8List.fromList(img.encodeJpg(image, quality: 88)), isDocument);
}

/// Detects sideways text by comparing the line structure of the ink: text
/// forms distinct horizontal streaks, so ink-per-row varies strongly when
/// upright and ink-per-column varies strongly when sideways.
img.Image _autoRotateForText(img.Image src) {
  try {
    // Only landscape shots are candidates: worksheets are portrait, so a
    // portrait image is already upright — rotating one to horizontal (a
    // misfire this heuristic used to make) is never an improvement.
    if (src.width <= src.height) return src;
    final small = img.copyResize(src, width: 160);
    final w = small.width, h = small.height;
    final rowInk = List<int>.filled(h, 0);
    final colInk = List<int>.filled(w, 0);
    var total = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = small.getPixel(x, y);
        final l = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
        if (l < 110) {
          rowInk[y]++;
          colInk[x]++;
          total++;
        }
      }
    }
    if (total < w * h * 0.005) return src; // not enough ink to judge

    double variance(List<int> v) {
      final mean = v.reduce((a, b) => a + b) / v.length;
      var s = 0.0;
      for (final x in v) {
        s += (x - mean) * (x - mean);
      }
      return s / v.length;
    }

    // Normalize each profile by its perpendicular axis length so the
    // comparison is fair for non-square images.
    final vRows = variance(rowInk) / (w * w);
    final vCols = variance(colInk) / (h * h);
    if (vCols > vRows * 1.4) {
      return img.copyRotate(src, angle: -90);
    }
    return src;
  } catch (e) {
    debugPrint('DocumentProcessor auto-rotate failed: $e');
    return src;
  }
}

/// Removes the last few degrees of tilt left after perspective correction.
/// Tries small rotations on a thumbnail and keeps the one whose ink rows
/// are most sharply separated (upright text = strong row-profile variance),
/// then applies it to the full image and crops away the rotation border.
img.Image _deskewSmallAngle(img.Image src) {
  try {
    final small = img.copyResize(src, width: 240);

    // Score only the central region so the black corners introduced by
    // trial rotations never count as ink.
    double rowVariance(img.Image im) {
      final x0 = (im.width * 0.15).round(), x1 = (im.width * 0.85).round();
      final y0 = (im.height * 0.15).round(), y1 = (im.height * 0.85).round();
      final rows = y1 - y0;
      if (rows <= 0 || x1 <= x0) return -1;
      final rowInk = List<int>.filled(rows, 0);
      var total = 0;
      for (var y = y0; y < y1; y++) {
        for (var x = x0; x < x1; x++) {
          final p = im.getPixel(x, y);
          final l = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
          if (l < 110) {
            rowInk[y - y0]++;
            total++;
          }
        }
      }
      if (total < (x1 - x0) * rows * 0.004) return -1; // not enough ink
      final mean = rowInk.reduce((a, b) => a + b) / rows;
      var s = 0.0;
      for (final v in rowInk) {
        s += (v - mean) * (v - mean);
      }
      return s / rows;
    }

    final base = rowVariance(small);
    if (base < 0) return src;
    var bestAngle = 0.0;
    var bestScore = base;
    for (var a = -6.0; a <= 6.01; a += 0.5) {
      if (a == 0) continue;
      final rot = img.copyRotate(small, angle: a, interpolation: img.Interpolation.linear);
      final score = rowVariance(rot);
      if (score > bestScore) {
        bestScore = score;
        bestAngle = a;
      }
    }
    if (bestAngle == 0 || bestScore < base * 1.04) return src;

    // Pad with white margin BEFORE rotating so the rotation wedges land in
    // padding, never on page content — straightening must not cut off edge
    // text (it used to crop the page to hide the wedges).
    final s = math.sin(bestAngle.abs() * math.pi / 180);
    final padX = (src.height * s).ceil() + 8;
    final padY = (src.width * s).ceil() + 8;
    final padded = img.Image(width: src.width + padX * 2, height: src.height + padY * 2);
    img.fill(padded, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(padded, src, dstX: padX, dstY: padY);
    var out = img.copyRotate(padded, angle: bestAngle, interpolation: img.Interpolation.cubic);
    // Rotation grows the canvas — crop the center back to the page size.
    if (out.width >= src.width && out.height >= src.height) {
      out = img.copyCrop(
        out,
        x: (out.width - src.width) ~/ 2,
        y: (out.height - src.height) ~/ 2,
        width: src.width,
        height: src.height,
      );
    }
    return out;
  } catch (e) {
    debugPrint('DocumentProcessor deskew failed: $e');
    return src;
  }
}

/// Full-photo sanity check: a real page is a large, near-WHITE (not just
/// bright — also color-neutral) region carrying genuine ink transitions.
/// A wooden desk is bright but warm-toned; bare floors and fabric have no
/// ink-like edges. Checked on a downscaled copy for speed.
bool _looksLikeDocument(img.Image src) {
  final small = img.copyResize(src, width: 200);
  var n = 0, bright = 0, brightSamples = 0, inkEdges = 0;
  double chroma = 0;
  for (var y = 0; y < small.height; y++) {
    var prev = -1;
    for (var x = 0; x < small.width; x++) {
      final p = small.getPixel(x, y);
      final l = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round();
      n++;
      if (l >= 150) {
        bright++;
        chroma += ((p.r - p.g).abs() + (p.g - p.b).abs() + (p.r - p.b).abs()).toDouble();
        brightSamples++;
      }
      if (prev >= 0) {
        final hi = l > prev ? l : prev;
        if (hi >= 120 && (l - prev).abs() >= 45) inkEdges++;
      }
      prev = l;
    }
  }
  if (n == 0) return false;
  final brightFrac = bright / n;
  final meanChroma = brightSamples == 0 ? 999.0 : chroma / brightSamples;
  final inkScore = inkEdges / n;
  return brightFrac >= 0.28 && meanChroma <= 70 && inkScore >= 0.008;
}

/// Light unsharp-style pass so pencil and faint pen read crisply.
img.Image _sharpen(img.Image image) {
  try {
    return img.convolution(image, filter: [0, -1, 0, -1, 6, -1, 0, -1, 0], div: 2);
  } catch (e) {
    debugPrint('DocumentProcessor sharpen failed: $e');
    return image;
  }
}

/// Finds the four corners of the page (the dominant bright region).
/// Returns [topLeft, topRight, bottomRight, bottomLeft] in full-resolution
/// coordinates, or null when no convincing page shape is visible.
List<img.Point>? _findPageCorners(img.Image src) {
  const targetW = 220;
  final small = img.copyResize(src, width: targetW);
  final w = small.width, h = small.height;
  final n = w * h;

  // Luma + histogram for Otsu's threshold (paper vs background).
  final luma = Uint8List(n);
  final hist = List<int>.filled(256, 0);
  var i = 0;
  for (final p in small) {
    final l = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(0, 255);
    luma[i++] = l;
    hist[l]++;
  }
  final thr = _otsuThreshold(hist, n);

  // Largest connected bright component = the page.
  final visited = Uint8List(n);
  List<int> best = const [];
  final stack = <int>[];
  for (var seed = 0; seed < n; seed++) {
    if (visited[seed] != 0 || luma[seed] < thr) continue;
    final component = <int>[];
    stack.add(seed);
    visited[seed] = 1;
    while (stack.isNotEmpty) {
      final idx = stack.removeLast();
      component.add(idx);
      final x = idx % w, y = idx ~/ w;
      for (final d in const [
        [1, 0], [-1, 0], [0, 1], [0, -1],
      ]) {
        final nx = x + d[0], ny = y + d[1];
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        final ni = ny * w + nx;
        if (visited[ni] == 0 && luma[ni] >= thr) {
          visited[ni] = 1;
          stack.add(ni);
        }
      }
    }
    if (component.length > best.length) best = component;
  }

  if (best.length < n * 0.20) return null; // no big page in view

  // Extreme-point corners of the component.
  var tl = best.first, tr = best.first, br = best.first, bl = best.first;
  int score(int idx, bool sum) {
    final x = idx % w, y = idx ~/ w;
    return sum ? x + y : x - y;
  }

  for (final idx in best) {
    if (score(idx, true) < score(tl, true)) tl = idx;
    if (score(idx, true) > score(br, true)) br = idx;
    if (score(idx, false) > score(tr, false)) tr = idx;
    if (score(idx, false) < score(bl, false)) bl = idx;
  }

  img.Point toFull(int idx) => img.Point(
        ((idx % w) * src.width / w).clamp(0, src.width - 1),
        ((idx ~/ w) * src.height / h).clamp(0, src.height - 1),
      );

  final quad = [toFull(tl), toFull(tr), toFull(br), toFull(bl)];

  // Sanity: the quad must cover a meaningful part of the frame.
  final area = _quadArea(quad);
  if (area < src.width * src.height * 0.20) return null;

  // Push the corners slightly outward: extreme-point detection on the
  // thumbnail can land a few (full-res) pixels inside the sheet, and
  // rectifying to corners inside the page slices off edge text.
  final cx = (quad[0].x + quad[1].x + quad[2].x + quad[3].x) / 4;
  final cy = (quad[0].y + quad[1].y + quad[2].y + quad[3].y) / 4;
  return [
    for (final p in quad)
      img.Point(
        (cx + (p.x - cx) * 1.03).clamp(0, src.width - 1),
        (cy + (p.y - cy) * 1.03).clamp(0, src.height - 1),
      ),
  ];
}

int _otsuThreshold(List<int> hist, int total) {
  double sum = 0;
  for (var i = 0; i < 256; i++) {
    sum += i * hist[i];
  }
  double sumB = 0;
  var wB = 0;
  var threshold = 128;
  double maxVar = -1;
  for (var i = 0; i < 256; i++) {
    wB += hist[i];
    if (wB == 0) continue;
    final wF = total - wB;
    if (wF == 0) break;
    sumB += i * hist[i];
    final mB = sumB / wB;
    final mF = (sum - sumB) / wF;
    final v = wB.toDouble() * wF.toDouble() * (mB - mF) * (mB - mF);
    if (v > maxVar) {
      maxVar = v;
      threshold = i;
    }
  }
  return threshold;
}

double _quadArea(List<img.Point> q) {
  double a = 0;
  for (var i = 0; i < 4; i++) {
    final p1 = q[i], p2 = q[(i + 1) % 4];
    a += p1.x * p2.y - p2.x * p1.y;
  }
  return a.abs() / 2;
}

/// Stretches the luminance range so the page reads white and ink reads
/// dark — big legibility boost for pencil and faint pen.
void _stretchContrast(img.Image image) {
  final hist = List<int>.filled(256, 0);
  var count = 0;
  for (var y = 0; y < image.height; y += 2) {
    for (var x = 0; x < image.width; x += 2) {
      final p = image.getPixel(x, y);
      final l = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(0, 255);
      hist[l]++;
      count++;
    }
  }

  var lo = 0, hi = 255, acc = 0;
  final loTarget = count * 0.03;
  for (var i = 0; i < 256; i++) {
    acc += hist[i];
    if (acc >= loTarget) {
      lo = i;
      break;
    }
  }
  acc = 0;
  final hiTarget = count * 0.03;
  for (var i = 255; i >= 0; i--) {
    acc += hist[i];
    if (acc >= hiTarget) {
      hi = i;
      break;
    }
  }

  if (hi - lo < 40) return; // already flat — avoid amplifying noise
  final gain = 255.0 / (hi - lo);

  for (final p in image) {
    p.r = math.max(0, math.min(255, ((p.r - lo) * gain).round()));
    p.g = math.max(0, math.min(255, ((p.g - lo) * gain).round()));
    p.b = math.max(0, math.min(255, ((p.b - lo) * gain).round()));
  }
}
