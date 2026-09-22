import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:marking_prokect_v2/services/overnight_page_store.dart';
import 'package:path_provider/path_provider.dart';

/// The phone's own documents folder, which is where a class set's scans have
/// always waited for the morning.
///
/// The documents folder, not the temporary one: the OS is free to empty the
/// temporary folder whenever it wants space back, and it would be doing
/// exactly that overnight while the app sits closed.
class FilePageStore implements OvernightPageStore {
  final Future<Directory> Function() _documentsDir;

  FilePageStore({Future<Directory> Function()? documentsDir})
      : _documentsDir = documentsDir ?? getApplicationDocumentsDirectory;

  /// A marked paper's scan is reopened from the result screen, so filing it
  /// is not a reason to throw the pages away.
  @override
  bool get keepsFiledPages => true;

  @override
  Future<List<String>> write(String customId, List<Uint8List> pages) async {
    final root = await _documentsDir();
    final dir = Directory('${root.path}/overnight/$customId');
    try {
      await dir.create(recursive: true);
      final keys = <String>[];
      for (var i = 0; i < pages.length; i++) {
        await File('${dir.path}/p$i.jpg').writeAsBytes(pages[i], flush: true);
        keys.add('overnight/$customId/p$i.jpg');
      }
      return keys;
    } catch (e) {
      // Half a paper is no use to anyone, least of all on a phone that has
      // just run out of room.
      await discard(customId);
      // Out of storage is the one failure worth naming: the teacher can
      // clear some space and try again tonight.
      if (e is FileSystemException && _outOfSpace(e)) {
        throw const PageStoreFull(
            'This phone is out of storage, so there\'s nowhere to keep the scans until morning. Free some space and try again.');
      }
      rethrow;
    }
  }

  /// No error code means "disk full" on every platform, so the message is
  /// what there is to go on.
  static bool _outOfSpace(FileSystemException e) {
    final text = '${e.osError?.message ?? ''} ${e.message}'.toLowerCase();
    return text.contains('no space') || text.contains('not enough space') || text.contains('disk is full');
  }

  @override
  Future<void> discard(String customId) async {
    try {
      final dir = Directory('${(await _documentsDir()).path}/overnight/$customId');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('FilePageStore.discard failed: $e');
    }
  }

  @override
  Future<Uint8List?> read(String key) async {
    try {
      final file = File('${(await _documentsDir()).path}/$key');
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } catch (e) {
      debugPrint('FilePageStore.read failed: $e');
      return null;
    }
  }

  @override
  Future<List<String>> keys() async {
    try {
      final root = (await _documentsDir()).path.replaceAll('\\', '/');
      final dir = Directory('$root/overnight');
      if (!await dir.exists()) return const [];
      final out = <String>[];
      await for (final entity in dir.list(recursive: true)) {
        if (entity is! File) continue;
        final path = entity.path.replaceAll('\\', '/');
        out.add(path.startsWith('$root/') ? path.substring(root.length + 1) : path);
      }
      out.sort();
      return out;
    } catch (e) {
      debugPrint('FilePageStore.keys failed: $e');
      return const [];
    }
  }

  @override
  Future<List<String>> resolve(List<String> keys) async {
    try {
      final root = await _documentsDir();
      return [for (final k in keys) '${root.path}/$k'];
    } catch (e) {
      // A phone that cannot say where its documents folder is must not cost
      // the teacher the mark as well. File it with what we have.
      debugPrint('FilePageStore.resolve failed: $e');
      return keys;
    }
  }
}

OvernightPageStore createOvernightPageStore({Future<Directory> Function()? documentsDir}) =>
    FilePageStore(documentsDir: documentsDir);
