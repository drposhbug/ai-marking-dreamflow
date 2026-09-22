import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:marking_prokect_v2/services/local_store.dart';
import 'package:marking_prokect_v2/services/word_locator.dart';

/// A page prepared for marking, with the student's identity kept behind.
class AnonymizedPage {
  /// What actually gets uploaded.
  final Uint8List bytes;

  /// The name read off the paper — read HERE, on the phone, and never sent
  /// anywhere. It is what links the result to the right student locally.
  final String? nameOnPaper;

  /// True when something was actually covered up. False means no name field
  /// was found, so the page went up unchanged.
  final bool redacted;

  const AnonymizedPage({required this.bytes, required this.nameOnPaper, required this.redacted});
}

/// A whole paper prepared for marking.
class AnonymizedSet {
  /// The pages that will be uploaded, in order.
  final List<Uint8List> pages;

  /// The name read off the paper, kept here to file the result.
  final String? nameOnPaper;

  /// True when at least one page had something covered. Page-by-page is the
  /// wrong unit to warn on — the second sheet of a test has no name field
  /// and never did. A paper where *nothing* was covered is the one the
  /// teacher needs to hear about.
  final bool anyRedacted;

  const AnonymizedSet({required this.pages, required this.nameOnPaper, required this.anyRedacted});
}

/// What actually happened to the student's name on work that is about to
/// be, or has just been, sent for marking.
///
/// This exists so the app can say it out loud. Silently uploading a page
/// with a child's name on it while a switch labelled "Hide student names"
/// sits on in Settings is the one behaviour this product must not have.
enum NameHiding {
  /// A name field was found and painted black. The name stayed here.
  hidden,

  /// Nothing was found to cover — no name field, or handwriting the
  /// recogniser could not read. The page went up as it is.
  notFound,

  /// Name hiding cannot run here at all. Nothing was read, nothing was
  /// covered, and nothing was attempted.
  unavailable,

  /// The teacher turned it off in Settings.
  off,
}

extension NameHidingReport on NameHiding {
  /// True only when the page really did go up with the name covered.
  /// Everything else has to be said to the teacher.
  bool get hidesTheName => this == NameHiding.hidden;

  /// The one line a teacher reads first.
  String get headline => switch (this) {
        NameHiding.hidden => 'Name hidden before upload',
        NameHiding.notFound => 'Name not hidden on this paper',
        NameHiding.unavailable => 'Names can\'t be hidden here',
        NameHiding.off => 'Name hiding is off',
      };

  /// The plain explanation under it. No hedging: a teacher decides what to
  /// do next based on this sentence.
  String get detail => switch (this) {
        NameHiding.hidden =>
          'The name was read on this device and painted out of the copy that was sent. It never left here.',
        NameHiding.notFound =>
          'No name field could be read on this paper, so it was sent exactly as scanned — including anything written on it. Cover the name yourself if that matters here.',
        // Every platform the app ships on has a reader now, so this is the
        // state nothing should reach. It stays because a reader that is
        // gone has to report that it is gone, not quietly do nothing.
        NameHiding.unavailable =>
          'Hiding names needs text recognition running on this device, and this one has none. Pages you upload are sent exactly as you picked them, name and all. Cover names before uploading, or mark from a Google Form or CSV instead — that route never sends the name column.',
        NameHiding.off =>
          'You turned off "Hide student names before marking" in Settings, so pages are sent with the name on them.',
      };
}

/// Keeps student identity out of what gets sent for marking.
///
/// The marking model never needs to know whose paper it is — it grades the
/// work. So the name is read on the device, blacked out of the image, and
/// only the anonymous page is uploaded. The name stays on the phone and is
/// what files the result under the right student.
///
/// This is better than it sounds for accuracy too: reading the name locally
/// is free and exact, where asking the model to read it costs tokens and
/// gets misread handwriting wrong.
class Anonymizer {
  /// Labels that introduce a student's identity on a school paper.
  static final _identityLabel = RegExp(
    r'^\s*(?:student\s+)?(?:name|nom|full\s+name|student|pupil|student\s*(?:id|number|#))\s*[:.\-]',
    caseSensitive: false,
  );

  /// Not a name, even when it follows a "Name:"-shaped label.
  static final _notAName = RegExp(
    r'^(?:date|class|period|block|section|grade|teacher|subject|score|mark|total|page)\b',
    caseSensitive: false,
  );

