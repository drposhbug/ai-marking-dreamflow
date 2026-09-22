import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marking_prokect_v2/app/app_state.dart';
import 'package:marking_prokect_v2/models/ai_marker_user.dart';
import 'package:marking_prokect_v2/models/grading_preset.dart';
import 'package:marking_prokect_v2/services/ai_grading_service.dart';
import 'package:marking_prokect_v2/services/auth_service.dart';
import 'package:marking_prokect_v2/services/batch_marking.dart';
import 'package:marking_prokect_v2/services/grading_queue_service.dart';
import 'package:marking_prokect_v2/services/local_store.dart';
import 'package:marking_prokect_v2/services/overnight_page_store.dart';
import 'package:marking_prokect_v2/services/overnight_page_store_native.dart';
import 'package:marking_prokect_v2/services/overnight_service.dart';
import 'package:marking_prokect_v2/services/students_service.dart';
import 'package:marking_prokect_v2/services/submissions_service.dart';
import 'package:provider/provider.dart';

class _MemoryStore implements LocalStore {
  final Map<String, String> values = {};

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async => values[key] = value;

  @override
  Future<void> clear() async => values.clear();
}

/// A page store with no disk and no browser behind it — what every one of
/// these tests uses in place of IndexedDB, which cannot be run off a real
/// browser. It keeps the two properties the rest of the app depends on:
/// the keys it hands back are relative, and it can be told to refuse a
/// write the way an origin over its quota does.
class _MemoryPageStore implements OvernightPageStore {
  final Map<String, Uint8List> blobs = {};

  /// The browser has no room left. Every write from here on is refused.
  bool full = false;

  @override
  bool keepsFiledPages;

  _MemoryPageStore({this.keepsFiledPages = true});

  @override
  Future<List<String>> write(String customId, List<Uint8List> pages) async {
    if (full) throw const PageStoreFull('no room');
    final out = <String>[];
    for (var i = 0; i < pages.length; i++) {
      final key = 'overnight/$customId/p$i.jpg';
      blobs[key] = pages[i];
      out.add(key);
    }
    return out;
  }

  @override
  Future<void> discard(String customId) async =>
      blobs.removeWhere((k, _) => k.startsWith('overnight/$customId/'));

  @override
  Future<Uint8List?> read(String key) async => blobs[key];

  @override
  Future<List<String>> keys() async => blobs.keys.toList();

  @override
  Future<List<String>> resolve(List<String> keys) async => keys;
}

class _FakeApi implements OvernightApi {
  final List<List<Map<String, dynamic>>> submitted = [];

  @override
  Future<String> submit({required String teacherId, required List<Map<String, dynamic>> items}) async {
    submitted.add(items);
    return 'batch_${submitted.length}';
  }

  @override
  Future<BatchOutcome> status({required String teacherId, required String batchId}) async =>
      const BatchOutcome(status: 'in_progress', results: {}, failures: {}, counts: {});
}

AiGradeRequest _req() => AiGradeRequest(
      teacherId: 't1',
      studentId: '',
      classId: 'class_1',
      presetId: 'preset_1',
      subject: 'Maths',
      mode: GradingMode.testQuiz,
      criteria: const {},
      harshness: 5,
      notes: null,
      overrideUsed: false,
      imageBytes: Uint8List.fromList([1, 2, 3]),
      pageImages: [Uint8List.fromList([1, 2, 3])],
    );

/// The tray, with a class set held in it waiting on the teacher's OK — the
/// state the overnight button is pressed from.
///
/// The pilot paper is left marking forever on purpose: the set is only ever
/// released by the teacher, and holding the pilot open keeps this test about
/// what happens to the held papers.
Future<GradingQueueService> _queueHolding(WidgetTester tester, int papers) async {
  final queue = GradingQueueService(grader: (_) => Completer<AiGradeResult>().future);
  queue.confirmFleet = (_, __) async => false;
  final students = StudentsService(store: _MemoryStore());
  final submissions = SubmissionsService(store: _MemoryStore());
  unawaited(queue.enqueueBatch(
    reqs: [for (var i = 0; i <= papers; i++) _req()],
    pagesList: [for (var i = 0; i <= papers; i++) [Uint8List.fromList([i + 1])]],
    labels: [for (var i = 0; i <= papers; i++) 'Paper ${i + 1}'],
    students: students,
    submissions: submissions,
  ));
  await tester.pump();
  return queue;
}

