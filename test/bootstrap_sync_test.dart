// R19.3 bootstrap_sync + R14 client grace.
//
// The backend now (a) answers the whole app-open sync in one round trip and
// (b) refuses any teacherId it can't match to the caller's signed-in JWT.
// These tests pin the two client behaviours that make that safe to deploy:
//
//  1. VERSION TOLERANCE — an older deployed function doesn't know
//     bootstrap_sync (its fallthrough answers 400), and that must read as
//     "use the old per-action calls", never as a broken startup.
//  2. LOCAL-ONLY GRACE — dev-mode / signInLocal accounts have no Supabase
//     session, so every guarded call 403s. That is expected, and must be a
//     quiet no-op (submission pushes, profile saves) rather than error spam.
//
// In tests Supabase.initialize never ran, so `isCloudAuthRefusal` sees "no
// session" — exactly the local-only account's situation on a device.

import 'package:flutter_test/flutter_test.dart';
import 'package:marking_prokect_v2/services/ai_grading_service.dart';
import 'package:marking_prokect_v2/services/cloud_collection.dart';
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

AiGradingService _service(_ScriptedTransport transport) => AiGradingService(
      transport: transport.invoke,
      sleep: (_) async {},
      random: () => 0.5,
    );

/// What the new server answers bootstrap_sync with.
FunctionResponse _bootstrapOk() => FunctionResponse(status: 200, data: {
      'profile': {
        'teacher_id': 't1',
        'name': 'Ms. Lee',
        'school': 'Northview HS',
        'region': 'ca-on',
        'default_mode': 'testQuiz',
        'default_harshness': 7,
      },
      'usage': {
        'planLabel': 'Pro',
        'dayPct': 3,
        'weekPct': 11,
        'monthPct': 42,
        'instantMarking': true,
        'monthlyCapUsd': 3.55,
        'liveUsdPerPaper': 0.039,
        'overnightUsdPerPaper': 0.0078,
      },
      'keys': [
        {'id': 'k1', 'name': 'Solubility Unit Test', 'subject': 'Science', 'total_marks': 25},
      ],
      'collections': {
        'classes': [
          {'id': 'c1', 'name': 'SNC2D P1'},
        ],
        'students': [
          {'id': 's1', 'name': 'Amara Ben'},
          {'id': 's2', 'name': 'Chloe Deven'},
        ],
        'student_class_links': [
          {'id': 'l1', 'studentId': 's1', 'classId': 'c1'},
        ],
      },
    });

/// The pre-R19.3 server never heard of bootstrap_sync — the action falls
/// through to the grade path, which demands images and answers 400.
const _oldServer400 = FunctionException(
  status: 400,
  details: {'error': 'imagesBase64 (or imageBase64) is required'},
);

const _notFound404 = FunctionException(status: 404, details: 'Not Found');

/// The R14 identity guard's refusal.
const _guard403 = FunctionException(
  status: 403,
  details: {'error': 'Sign in again to sync your account.'},
);

const _serverError500 = FunctionException(status: 500, details: {'error': 'boom'});

