import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:marking_prokect_v2/services/local_store.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

/// The four things UMarkless will interrupt a teacher's evening for.
enum PushKind {
  /// "Your class set is marked" — the point of overnight marking.
  batchDone,

  /// The trial runs out in a couple of days.
  trialEnding,

  /// This month's marking credits are nearly spent.
  markCapNear,

  /// "You saved about N hours this week."
  weeklySummary,
}

/// Which notifications the teacher has said yes to, straight off the
/// Settings screen. Kept per account, because two teachers sharing a staff
/// tablet should not inherit each other's answers.
class PushPrefs {
  final bool batchDone;

  /// Trial-ending and credit-cap reminders — the two that mention money.
  final bool planNudges;
  final bool weeklySummary;

  const PushPrefs({
    this.batchDone = true,
    this.planNudges = true,
    this.weeklySummary = false,
  });

  static const defaults = PushPrefs();

  bool allows(PushKind kind) => switch (kind) {
        PushKind.batchDone => batchDone,
        PushKind.trialEnding => planNudges,
        PushKind.markCapNear => planNudges,
        PushKind.weeklySummary => weeklySummary,
      };

  PushPrefs copyWith({bool? batchDone, bool? planNudges, bool? weeklySummary}) => PushPrefs(
        batchDone: batchDone ?? this.batchDone,
        planNudges: planNudges ?? this.planNudges,
        weeklySummary: weeklySummary ?? this.weeklySummary,
      );

  Map<String, dynamic> toJson() => {'batch_done': batchDone, 'plan_nudges': planNudges, 'weekly': weeklySummary};

  factory PushPrefs.fromJson(Map<String, dynamic> j) => PushPrefs(
        batchDone: j['batch_done'] != false,
        planNudges: j['plan_nudges'] != false,
        weeklySummary: j['weekly'] == true,
      );
}

/// What the teacher's account looks like right now, as far as notifications
/// are concerned. Holds nothing from the SDK, so what a teacher would be
/// sent can be worked out — and tested — without a network or a device.
class PushAudience {
  /// Has this teacher ever sent a class set off overnight? Nothing is sent
  /// to somebody who hasn't.
  final bool everQueuedBatch;

  /// Papers filed by the batch that just finished; 0 when none has.
  final int papersJustFiled;
  final String batchLabel;

  /// Days left on the trial, or null when they aren't on one.
  final int? trialDaysLeft;

  /// Share of this month's marking credits already spent.
  final int monthPct;

  /// Papers marked in the last seven days.
  final int papersThisWeek;

  const PushAudience({
    required this.everQueuedBatch,
    this.papersJustFiled = 0,
    this.batchLabel = 'Your class set',
    this.trialDaysLeft,
    this.monthPct = 0,
    this.papersThisWeek = 0,
  });
}

/// One notification, ready to send: the copy and where tapping it lands.
class PushMessage {
  final PushKind kind;
  final String title;
  final String body;

  /// Route the tap opens — matches the paths in AppRoutes.
  final String deepLink;

  const PushMessage({required this.kind, required this.title, required this.body, required this.deepLink});
}

/// Everything that actually talks to OneSignal, behind one small interface.
///
/// The SDK is static and native-only, so the decision logic above would be
/// untestable if it called it directly. Nothing here has an opinion; the
/// opinions all live in [PushService].
abstract class PushBridge {
  Future<void> initialise(String appId);
  Future<void> login(String externalUserId);
  Future<void> logOut();
  Future<bool> requestPermission();
  Future<void> setTags(Map<String, String> tags);
  void onOpened(void Function(String? deepLink) handler);
}

/// The real OneSignal SDK.
class OneSignalBridge implements PushBridge {
  const OneSignalBridge();

  @override
  Future<void> initialise(String appId) async {
    await OneSignal.Debug.setLogLevel(kReleaseMode ? OSLogLevel.warn : OSLogLevel.debug);
    await OneSignal.initialize(appId);
  }

  @override
  Future<void> login(String externalUserId) => OneSignal.login(externalUserId);

  @override
  Future<void> logOut() => OneSignal.logout();

