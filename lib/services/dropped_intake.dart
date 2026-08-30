import 'package:flutter/foundation.dart';
import 'package:marking_prokect_v2/app/app_state.dart' show ScannedPage;
import 'package:marking_prokect_v2/services/bulk_page_processor.dart';
import 'package:marking_prokect_v2/services/drive_picker.dart' show looksLikeImageFile, looksLikePdfFile;

/// One file a teacher dragged onto the window, or pasted from the clipboard.
///
/// This is the browser's side of the intake and nothing more: it carries the
/// same three things a picked file carries, so a drop can be turned into the
/// exact [PickedPhoto] list a gallery pick produces and take the identical
/// route from there.
class DroppedFile {
  final String name;
  final String mime;
  final Uint8List bytes;

  const DroppedFile({required this.name, required this.mime, required this.bytes});

  /// A PDF needs its pages rendered before anything can mark them, so the
  /// intake has to know before it starts.
  bool get isPdf => _magicIsPdf(bytes) || looksLikePdfFile(name, mime);
}

/// What the FILE ITSELF says it is. A drag out of a Drive folder, or a
/// scanner's output, often arrives named "scan" with no extension and a
/// generic type — the bytes are the only thing worth trusting.
bool _magicIsPdf(Uint8List b) =>
    b.length > 4 && b[0] == 0x25 && b[1] == 0x50 && b[2] == 0x44 && b[3] == 0x46; // %PDF

bool _magicIsImage(Uint8List b) {
  if (b.length < 12) return false;
  if (b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return true; // JPEG
  if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return true; // PNG
  if (b[0] == 0x42 && b[1] == 0x4D) return true; // BMP
  if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return true; // GIF
  if (b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 && b[8] == 0x57 && b[9] == 0x45) return true; // WEBP
  if (b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70) return true; // HEIC/HEIF/AVIF
  return false;
}

/// The dropped files Markless can do something with.
///
/// A teacher who drags a whole folder over gets its spreadsheets, its
/// `.DS_Store` and its zip along with the scans. Those are dropped quietly
/// here rather than becoming twenty failures at the end of a long run — but
/// the count of what was left out is worth telling her, which is why this
/// returns a list to compare rather than filtering in place.
List<DroppedFile> markableDrops(List<DroppedFile> files) => [
      for (final f in files)
        if (f.bytes.isNotEmpty && (f.isPdf || _magicIsImage(f.bytes) || looksLikeImageFile(f.name, f.mime))) f,
    ];

/// A drop, in the shape a gallery pick hands over — from here on the two are
/// the same thing and take the same route.
List<PickedPhoto> photosFromDrop(List<DroppedFile> files) =>
    [for (final f in files) PickedPhoto(bytes: f.bytes, fileName: f.name)];

/// A pasted screenshot has no filename of its own — every browser calls it
/// "image.png". The teacher still has to recognise it in a list of failures
/// or a batch of marks, and two pastes must not look like the same page, so
/// it is named for what it is and when it arrived.
String pastedFileName(String mime, DateTime at) {
  final ext = switch (mime) {
    'image/jpeg' || 'image/jpg' => 'jpg',
    'image/webp' => 'webp',
    'image/gif' => 'gif',
    'image/bmp' => 'bmp',
    _ => 'png',
  };
  String two(int n) => n.toString().padLeft(2, '0');
  return 'Pasted ${two(at.hour)}-${two(at.minute)}-${two(at.second)}.$ext';
}

final RegExp _pageSuffix = RegExp(r'\s*\(page \d+\)$');

/// Puts prepared pages back into one group per file they came from.
///
/// It matters when the teacher says "one test per file": a photo is one
/// student, but the three pages of a dropped PDF are one student's paper and
/// marking them as three separate students would hand back three part-marks
/// and three wrong names. Only pages that actually carry a "(page n)" suffix
/// are joined up, and only to the page right before them, so two photos that
/// happen to share a name can never be merged.
List<List<ScannedPage>> groupPagesBySourceFile(List<ScannedPage> pages) {
  final groups = <List<ScannedPage>>[];
  String? openBase;
  for (final page in pages) {
    final match = _pageSuffix.firstMatch(page.fileName);
    if (match == null) {
      groups.add([page]);
      openBase = null;
      continue;
    }
    final base = page.fileName.substring(0, match.start);
    if (openBase == base) {
      groups.last.add(page);
    } else {
      groups.add([page]);
      openBase = base;
    }
  }
  return groups;
}
