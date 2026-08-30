import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marking_prokect_v2/app/app_state.dart' show ScannedPage;
import 'package:marking_prokect_v2/services/bulk_page_processor.dart';
import 'package:marking_prokect_v2/services/dropped_intake.dart';

Uint8List _jpeg() => Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 16, 74, 70, 73, 70, 0, 1]);
Uint8List _pdf() => Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34, 10, 10, 10, 10]);
Uint8List _junk() => Uint8List.fromList(List.filled(64, 7));

DroppedFile _f(String name, String mime, [Uint8List? bytes]) =>
    DroppedFile(name: name, mime: mime, bytes: bytes ?? _junk());

ScannedPage _page(String name) => ScannedPage(bytes: _jpeg(), fileName: name);

void main() {
  group('what a teacher can actually drop on the window', () {
    test('keeps the photos and PDFs, drops the rest of the folder', () {
      final kept = markableDrops([
        _f('scan1.jpg', 'image/jpeg', _jpeg()),
        _f('scan2.PNG', 'image/png', _jpeg()),
        _f('class set.pdf', 'application/pdf', _pdf()),
        _f('marks.xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
        _f('notes.zip', 'application/zip'),
        _f('.DS_Store', ''),
      ]);

      expect(kept.map((f) => f.name), ['scan1.jpg', 'scan2.PNG', 'class set.pdf']);
    });

    test('a photo saved without an extension is still a photo', () {
      // Drive and some scanners hand over a JPEG named "scan" with no
      // extension and a generic type. Refusing it looks like a broken app.
      final kept = markableDrops([_f('scan', 'application/octet-stream', _jpeg())]);
      expect(kept, hasLength(1));
    });

    test('an empty file is skipped rather than sent up as a blank page', () {
      final kept = markableDrops([
        DroppedFile(name: 'empty.jpg', mime: 'image/jpeg', bytes: Uint8List(0)),
      ]);
      expect(kept, isEmpty);
    });

    test('knows a PDF so its pages can be rendered before marking', () {
      expect(_f('a.pdf', 'application/pdf', _pdf()).isPdf, isTrue);
      expect(_f('a', '', _pdf()).isPdf, isTrue);
      expect(_f('a.jpg', 'image/jpeg', _jpeg()).isPdf, isFalse);
    });
  });

  group('a drop lands in the same shape a gallery pick does', () {
    test('bytes and names come through untouched', () {
      final photos = photosFromDrop([
        _f('scan1.jpg', 'image/jpeg', _jpeg()),
        _f('scan2.jpg', 'image/jpeg', _jpeg()),
      ]);

      expect(photos, isA<List<PickedPhoto>>());
      expect(photos.map((p) => p.fileName), ['scan1.jpg', 'scan2.jpg']);
      expect(photos.first.bytes, _jpeg());
    });

    test('dropping a folder of 300 scans is warned about and capped, not crashed', () {
      final dropped = [for (var i = 0; i < 300; i++) _f('scan$i.jpg', 'image/jpeg', _jpeg())];
      final photos = photosFromDrop(markableDrops(dropped));

      expect(bulkPickWarning(photos.length), contains('300'));
      expect(capPicked(photos).length, kMaxGalleryPhotos);
    });
  });

  group('a pasted screenshot', () {
    test('gets a name that says where it came from, with the right extension', () {
      final at = DateTime(2026, 8, 30, 14, 32, 5);
      expect(pastedFileName('image/png', at), 'Pasted 14-32-05.png');
      expect(pastedFileName('image/jpeg', at), 'Pasted 14-32-05.jpg');
      // Unknown or missing type: still an image, still openable.
      expect(pastedFileName('', at), 'Pasted 14-32-05.png');
    });

    test('two pastes a second apart do not share a name', () {
      final a = pastedFileName('image/png', DateTime(2026, 8, 30, 14, 32, 5));
      final b = pastedFileName('image/png', DateTime(2026, 8, 30, 14, 32, 6));
      expect(a, isNot(b));
    });
  });

  group('keeping one student\'s pages together', () {
    test('a photo per student stays a student per photo', () {
      final groups = groupPagesBySourceFile([_page('a.jpg'), _page('b.jpg'), _page('c.jpg')]);
      expect(groups.map((g) => g.length), [1, 1, 1]);
    });

    test('the pages of one dropped PDF are marked as one paper', () {
      final groups = groupPagesBySourceFile([
        _page('ana.pdf (page 1)'),
        _page('ana.pdf (page 2)'),
        _page('ben.pdf (page 1)'),
      ]);

      expect(groups, hasLength(2));
      expect(groups.first.map((p) => p.fileName), ['ana.pdf (page 1)', 'ana.pdf (page 2)']);
      expect(groups.last.single.fileName, 'ben.pdf (page 1)');
    });

    test('a photo sitting between two PDF pages does not join them up', () {
      final groups = groupPagesBySourceFile([
        _page('ana.pdf (page 1)'),
        _page('snap.jpg'),
        _page('ana.pdf (page 2)'),
      ]);

      expect(groups.map((g) => g.length), [1, 1, 1]);
    });

    test('nothing prepared is no groups, not one empty one', () {
      expect(groupPagesBySourceFile(const []), isEmpty);
    });
  });
}
