import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Prints the identity onto the paper so the student never has to.
///
/// A teacher hands in one test file and gets back a single PDF containing
/// every copy, each stamped in the footer of EVERY page with its own code:
///
///     mk-7F3A-01      on all pages of copy 1
///     mk-7F3A-02      on all pages of copy 2
///
/// Scanned back, pages sharing a code are one student's paper — printed
/// text, machine-clean, and unaffected by handwriting, creases or a student
/// who couldn't be bothered to write their name again.
///
/// Everything here runs on the device. No API call, no credits — and it
/// removes the credits a mis-split stack would otherwise burn on
/// handwriting matching or on marking the wrong pages together.
class TestStamper {
  /// Characters that survive being read back off a scan. No 0/O, 1/I/L,
  /// 5/S, 8/B — a code is worthless if it can be misread as another code.
  /// No duplicates either, or the generator quietly favours one character.
  static const _alphabet = 'ACDEFGHJKMNPQRTUVWXY234679';

  /// Copies one PDF may carry. A teacher printing the same test for five
  /// sections of thirty wants every copy across all of them distinct, so
  /// this is sized for a whole teaching load rather than one class.
  static const int maxCopies = 250;

  /// A short code for one assessment, e.g. "7F3A". Four characters is one
  /// in ~530,000 per teacher, which is far beyond how many tests anyone
  /// has in flight at once.
  static String newTestCode([math.Random? rng]) {
    final r = rng ?? math.Random.secure();
    return List.generate(4, (_) => _alphabet[r.nextInt(_alphabet.length)]).join();
  }

  /// The footer stamped on a page. Deliberately terse and lower-case so it
  /// reads as a print artefact rather than something a student should worry
  /// about — but still unambiguous to read back.
  ///
  /// ASCII ONLY. Two reasons, and neither is tidiness: the PDF ships with
  /// the built-in Helvetica rather than an embedded font, so anything
  /// outside its encoding is a risk not worth taking on the one string the
  /// whole feature depends on; and a hyphen survives being read back off a
  /// 7pt scan far more reliably than a middle dot, which OCR loves to drop.
  static String stampFor({
    required String testCode,
    required int copyNumber,
    required int pageNumber,
    required int pageCount,
  }) =>
      'mk-$testCode-${copyNumber.toString().padLeft(2, '0')}  p$pageNumber/$pageCount';

  /// Reads a stamp back off a scanned page. Returns null when the page
  /// carries no Markless stamp — every other route (names, page numbers,
  /// handwriting) still applies to those.
  ///
  /// Tolerant of what OCR does to a tiny grey footer: the separators come
  /// back as dots, bullets, hyphens or spaces, and case is unreliable.
  static StampRead? readStamp(String text) {
    // Separators are OPTIONAL: a 7pt grey footer often comes back with the
    // dots dropped or turned into spaces. What stops a looser pattern from
    // matching stray text is the alphabet check below — the code can only
    // contain characters the generator is able to produce.
    final m = RegExp(
      r'mk\s*[·•.\-–—:]?\s*([A-Za-z0-9]{4})\s*[·•.\-–—:]?\s*(\d{1,3})',
      caseSensitive: false,
    ).firstMatch(text);
    if (m == null) return null;
    final code = (m.group(1) ?? '').toUpperCase();
    final copy = int.tryParse(m.group(2) ?? '');
    if (code.length != 4 || copy == null || copy < 1) return null;
    if (!code.split('').every(_alphabet.contains)) return null;

    int? pageNo;
    int? pageTotal;
    final p = RegExp(r'\bp\s*(\d{1,3})\s*/\s*(\d{1,3})\b', caseSensitive: false).firstMatch(text);
    if (p != null) {
      pageNo = int.tryParse(p.group(1) ?? '');
      pageTotal = int.tryParse(p.group(2) ?? '');
    }
    return StampRead(testCode: code, copyNumber: copy, pageNumber: pageNo, pageCount: pageTotal);
  }

