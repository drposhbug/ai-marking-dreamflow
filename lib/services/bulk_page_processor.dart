import 'package:flutter/foundation.dart';
import 'package:marking_prokect_v2/app/app_state.dart';

/// One photo as the picker handed it over, before any straightening.
class PickedPhoto {
  final Uint8List bytes;
  final String fileName;
  const PickedPhoto({required this.bytes, required this.fileName});
}

/// What came back from preparing a pile of photos.
class BulkPageResult {
  final List<ScannedPage> pages;

  /// Photos that could not be read at all. Named so the teacher can go back
  /// and re-shoot the two that failed instead of the whole class set.
  final List<String> failed;

  final bool cancelled;

  const BulkPageResult({required this.pages, required this.failed, required this.cancelled});
}

/// Most photos a single gallery pick will prepare in one go.
///
/// Each photo is decoded at full camera resolution before it is scaled down,
/// and the prepared pages are all held until the teacher chooses what to do
/// with them, so an unbounded pick is an out-of-memory crash on a mid-range
/// phone. A scan of a whole copier stack belongs in the stack splitter, which
/// streams a PDF instead of holding photos.
const int kMaxGalleryPhotos = 60;

/// Plain-English warning when a pick is larger than we will actually prepare,
/// or null when the pick is a normal size. Returns the real numbers because
/// "too many photos" tells a teacher nothing about what to do next.
String? bulkPickWarning(int picked) {
  if (picked <= kMaxGalleryPhotos) return null;
  return 'You picked $picked photos. Markless will prepare the first $kMaxGalleryPhotos — '
      'pick the rest afterwards, or scan the stack to a PDF and use "Split a scanned stack", '
      'which handles a whole class in one file.';
}

List<PickedPhoto> capPicked(List<PickedPhoto> picked) =>
    picked.length <= kMaxGalleryPhotos ? picked : picked.sublist(0, kMaxGalleryPhotos);

/// Straightens and cleans each picked photo in turn, reporting progress so the
/// teacher can see it moving, and stopping the moment they cancel.
///
/// One unreadable photo must never cost the teacher the other twenty-nine:
/// a failure is recorded by name and the run carries on.
Future<BulkPageResult> processPickedPages(
  List<PickedPhoto> picked, {
  required Future<Uint8List> Function(Uint8List bytes) process,
  void Function(int done, int total)? onProgress,
  bool Function()? isCancelled,
}) async {
  final pages = <ScannedPage>[];
  final failed = <String>[];
  final total = picked.length;

  for (var i = 0; i < total; i++) {
    // Checked before each photo rather than after, so cancelling stops the
    // next second of work instead of the next minute of it.
    if (isCancelled?.call() ?? false) {
      return BulkPageResult(pages: pages, failed: failed, cancelled: true);
    }
    final photo = picked[i];
    try {
      pages.add(ScannedPage(bytes: await process(photo.bytes), fileName: photo.fileName));
    } catch (e) {
      debugPrint('Preparing ${photo.fileName} failed: $e');
      failed.add(photo.fileName);
    }
    onProgress?.call(i + 1, total);
  }

  return BulkPageResult(pages: pages, failed: failed, cancelled: false);
}
