import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:marking_prokect_v2/app/app_state.dart';
import 'package:marking_prokect_v2/models/grading_preset.dart';
import 'package:marking_prokect_v2/main.dart' show rootMessengerKey;
import 'package:marking_prokect_v2/services/auth_service.dart';
import 'package:marking_prokect_v2/services/batch_marking.dart';
import 'package:marking_prokect_v2/services/overnight_service.dart';
import 'package:marking_prokect_v2/services/billing_service.dart';
import 'package:marking_prokect_v2/services/classes_service.dart';
import 'package:marking_prokect_v2/services/presets_service.dart';
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

  /// Whose data is currently in memory. Signing in later in the session
  /// changes this, which is what triggers the reload.
  String? _loadedForUserId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _auth?.removeListener(_onAuthChanged);
    super.dispose();
  }

  Future<void> _init() async {
    try {
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

    // Pull the saved profile if available (default_mode / harshness).
    try {
      final hook = context.read<SupabaseHook>();
      final row = await hook.fetchProfile(teacherId: userId);
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
    if (overnight.batches.isNotEmpty) {
      final filed = await checkOvernight(context);
      if (filed > 0) {
        rootMessengerKey.currentState?.showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 6),
            content: Text('$filed papers finished marking overnight — they\'re on your dashboard.'),
          ),
        );
      }
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
