import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:marking_prokect_v2/app/app_state.dart';
import 'package:marking_prokect_v2/models/grading_preset.dart';
import 'package:marking_prokect_v2/main.dart' show rootMessengerKey;
import 'package:marking_prokect_v2/nav.dart';
import 'package:marking_prokect_v2/services/ai_grading_service.dart';
import 'package:marking_prokect_v2/services/auth_service.dart';
import 'package:marking_prokect_v2/services/batch_marking.dart';
import 'package:marking_prokect_v2/services/overnight_service.dart';
import 'package:marking_prokect_v2/services/billing_service.dart';
import 'package:marking_prokect_v2/services/classes_service.dart';
import 'package:marking_prokect_v2/services/cloud_collection.dart';
import 'package:marking_prokect_v2/services/presets_service.dart';
import 'package:marking_prokect_v2/services/push_service.dart';
import 'package:marking_prokect_v2/services/student_class_links_service.dart';
import 'package:marking_prokect_v2/services/students_service.dart';
import 'package:marking_prokect_v2/services/submissions_service.dart';
import 'package:marking_prokect_v2/services/supabase_hook.dart';
import 'package:marking_prokect_v2/theme.dart';
import 'package:provider/provider.dart';

class AppBootstrap extends StatefulWidget {
  final Widget child;
  const AppBootstrap({super.key, required this.child});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  bool _loading = true;
  AuthService? _auth;
  OvernightService? _overnight;

  /// Whose data is currently in memory. Signing in later in the session
  /// changes this, which is what triggers the reload.
  String? _loadedForUserId;
  bool _busy = false;

  /// Batches already known about, so a set the teacher queues during this
  /// session can be told apart from the ones restored off disk at launch.
  Set<String> _knownBatchIds = const {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _auth?.removeListener(_onAuthChanged);
    _overnight?.removeListener(_onOvernightChanged);
    super.dispose();
  }

