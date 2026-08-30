import 'package:flutter_test/flutter_test.dart';
import 'package:marking_prokect_v2/services/local_store.dart';
import 'package:marking_prokect_v2/services/push_service.dart';

/// Stands in for shared_preferences so the toggles can be read back without
/// a platform channel.
class _MemoryStore implements LocalStore {
  final Map<String, String> values = {};

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async => values[key] = value;

  @override
  Future<void> clear() async => values.clear();
}

/// Stands in for the OneSignal SDK. Every test in this file runs without a
/// network, a device, or a OneSignal account.
class _FakeBridge implements PushBridge {
  String? initialisedWith;
  String? externalId;
  bool loggedOut = false;
  int permissionRequests = 0;
  bool grantPermission = true;
  Map<String, String> tags = {};

  @override
  Future<void> initialise(String appId) async => initialisedWith = appId;

  @override
  Future<void> login(String externalUserId) async => externalId = externalUserId;

  @override
  Future<void> logOut() async {
    loggedOut = true;
    externalId = null;
  }

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return grantPermission;
  }

  @override
  Future<void> setTags(Map<String, String> newTags) async => tags = {...tags, ...newTags};

  @override
  void onOpened(void Function(String? deepLink) handler) {}
}

/// A teacher every nudge would otherwise apply to, so a test only has to say
/// what it is changing.
const _qualifiesForEverything = PushAudience(
  everQueuedBatch: true,
  papersJustFiled: 12,
  batchLabel: 'Year 9 English',
  trialDaysLeft: 2,
  monthPct: 92,
  papersThisWeek: 45,
);

