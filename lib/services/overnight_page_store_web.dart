import 'dart:async';
// The conditional-import shape browser_intake_web.dart and
// web_image_picker_web.dart already use: these files only ever compile for
// the browser, and a second style here would be one more thing to keep in
// step for no gain.
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
// The analyser's SDK no longer lists dart:indexed_db, but dart2js — which
// is what actually builds this file — still ships it, and the web bundle
// compiles and runs against it. The alternative is hand-written js_interop
// bindings for six IndexedDB types, which is more code to get wrong for the
// same result.
// ignore: avoid_web_libraries_in_flutter, uri_does_not_exist
import 'dart:indexed_db' as idb;
// Only for the type in the factory below. Nothing here ever builds one — a
// browser has no documents folder, which is the whole reason this file
// exists.
import 'dart:io' show Directory;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:marking_prokect_v2/services/overnight_page_store.dart';

const _dbName = 'markless_overnight';
const _pages = 'pages';

/// The browser's own durable storage, which is where a class set's scans
/// wait when Markless is a tab rather than an app.
///
/// IndexedDB, not localStorage and not the cache: it survives the tab being
/// closed, the browser being quit and the laptop being rebooted, and it
/// takes bytes. A thirty-paper class set is tens of megabytes, so the pages
/// go in as blobs — base64 would make it a third bigger for nothing.
///
/// Keys are the same relative strings a phone writes down
/// ("overnight/ov_abc/p0.jpg"), so a batch reads back the same way on either
/// platform and nothing above this file has to know the difference.
class IndexedDbPageStore implements OvernightPageStore {
  Future<idb.Database>? _opening;

  Future<idb.Database> _db() => _opening ??= html.window.indexedDB!.open(
        _dbName,
        version: 1,
        onUpgradeNeeded: (event) {
          final db = (event.target as idb.Request).result as idb.Database;
          if (!(db.objectStoreNames ?? const []).contains(_pages)) db.createObjectStore(_pages);
        },
      );

  /// Nothing in a browser reopens a marked paper's scan — the result screen
  /// only reads pages back off a real filesystem — so a filed paper's blobs
  /// are dead weight in a teacher's site data. They go as soon as the batch
  /// is over.
  @override
  bool get keepsFiledPages => false;

  @override
  Future<List<String>> write(String customId, List<Uint8List> pages) async {
    final keys = <String>[];
    try {
      final db = await _db();
      final txn = db.transaction(_pages, 'readwrite');
      final store = txn.objectStore(_pages);
      // Every page is asked for in this one turn of the event loop and only
      // then waited on. Awaiting them one at a time lets the browser close
      // the transaction underneath us between pages.
      final writes = <Future<dynamic>>[];
      for (var i = 0; i < pages.length; i++) {
        final key = 'overnight/$customId/p$i.jpg';
        writes.add(store.put(pages[i], key));
        keys.add(key);
      }
      await Future.wait(writes);
      await txn.completed;
      return keys;
    } catch (e) {
      // A half-written paper is no use to anyone, and on a browser that has
      // just said it is out of room, leaving three of its five pages behind
      // is the opposite of helpful.
      await discard(customId);
      if (_outOfRoom(e)) {
        throw const PageStoreFull(
            'This browser has no room left to keep the scans until morning. Clear some site data, or mark this set now instead.');
      }
      debugPrint('IndexedDbPageStore.write failed: $e');
      rethrow;
    }
  }

  /// A browser refuses a write it has no room for with a QuotaExceededError;
  /// Firefox has its own name for the same thing.
  ///
  /// What arrives here is usually the failed request's error *event*, not
  /// the exception itself — IndexedDB reports failures by firing at the
  /// request — so the reason has to be fished off whatever fired.
  static bool _outOfRoom(Object e) {
    final name = _failureName(e);
    if (name == 'QuotaExceededError' || name == 'NS_ERROR_DOM_QUOTA_REACHED') return true;
    return '$e'.toLowerCase().contains('quota');
  }

  static String _failureName(Object e) {
    if (e is html.DomException) return e.name;
    if (e is html.Event) {
      final target = e.target;
      if (target is idb.Request) return target.error?.name ?? '';
      if (target is idb.Transaction) return target.error?.name ?? '';
    }
    return '';
  }

  @override
  Future<void> discard(String customId) async {
    try {
      final db = await _db();
      final txn = db.transaction(_pages, 'readwrite');
      // Every page of one paper in a single delete: they all sort together
      // under the paper's own prefix.
      final prefix = 'overnight/$customId/';
      final done = txn.completed;
      await txn.objectStore(_pages).delete(idb.KeyRange.bound(prefix, '$prefix￿'));
      await done;
    } catch (e) {
      debugPrint('IndexedDbPageStore.discard failed: $e');
    }
  }

  @override
  Future<Uint8List?> read(String key) async {
    try {
      final db = await _db();
      final value = await db.transaction(_pages, 'readonly').objectStore(_pages).getObject(key);
      if (value is Uint8List) return value;
      if (value is ByteBuffer) return Uint8List.view(value);
      if (value is List<int>) return Uint8List.fromList(value);
      return null;
    } catch (e) {
      debugPrint('IndexedDbPageStore.read failed: $e');
      return null;
    }
  }

  @override
  Future<List<String>> keys() async {
    try {
      final db = await _db();
      final store = db.transaction(_pages, 'readonly').objectStore(_pages);
      // Keys only. Walking a cursor would drag every page's bytes back out
      // of the database just to find out what is in there.
      final result = await _awaitRequest(store.getAllKeys(null));
      final out = [for (final k in (result as List? ?? const [])) k.toString()];
      out.sort();
      return out;
    } catch (e) {
      debugPrint('IndexedDbPageStore.keys failed: $e');
      return const [];
    }
  }

  /// The handful of IndexedDB calls that hand back a raw request rather than
  /// a future.
  static Future<dynamic> _awaitRequest(idb.Request request) {
    final done = Completer<dynamic>.sync();
    request.onSuccess.listen((_) {
      if (!done.isCompleted) done.complete(request.result);
    });
    request.onError.listen((e) {
      if (!done.isCompleted) done.completeError(e);
    });
    return done.future;
  }

  /// There is no filesystem to point at, so the key is the address.
  @override
  Future<List<String>> resolve(List<String> keys) async => keys;
}

OvernightPageStore createOvernightPageStore({Future<Directory> Function()? documentsDir}) => IndexedDbPageStore();
