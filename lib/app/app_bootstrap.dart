import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:marking_prokect_v2/app/app_state.dart';
import 'package:marking_prokect_v2/models/grading_preset.dart';
import 'package:marking_prokect_v2/services/auth_service.dart';
import 'package:marking_prokect_v2/services/classes_service.dart';
import 'package:marking_prokect_v2/services/presets_service.dart';
import 'package:marking_prokect_v2/services/student_class_links_service.dart';
import 'package:marking_prokect_v2/services/students_service.dart';
import 'package:marking_prokect_v2/services/submissions_service.dart';
import 'package:marking_prokect_v2/services/supabase_hook.dart';
import 'package:provider/provider.dart';

class AppBootstrap extends StatefulWidget {
  final Widget child;
  const AppBootstrap({super.key, required this.child});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await context.read<AppState>().initTheme();

      final auth = context.read<AuthService>();
      await auth.init();

      final user = auth.currentUser;
      if (user == null) return;

      // Pull Supabase user preferences if available (default_mode / harshness).
      try {
        final hook = context.read<SupabaseHook>();
        final row = await hook.fetchUserByEmail(user.email);
        if (row.isNotEmpty) {
          final rawMode = (row['default_mode'] ?? '').toString().trim();
          final mode = rawMode.isEmpty ? null : GradingMode.values.cast<GradingMode?>().firstWhere((m) => m?.name == rawMode, orElse: () => null);
          if (mode != null) {
            await context.read<AppState>().setDefaultMode(teacherId: user.id, mode: mode);
          }
          final harsh = (row['default_harshness'] as num?)?.toInt();
          if (harsh != null) {
            await context.read<AppState>().setDefaultHarshness(teacherId: user.id, harshness: harsh);
          }
        }
      } catch (e) {
        debugPrint('AppBootstrap Supabase preference sync failed: $e');
      }

      await context.read<AppState>().initForUser(teacherId: user.id);

      final classes = context.read<ClassesService>();
      await classes.init(teacherId: user.id);

      final students = context.read<StudentsService>();
      await students.init(teacherId: user.id, classIds: classes.classes.map((e) => e.id).toList());

      await context.read<StudentClassLinksService>().init();

      final presets = context.read<PresetsService>();
      await presets.init(teacherId: user.id, classIds: classes.classes.map((e) => e.id).toList());

      final submissions = context.read<SubmissionsService>();
      await submissions.init(
        teacherId: user.id,
        studentIds: students.students.map((e) => e.id).toList(),
        classIds: classes.classes.map((e) => e.id).toList(),
        presetIds: presets.presets.map((e) => e.id).toList(),
      );
    } catch (e) {
      debugPrint('AppBootstrap init failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))));
    }
    return widget.child;
  }
}