  /// fallbackToSettings: false — a teacher who already said no should not be
  /// bounced into system settings for having queued another batch.
  @override
  Future<bool> requestPermission() => OneSignal.Notifications.requestPermission(false);

  @override
  Future<void> setTags(Map<String, String> tags) => OneSignal.User.addTags(tags);

  @override
  void onOpened(void Function(String? deepLink) handler) {
    OneSignal.Notifications.addClickListener((event) {
      handler(event.notification.additionalData?['route']?.toString());
    });
  }
}

/// Push notifications for UMarkless.
///
/// The feature this exists for is overnight marking: a teacher scans a class
/// set at bedtime and the marks land hours later. Without a notification the
/// only way to find out is to reopen the app and look, which is exactly the
/// chore the feature was meant to remove.
///
/// Who gets what is decided by [due] and [tagsFor] — pure functions with no
/// SDK in them. The tags are what OneSignal segments and journeys target, so
/// the rules a teacher sees enforced in Settings are the same rules the
/// dashboard sends on.
///
/// Sending is OneSignal's job, not this app's: a phone with the app closed
/// can't push to itself. See the follow-up note on [batchDoneCopy] for the
/// server hook that will fire the "class set is marked" message.
class PushService extends ChangeNotifier {
  // OneSignal app id. Ships empty: pass the real one at build time with
  // --dart-define=ONESIGNAL_APP_ID=xxxx (or paste it into _bakedAppId).
  // EMPTY disables push entirely — no initialize call, no permission prompt,
  // no OneSignal contact at all — and the rest of the app is untouched.
  // Public by design once set — safe to ship in the APK.
  static const _bakedAppId = '';
  static const _envAppId = String.fromEnvironment('ONESIGNAL_APP_ID');
  static String get _defaultAppId => _envAppId.isNotEmpty ? _envAppId : _bakedAppId;

  /// The last few days of a trial are when a teacher decides. Earlier than
  /// this and the reminder is just noise.
  static const trialNudgeDays = 3;

  /// Warn while there are still credits left to spend, not once they're gone.
  static const markCapNudgePct = 80;

  /// Roughly what a teacher spends marking one paper by hand. An estimate,
  /// and the summary says "about" because of it — never presented as a
  /// measurement.
  static const minutesPerPaperByHand = 4;

  /// Routes tapping a notification opens. Same paths as AppRoutes, kept as
  /// plain strings so a background service doesn't pull in the router.
  static const _dashboard = '/dashboard';
  static const _plans = '/plans';

  final PushBridge _bridge;
  final LocalStore _store;
  final String _appId;

  PushService({PushBridge? bridge, LocalStore? store, String? appId})
      : _bridge = bridge ?? const OneSignalBridge(),
        _store = store ?? const LocalStore(),
        _appId = appId ?? _defaultAppId;

  bool _enabled = false;
  bool get enabled => _enabled;

  /// Plain-English reason push is off, so Settings can say why instead of
  /// showing a toggle that does nothing.
  String _unavailableReason = '';
  String get unavailableReason => _unavailableReason;

  PushPrefs _prefs = PushPrefs.defaults;
  PushPrefs get prefs => _prefs;

  bool _everQueuedBatch = false;
  bool get everQueuedBatch => _everQueuedBatch;

  bool _permissionAsked = false;
  bool get permissionAsked => _permissionAsked;

  bool _permissionGranted = false;
  bool get permissionGranted => _permissionGranted;

  /// Where a tapped notification should take the teacher. Set by the app so
  /// this service never has to know about the router.
  void Function(String route)? onDeepLink;

  String _prefsKey(String teacherId) => 'ai_marker.push_prefs.v1.$teacherId';
  String _queuedKey(String teacherId) => 'ai_marker.push_queued_batch.v1.$teacherId';
  String _askedKey(String teacherId) => 'ai_marker.push_permission_asked.v1.$teacherId';

