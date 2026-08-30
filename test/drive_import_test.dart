import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:marking_prokect_v2/app/app_state.dart';
import 'package:marking_prokect_v2/services/drive_picker.dart';

Uint8List _b(int n) => Uint8List.fromList([n]);

List<PickedDriveFile> _files(int count) =>
    [for (var i = 0; i < count; i++) PickedDriveFile(name: 'test$i.pdf', bytes: _b(i))];

/// Stands in for the real render-and-clean pass, which is the slow part.
Future<({List<ScannedPage> pages, bool truncated})> _onePagePerFile(PickedDriveFile f) async =>
    (pages: [ScannedPage(bytes: f.bytes!, fileName: f.name)], truncated: false);

void main() {
  group('turning picked Drive files into pages', () {
    test('gives every file its own group, so one PDF per student stays one test', () async {
      final result = await convertPickedDriveFiles(
        _files(3),
        picked: 3,
        convert: _onePagePerFile,
      );

      expect(result.fileGroups.length, 3);
      expect(result.pages.length, 3);
      expect(result.unreadable, 0);
      expect(result.cancelled, isFalse);
    });

    test('says how many files there are before it starts, then counts them off', () async {
      // The leading (0, 3) is what lets the dialog stop saying "Loading from
      // Google Drive…" and start saying "file 1 of 3" the moment it can.
      final seen = <(int, int)>[];
      await convertPickedDriveFiles(
        _files(3),
        picked: 3,
        convert: _onePagePerFile,
        onProgress: (done, total) => seen.add((done, total)),
      );

      expect(seen, [(0, 3), (1, 3), (2, 3), (3, 3)]);
    });

    test('stops when the teacher stops, and keeps the files already read', () async {
      var converted = 0;
      var stop = false;
      final result = await convertPickedDriveFiles(
        _files(12),
        picked: 12,
        convert: (f) async {
          converted++;
          if (converted == 2) stop = true;
          return _onePagePerFile(f);
        },
        isCancelled: () => stop,
      );

      expect(converted, 2, reason: 'stopping must not read the other ten');
      expect(result.fileGroups.length, 2, reason: 'the two already read are still worth marking');
      // The eight never opened are not failures — nothing went wrong with them.
      expect(result.unreadable, 0);
    });

    test('names the file that could not be read and carries on with the rest', () async {
      final result = await convertPickedDriveFiles(
        [
          const PickedDriveFile(name: 'good.pdf', bytes: null),
          PickedDriveFile(name: 'ok.jpg', bytes: _b(1)),
        ],
        picked: 2,
        convert: (f) async => f.bytes == null
            ? (pages: const <ScannedPage>[], truncated: false)
            : await _onePagePerFile(f),
      );

      expect(result.unreadableNames, ['good.pdf']);
      expect(result.unreadable, 1);
      expect(result.fileGroups.length, 1);
    });

    test('counts files the phone never streamed at all as unreadable', () async {
      // Three picked in Drive, only two arrived over the channel.
      final result = await convertPickedDriveFiles(
        _files(2),
        picked: 3,
        convert: _onePagePerFile,
      );

      expect(result.unreadable, 1);
      expect(result.cancelled, isFalse);
    });
  });
}
