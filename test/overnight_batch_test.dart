import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:marking_prokect_v2/models/grading_preset.dart';
import 'package:marking_prokect_v2/models/submission.dart';
import 'package:marking_prokect_v2/services/ai_grading_service.dart';
import 'package:marking_prokect_v2/services/local_store.dart';
import 'package:marking_prokect_v2/services/overnight_service.dart';
import 'package:marking_prokect_v2/services/students_service.dart';
import 'package:marking_prokect_v2/services/submissions_service.dart';

/// Stands in for shared_preferences. Handing the same store to a second
/// service is how "the app was killed and reopened" is written here.
class _MemoryStore implements LocalStore {
  final Map<String, String> values = {};

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async => values[key] = value;

  @override
  Future<void> clear() async => values.clear();
}

/// The server, without the server. Records every poll, so "how many times
/// was this batch asked about" — the thing that used to double-charge — is
/// checkable.
class _FakeApi implements OvernightApi {
  final Map<String, BatchOutcome> outcomes = {};
  final List<String> polls = [];
  Object? throwOnStatus;

  @override
  Future<String> submit({required String teacherId, required List<Map<String, dynamic>> items}) async => 'batch_1';

  @override
  Future<BatchOutcome> status({required String teacherId, required String batchId}) async {
    polls.add(batchId);
    final boom = throwOnStatus;
    if (boom != null) throw boom;
    return outcomes[batchId] ?? const BatchOutcome(status: 'in_progress', results: {}, failures: {}, counts: {});
  }
}

/// A results store that can be told to fail one save, so a paper that could
/// not be written on the first try can be re-tried on the next launch.
class _FlakySubmissions extends SubmissionsService {
  _FlakySubmissions({super.store});

  /// Fails the first save whose feedback contains this text.
  String? failOnceContaining;

  @override
  Future<Submission> create(Submission submission) async {
    final needle = failOnceContaining;
    if (needle != null && submission.feedback.contains(needle)) {
      failOnceContaining = null;
      throw Exception('disk full');
    }
    return super.create(submission);
  }
}

AiGradeResult _result({String? name, String summary = 'ok'}) => AiGradeResult(
      detectedSubject: 'Maths',
      detectedGrade: 9,
      provider: 'claude',
      studentNameOnPaper: name,
      gradingFormat: 'percentage',
      percentage: 80,
      percentageDisplay: '80%',
      level: null,
      levelDisplay: null,
      rawScore: 20,
      maxScore: 25,
      summary: summary,
      strengths: const [],
      improvements: const [],
      criteriaBreakdown: const [],
      annotations: const [],
      rawText: '',
      confidence: 90,
      flags: const [],
      triageStatus: TriageStatus.graded,
    );

OvernightPaper _paper(String id, String label, [List<String> pages = const []]) => OvernightPaper(
      customId: id,
      label: label,
      pagePaths: pages,
      classId: 'class_1',
      presetId: 'preset_1',
      subject: 'Maths',
      mode: GradingMode.testQuiz,
    );

/// A batch written the way an older build of the app wrote it — no record of
/// what has been filed, absolute page paths — so loading one still works.
String _legacyBatchJson({required DateTime submittedAt, String pagePath = ''}) => jsonEncode([
      {
        'batch_id': 'batch_1',
        'teacher_id': 't1',
        'label': 'Year 9 Maths',
        'submitted_at': submittedAt.toIso8601String(),
        'papers': [
          {
            'custom_id': 'a',
            'label': 'Ana',
            'page_paths': [if (pagePath.isNotEmpty) pagePath],
            'class_id': 'class_1',
            'preset_id': 'preset_1',
            'subject': 'Maths',
            'mode': 'testQuiz',
          },
        ],
      },
    ]);