  /// Configure once at app start. Safe to call when push isn't possible
  /// (web, no app id) — the service just stays disabled.
  Future<void> init() async {
    if (kIsWeb) {
      _unavailableReason = 'Notifications arrive in the phone app.';
      return;
    }
    if (_appId.isEmpty) {
      _unavailableReason = 'Notifications aren\'t switched on in this build yet.';
      return;
    }
    try {
      await _bridge.initialise(_appId);
      _bridge.onOpened((route) {
        if (route != null && route.isNotEmpty) onDeepLink?.call(route);
      });
      _enabled = true;
      _unavailableReason = '';
    } catch (e) {
      debugPrint('PushService.init failed: $e');
      _unavailableReason = 'Couldn\'t set up notifications on this device.';
    }
    notifyListeners();
  }

  /// Addresses the teacher by the same id BillingService hands RevenueCat,
  /// so a nudge about their plan reaches the phone that holds the plan.
  Future<void> login(String teacherId) async {
    await loadPrefs(teacherId);
    if (!_enabled) return;
    try {
      await _bridge.login(teacherId);
    } catch (e) {
      debugPrint('PushService.login failed: $e');
    }
  }

  Future<void> logOut() async {
    _prefs = PushPrefs.defaults;
    _everQueuedBatch = false;
    _permissionAsked = false;
    if (!_enabled) return;
    try {
      await _bridge.logOut();
    } catch (e) {
      debugPrint('PushService.logOut failed: $e');
    }
  }

  /// Reads this teacher's answers back. Falls to the defaults for an account
  /// that has never set them, so a second sign-in on the same phone doesn't
  /// inherit the first teacher's choices.
  Future<void> loadPrefs(String teacherId) async {
    _prefs = PushPrefs.defaults;
    _everQueuedBatch = false;
    _permissionAsked = false;
    try {
      final raw = await _store.getString(_prefsKey(teacherId));
      if (raw != null && raw.isNotEmpty) {
        _prefs = PushPrefs.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
      }
      _everQueuedBatch = await _store.getString(_queuedKey(teacherId)) == '1';
      _permissionAsked = await _store.getString(_askedKey(teacherId)) == '1';
    } catch (e) {
      debugPrint('PushService.loadPrefs failed: $e');
    }
    notifyListeners();
  }

  Future<void> setPrefs(String teacherId, PushPrefs prefs) async {
    _prefs = prefs;
    notifyListeners();
    await _store.setString(_prefsKey(teacherId), jsonEncode(prefs.toJson()));
    // Switched off means switched off now, not at the next launch. Before
    // the first sync there are no counts to re-send, and the empty audience
    // errs towards silence rather than towards a nudge.
    await syncAudience(_lastAudience ?? PushAudience(everQueuedBatch: _everQueuedBatch));
  }

  /// The moment a class set is sent off for the night.
  ///
  /// This is where the Android permission is asked for, and nowhere else. On
  /// first launch a teacher has no idea what we'd notify them about and taps
  /// no; asked here, they have just queued thirty papers and want to know
  /// when the marks land. Android only ever shows the prompt once, so
  /// spending it on the wrong moment costs the feature permanently.
  Future<void> onBatchQueued({required String teacherId}) async {
    if (!_everQueuedBatch) {
      _everQueuedBatch = true;
      await _store.setString(_queuedKey(teacherId), '1');
      notifyListeners();
    }
    if (!_enabled || _permissionAsked) return;
    _permissionAsked = true;
    await _store.setString(_askedKey(teacherId), '1');
    try {
      _permissionGranted = await _bridge.requestPermission();
    } catch (e) {
      debugPrint('PushService.onBatchQueued permission request failed: $e');
    }
    notifyListeners();
  }

  /// The last facts sent, so a toggle change can re-send them without the
  /// caller having to gather everything again.
  PushAudience? _lastAudience;

  /// Tells OneSignal who this teacher is to the segments. Cheap and
  /// idempotent — call it whenever the facts change.
  Future<void> syncAudience(PushAudience audience) async {
    _lastAudience = audience;
    if (!_enabled) return;
    try {
      await _bridge.setTags(tagsFor(audience: audience, prefs: _prefs));
    } catch (e) {
      debugPrint('PushService.syncAudience failed: $e');
    }
  }