void main() {
  group('the service switches itself off without a key', () {
    test('an empty OneSignal app id disables push instead of crashing', () async {
      final bridge = _FakeBridge();
      final push = PushService(bridge: bridge, store: _MemoryStore(), appId: '');

      await push.init();

      expect(push.enabled, isFalse);
      expect(push.unavailableReason, isNotEmpty);
      expect(bridge.initialisedWith, isNull, reason: 'the SDK must not be touched without a key');
    });

    test('a disabled service still lets the teacher change the toggles', () async {
      final store = _MemoryStore();
      final push = PushService(bridge: _FakeBridge(), store: store, appId: '');
      await push.init();

      await push.loadPrefs('teacher_1');
      await push.setPrefs('teacher_1', const PushPrefs(batchDone: false, planNudges: false, weeklySummary: true));

      expect(push.prefs.weeklySummary, isTrue);
    });

    test('signing in with no key never reaches the SDK', () async {
      final bridge = _FakeBridge();
      final push = PushService(bridge: bridge, store: _MemoryStore(), appId: '');
      await push.init();

      await push.login('teacher_1');
      await push.onBatchQueued(teacherId: 'teacher_1');

      expect(bridge.externalId, isNull);
      expect(bridge.permissionRequests, 0);
    });

    test('a real app id brings the service up', () async {
      final bridge = _FakeBridge();
      final push = PushService(bridge: bridge, store: _MemoryStore(), appId: 'app-id-123');

      await push.init();

      expect(push.enabled, isTrue);
      expect(push.unavailableReason, isEmpty);
      expect(bridge.initialisedWith, 'app-id-123');
    });
  });

  group('nobody is notified who has not asked for it', () {
    test('a teacher who has never queued a batch gets nothing', () {
      // The whole feature exists for overnight marking. A teacher who has
      // never sent a class set off has no reason to hear from us at all.
      final due = PushService.due(
        enabled: true,
        prefs: const PushPrefs(batchDone: true, planNudges: true, weeklySummary: true),
        audience: const PushAudience(
          everQueuedBatch: false,
          papersJustFiled: 12,
          batchLabel: 'Year 9 English',
          trialDaysLeft: 2,
          monthPct: 92,
          papersThisWeek: 45,
        ),
      );

      expect(due, isEmpty);
    });

    test('a service with no key sends nothing even to a batching teacher', () {
      final due = PushService.due(
        enabled: false,
        prefs: const PushPrefs(batchDone: true, planNudges: true, weeklySummary: true),
        audience: _qualifiesForEverything,
      );

      expect(due, isEmpty);
    });

    test('each notification answers to its own Settings toggle', () {
      List<PushKind> kindsWith(PushPrefs prefs) => PushService.due(
            enabled: true,
            prefs: prefs,
            audience: _qualifiesForEverything,
          ).map((m) => m.kind).toList();

      expect(
        kindsWith(const PushPrefs(batchDone: true, planNudges: true, weeklySummary: true)),
        containsAll(<PushKind>[PushKind.batchDone, PushKind.trialEnding, PushKind.markCapNear, PushKind.weeklySummary]),
      );
      expect(kindsWith(const PushPrefs(batchDone: false, planNudges: true, weeklySummary: true)), isNot(contains(PushKind.batchDone)));
      expect(kindsWith(const PushPrefs(batchDone: true, planNudges: false, weeklySummary: true)), isNot(contains(PushKind.trialEnding)));
      expect(kindsWith(const PushPrefs(batchDone: true, planNudges: false, weeklySummary: true)), isNot(contains(PushKind.markCapNear)));
      expect(kindsWith(const PushPrefs(batchDone: true, planNudges: true, weeklySummary: false)), isNot(contains(PushKind.weeklySummary)));
      expect(kindsWith(const PushPrefs(batchDone: false, planNudges: false, weeklySummary: false)), isEmpty);
    });

    test('the toggles survive a restart', () async {
      final store = _MemoryStore();
      final first = PushService(bridge: _FakeBridge(), store: store, appId: 'app-id-123');
      await first.init();
      await first.setPrefs('teacher_1', const PushPrefs(batchDone: false, planNudges: true, weeklySummary: true));

      final second = PushService(bridge: _FakeBridge(), store: store, appId: 'app-id-123');
      await second.init();
      await second.loadPrefs('teacher_1');

      expect(second.prefs.batchDone, isFalse);
      expect(second.prefs.weeklySummary, isTrue);
    });

    test('one teacher\'s toggles are not another\'s', () async {
      final store = _MemoryStore();
      final push = PushService(bridge: _FakeBridge(), store: store, appId: 'app-id-123');
      await push.init();
      await push.setPrefs('teacher_1', const PushPrefs(batchDone: false, planNudges: false, weeklySummary: false));

      await push.loadPrefs('teacher_2');

      expect(push.prefs.batchDone, isTrue, reason: 'a second account starts on the defaults');
    });
  });

  group('permission is asked at the right moment', () {
    test('not on first launch', () async {
      final bridge = _FakeBridge();
      final push = PushService(bridge: bridge, store: _MemoryStore(), appId: 'app-id-123');

      await push.init();
      await push.login('teacher_1');

      expect(bridge.permissionRequests, 0, reason: 'asking before the teacher has queued anything gets a no');
    });

    test('right after the first batch is queued', () async {
      final bridge = _FakeBridge();
      final push = PushService(bridge: bridge, store: _MemoryStore(), appId: 'app-id-123');
      await push.init();
      await push.login('teacher_1');

      await push.onBatchQueued(teacherId: 'teacher_1');

      expect(bridge.permissionRequests, 1);
      expect(push.everQueuedBatch, isTrue);
    });

    test('and never again for the second batch', () async {
      final bridge = _FakeBridge();
      final push = PushService(bridge: bridge, store: _MemoryStore(), appId: 'app-id-123');
      await push.init();
      await push.login('teacher_1');

      await push.onBatchQueued(teacherId: 'teacher_1');
      await push.onBatchQueued(teacherId: 'teacher_1');
      await push.onBatchQueued(teacherId: 'teacher_1');

      expect(bridge.permissionRequests, 1);
    });

    test('a teacher who said no is not asked again on the next launch', () async {
      final store = _MemoryStore();
      final first = _FakeBridge()..grantPermission = false;
      final push = PushService(bridge: first, store: store, appId: 'app-id-123');
      await push.init();
      await push.onBatchQueued(teacherId: 'teacher_1');

      final second = _FakeBridge();
      final relaunched = PushService(bridge: second, store: store, appId: 'app-id-123');
      await relaunched.init();
      await relaunched.loadPrefs('teacher_1');
      await relaunched.onBatchQueued(teacherId: 'teacher_1');

      expect(second.permissionRequests, 0);
    });
  });

  test('OneSignal addresses the same teacher id RevenueCat does', () async {
    // BillingService calls Purchases.logIn(teacherId) with the Supabase user
    // id. If these two drift apart, a nudge lands on the wrong phone.
    final bridge = _FakeBridge();
    final push = PushService(bridge: bridge, store: _MemoryStore(), appId: 'app-id-123');
    await push.init();

    await push.login('9f1c2b7e-teacher');

    expect(bridge.externalId, '9f1c2b7e-teacher');

    await push.logOut();
    expect(bridge.externalId, isNull);
  });

  group('what each notification says', () {
    PushMessage only(PushKind kind, PushAudience audience) => PushService.due(
          enabled: true,
          prefs: const PushPrefs(batchDone: true, planNudges: true, weeklySummary: true),
          audience: audience,
        ).firstWhere((m) => m.kind == kind);

    test('a finished class set names the set and links to the results', () {
      final msg = only(PushKind.batchDone, _qualifiesForEverything);

      expect(msg.body, contains('Year 9 English'));
      expect(msg.body, contains('12'));
      expect(msg.deepLink, '/dashboard');
    });

    test('nothing is announced when no papers came back', () {
      final due = PushService.due(
        enabled: true,
        prefs: const PushPrefs(batchDone: true, planNudges: true, weeklySummary: true),
        audience: const PushAudience(everQueuedBatch: true, papersJustFiled: 0),
      );

      expect(due.map((m) => m.kind), isNot(contains(PushKind.batchDone)));
    });

    test('the trial nudge only fires in the last few days', () {
      List<PushKind> at(int? days) => PushService.due(
            enabled: true,
            prefs: const PushPrefs(batchDone: true, planNudges: true, weeklySummary: true),
            audience: PushAudience(everQueuedBatch: true, trialDaysLeft: days),
          ).map((m) => m.kind).toList();

      expect(at(null), isNot(contains(PushKind.trialEnding)));
      expect(at(9), isNot(contains(PushKind.trialEnding)));
      expect(at(3), contains(PushKind.trialEnding));
      expect(at(1), contains(PushKind.trialEnding));
      expect(at(0), isNot(contains(PushKind.trialEnding)), reason: 'the trial is over — that is a different message');
    });

    test('the credit nudge fires as the cap comes into view, not after', () {
      List<PushKind> at(int pct) => PushService.due(
            enabled: true,
            prefs: const PushPrefs(batchDone: true, planNudges: true, weeklySummary: true),
            audience: PushAudience(everQueuedBatch: true, monthPct: pct),
          ).map((m) => m.kind).toList();

      expect(at(50), isNot(contains(PushKind.markCapNear)));
      expect(at(79), isNot(contains(PushKind.markCapNear)));
      expect(at(80), contains(PushKind.markCapNear));
      expect(at(99), contains(PushKind.markCapNear));
    });

    test('the weekly summary is skipped when it would not add up to an hour', () {
      List<PushKind> after(int papers) => PushService.due(
            enabled: true,
            prefs: const PushPrefs(batchDone: true, planNudges: true, weeklySummary: true),
            audience: PushAudience(everQueuedBatch: true, papersThisWeek: papers),
          ).map((m) => m.kind).toList();

      expect(after(0), isNot(contains(PushKind.weeklySummary)));
      expect(after(5), isNot(contains(PushKind.weeklySummary)), reason: '"you saved 20 minutes" is not worth a notification');
      expect(after(45), contains(PushKind.weeklySummary));
    });

    test('the weekly summary counts hours, hedged', () {
      final msg = only(PushKind.weeklySummary, const PushAudience(everQueuedBatch: true, papersThisWeek: 45));

      expect(msg.body, contains('about'));
      expect(msg.body, contains('3 hours'));
    });
  });

  test('switching a notification off updates the tags there and then', () async {
    // Otherwise a teacher who turns the weekly summary off on Sunday still
    // gets one on Monday, because OneSignal is targeting yesterday's tags.
    final bridge = _FakeBridge();
    final push = PushService(bridge: bridge, store: _MemoryStore(), appId: 'app-id-123');
    await push.init();
    await push.setPrefs('teacher_1', const PushPrefs(batchDone: true, planNudges: true, weeklySummary: true));
    await push.syncAudience(_qualifiesForEverything);
    expect(bridge.tags['notify_weekly'], '1');

    await push.setPrefs('teacher_1', const PushPrefs(batchDone: true, planNudges: true, weeklySummary: false));

    expect(bridge.tags['notify_weekly'], '0');
    expect(bridge.tags['month_pct'], '92', reason: 'the facts already sent are not thrown away');
  });

  test('the tags handed to OneSignal say who may be targeted', () {
    // Segments are built on these in the OneSignal dashboard, so they carry
    // the same rules the pure logic above enforces.
    final tags = PushService.tagsFor(
      audience: _qualifiesForEverything,
      prefs: const PushPrefs(batchDone: true, planNudges: false, weeklySummary: true),
    );

    expect(tags['queued_batch'], '1');
    expect(tags['notify_batch_done'], '1');
    expect(tags['notify_plan'], '0');
    expect(tags['notify_weekly'], '1');
    expect(tags['month_pct'], '92');
  });
}