void main() {
  late Directory docs;

  setUp(() async {
    docs = await Directory.systemTemp.createTemp('markless_overnight');
  });

  tearDown(() async {
    if (await docs.exists()) await docs.delete(recursive: true);
  });

  Future<Directory> docsDir() async => docs;

  group('a class set queued at bedtime', () {
    test('survives the app being killed: the batch is read back off disk on the next launch', () async {
      final store = _MemoryStore();
      final api = _FakeApi();

      final tonight = OvernightService(store: store, api: api, documentsDir: docsDir);
      await tonight.init();
      final paths = await tonight.stashPages('ov_1', [Uint8List.fromList([1, 2, 3])]);
      expect(paths, isNotEmpty);
      await tonight.submit(
        teacherId: 't1',
        label: 'Year 9 Maths',
        items: const [{'customId': 'ov_1'}],
        papers: [_paper('ov_1', 'Ana', paths)],
      );

      // The app is killed. Nothing of the old service survives except what
      // it wrote down.
      final morning = OvernightService(store: store, api: api, documentsDir: docsDir);
      await morning.init();

      expect(morning.batches, hasLength(1));
      expect(morning.batches.first.label, 'Year 9 Maths');
      expect(morning.pendingPapers, 1);
      final page = File(morning.batches.first.papers.first.absolutePagePaths(docs).first);
      expect(await page.exists(), isTrue, reason: 'the scans have to still be there in the morning');
    });

    test('survives an app update moving the folder the scans live in', () async {
      final store = _MemoryStore();
      final api = _FakeApi();

      final tonight = OvernightService(store: store, api: api, documentsDir: docsDir);
      await tonight.init();
      final paths = await tonight.stashPages('ov_1', [Uint8List.fromList([1, 2, 3])]);
      await tonight.submit(
        teacherId: 't1',
        label: 'Year 9 Maths',
        items: const [{'customId': 'ov_1'}],
        papers: [_paper('ov_1', 'Ana', paths)],
      );

      // iOS hands the app a new container folder after an update and moves
      // the documents across: same files, different absolute path. The path
      // written down last night no longer points at anything.
      final moved = await Directory.systemTemp.createTemp('markless_overnight_v2');
      await Directory('${moved.path}/overnight/ov_1').create(recursive: true);
      await File('${docs.path}/overnight/ov_1/p0.jpg').copy('${moved.path}/overnight/ov_1/p0.jpg');
      await Directory('${docs.path}/overnight').delete(recursive: true);

      final morning = OvernightService(store: store, api: api, documentsDir: () async => moved);
      await morning.init();
      final page = File(morning.batches.first.papers.first.absolutePagePaths(moved).first);
      expect(await page.exists(), isTrue, reason: 'a phone that updated overnight still has the scans');
      await moved.delete(recursive: true);
    });

    test('a batch written by an older build still loads, scans and all', () async {
      final store = _MemoryStore();
      // The absolute path an older build wrote down, under the container the
      // app no longer has.
      final gone = '/var/mobile/Containers/Data/Application/OLD/Documents/overnight/a/p0.jpg';
      store.values[OvernightService.storageKey] = _legacyBatchJson(submittedAt: DateTime.now(), pagePath: gone);
      await Directory('${docs.path}/overnight/a').create(recursive: true);
      await File('${docs.path}/overnight/a/p0.jpg').writeAsBytes([1, 2, 3]);

      final morning = OvernightService(store: store, api: _FakeApi(), documentsDir: docsDir);
      await morning.init();

      expect(morning.batches, hasLength(1));
      final page = File(morning.batches.first.papers.first.absolutePagePaths(docs).first);
      expect(await page.exists(), isTrue);
    });
  });

  group('checking in the morning', () {
    late _MemoryStore store;
    late _FakeApi api;
    late OvernightService overnight;
    late StudentsService students;
    late _FlakySubmissions submissions;

    Future<void> queue(List<OvernightPaper> papers) => overnight.submit(
          teacherId: 't1',
          label: 'Year 9 Maths',
          items: [for (final p in papers) {'customId': p.customId}],
          papers: papers,
        );

    Future<int> check() => overnight.checkNow(teacherId: 't1', students: students, submissions: submissions);

    setUp(() async {
      store = _MemoryStore();
      api = _FakeApi();
      overnight = OvernightService(store: store, api: api, documentsDir: docsDir);
      await overnight.init();
      students = StudentsService(store: _MemoryStore());
      submissions = _FlakySubmissions(store: _MemoryStore());
    });

    test('a paper that cannot be saved does not stop the others, and is not saved twice on the retry', () async {
      await queue([_paper('a', 'Ana'), _paper('b', 'Ben'), _paper('c', 'Cara')]);
      api.outcomes['batch_1'] = BatchOutcome(
        status: 'ended',
        results: {'a': _result(summary: 'A'), 'b': _result(summary: 'B'), 'c': _result(summary: 'C')},
        failures: const {},
        counts: const {},
      );
      submissions.failOnceContaining = 'B';

      expect(await check(), 2, reason: "Ben failing must not cost Cara her mark");
      expect(overnight.batches, hasLength(1), reason: 'Ben is still owed a mark, so the batch stays');

      expect(await check(), 1);
      expect(submissions.submissions, hasLength(3), reason: 'Ana and Cara must not land in the gradebook twice');
      expect(submissions.submissions.map((s) => s.feedback).toSet(), {'A', 'B', 'C'});
      expect(overnight.batches, isEmpty);
    });

    test('a half-filed batch that is killed mid-save picks up where it left off', () async {
      await queue([_paper('a', 'Ana'), _paper('b', 'Ben')]);
      api.outcomes['batch_1'] = BatchOutcome(
        status: 'ended',
        results: {'a': _result(summary: 'A'), 'b': _result(summary: 'B')},
        failures: const {},
        counts: const {},
      );
      submissions.failOnceContaining = 'B';
      await check();

      // Killed after Ana was filed. A fresh service, same disk.
      final reopened = OvernightService(store: store, api: api, documentsDir: docsDir);
      await reopened.init();
      expect(await reopened.checkNow(teacherId: 't1', students: students, submissions: submissions), 1);
      expect(submissions.submissions, hasLength(2));
    });

    test('the papers that came back are filed, and the ones that did not are reported rather than dropped', () async {
      await queue([_paper('a', 'Ana'), _paper('b', 'Ben'), _paper('c', 'Cara')]);
      api.outcomes['batch_1'] = BatchOutcome(
        status: 'ended',
        results: {'a': _result(summary: 'A'), 'c': _result(summary: 'C')},
        failures: const {'b': 'expired'},
        counts: const {},
      );

      expect(await check(), 2);
      expect(overnight.lastReport?.filed, 2);
      expect(overnight.lastReport?.unfinished, ['Ben'], reason: 'the teacher has to be told which paper is missing');
      expect(overnight.batches, isEmpty, reason: 'it is not still marking, so stop saying it is');
      expect(overnight.needsAttention, hasLength(1), reason: "Ben's scan is kept, not thrown away");
      expect(overnight.needsAttention.first.failures.keys, contains('b'));
    });

    test('a settled batch is never polled — or billed — again', () async {
      await queue([_paper('a', 'Ana')]);
      api.outcomes['batch_1'] = BatchOutcome(
        status: 'ended',
        results: {'a': _result(summary: 'A')},
        failures: const {},
        counts: const {},
      );

      await check();
      await check();
      await check();
      expect(api.polls, hasLength(1), reason: 'polling an ended batch again is what used to double-charge');
      expect(submissions.submissions, hasLength(1));
    });

    test('no network at 3am loses nothing — the batch is still there to check again', () async {
      await queue([_paper('a', 'Ana')]);
      api.throwOnStatus = Exception('SocketException: no route to host');

      expect(await check(), 0);
      expect(overnight.batches, hasLength(1));
      expect(overnight.needsAttention, isEmpty, reason: 'a phone with no signal is not a failed batch');

      api.throwOnStatus = null;
      api.outcomes['batch_1'] = BatchOutcome(
        status: 'ended',
        results: {'a': _result(summary: 'A')},
        failures: const {},
        counts: const {},
      );
      expect(await check(), 1);
    });

    test('a batch still marking after its 24 hours are up stops promising marks in the morning', () async {
      store.values[OvernightService.storageKey] =
          _legacyBatchJson(submittedAt: DateTime.now().subtract(const Duration(hours: 40)));
      await overnight.init();
      api.outcomes['batch_1'] = const BatchOutcome(status: 'in_progress', results: {}, failures: {}, counts: {});

      await check();
      expect(overnight.batches, isEmpty, reason: 'the card must stop saying "marking overnight" forever');
      expect(overnight.needsAttention, hasLength(1));
      expect(overnight.lastReport?.unfinished, ['Ana']);
    });

    test('a batch still marking inside its window is left alone', () async {
      await queue([_paper('a', 'Ana')]);
      api.outcomes['batch_1'] = const BatchOutcome(status: 'in_progress', results: {}, failures: {}, counts: {});

      await check();
      expect(overnight.batches, hasLength(1));
      expect(overnight.lastReport?.stillMarking, isTrue);
    });

    test('another teacher signed in on this phone does not see, or poll, this set', () async {
      await queue([_paper('a', 'Ana')]);
      final filed = await overnight.checkNow(teacherId: 't2', students: students, submissions: submissions);
      expect(filed, 0);
      expect(api.polls, isEmpty);
      expect(submissions.submissions, isEmpty);
    });

    test('the marks land on the student the name says', () async {
      final ana = await students.create(teacherId: 't1', classId: 'class_1', name: 'Ana Silva', studentId: 'S1');
      await students.create(teacherId: 't1', classId: 'class_1', name: 'Ben Ito', studentId: 'S2');
      await queue([_paper('a', 'Ana')]);
      api.outcomes['batch_1'] = BatchOutcome(
        status: 'ended',
        results: {'a': _result(name: 'Ana Silva', summary: 'A')},
        failures: const {},
        counts: const {},
      );

      await check();
      expect(submissions.submissions.single.studentId, ana.id);
    });

    test('a filed paper keeps a working path to its scan', () async {
      final paths = await overnight.stashPages('a', [Uint8List.fromList([1, 2, 3])]);
      await queue([_paper('a', 'Ana', paths)]);
      api.outcomes['batch_1'] = BatchOutcome(
        status: 'ended',
        results: {'a': _result(summary: 'A')},
        failures: const {},
        counts: const {},
      );

      await check();
      final saved = submissions.submissions.single.pageImagePaths.single;
      expect(await File(saved).exists(), isTrue);
    });
  });
}
