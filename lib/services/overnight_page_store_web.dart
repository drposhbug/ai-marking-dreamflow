import 'dart:async';
// The conditional-import shape browser_intake_web.dart and
// web_image_picker_web.dart already use: these files only ever compile for
// the browser, and a second style here would be one more thing to keep in
// step for no gain.
import 'dart:js_interop';
// Only for the type in the factory below. Nothing here ever builds one — a
// browser has no documents folder, which is the whole reason this file
// exists.
import 'dart:io' show Directory;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:marking_prokect_v2/services/overnight_page_store.dart';
import 'package:web/web.dart' as web;

const _dbName = 'markless_overnight';
const _pages = 'pages';

/// The browser's own durable storage, which is where a class set's scans
/// wait when UMarkless is a tab rather than an app.
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
  Future<web.IDBDatabase>? _opening;

  Future<web.IDBDatabase> _db() => _opening ??= () async {
        final request = web.window.indexedDB.open(_dbName, 1);
        request.onupgradeneeded = ((web.Event _) {
          final db = request.result as web.IDBDatabase;
          if (!db.objectStoreNames.contains(_pages)) db.createObjectStore(_pages);
        }).toJS;
        return await _awaitRequest(request) as web.IDBDatabase;
      }();

  /// The result screen reopens a marked paper's scan from here, exactly as
  /// a phone reopens it from disk — it used to read only real files, so on
  /// the web the Original and Annotated tabs were always empty. A filed
  /// paper's pages now stay until its result is deleted, which discards
  /// them (SubmissionsService.delete).
  @override
  bool get keepsFiledPages => true;

  @override
  Future<List<String>> write(String customId, List<Uint8List> pages) async {
    final keys = <String>[];
    try {
      final db = await _db();
      final txn = db.transaction(_pages.toJS, 'readwrite');
      final store = txn.objectStore(_pages);
      final done = _awaitTransaction(txn);
      // Every page is asked for in this one turn of the event loop and only
      // then waited on. Awaiting them one at a time lets the browser close
      // the transaction underneath us between pages.
      final writes = <Future<JSAny?>>[];
      for (var i = 0; i < pages.length; i++) {
        final key = 'overnight/$customId/p$i.jpg';
        writes.add(_awaitRequest(store.put(pages[i].toJS, key.toJS)));
        keys.add(key);
      }
      await Future.wait(writes);
      await done;
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
  /// IndexedDB reports a failure by firing at the request or transaction;
  /// the waits below turn that into an [_IdbFailure] carrying its name.
  static bool _outOfRoom(Object e) {
    final name = e is _IdbFailure ? e.name : '';
    if (name == 'QuotaExceededError' || name == 'NS_ERROR_DOM_QUOTA_REACHED') return true;
    return '$e'.toLowerCase().contains('quota');
  }

  @override
  Future<void> discard(String customId) async {
    try {
      final db = await _db();
      final txn = db.transaction(_pages.toJS, 'readwrite');
      // Every page of one paper in a single delete: they all sort together
      // under the paper's own prefix.
      final prefix = 'overnight/$customId/';
      final done = _awaitTransaction(txn);
      await _awaitRequest(txn.objectStore(_pages).delete(web.IDBKeyRange.bound(prefix.toJS, '$prefix￿'.toJS)));
      await done;
    } catch (e) {
      debugPrint('IndexedDbPageStore.discard failed: $e');
    }
  }

  @override
  Future<Uint8List?> read(String key) async {
    try {
      final db = await _db();
      final value = await _awaitRequest(db.transaction(_pages.toJS, 'readonly').objectStore(_pages).get(key.toJS));
      if (value == null) return null;
      // Pages go in as a Uint8Array; an ArrayBuffer is read too, in case
      // anything ever stored one.
      if (value.isA<JSUint8Array>()) return (value as JSUint8Array).toDart;
      if (value.isA<JSArrayBuffer>()) return (value as JSArrayBuffer).toDart.asUint8List();
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
      final store = db.transaction(_pages.toJS, 'readonly').objectStore(_pages);
      // Keys only. Walking a cursor would drag every page's bytes back out
      // of the database just to find out what is in there.
      final result = await _awaitRequest(store.getAllKeys());
      final out = [for (final k in (result.dartify() as List? ?? const [])) k.toString()];
      out.sort();
      return out;
    } catch (e) {
      debugPrint('IndexedDbPageStore.keys failed: $e');
      return const [];
    }
  }

  /// Every IndexedDB call hands back a raw request rather than a future.
  static Future<JSAny?> _awaitRequest(web.IDBRequest request) {
    final done = Completer<JSAny?>.sync();
    request.onsuccess = ((web.Event _) {
      if (!done.isCompleted) done.complete(request.result);
    }).toJS;
    request.onerror = ((web.Event _) {
      if (!done.isCompleted) done.completeError(_IdbFailure.from(request.error));
    }).toJS;
    return done.future;
  }

  /// A write is only kept once its transaction completes, and running out of
  /// room often shows up here, as an abort, rather than on any one request.
  static Future<void> _awaitTransaction(web.IDBTransaction txn) {
    final done = Completer<void>.sync();
    txn.oncomplete = ((web.Event _) {
      if (!done.isCompleted) done.complete();
    }).toJS;
    void fail(web.Event _) {
      if (!done.isCompleted) done.completeError(_IdbFailure.from(txn.error));
    }

    txn.onerror = fail.toJS;
    txn.onabort = fail.toJS;
    return done.future;
  }

  /// There is no filesystem to point at, so the key is the address.
  @override
  Future<List<String>> resolve(List<String> keys) async => keys;
}

OvernightPageStore createOvernightPageStore({Future<Directory> Function()? documentsDir}) => IndexedDbPageStore();

/// An IndexedDB failure, named the way the browser named it.
class _IdbFailure implements Exception {
  _IdbFailure(this.name, this.message);

  factory _IdbFailure.from(web.DOMException? error) =>
      _IdbFailure(error?.name ?? 'UnknownError', error?.message ?? '');

  final String name;
  final String message;

  @override
  String toString() => 'IndexedDB $name: $message';
}
