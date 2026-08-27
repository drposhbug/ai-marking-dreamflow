
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Cheap, on-device "is this the same page?" fingerprinting.
///
/// A difference hash: shrink the page to 9×8 greyscale and record, for each
/// row, whether each pixel is brighter than the one to its right. That gives
/// 64 bits that survive rescanning, JPEG noise and slight skew, but change
/// completely when the content changes.
///
/// Free, instant, and nothing leaves the phone — which matters because this
/// runs over a whole class set before a single credit is spent.
class PageFingerprint {
  /// Bits that may differ and still count as the same page. Rescans of one
  /// sheet land within a couple of bits; two different students' pages are
  /// typically 20+ apart. 8 leaves room for scanner noise without merging
  /// pages that merely share a layout.
  static const int sameThreshold = 8;

  /// Two blank-ish pages hash almost identically, which would make every
  /// empty back page look like a duplicate. Below this much detail a page
  /// is treated as "no opinion" rather than a match.
  static const int _minDetailBits = 6;

  final String hex;
  final int detail;
  const PageFingerprint(this.hex, this.detail);

  bool get isBlankish => detail < _minDetailBits;

  /// Hamming distance to another fingerprint (0 = identical).
  int distanceTo(PageFingerprint other) {
    var d = 0;
    for (var i = 0; i < hex.length && i < other.hex.length; i++) {
      final a = int.parse(hex[i], radix: 16);
      final b = int.parse(other.hex[i], radix: 16);
      var x = a ^ b;
      while (x != 0) {
        d += x & 1;
        x >>= 1;
      }
    }
    return d;
  }

  /// Same sheet of paper, allowing for rescan noise. Blank pages never
  /// match — they carry no evidence either way.
  bool matches(PageFingerprint other) {
    if (isBlankish || other.isBlankish) return false;
    return distanceTo(other) <= sameThreshold;
  }

  static Future<PageFingerprint?> of(Uint8List bytes) async {
    try {
      return await compute(_hash, bytes);
    } catch (e) {
      debugPrint('PageFingerprint.of failed: $e');
      return null;
    }
  }

  static Future<List<PageFingerprint?>> ofAll(List<Uint8List> pages) async {
    final out = <PageFingerprint?>[];
    for (final p in pages) {
      out.add(await of(p));
    }
    return out;
  }
}

/// Runs in a background isolate — decoding 90 pages on the UI thread would
/// freeze the app mid-import.
PageFingerprint _hash(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return const PageFingerprint('0000000000000000', 0);
  final small = img.grayscale(img.copyResize(decoded, width: 9, height: 8));
  var bits = 0;
  var ones = 0;
  final buf = StringBuffer();
  var nibble = 0;
  var nibbleBits = 0;
  for (var y = 0; y < 8; y++) {
    for (var x = 0; x < 8; x++) {
      final left = small.getPixel(x, y).luminance;
      final right = small.getPixel(x + 1, y).luminance;
      final bit = left > right ? 1 : 0;
      if (bit == 1) ones++;
      bits++;
      nibble = (nibble << 1) | bit;
      nibbleBits++;
      if (nibbleBits == 4) {
        buf.write(nibble.toRadixString(16));
        nibble = 0;
        nibbleBits = 0;
      }
    }
  }
  // "Detail" = how far from all-same the page is. A blank sheet lands near 0
  // or near 64; both mean there was nothing to fingerprint.
  final detail = ones < bits - ones ? ones : bits - ones;
  return PageFingerprint(buf.toString(), detail);
}

/// What's wrong with one paper in a split stack.
enum PaperFault {
  /// The same sheet appears twice inside this one paper — the boundaries
  /// are off, or the feeder scanned a sheet twice.
  duplicatePage,

  /// Two cover pages inside one paper: a boundary was missed and two
  /// students' work is stuck together.
  twoCoverPages,

  /// This exact paper appears elsewhere in the same stack.
  duplicateOfAnotherPaper,
}

class PaperCheck {
  final int paperIndex;
  final Set<PaperFault> faults;
  const PaperCheck(this.paperIndex, this.faults);
  bool get isSuspect => faults.isNotEmpty;
}

/// Looks over a whole split stack for the mistakes that mean the SPLIT is
/// wrong rather than the marking — before any credits are spent on it.
class StackCheck {
  final List<PaperCheck> papers;
  const StackCheck(this.papers);

  List<PaperCheck> get suspects => papers.where((p) => p.isSuspect).toList();
  bool get anySuspect => suspects.isNotEmpty;

  /// When most of the stack looks wrong, the boundaries are wrong, not the
  /// individual papers — the teacher should fix the order rather than chase
  /// them one at a time.
  bool get wholeStackLooksWrong => papers.length >= 3 && suspects.length * 3 >= papers.length;

  /// Groups are lists of page indexes into [fingerprints]; [coverPage] says
  /// whether each page read as the start of a paper.
  static StackCheck run({
    required List<List<int>> groups,
    required List<PageFingerprint?> fingerprints,
    required List<bool> coverPage,
  }) {
    final checks = <PaperCheck>[];
    // First page of each paper, for spotting the same paper twice in a stack.
    final firstPages = <int, PageFingerprint>{};
    for (var g = 0; g < groups.length; g++) {
      final pages = groups[g];
      if (pages.isEmpty) {
        checks.add(PaperCheck(g, const {}));
        continue;
      }
      final faults = <PaperFault>{};

      // The same sheet twice inside one paper.
      for (var i = 0; i < pages.length; i++) {
        for (var j = i + 1; j < pages.length; j++) {
          final a = _at(fingerprints, pages[i]);
          final b = _at(fingerprints, pages[j]);
          if (a != null && b != null && a.matches(b)) {
            faults.add(PaperFault.duplicatePage);
          }
        }
      }

      // Two cover pages inside one paper.
      var covers = 0;
      for (final p in pages) {
        if (p < coverPage.length && coverPage[p]) covers++;
      }
      if (covers > 1) faults.add(PaperFault.twoCoverPages);

      final first = _at(fingerprints, pages.first);
      if (first != null) {
        for (final entry in firstPages.entries) {
          if (entry.value.matches(first)) {
            faults.add(PaperFault.duplicateOfAnotherPaper);
            break;
          }
        }
        firstPages[g] = first;
      }

      checks.add(PaperCheck(g, faults));
    }
    return StackCheck(checks);
  }

  static PageFingerprint? _at(List<PageFingerprint?> fps, int i) => (i >= 0 && i < fps.length) ? fps[i] : null;
}
