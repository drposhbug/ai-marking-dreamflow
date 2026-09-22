import 'dart:io' show Directory;
import 'dart:typed_data';

import 'package:marking_prokect_v2/services/overnight_page_store_native.dart'
    if (dart.library.html) 'package:marking_prokect_v2/services/overnight_page_store_web.dart' as impl;

/// There is nowhere left to put a class set's scans.
///
/// Its own type because it is the one stash failure a teacher can act on: a
/// browser that is out of room can be given room, or the set can be marked
/// now instead. Everything else — a write that failed for some reason nobody
/// can name — is just a paper that stays in the tray.
///
/// [toString] is the sentence the teacher reads, so it carries no "Exception:"
/// prefix and no class name.
class PageStoreFull implements Exception {
  final String message;
  const PageStoreFull(this.message);

  @override
  String toString() => message;
}

/// Where a queued class set's scanned pages wait while the app is shut.
///
/// A phone has a documents folder. A browser has IndexedDB, which survives a
/// closed tab, a restarted browser and a rebooted laptop just as well. That
/// is the only property overnight marking needs, so nothing above this line
/// — not the batch builder, not the morning filing — has to know which one
/// it got.
abstract class OvernightPageStore {
  /// Writes one paper's pages and hands back the keys to read them by.
  ///
  /// The keys are relative to whatever this store keeps things under, never
  /// absolute: iOS moves the documents folder out from under the app on
  /// every update, so a path written down at bedtime can point nowhere by
  /// morning.
  ///
  /// Throws [PageStoreFull] when the device refuses the write for space.
  Future<List<String>> write(String customId, List<Uint8List> pages);

  /// Everything written for one paper, gone.
  Future<void> discard(String customId);

  /// One page back as it went in, or null when it is no longer there.
  Future<Uint8List?> read(String key);

  /// Every key this store is still holding.
  Future<List<String>> keys();

  /// Whether a filed paper's pages are worth keeping.
  ///
  /// On a phone the result screen reopens a marked paper's scan from disk,
  /// so they stay. Nothing in a browser reads them back, so there they go
  /// the moment the batch is over rather than sitting in a teacher's site
  /// data forever.
  bool get keepsFiledPages;

  /// Turns keys into the form the rest of the app stores them in — a real
  /// path on a phone, the key itself in a browser.
  Future<List<String>> resolve(List<String> keys);
}

/// The store this build gets: files on a phone, IndexedDB in a browser.
///
/// [documentsDir] is only meaningful to the file store, and is there so a
/// test can hand it a temporary folder instead of the real one.
OvernightPageStore createOvernightPageStore({Future<Directory> Function()? documentsDir}) =>
    impl.createOvernightPageStore(documentsDir: documentsDir);