  /// Whether name hiding can run on this device at all.
  ///
  /// It needs text recognition that runs here, on this machine, with the
  /// page never leaving it. Every platform the app ships on now has one —
  /// ML Kit on a phone, a vendored Tesseract build in a browser — but this
  /// asks the reader rather than assuming, so a platform that loses its
  /// reader reports honestly instead of leaving a switch looking like it is
  /// working.
  static bool get available => WordLocator.available;

  /// The paragraph under the Settings switch. Platform-dependent, because
  /// what actually happens is platform-dependent and a teacher acts on this
  /// sentence with a child's work.
  static String get hidingExplainer => switch (WordLocator.trust) {
        OcrTrust.readsHandwriting =>
          'Your phone reads the name off each paper and blacks it out before the page is sent to be marked — so the work is marked, not the student. The name never leaves this device; it is what files the result under the right student here. You still see the original paper, name and all. If it cannot read a name field on a page, that page is sent as it is, and the app tells you so.',
        OcrTrust.printedLabelsOnly =>
          'This browser reads each page here, on your machine, finds the printed "Name:" line and blacks out that whole line before the page is sent to be marked. Nothing is read anywhere else and the page never leaves your machine unredacted. Browser reading is weaker than a phone\'s: it reads the printed label, not the handwriting, so it covers the line edge to edge rather than the name exactly — and on a page where it cannot find a label, nothing is covered and the app tells you so.',
      };

  /// The line shown just above the Mark button, saying what is about to
  /// happen to the name.
  static String get beforeMarkNote => switch (WordLocator.trust) {
        OcrTrust.readsHandwriting =>
          'Your device reads the name off the page and blacks it out before this is sent. If it can\'t read one, the page goes up as it is.',
        OcrTrust.printedLabelsOnly =>
          'This browser finds the printed "Name:" line and blacks out that whole line before this is sent. If it can\'t find one, the page goes up as it is, and you\'ll be told.',
      };

  /// What to tell the teacher, given the setting and what actually
  /// happened. Pure, because the wording is the part that has to be right.
  ///
  /// The platform answer comes first: a teacher whose switch is on where
  /// nothing can read a page must be told that, not that it is off.
  static NameHiding outcome({
    required bool settingOn,
    required bool anyRedacted,
    bool? available,
  }) {
    if (!(available ?? Anonymizer.available)) return NameHiding.unavailable;
    if (!settingOn) return NameHiding.off;
    return anyRedacted ? NameHiding.hidden : NameHiding.notFound;
  }

  /// What will happen to the name when the teacher taps Mark, said before
  /// they tap it.
  ///
  /// Whether a name field can actually be read is only answered by trying,
  /// so this never promises [NameHiding.notFound] away — it reports what
  /// the app is going to attempt. [outcome] reports what happened.
  static NameHiding intent({required bool settingOn, bool? available}) {
    if (!(available ?? Anonymizer.available)) return NameHiding.unavailable;
    return settingOn ? NameHiding.hidden : NameHiding.off;
  }

  /// The identity on one page, from its recognised words: the name to keep
  /// here, and every line that has to be painted over before upload.
  ///
  /// [trust] says what the reader that produced [words] could actually read,
  /// and that changes both answers. A reader that sees the handwriting knows
  /// where the name is and what it says. A reader that only sees the printed
  /// label knows neither — so it covers the line right across the page and
  /// reports no name at all, rather than a guess dressed up as a fact.
  @visibleForTesting
  static IdentityOnPage identityIn(
    List<RecognizedWord> words, {
    OcrTrust trust = OcrTrust.readsHandwriting,
  }) {
    final byLine = <int, List<RecognizedWord>>{};
    for (final w in words) {
      (byLine[w.lineId] ??= <RecognizedWord>[]).add(w);
    }

    final readsHandwriting = trust == OcrTrust.readsHandwriting;
    String? name;
    final toCover = <Rect>[];
    for (final entry in byLine.entries) {
      final lineWords = entry.value..sort((a, b) => a.rect.left.compareTo(b.rect.left));
      final text = lineWords.map((w) => w.text).join(' ').trim();
      if (text.isEmpty || !_identityLabel.hasMatch(text)) continue;

      final bounds = _lineBounds(lineWords);
      if (readsHandwriting) {
        // Cover the whole line: the label alone identifies nobody, but the
        // handwriting beside it does, and its exact extent is guesswork.
        toCover.add(bounds);
        name ??= _valueAfterLabel(text);
      } else {
        // The reader did not see the handwriting, so the line it measured
        // may stop at the colon with the child's name sitting just past it.
        // Covering from edge to edge is the only version of this that is
        // not a lie. Infinity here means "to the paper's edge"; the masker
        // is the only thing that knows where that is.
        toCover.add(Rect.fromLTRB(0, bounds.top, double.infinity, bounds.bottom));
        // No name is reported. Whatever this reader made of the scrawl is a
        // guess, and a guessed name files a result under the wrong child
        // without ever saying it guessed.
      }
    }
    return IdentityOnPage(name: name, regions: toCover);
  }