  /// Every notification this teacher currently qualifies for.
  ///
  /// The two hard rules first: push that isn't switched on sends nothing,
  /// and a teacher who has never queued a batch hears from us never — they
  /// didn't sign up for a marking app to be nagged by it.
  static List<PushMessage> due({
    required bool enabled,
    required PushPrefs prefs,
    required PushAudience audience,
  }) {
    if (!enabled || !audience.everQueuedBatch) return const [];

    final out = <PushMessage>[];

    if (prefs.allows(PushKind.batchDone) && audience.papersJustFiled > 0) {
      out.add(batchDoneCopy(label: audience.batchLabel, papers: audience.papersJustFiled));
    }

    final days = audience.trialDaysLeft;
    if (prefs.allows(PushKind.trialEnding) && days != null && days > 0 && days <= trialNudgeDays) {
      out.add(PushMessage(
        kind: PushKind.trialEnding,
        title: days == 1 ? 'Your trial ends tomorrow' : 'Your trial ends in $days days',
        body: 'Pick a plan and your classes, keys and marked work carry straight on.',
        deepLink: _plans,
      ));
    }

    if (prefs.allows(PushKind.markCapNear) && audience.monthPct >= markCapNudgePct) {
      out.add(PushMessage(
        kind: PushKind.markCapNear,
        title: 'You\'ve used ${audience.monthPct}% of this month\'s marking',
        body: 'Enough left for a set or two. A bigger plan tops you up now rather than at the end of the month.',
        deepLink: _plans,
      ));
    }

    if (prefs.allows(PushKind.weeklySummary)) {
      final hours = hoursSaved(audience.papersThisWeek);
      // Under an hour isn't worth a notification — "you saved 20 minutes"
      // reads as a boast, not a thank-you.
      if (hours >= 1) {
        out.add(PushMessage(
          kind: PushKind.weeklySummary,
          title: 'Your week in marking',
          body: '${audience.papersThisWeek} papers marked — about ${_hoursPhrase(hours)} you didn\'t spend on them.',
          deepLink: _dashboard,
        ));
      }
    }

    return out;
  }

  /// The "your class set is marked" copy.
  ///
  /// FOLLOW-UP (server): batch completion is only ever noticed by the client
  /// polling batch_status, so nothing on the server currently knows a batch
  /// ended. Sending this at the moment it actually finishes needs a
  /// scheduled function that walks marking_batches for status != 'ended',
  /// asks Anthropic, and calls the OneSignal REST API with
  /// include_aliases.external_id = teacher_id and
  /// data.route = '/dashboard'. Deliberately not built into
  /// MARKING-PROCESS: that function is request-scoped and business-critical,
  /// and this needs a cron, not a new branch inside it.
  static PushMessage batchDoneCopy({required String label, required int papers}) => PushMessage(
        kind: PushKind.batchDone,
        title: 'Your class set is marked',
        body: '$label — $papers ${papers == 1 ? 'paper' : 'papers'} came back marked overnight.',
        deepLink: _dashboard,
      );

  /// Hours of hand-marking [papers] stood in for, to the nearest half hour.
  static double hoursSaved(int papers) {
    if (papers <= 0) return 0;
    final hours = (papers * minutesPerPaperByHand) / 60;
    return (hours * 2).round() / 2;
  }

  static String _hoursPhrase(double hours) {
    final whole = hours.floor();
    final half = hours - whole >= 0.5;
    final unit = (whole == 1 && !half) ? 'hour' : 'hours';
    if (whole == 0) return 'half an hour';
    if (!half) return '$whole $unit';
    return '$whole and a half $unit';
  }

  /// What OneSignal is told about this teacher, so its segments can send the
  /// same things [due] would allow. Every value is a string: OneSignal tags
  /// have no other type.
  static Map<String, String> tagsFor({required PushAudience audience, required PushPrefs prefs}) => {
        'queued_batch': audience.everQueuedBatch ? '1' : '0',
        'notify_batch_done': prefs.batchDone ? '1' : '0',
        'notify_plan': prefs.planNudges ? '1' : '0',
        'notify_weekly': prefs.weeklySummary ? '1' : '0',
        'month_pct': audience.monthPct.toString(),
        'papers_week': audience.papersThisWeek.toString(),
        if (audience.trialDaysLeft != null) 'trial_days_left': audience.trialDaysLeft.toString(),
      };
}