  /// Builds the print-ready PDF: [copies] copies of the same test, each
  /// stamped with its own code.
  ///
  /// [pageImages] are the test's pages, rendered once. Each is embedded in
  /// the document a single time and referenced by every copy, so thirty
  /// copies of a three-page test is three images on disk, not ninety.
  static Future<Uint8List> build({
    required List<Uint8List> pageImages,
    required String testCode,
    required int copies,
    void Function(int done, int total)? onProgress,
  }) async {
    final doc = pw.Document(title: 'Markless test $testCode');
    // Embed each source page ONCE. Without this a 30-copy set would carry
    // 90 copies of the same image and run to hundreds of megabytes.
    final images = [for (final bytes in pageImages) pw.MemoryImage(bytes)];

    for (var copy = 1; copy <= copies; copy++) {
      for (var p = 0; p < images.length; p++) {
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.letter,
            margin: pw.EdgeInsets.zero,
            build: (context) => pw.Stack(
              children: [
                pw.Positioned.fill(child: pw.Image(images[p], fit: pw.BoxFit.contain)),
                // Bottom-left, small and grey: legible to a scanner,
                // ignorable to a fifteen-year-old.
                pw.Positioned(
                  left: 24,
                  bottom: 14,
                  child: pw.Text(
                    stampFor(
                      testCode: testCode,
                      copyNumber: copy,
                      pageNumber: p + 1,
                      pageCount: images.length,
                    ),
                    style: pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      onProgress?.call(copy, copies);
    }
    return Uint8List.fromList(await doc.save());
  }

  /// Groups scanned pages by the copy code stamped on them.
  ///
  /// This is the whole point: when every page carries its copy number,
  /// splitting stops being a guess. Pages with no stamp are returned
  /// separately so the name/handwriting routes can still handle them.
  static StampGrouping groupByStamp(List<StampRead?> stamps) {
    // Keyed on the TEST code as well as the copy number. Grouping on the
    // copy number alone would merge copy 01 of the Friday quiz with copy 01
    // of the unit test if both ended up in one scan — two students' work
    // filed as one paper, which is the exact failure this feature exists to
    // prevent.
    final byCopy = <String, List<int>>{};
    final unstamped = <int>[];
    for (var i = 0; i < stamps.length; i++) {
      final s = stamps[i];
      if (s == null) {
        unstamped.add(i);
        continue;
      }
      (byCopy['${s.testCode}-${s.copyNumber}'] ??= <int>[]).add(i);
    }
    // Order each paper by its printed page number where we have one, so a
    // stack fed in backwards still comes out reading correctly.
    final groups = <List<int>>[];
    final keys = byCopy.keys.toList()
      ..sort((a, b) {
        // Papers come out in test order, then copy order.
        final ca = int.tryParse(a.split('-').last) ?? 0;
        final cb = int.tryParse(b.split('-').last) ?? 0;
        final ta = a.substring(0, a.lastIndexOf('-'));
        final tb = b.substring(0, b.lastIndexOf('-'));
        return ta == tb ? ca.compareTo(cb) : ta.compareTo(tb);
      });
    final copyNumbers = [for (final k in keys) int.tryParse(k.split('-').last) ?? 0];
    for (final c in keys) {
      final pages = byCopy[c]!
        ..sort((a, b) {
          final pa = stamps[a]?.pageNumber ?? 0;
          final pb = stamps[b]?.pageNumber ?? 0;
          if (pa != pb && pa > 0 && pb > 0) return pa.compareTo(pb);
          return a.compareTo(b);
        });
      groups.add(pages);
    }
    return StampGrouping(groups: groups, copyNumbers: copyNumbers, unstamped: unstamped);
  }
}

class StampRead {
  final String testCode;
  final int copyNumber;
  final int? pageNumber;
  final int? pageCount;
  const StampRead({required this.testCode, required this.copyNumber, this.pageNumber, this.pageCount});

  /// True when this paper is missing pages the stamp says should exist.
  bool get knowsPageCount => pageCount != null && pageCount! > 0;
}

class StampGrouping {
  final List<List<int>> groups;
  final List<int> copyNumbers;
  final List<int> unstamped;
  const StampGrouping({required this.groups, required this.copyNumbers, required this.unstamped});

  bool get isUsable => groups.isNotEmpty;

  /// Copies whose page count doesn't match what the stamp claims — a
  /// double-feed, or a page that ended up in the wrong pile.
  List<int> shortCopies(List<StampRead?> stamps) {
    final out = <int>[];
    for (var g = 0; g < groups.length; g++) {
      final pages = groups[g];
      final expected = stamps[pages.first]?.pageCount;
      if (expected != null && expected > 0 && pages.length != expected) {
        out.add(copyNumbers[g]);
      }
    }
    return out;
  }
}

/// Debug helper: what the stamper produced, without printing anything.
void debugStamp(String s) {
  if (kDebugMode) debugPrint('TestStamper: $s');
}