  /// Paints solid black over [regions] and returns the page that would be
  /// uploaded, or null when the image cannot be decoded.
  ///
  /// Public so the covering itself is testable — "blacked out before
  /// upload" is the claim everything else rests on.
  @visibleForTesting
  static Uint8List? maskRegions(Uint8List bytes, List<Rect> regions) => _maskRegions(_MaskJob(bytes, regions));

  /// Reads and hides the identity on one page.
  ///
  /// Falls back to the untouched page whenever recognition or redaction
  /// fails — a marking run must never be blocked by this, but the caller is
  /// told via [AnonymizedPage.redacted] so the UI can be honest about it.
  static Future<AnonymizedPage> page(Uint8List bytes) async {
    if (!available) return AnonymizedPage(bytes: bytes, nameOnPaper: null, redacted: false);
    try {
      final words = await WordLocator.recognize(bytes);
      if (words.isEmpty) return AnonymizedPage(bytes: bytes, nameOnPaper: null, redacted: false);

      final found = identityIn(words, trust: WordLocator.trust);
      if (!found.found) return AnonymizedPage(bytes: bytes, nameOnPaper: null, redacted: false);

      // A browser has no isolates: `compute` runs this inline there, which
      // is correct — the masking is one decode and one encode, and the page
      // has already waited on OCR.
      final redacted = await compute(_maskRegions, _MaskJob(bytes, found.regions));
      return AnonymizedPage(
        bytes: redacted ?? bytes,
        nameOnPaper: found.name,
        redacted: redacted != null,
      );
    } catch (e) {
      debugPrint('Anonymizer.page failed: $e');
      return AnonymizedPage(bytes: bytes, nameOnPaper: null, redacted: false);
    }
  }

  /// Runs [page] across a whole paper, keeping the first name found and
  /// whether anything was covered anywhere on it.
  static Future<AnonymizedSet> pageSet(List<Uint8List> pages) async {
    final out = <Uint8List>[];
    String? name;
    var anyRedacted = false;
    for (final p in pages) {
      final a = await page(p);
      out.add(a.bytes);
      name ??= a.nameOnPaper;
      anyRedacted = anyRedacted || a.redacted;
    }
    return AnonymizedSet(pages: out, nameOnPaper: name, anyRedacted: anyRedacted);
  }

  /// Runs [page] across a whole paper, keeping the first name found.
  static Future<(List<Uint8List>, String?)> pages(List<Uint8List> pages) async {
    final set = await pageSet(pages);
    return (set.pages, set.nameOnPaper);
  }