void main() {
  setUp(AiGradingService.invalidateUsageCache);

  group('bootstrapSync', () {
    test('parses the full snapshot', () async {
      final transport = _ScriptedTransport([_bootstrapOk()]);
      final boot = await _service(transport).bootstrapSync(teacherId: 't1');

      expect(boot, isNotNull);
      expect(boot!.localOnly, isFalse);
      expect(boot.profile?['default_mode'], 'testQuiz');
      expect(boot.profile?['default_harshness'], 7);
      expect(boot.usage?.planLabel, 'Pro');
      expect(boot.usage?.monthPct, 42);
      expect(boot.keys.single.id, 'k1');
      expect(boot.keys.single.totalMarks, 25);
      expect(boot.collections['classes'], hasLength(1));
      expect(boot.collections['students'], hasLength(2));
      expect(boot.collections['student_class_links']?.single['classId'], 'c1');
      expect(transport.bodies.single?['action'], 'bootstrap_sync');
      expect(transport.bodies.single?['teacherId'], 't1');
    });

    test('primes the getUsage cache so the startup meter costs nothing', () async {
      // The script holds ONLY the bootstrap answer: if getUsage went to the
      // network afterwards the transport would fail the test.
      final transport = _ScriptedTransport([_bootstrapOk()]);
      final service = _service(transport);
      await service.bootstrapSync(teacherId: 't1');

      final usage = await service.getUsage(teacherId: 't1');
      expect(usage.monthPct, 42);
      expect(usage.planLabel, 'Pro');
      expect(transport.calls, 1, reason: 'getUsage must be served from the primed cache');
    });

    test('returns null on the old server\'s 400 so startup falls back', () async {
      final transport = _ScriptedTransport([_oldServer400]);
      final boot = await _service(transport).bootstrapSync(teacherId: 't1');
      expect(boot, isNull);
    });

    test('returns null on 404 so startup falls back', () async {
      final transport = _ScriptedTransport([_notFound404]);
      final boot = await _service(transport).bootstrapSync(teacherId: 't1');
      expect(boot, isNull);
    });

    test('403 with no Supabase session is a quiet local-only snapshot', () async {
      final transport = _ScriptedTransport([_guard403]);
      final boot = await _service(transport).bootstrapSync(teacherId: 'u_dev_markless_app');

      expect(boot, isNotNull);
      expect(boot!.localOnly, isTrue);
      expect(boot.profile, isNull);
      expect(boot.usage, isNull);
      expect(boot.collections, isEmpty);
      expect(transport.calls, 1, reason: 'a guard refusal must not be retried');
    });

    test('a real server error still surfaces', () async {
      final transport = _ScriptedTransport([_serverError500]);
      expect(
        () => _service(transport).bootstrapSync(teacherId: 't1'),
        throwsA(isA<FunctionException>()),
      );
    });
  });

  group('R14 grace on cloud-sync writes and reads', () {
    test('saveSubmissionCloud swallows the guard 403 quietly', () async {
      final transport = _ScriptedTransport([_guard403]);
      await _service(transport)
          .saveSubmissionCloud(teacherId: 'u_dev', submission: {'id': 'sub_1'});
      expect(transport.calls, 1);
    });

    test('saveSubmissionCloud still throws on other failures', () async {
      final transport = _ScriptedTransport([_serverError500]);
      expect(
        () => _service(transport).saveSubmissionCloud(teacherId: 't1', submission: {'id': 'sub_1'}),
        throwsA(isA<FunctionException>()),
      );
    });

    test('deleteSubmissionCloud swallows the guard 403 quietly', () async {
      final transport = _ScriptedTransport([_guard403]);
      await _service(transport).deleteSubmissionCloud(teacherId: 'u_dev', id: 'sub_1');
      expect(transport.calls, 1);
    });

    test('listSubmissionsCloud answers empty on the guard 403', () async {
      final transport = _ScriptedTransport([_guard403]);
      final subs = await _service(transport).listSubmissionsCloud(teacherId: 'u_dev');
      expect(subs, isEmpty);
    });

    test('saveProfile swallows the guard 403 quietly', () async {
      final transport = _ScriptedTransport([_guard403]);
      await _service(transport).saveProfile(teacherId: 'u_dev', name: 'Dev');
      expect(transport.calls, 1);
    });

    test('isCloudAuthRefusal recognises only the guard case', () {
      // No Supabase session in tests — a 403 is the guard refusing a
      // local-only account.
      expect(AiGradingService.isCloudAuthRefusal(_guard403), isTrue);
      expect(AiGradingService.isCloudAuthRefusal(_serverError500), isFalse);
      expect(AiGradingService.isCloudAuthRefusal(_oldServer400), isFalse);
      expect(AiGradingService.isCloudAuthRefusal(Exception('boom')), isFalse);
    });
  });

  group('CloudCollection priming', () {
    test('a primed collection is served once without the network', () async {
      CloudCollection.prime(teacherId: 't1', collections: {
        'classes': [
          {'id': 'c1', 'name': 'SNC2D P1'},
        ],
      });

      final first = await CloudCollection.fetch(teacherId: 't1', kind: 'classes');
      expect(first.single['id'], 'c1');

      // Consumed: the next fetch would go to the network (and here, with no
      // Supabase configured, quietly answers empty — local-only behaviour).
      final second = await CloudCollection.fetch(teacherId: 't1', kind: 'classes');
      expect(second, isEmpty);
    });

    test('priming one teacher never answers for another', () async {
      CloudCollection.prime(teacherId: 't1', collections: {
        'students': [
          {'id': 's1'},
        ],
      });
      final other = await CloudCollection.fetch(teacherId: 't2', kind: 'students');
      expect(other, isEmpty);
      // Clean up the unconsumed prime so tests stay independent.
      final own = await CloudCollection.fetch(teacherId: 't1', kind: 'students');
      expect(own, hasLength(1));
    });
  });
}
