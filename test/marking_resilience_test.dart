import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:marking_prokect_v2/models/grading_preset.dart';
import 'package:marking_prokect_v2/models/submission.dart';
import 'package:marking_prokect_v2/services/ai_grading_service.dart';
import 'package:marking_prokect_v2/services/grading_queue_service.dart';
import 'package:marking_prokect_v2/services/local_store.dart';
import 'package:marking_prokect_v2/services/students_service.dart';
import 'package:marking_prokect_v2/services/submissions_service.dart';

class _MemoryStore implements LocalStore {
  final Map<String, String> values = {};

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async => values[key] = value;

  @override
  Future<void> clear() async => values.clear();
}

/// A marker the test starts and stops by hand, so "how many papers are being
/// uploaded at this instant" is something a test can actually look at.
class _ControlledGrader {
  final List<Completer<AiGradeResult>> pending = [];
  int started = 0;
  int inFlight = 0;
  int peak = 0;
  Object? throwInstead;

  /// Once set, every paper from here on marks straight away — for draining
  /// the rest of the set after the interesting part has been measured.
  bool autoComplete = false;

  Future<AiGradeResult> grade(AiGradeRequest req) {
    started++;
    inFlight++;
    if (inFlight > peak) peak = inFlight;
    final boom = throwInstead;
    if (boom != null) {
      inFlight--;
      return Future<AiGradeResult>.error(boom);
    }
    if (autoComplete) {
      inFlight--;
      return Future<AiGradeResult>.value(_result());
    }
    final c = Completer<AiGradeResult>();
    pending.add(c);
    return c.future.whenComplete(() => inFlight--);
  }

  void finishOne() {
    final c = pending.firstWhere((c) => !c.isCompleted);
    pending.remove(c);
    c.complete(_result());
  }

  void finishAll() {
    for (final c in [...pending]) {
      if (!c.isCompleted) c.complete(_result());
    }
    pending.clear();
  }
}

AiGradeResult _result() => const AiGradeResult(
      detectedSubject: 'Maths',
      detectedGrade: 9,
      provider: 'claude',
      gradingFormat: 'percentage',
      percentage: 80,
      percentageDisplay: '80%',
      level: null,
      levelDisplay: null,
      rawScore: 20,
      maxScore: 25,
      summary: 'ok',
      strengths: [],
      improvements: [],
      criteriaBreakdown: [],
      annotations: [],
      rawText: '',
      confidence: 90,
      flags: [],
      triageStatus: TriageStatus.graded,
    );

AiGradeRequest _req() => AiGradeRequest(
      teacherId: 't1',
      studentId: '',
      classId: 'class_1',
      presetId: 'preset_1',
      subject: 'Maths',
      mode: GradingMode.testQuiz,
      criteria: const {},
      harshness: 5,
      overrideUsed: false,
      imageBytes: Uint8List(0),
    );

GradingJob _held(String id, String label) => GradingJob(
      id: id,
      createdAt: DateTime.now(),
      pages: [Uint8List.fromList([1, 2, 3])],
      req: _req(),
      label: label,
      status: GradingJobStatus.held,
    );

/// Lets the queue's un-awaited background work run. Real time, not just
/// microtasks: finishing a paper hashes its pages on another isolate.
Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 250));

/// Waits for something to become true, or gives up so a broken expectation
/// fails as an expectation rather than as a hung test.
Future<void> _until(bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!done() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  group('a call to the marking server always gives up eventually', () {
    test('marking gets minutes, a lookup gets seconds, and nothing waits forever', () {
      final marking = AiGradingService.timeoutFor(null);
      final lookup = AiGradingService.timeoutFor('get_usage');

      expect(marking.inMinutes, greaterThanOrEqualTo(2), reason: 'a class set is legitimately slow to upload');
      expect(marking.inMinutes, lessThanOrEqualTo(10), reason: 'but not so long a teacher gives up first');
      expect(lookup, lessThan(marking));
      expect(lookup.inSeconds, greaterThan(5));
    });

    test('an action nobody listed is treated as slow, never as instant', () {
      // Guessing wrong the other way would cut a real marking call short.
      expect(AiGradingService.timeoutFor('some_action_added_later'), AiGradingService.timeoutFor(null));
    });
  });

  group('marking a class set on school wifi', () {
    late _ControlledGrader grader;
    late GradingQueueService queue;
    late StudentsService students;
    late SubmissionsService submissions;

    setUp(() {
      grader = _ControlledGrader();
      queue = GradingQueueService(grader: grader.grade);
      students = StudentsService(store: _MemoryStore());
      submissions = SubmissionsService(store: _MemoryStore());
    });

    test('the whole class does not go up the same phone connection at once', () async {
      final jobs = [for (var i = 0; i < 8; i++) _held('j$i', 'Paper $i')];
      queue.releaseHeld(students: students, submissions: submissions, jobs: jobs);
      await _settle();

      expect(grader.started, GradingQueueService.maxConcurrentMarking);
      expect(grader.peak, lessThanOrEqualTo(GradingQueueService.maxConcurrentMarking));

      grader.finishOne();
      await _settle();
      expect(grader.started, GradingQueueService.maxConcurrentMarking + 1,
          reason: 'a finished paper lets the next one start');

      grader.autoComplete = true;
      grader.finishAll();
      await _until(() => grader.started == 8);
      expect(grader.started, 8, reason: 'every paper still gets marked, just not all at once');
      expect(grader.peak, lessThanOrEqualTo(GradingQueueService.maxConcurrentMarking));
    });

    test('the rest of the class is in the tray before the first paper comes back', () async {
      // The pilot is left hanging, which is what a captive-portal wifi does.
      unawaited(queue.enqueueBatch(
        reqs: [for (var i = 0; i < 5; i++) _req()],
        pagesList: [for (var i = 0; i < 5; i++) [Uint8List.fromList([1, 2, 3])]],
        labels: const ['Ana', 'Ben', 'Cara', 'Dev', 'Eze'],
        students: students,
        submissions: submissions,
      ));
      await _settle();

      expect(grader.started, 1, reason: 'only the pilot goes up until the teacher has seen it');
      expect(queue.jobs, hasLength(5),
          reason: 'the other four must be visible in the tray, not stuck inside a hung function');
      expect(queue.heldJobs.map((j) => j.label).toSet(), {'Ben', 'Cara', 'Dev', 'Eze'});
    });

    test('a paper the server never answers for stays in the tray, retryable, with its scan', () async {
      grader.throwInstead = const MarkingTimeoutException();
      final job = _held('j1', 'Ana');
      queue.releaseHeld(students: students, submissions: submissions, jobs: [job]);
      await _settle();

      expect(job.status, GradingJobStatus.error);
      expect(job.pages, isNotEmpty, reason: 'the scan is the only copy — losing it means rescanning the paper');
      expect(job.error, isNot(contains('Future not completed')),
          reason: 'a teacher should not be shown a Dart exception');
      expect(job.error?.toLowerCase(), contains('again'), reason: 'it has to say what to do about it');
    });
  });
}