  static Rect _lineBounds(List<RecognizedWord> words) {
    var left = double.infinity, top = double.infinity, right = 0.0, bottom = 0.0;
    for (final w in words) {
      if (w.rect.left < left) left = w.rect.left;
      if (w.rect.top < top) top = w.rect.top;
      if (w.rect.right > right) right = w.rect.right;
      if (w.rect.bottom > bottom) bottom = w.rect.bottom;
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  static String? _valueAfterLabel(String line) {
    final m = RegExp(r'[:.\-]\s*(.+)$').firstMatch(line);
    var rest = (m?.group(1) ?? '').trim();
    if (rest.isEmpty) return null;
    final cut = RegExp(r'\s{2,}|\s(?=(?:date|class|period|block|section|grade)\s*[:.\-])', caseSensitive: false).firstMatch(rest);
    if (cut != null) rest = rest.substring(0, cut.start).trim();
    rest = rest.replaceAll(RegExp(r'[_\.]{2,}'), ' ').trim();
    if (rest.isEmpty || _notAName.hasMatch(rest)) return null;
    if (rest.length < 2 || rest.length > 40) return null;
    if (!RegExp(r'[A-Za-z]').hasMatch(rest)) return null;
    return rest;
  }

  /// Removes names the teacher already knows from free text before it is
  /// sent for marking — a student who signed their essay, or wrote a
  /// classmate's name in an answer.
  ///
  /// Whole-word, case-insensitive, longest names first so "Ana Lopez" is
  /// replaced before the bare "Ana" inside it.
  static String scrubNames(String text, Iterable<String> names) {
    if (text.isEmpty) return text;
    final parts = <String>{};
    for (final full in names) {
      final n = full.trim();
      if (n.length < 3) continue; // "Al", "Jo" — too short to match safely
      parts.add(n);
      for (final piece in n.split(RegExp(r'\s+'))) {
        if (piece.length >= 3) parts.add(piece);
      }
    }
    if (parts.isEmpty) return text;
    final ordered = parts.toList()..sort((a, b) => b.length.compareTo(a.length));
    var out = text;
    for (final p in ordered) {
      out = out.replaceAll(
        RegExp('(?<![A-Za-z])${RegExp.escape(p)}(?![A-Za-z])', caseSensitive: false),
        '[name]',
      );
    }
    return out;
  }
}

/// What one page's recognised words say about who wrote it.
class IdentityOnPage {
  /// The name beside the label, for filing the result here.
  final String? name;

  /// Every line that has to be painted black before the page is uploaded.
  final List<Rect> regions;

  const IdentityOnPage({required this.name, required this.regions});

  /// True when there is something to cover. False means the page uploads
  /// exactly as it was scanned.
  bool get found => regions.isNotEmpty;
}

/// Remembers that a teacher has been told what hiding names in a browser
/// does and does not do.
///
/// Asked once per teacher, before their first upload of student work in a
/// browser. It is a fact they have to have before they decide, not a dialog
/// to sit through every time they mark.
class WebUploadNotice {
  final LocalStore _store;

  const WebUploadNotice({LocalStore store = const LocalStore()}) : _store = store;

  /// v2 deliberately does not read v1. Teachers on v1 agreed to "names go
  /// up uncovered in a browser", which is no longer what happens; the thing
  /// they agreed to is not the thing they should be agreeing to, so they
  /// are told once more and asked again.
  static String _key(String teacherId) => 'ai_marker.web_upload_ack.v2.$teacherId';

  /// Whether the teacher still has to be asked before this upload.
  static bool needed({required bool onWeb, required bool alreadyAcknowledged}) => onWeb && !alreadyAcknowledged;

  Future<bool> acknowledged(String teacherId) async => (await _store.getString(_key(teacherId))) == '1';

  Future<void> acknowledge(String teacherId) => _store.setString(_key(teacherId), '1');
}

class _MaskJob {
  final Uint8List bytes;
  final List<Rect> regions;
  const _MaskJob(this.bytes, this.regions);
}

/// Paints solid black over each region. Runs in a background isolate — a
/// full-page decode/encode would jank the UI on a class set.
Uint8List? _maskRegions(_MaskJob job) {
  try {
    final image = img.decodeImage(job.bytes);
    if (image == null) return null;
    for (final r in job.regions) {
      // A little padding: recognition boxes hug the glyphs, and a descender
      // or a long tail on handwriting can sit outside them.
      final pad = (image.height * 0.006).round().clamp(2, 14);
      // An infinite edge means "as far as the paper goes" — what a reader
      // that cannot see the handwriting asks for, because it does not know
      // where the name ends. This is the only place that knows the answer.
      final left = r.left.isFinite ? r.left : 0.0;
      final top = r.top.isFinite ? r.top : 0.0;
      final right = r.right.isFinite ? r.right : image.width.toDouble();
      final bottom = r.bottom.isFinite ? r.bottom : image.height.toDouble();
      final x = (left - pad).round().clamp(0, image.width - 1);
      final y = (top - pad).round().clamp(0, image.height - 1);
      final w = (right - left + pad * 2).round().clamp(1, image.width - x);
      final h = (bottom - top + pad * 2).round().clamp(1, image.height - y);
      img.fillRect(image, x1: x, y1: y, x2: x + w, y2: y + h, color: img.ColorRgb8(0, 0, 0));
    }
    return Uint8List.fromList(img.encodeJpg(image, quality: 88));
  } catch (e) {
    debugPrint('_maskRegions failed: $e');
    return null;
  }
}
