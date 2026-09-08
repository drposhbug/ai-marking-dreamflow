import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:marking_prokect_v2/models/grading_preset.dart';
import 'package:marking_prokect_v2/services/ai_grading_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A fake edge function: each entry is one attempt's outcome, consumed in
/// order. A [FunctionResponse] is returned; anything else is thrown.
class _ScriptedTransport {
  final List<Object> script;
  final List<Map<String, dynamic>?> bodies = [];
  int calls = 0;

  _ScriptedTransport(this.script);

  Future<FunctionResponse> invoke(String function, {Map<String, dynamic>? body}) {
    calls++;
    bodies.add(body);
    if (script.isEmpty) fail('transport called more times than scripted');
    final next = script.removeAt(0);
    if (next is FunctionResponse) return Future.value(next);
    return Future.error(next);
  }
}

FunctionResponse _usageOk({int monthPct = 10}) => FunctionResponse(status: 200, data: {
      'planLabel': 'Pro',
      'dayPct': 1,
      'weekPct': 5,
      'monthPct': monthPct,
      'monthlyCapUsd': 8.0,
    });

FunctionResponse _gradeOk() => FunctionResponse(status: 200, data: {
      'percentage': 80,
      'rawScore': 20,
      'maxScore': 25,
      'gradingFormat': 'percentage',
      'summary': 'ok',
    });

const _serviceUnavailable = FunctionException(status: 503, details: 'Service Unavailable');
const _bootError = FunctionException(
  status: 503,
  details: {'code': 'BOOT_ERROR', 'message': 'Function failed to start'},
);
const _clockSkew = FunctionException(status: 500, details: {'error': 'JWT issued at future'});
const _badRequest = FunctionException(status: 422, details: {'error': 'missing field'});

/// Builds a service whose network, sleeps and dice are all under the test's
/// control. Sleeps are recorded, never actually slept.
AiGradingService _service(_ScriptedTransport transport, List<Duration> sleeps, {double roll = 0.5}) {
  return AiGradingService(
    transport: transport.invoke,
    sleep: (d) async => sleeps.add(d),
    random: () => roll,
  );
}

AiGradeRequest _gradeReq() => AiGradeRequest(
      teacherId: 't1',
      studentId: 's1',
      classId: 'c1',
      presetId: 'p1',
      subject: 'Maths',
      mode: GradingMode.testQuiz,
      criteria: const {},
      harshness: 5,
      overrideUsed: false,
      imageBytes: Uint8List(0),
    );