  Future<void> _init() async {
    try {
      // Tapping a notification has to land on the marked papers, not on
      // whatever screen the app was last left on.
      context.read<PushService>().onDeepLink = (route) {
        try {
          AppRouter.router.go(route);
        } catch (e) {
          debugPrint('AppBootstrap deep link to $route failed: $e');
        }
      };

      await context.read<AppState>().initTheme();

      final auth = context.read<AuthService>();
      _auth = auth;
      await auth.init();
      await _loadCurrentUser();
      // Classes, students and marked results are only ever loaded here. A
      // teacher who opens the app signed out and signs in afterwards would
      // otherwise sit in front of an empty dashboard until the next launch —
      // so re-run the load whenever the signed-in account changes.
      auth.addListener(_onAuthChanged);
    } catch (e) {
      debugPrint('AppBootstrap init failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onAuthChanged() {
    final id = _auth?.currentUser?.id;
    if (id == null) {
      // Signed out — the next sign-in must load again, even if it's the
      // same account.
      _loadedForUserId = null;
      return;
    }
    if (id == _loadedForUserId || _busy) return;
    _loadCurrentUser();
  }

  /// Loads (or reloads) everything the signed-in teacher owns. Re-entrant:
  /// a sign-in that lands mid-load is picked up on the next pass.
  Future<void> _loadCurrentUser() async {
    if (_busy) return;
    _busy = true;
    try {
      var user = _auth?.currentUser;
      while (mounted && user != null && user.id != _loadedForUserId) {
        await _loadUserData(user.id);
        _loadedForUserId = user.id;
        user = _auth?.currentUser;
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _loadUserData(String userId) async {
    // Tie RevenueCat purchases to the account so Pro follows the teacher
    // across devices. Fire-and-forget — billing must never block startup.
    try {
      context.read<BillingService>().logIn(userId);
    } catch (e) {
      debugPrint('AppBootstrap billing login failed: $e');
    }

    // Same id on the OneSignal side, so a nudge about a plan reaches the
    // phone that holds the plan. This asks for no permission — that waits
    // until the teacher has queued a class set.
    try {
      await context.read<PushService>().login(userId);
    } catch (e) {
      debugPrint('AppBootstrap push login failed: $e');
    }
    if (!mounted) return;

    // ── R19.3: ONE bootstrap_sync round trip replaces the separate
    // profile, usage, keys and three-collection fetches the app used to
    // make on every open. The usage answer is primed into the getUsage
    // cache (so _tellTheTeacher's meter read below is free) and the
    // collections are primed into CloudCollection (so the service inits
    // below are answered without their own edge calls).
    BootstrapSnapshot? boot;
    try {
      boot = await AiGradingService().bootstrapSync(teacherId: userId);
    } catch (e) {
      // A transient failure only — the per-action calls below still run,
      // so startup degrades to the old behaviour instead of breaking.
      debugPrint('AppBootstrap bootstrap_sync failed (falling back): $e');
    }
    if (boot != null) {
      CloudCollection.prime(
        teacherId: userId,
        // A local-only account (no Supabase session) has nothing in the
        // cloud and every call would be refused — prime the three kinds
        // empty so the services don't even ask.
        collections: boot.localOnly
            ? const {
                CloudCollection.kClasses: [],
                CloudCollection.kStudents: [],
                CloudCollection.kLinks: [],
              }
            : boot.collections,
      );
    }
    if (!mounted) return;

    // Pull the saved profile if available (default_mode / harshness).
    try {
      // VERSION TOLERANCE: bootstrapSync answers null when the deployed
      // function predates bootstrap_sync — fall back to the individual
      // get_profile call so an older backend can never brick app startup.
      // Remove the fallback once the deploy is confirmed everywhere.
      final row = boot != null
          ? (boot.profile ?? const <String, dynamic>{})
          : await context.read<SupabaseHook>().fetchProfile(teacherId: userId);
      if (row.isNotEmpty && mounted) {
        final rawMode = (row['default_mode'] ?? '').toString().trim();
        final mode = rawMode.isEmpty ? null : GradingMode.values.cast<GradingMode?>().firstWhere((m) => m?.name == rawMode, orElse: () => null);
        if (mode != null) {
          await context.read<AppState>().setDefaultMode(teacherId: userId, mode: mode);
        }
        final harsh = (row['default_harshness'] as num?)?.toInt();
        if (harsh != null && mounted) {
          await context.read<AppState>().setDefaultHarshness(teacherId: userId, harshness: harsh);
        }
      }
    } catch (e) {
      debugPrint('AppBootstrap Supabase preference sync failed: $e');
    }
    if (!mounted) return;

    await context.read<AppState>().initForUser(teacherId: userId);
    if (!mounted) return;

    final classes = context.read<ClassesService>();
    await classes.init(teacherId: userId);
    if (!mounted) return;

    final students = context.read<StudentsService>();
    await students.init(teacherId: userId, classIds: classes.classes.map((e) => e.id).toList());
    if (!mounted) return;

    await context.read<StudentClassLinksService>().init(teacherId: userId);
    if (!mounted) return;

    final presets = context.read<PresetsService>();
    await presets.init(teacherId: userId, classIds: classes.classes.map((e) => e.id).toList());
    if (!mounted) return;

    final submissions = context.read<SubmissionsService>();
    await submissions.init(
      teacherId: userId,
      studentIds: students.students.map((e) => e.id).toList(),
      classIds: classes.classes.map((e) => e.id).toList(),
      presetIds: presets.presets.map((e) => e.id).toList(),
    );
    if (!mounted) return;

    // Overnight marking that finished while the app was closed gets filed
    // now — this is the "wake up to marked papers" half of the feature.
    final overnight = context.read<OvernightService>();
    await overnight.init();
    if (!mounted) return;
    // Everything already in flight was queued on a previous run; only a
    // batch added after this point means "the teacher just sent one off".
    _knownBatchIds = overnight.batches.map((b) => b.batchId).toSet();
    _overnight?.removeListener(_onOvernightChanged);
    _overnight = overnight;
    overnight.addListener(_onOvernightChanged);

    var filed = 0;
    var batchLabel = 'Your class set';
    if (overnight.batches.isNotEmpty) {
      batchLabel = overnight.batches.first.label;
      filed = await checkOvernight(context);
    }
    if (!mounted) return;
    await _tellTheTeacher(userId: userId, papersJustFiled: filed, batchLabel: batchLabel);
    if (!mounted) return;
    _tellThemWhatIsMissing(overnight.lastReport);
  }

  /// Papers that went off overnight and are never coming back.
  ///
  /// Said out loud, by name. A teacher who handed over thirty papers and
  /// got twenty-seven has to find out from us, not from a gap in the
  /// gradebook three days later when they come to write reports.
  void _tellThemWhatIsMissing(OvernightReport? report) {
    final missing = report?.unfinished ?? const <String>[];
    if (missing.isEmpty) return;
    final named = missing.take(3).join(', ');
    final rest = missing.length - 3;
    final who = rest > 0 ? '$named and $rest more' : named;
    rootMessengerKey.currentState?.showSnackBar(SnackBar(
      duration: const Duration(seconds: 8),
      content: Text(missing.length == 1
          ? '$who didn\'t come back marked. Scan that one again — nothing else was affected.'
          : '${missing.length} papers didn\'t come back marked ($who). Scan those again — the rest are on your dashboard.'),
    ));
  }

  /// A class set queued during this session is the one moment we ask for
  /// notification permission — the teacher has just handed over thirty
  /// papers and wants to know when the marks land.
  void _onOvernightChanged() {
    final overnight = _overnight;
    final userId = _loadedForUserId;
    if (!mounted || overnight == null || userId == null) return;
    final ids = overnight.batches.map((b) => b.batchId).toSet();
    final fresh = ids.difference(_knownBatchIds);
    _knownBatchIds = ids;
    if (fresh.isEmpty) return;
    context.read<PushService>().onBatchQueued(teacherId: userId);
  }

  /// Says what happened, and tells OneSignal who this teacher is to its
  /// segments.
  ///
  /// The "class set is marked" line goes through PushService so the wording
  /// and the Settings toggle are the same whether it arrives as a push or
  /// as this banner. Until the server-side sender exists (see
  /// PushService.batchDoneCopy) this banner is the only place it appears.
  Future<void> _tellTheTeacher({required String userId, required int papersJustFiled, required String batchLabel}) async {
    final push = context.read<PushService>();
    final week = DateTime.now().subtract(const Duration(days: 7));
    final papersThisWeek = context.read<SubmissionsService>().submissions.where((s) => s.createdAt.isAfter(week)).length;

    var monthPct = 0;
    try {
      monthPct = (await AiGradingService().getUsage(teacherId: userId)).monthPct;
    } catch (e) {
      debugPrint('AppBootstrap usage lookup for notifications failed: $e');
    }
    if (!mounted) return;

    final audience = PushAudience(
      // Papers coming back is itself proof a batch was queued — a teacher
      // upgrading into this build shouldn't lose the banner just because
      // their set was sent off before push existed.
      everQueuedBatch: push.everQueuedBatch || papersJustFiled > 0,
      papersJustFiled: papersJustFiled,
      batchLabel: batchLabel,
      trialDaysLeft: context.read<BillingService>().trialDaysLeft,
      monthPct: monthPct,
      papersThisWeek: papersThisWeek,
    );
    await push.syncAudience(audience);

    // enabled: true because this is the in-app banner, not the push — it
    // has to keep working in a build with no OneSignal key. The Settings
    // toggle and the "never queued a batch" rule still apply.
    final marked = PushService.due(enabled: true, prefs: push.prefs, audience: audience)
        .where((m) => m.kind == PushKind.batchDone)
        .toList();
    if (marked.isNotEmpty) {
      rootMessengerKey.currentState?.showSnackBar(
        SnackBar(duration: const Duration(seconds: 6), content: Text(marked.first.body)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      // Wrapped in its own MaterialApp: this sits above the app's own
      // MaterialApp, so a bare Scaffold here has no Directionality to read.
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: context.watch<AppState>().themeMode,
        home: const Scaffold(body: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))),
      );
    }
    return widget.child;
  }
}