/// Presses the overnight button, in effect: runs [sendHeldOvernight] against
/// a real provider tree, the way the pilot review screen does.
Future<Object?> _sendOvernight({
  required WidgetTester tester,
  required GradingQueueService queue,
  required OvernightService overnight,
  required AppState app,
}) async {
  final store = _MemoryStore();
  store.values['ai_marker.current_user'] = jsonEncode(AiMarkerUser(
    id: 't1',
    email: 'teacher@example.com',
    name: 'Lee',
    school: 'School',
    title: 'Teacher',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  ).toJson());
  final auth = AuthService(store: store);
  // Reading the saved account back goes through a real isolate, which only
  // runs outside the fake clock a widget test lives in.
  await tester.runAsync(auth.init);
  expect(auth.currentUser, isNotNull, reason: 'the harness itself has to be signed in');

  late BuildContext ctx;
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthService>.value(value: auth),
      ChangeNotifierProvider<GradingQueueService>.value(value: queue),
      ChangeNotifierProvider<OvernightService>.value(value: overnight),
      ChangeNotifierProvider<AppState>.value(value: app),
    ],
    child: MaterialApp(
      home: Builder(builder: (context) {
        ctx = context;
        return const Scaffold(body: SizedBox.shrink());
      }),
    ),
  ));

  try {
    return await sendHeldOvernight(context: ctx, label: 'Year 9 Maths');
  } catch (e) {
    return e;
  }
}

