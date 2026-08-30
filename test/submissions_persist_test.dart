import 'package:flutter_test/flutter_test.dart';
import 'package:marking_prokect_v2/models/grading_preset.dart';
import 'package:marking_prokect_v2/models/submission.dart';
import 'package:marking_prokect_v2/services/local_store.dart';
import 'package:marking_prokect_v2/services/submissions_service.dart';

/// Saving marked work has to stay cheap as a teacher's year fills up.
///
/// Every result carries its annotations and the text read off the page, and
/// the whole lot lives in one string on the phone. A class set finishing used
/// to rewrite that whole string thirty times over — by March that is seconds
/// of the app locking up at the exact moment she is watching it save.
class _CountingStore implements LocalStore {
  final data = <String, String>{};
  final writes = <String, int>{};
  @override
  Future<String?> getString(String key) async => data[key];
  @override
  Future<void> setString(String key, String value) async {
    data[key] = value;
    writes[key] = (writes[key] ?? 0) + 1;
  }

  @override
  Future<void> clear() async => data.clear();
}

const _kKey = 'ai_marker.submissions';

Submission _sub(String id, {double score = 10}) {
  final at = DateTime(2026, 3, 1);
  return Submission(
    id: id,
    teacherId: 't1',
    studentId: 'stu_$id',
    classId: 'c1',
    presetId: GradingPreset.builtInTestId,
    subject: 'Science',
    gradingMode: GradingMode.testQuiz,
    score: score,
    maxScore: 20,
    feedback: 'Solid.',
    triageStatus: TriageStatus.graded,
    overrideUsed: false,
    triageFlags: const [],
    confidence: 90,
    createdAt: at,
    updatedAt: at,
    resultJson: {'rawText': 'a page of writing', 'annotations': []},
  );
}

void main() {
  group('filing a whole class set at once', () {
    test('writes to the phone once, not once per student', () async {
      final store = _CountingStore();
      final service = SubmissionsService(store: store);

      await service.createAll([for (var i = 0; i < 30; i++) _sub('s$i')]);

      expect(store.writes[_kKey], 1);
      expect(service.submissions.length, 30);
    });

    test('every student in the batch is on disk, readable next launch', () async {
      final store = _CountingStore();
      await SubmissionsService(store: store).createAll([_sub('a'), _sub('b'), _sub('c')]);

      final onDisk = Submission.decodeList(store.data[_kKey]!);
      expect(onDisk.map((s) => s.id).toSet(), {'a', 'b', 'c'});
    });

    test('an empty batch touches nothing', () async {
      final store = _CountingStore();
      await SubmissionsService(store: store).createAll(const []);
      expect(store.writes[_kKey], isNull);
    });
  });

  group('what gets written', () {
    test('is exactly what the old whole-list encoding wrote', () async {
      // The saved text is re-read on every launch, so a cheaper encoder that
      // wrote anything different would quietly cost a teacher her term.
      final store = _CountingStore();
      final service = SubmissionsService(store: store);
      await service.createAll([_sub('a'), _sub('b')]);

      expect(store.data[_kKey], Submission.encodeList(service.submissions));
    });

    test('an edited result is written as edited, not as it first arrived', () async {
      final store = _CountingStore();
      final service = SubmissionsService(store: store);
      await service.create(_sub('a', score: 10));
      await service.update(_sub('a', score: 17));

      expect(Submission.decodeList(store.data[_kKey]!).single.score, 17);
      expect(store.data[_kKey], Submission.encodeList(service.submissions));
    });

    test('a deleted result is gone from the file', () async {
      final store = _CountingStore();
      final service = SubmissionsService(store: store);
      await service.createAll([_sub('a'), _sub('b')]);
      await service.delete('a');

      expect(Submission.decodeList(store.data[_kKey]!).map((s) => s.id), ['b']);
    });
  });
}