void main() {
  setUp(AiGradingService.invalidateUsageCache);

  group('transient failures are retried with backoff', () {
    test('a 503 then a 200 succeeds with exactly 2 attempts and a jittered pause between', () async {
      final transport = _ScriptedTransport([_serviceUnavailable, _usageOk()]);
      final sleeps = <Duration>[];
      final svc = _service(transport, sleeps, roll: 0.5);

      final usage = await svc.getUsage(teacherId: 't1');

      expect(usage.planLabel, 'Pro');
      expect(transport.calls, 2);
      expect(sleeps, hasLength(1), reason: 'a backoff pause must sit between the attempts');
      // Full jitter over a 400ms first window: roll of 0.5 means 200ms.
      expect(sleeps.single, const Duration(milliseconds: 200));
      expect(sleeps.single, lessThanOrEqualTo(const Duration(milliseconds: 400)));
    });

    test('a BOOT_ERROR body then a 200 succeeds', () async {
      final transport = _ScriptedTransport([_bootError, _usageOk()]);
      final svc = _service(transport, <Duration>[]);

      final usage = await svc.getUsage(teacherId: 't1');

      expect(usage.monthPct, 10);
      expect(transport.calls, 2);
    });

    test('the clock-skew 500 then a 200 succeeds', () async {
      final transport = _ScriptedTransport([_clockSkew, _usageOk()]);
      final svc = _service(transport, <Duration>[]);

      await svc.getUsage(teacherId: 't1');

      expect(transport.calls, 2);
    });

    test('an HTML page where JSON should be, then a 200, succeeds', () async {
      final transport = _ScriptedTransport([
        const FunctionResponse(status: 200, data: '<html><body>Cloudflare error</body></html>'),
        _usageOk(),
      ]);
      final svc = _service(transport, <Duration>[]);

      await svc.getUsage(teacherId: 't1');

      expect(transport.calls, 2);
    });

    test('a network-level failure then a 200 succeeds', () async {
      final transport = _ScriptedTransport([
        http.ClientException('Connection closed before full header was received'),
        _usageOk(),
      ]);
      final svc = _service(transport, <Duration>[]);

      await svc.getUsage(teacherId: 't1');

      expect(transport.calls, 2);
    });

    test('3 transient failures gives up with the original error after 3 attempts', () async {
      const second = FunctionException(status: 503, details: 'second');
      const third = FunctionException(status: 503, details: 'third');
      final transport = _ScriptedTransport([_serviceUnavailable, second, third]);
      final sleeps = <Duration>[];
      final svc = _service(transport, sleeps, roll: 0.5);

      await expectLater(
        svc.getUsage(teacherId: 't1'),
        throwsA(same(_serviceUnavailable)),
      );
      expect(transport.calls, 3);
      // Exponential windows: 400ms then 1200ms, both at roll 0.5.
      expect(sleeps, [const Duration(milliseconds: 200), const Duration(milliseconds: 600)]);
    });

    test('a 400/422 application error is not retried — it would fail identically', () async {
      final transport = _ScriptedTransport([_badRequest]);
      final sleeps = <Duration>[];
      final svc = _service(transport, sleeps);

      await expectLater(svc.getUsage(teacherId: 't1'), throwsA(same(_badRequest)));
      expect(transport.calls, 1);
      expect(sleeps, isEmpty);
    });
  });

  group('billed actions are never retried', () {
    test('mark_responses getting a 503 makes exactly 1 attempt and surfaces the error', () async {
      final transport = _ScriptedTransport([_serviceUnavailable]);
      final sleeps = <Duration>[];
      final svc = _service(transport, sleeps);

      await expectLater(
        svc.markResponses(teacherId: 't1', questions: [
          {'title': 'Q1', 'answers': []},
        ]),
        throwsA(same(_serviceUnavailable)),
      );
      expect(transport.calls, 1, reason: 'the server bills on completion — a retry could buy the same marking twice');
      expect(sleeps, isEmpty);
    });

    test('grade getting a 503 makes exactly 1 attempt and surfaces the error', () async {
      final transport = _ScriptedTransport([_serviceUnavailable]);
      final svc = _service(transport, <Duration>[]);

      await expectLater(svc.grade(_gradeReq()), throwsA(same(_serviceUnavailable)));
      expect(transport.calls, 1);
    });

    test('every billed action stays off the retryable allowlist', () {
      for (final billed in [
        'grade', 'mark_responses', 'extract_key', 'extract_roster', 'report_comments',
        'plan', 'explain', 'group_pages', 'suggest_schools', 'batch_submit',
      ]) {
        expect(retryableEdgeActions, isNot(contains(billed)),
            reason: '$billed bills for AI work — auto-retrying it can charge the teacher twice');
      }
      // And the un-named marking call (no action field) must not sneak in.
      expect(retryableEdgeActions, isNot(contains(null)));
    });
  });

  group('getUsage cache', () {
    test('two calls inside 45s make one network trip', () async {
      final transport = _ScriptedTransport([_usageOk()]);
      final svc = _service(transport, <Duration>[]);

      final first = await svc.getUsage(teacherId: 't1');
      final second = await svc.getUsage(teacherId: 't1');

      expect(transport.calls, 1);
      expect(second.monthPct, first.monthPct);
    });

    test('the cache is per teacher, not global', () async {
      final transport = _ScriptedTransport([_usageOk(), _usageOk(monthPct: 90)]);
      final svc = _service(transport, <Duration>[]);

      await svc.getUsage(teacherId: 't1');
      final other = await svc.getUsage(teacherId: 't2');

      expect(transport.calls, 2);
      expect(other.monthPct, 90);
    });

    test('force: true bypasses and refreshes the cache', () async {
      final transport = _ScriptedTransport([_usageOk(), _usageOk(monthPct: 55)]);
      final svc = _service(transport, <Duration>[]);

      await svc.getUsage(teacherId: 't1');
      final refreshed = await svc.getUsage(teacherId: 't1', force: true);

      expect(transport.calls, 2);
      expect(refreshed.monthPct, 55);
      // The forced result replaces the cached one for later callers.
      final after = await svc.getUsage(teacherId: 't1');
      expect(after.monthPct, 55);
      expect(transport.calls, 2);
    });

    test('a completed grade invalidates the cache so the usage bar moves', () async {
      final transport = _ScriptedTransport([_usageOk(), _gradeOk(), _usageOk(monthPct: 12)]);
      final svc = _service(transport, <Duration>[]);

      await svc.getUsage(teacherId: 't1');
      await svc.grade(_gradeReq());
      final after = await svc.getUsage(teacherId: 't1');

      expect(transport.calls, 3, reason: 'the grade must throw the cached usage away');
      expect(after.monthPct, 12);
    });

    test('a failed grade leaves the cache alone', () async {
      final transport = _ScriptedTransport([_usageOk(), _badRequest]);
      final svc = _service(transport, <Duration>[]);

      await svc.getUsage(teacherId: 't1');
      await expectLater(svc.grade(_gradeReq()), throwsA(anything));
      await svc.getUsage(teacherId: 't1');

      expect(transport.calls, 2, reason: 'nothing was billed, so nothing moved');
    });

    test('marked responses invalidate the cache', () async {
      final transport = _ScriptedTransport([
        _usageOk(),
        const FunctionResponse(status: 200, data: {'results': []}),
        _usageOk(monthPct: 20),
      ]);
      final svc = _service(transport, <Duration>[]);

      await svc.getUsage(teacherId: 't1');
      await svc.markResponses(teacherId: 't1', questions: const []);
      final after = await svc.getUsage(teacherId: 't1');

      expect(transport.calls, 3);
      expect(after.monthPct, 20);
    });

    test('a batch poll that came back with results invalidates the cache', () async {
      final transport = _ScriptedTransport([
        _usageOk(),
        const FunctionResponse(status: 200, data: {
          'status': 'ended',
          'results': [
            {'customId': 'p1', 'result': {'percentage': 70}},
          ],
        }),
        _usageOk(monthPct: 30),
      ]);
      final svc = _service(transport, <Duration>[]);

      await svc.getUsage(teacherId: 't1');
      final outcome = await svc.batchStatus(teacherId: 't1', batchId: 'b1');
      expect(outcome.isEnded, isTrue);
      final after = await svc.getUsage(teacherId: 't1');

      expect(transport.calls, 3);
      expect(after.monthPct, 30);
    });

    test('a still-running batch poll does not invalidate the cache', () async {
      final transport = _ScriptedTransport([
        _usageOk(),
        const FunctionResponse(status: 200, data: {'status': 'in_progress', 'results': []}),
      ]);
      final svc = _service(transport, <Duration>[]);

      await svc.getUsage(teacherId: 't1');
      await svc.batchStatus(teacherId: 't1', batchId: 'b1');
      await svc.getUsage(teacherId: 't1');

      expect(transport.calls, 2, reason: 'nothing finished, nothing was billed');
    });
  });
}