void main() {
  group('where a queued class set keeps its scans', () {
    late Directory docs;

    setUp(() async => docs = await Directory.systemTemp.createTemp('markless_pages'));
    tearDown(() async {
      if (await docs.exists()) await docs.delete(recursive: true);
    });

    test('the pages go in and come back out as the same bytes', () async {
      final store = FilePageStore(documentsDir: () async => docs);
      final keys = await store.write('ov_1', [
        Uint8List.fromList([1, 2, 3]),
        Uint8List.fromList([9, 9]),
      ]);

      expect(keys, ['overnight/ov_1/p0.jpg', 'overnight/ov_1/p1.jpg']);
      expect(await store.read(keys.first), [1, 2, 3]);
      expect(await store.read(keys.last), [9, 9]);
    });

    test('the keys written down are relative, so an app update that moves the folder loses nothing', () async {
      final store = FilePageStore(documentsDir: () async => docs);
      final keys = await store.write('ov_1', [Uint8List.fromList([1, 2, 3])]);
      expect(keys.single.startsWith('overnight/'), isTrue, reason: 'an absolute path points nowhere after an update');

      // iOS hands the app a new container and moves the documents across.
      final moved = await Directory.systemTemp.createTemp('markless_pages_v2');
      await Directory('${moved.path}/overnight/ov_1').create(recursive: true);
      await File('${docs.path}/overnight/ov_1/p0.jpg').copy('${moved.path}/overnight/ov_1/p0.jpg');

      final afterUpdate = FilePageStore(documentsDir: () async => moved);
      expect(await afterUpdate.read(keys.single), [1, 2, 3]);
      expect((await afterUpdate.resolve(keys)).single, '${moved.path}/overnight/ov_1/p0.jpg');
      await moved.delete(recursive: true);
    });

    test('discarding a paper takes its pages with it', () async {
      final store = FilePageStore(documentsDir: () async => docs);
      final keys = await store.write('ov_1', [Uint8List.fromList([1, 2, 3])]);
      await store.write('ov_2', [Uint8List.fromList([4])]);

      await store.discard('ov_1');

      expect(await store.read(keys.single), isNull);
      expect(await store.keys(), ['overnight/ov_2/p0.jpg'], reason: 'the other paper must not be collateral');
    });
  });

  group('the service does not care which platform it got', () {
    test('stashing and discarding go through the store it was given', () async {
      final pages = _MemoryPageStore();
      final overnight = OvernightService(store: _MemoryStore(), api: _FakeApi(), pages: pages);

      final keys = await overnight.stashPages('ov_1', [Uint8List.fromList([7])]);
      expect(keys, ['overnight/ov_1/p0.jpg']);
      expect(pages.blobs, hasLength(1));

      await overnight.discardStash('ov_1');
      expect(pages.blobs, isEmpty);
    });

    test('a store with no room says so rather than quietly writing nothing', () async {
      final pages = _MemoryPageStore()..full = true;
      final overnight = OvernightService(store: _MemoryStore(), api: _FakeApi(), pages: pages);

      expect(() => overnight.stashPages('ov_1', [Uint8List.fromList([7])]), throwsA(isA<PageStoreFull>()));
    });

    test('a store that cannot be read back loses the scans once the set is filed', () async {
      // A browser: nothing in it ever reopens a marked paper's scan, so
      // holding on to thirty of them is site data the teacher never gets
      // back. On a phone they stay, which the other overnight tests check.
      final pages = _MemoryPageStore(keepsFiledPages: false);
      final local = _MemoryStore();
      final api = _FakeApi();
      final overnight = OvernightService(store: local, api: api, pages: pages);
      await overnight.init();
      final keys = await overnight.stashPages('ov_1', [Uint8List.fromList([7])]);
      await overnight.submit(
        teacherId: 't1',
        label: 'Year 9 Maths',
        items: const [{'customId': 'ov_1'}],
        papers: [
          OvernightPaper(
            customId: 'ov_1',
            label: 'Ana',
            pagePaths: keys,
            classId: 'class_1',
            presetId: 'preset_1',
            subject: 'Maths',
            mode: GradingMode.testQuiz,
          ),
        ],
      );

      await overnight.forget('batch_1');
      expect(pages.blobs, isEmpty, reason: 'a set the teacher dropped must not sit in storage forever');
    });

    test('scans no batch is waiting on any more are swept up on the next launch', () async {
      final pages = _MemoryPageStore(keepsFiledPages: false);
      await pages.write('ov_orphan', [Uint8List.fromList([7])]);

      final overnight = OvernightService(store: _MemoryStore(), api: _FakeApi(), pages: pages);
      await overnight.init();

      expect(pages.blobs, isEmpty);
    });
  });

  group('sending the tray off for the night', () {
    late AppState app;

    setUp(() async {
      app = AppState(store: _MemoryStore());
      // Redaction runs the on-device text recogniser, which needs a phone.
      // It is tested where it belongs; this is about where the pages go.
      await app.setAnonymizeUploads(teacherId: 't1', on: false);
    });

    testWidgets('with somewhere to put the scans, the held papers go', (tester) async {
      final queue = await _queueHolding(tester, 3);
      expect(queue.heldJobs, hasLength(3));
      final pages = _MemoryPageStore();
      final api = _FakeApi();
      final overnight = OvernightService(store: _MemoryStore(), api: api, pages: pages);
      await overnight.init();

      final outcome = await _sendOvernight(tester: tester, queue: queue, overnight: overnight, app: app);

      expect(outcome, 3);
      expect(api.submitted.single, hasLength(3));
      expect(queue.heldJobs, isEmpty, reason: 'the batch owns those papers now');
      expect(overnight.pendingPapers, 3);
      expect(pages.blobs, hasLength(3), reason: 'every paper\'s scan has to still be there in the morning');
    });

    testWidgets('a browser with no room left keeps every paper in the tray and says why', (tester) async {
      final queue = await _queueHolding(tester, 3);
      final pages = _MemoryPageStore()..full = true;
      final api = _FakeApi();
      final overnight = OvernightService(store: _MemoryStore(), api: api, pages: pages);
      await overnight.init();

      final outcome = await _sendOvernight(tester: tester, queue: queue, overnight: overnight, app: app);

      expect(outcome, isA<PageStoreFull>());
      expect(api.submitted, isEmpty, reason: 'nothing may be sent that cannot be filed in the morning');
      expect(queue.heldJobs, hasLength(3), reason: 'a paper the teacher handed over must not vanish');
      expect(pages.blobs, isEmpty, reason: 'a set that never went leaves nothing behind');
      expect('$outcome', isNot(contains('Exception')), reason: 'this message is shown to a teacher');
    });
  });
}
