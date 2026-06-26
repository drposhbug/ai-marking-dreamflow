import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:marking_prokect_v2/app/app_routes.dart';
import 'package:marking_prokect_v2/screens/classes/classes_main_screen.dart';
import 'package:marking_prokect_v2/screens/dashboard/dashboard_screen.dart';
import 'package:marking_prokect_v2/screens/grading/grading_home_screen.dart';
import 'package:marking_prokect_v2/screens/grading/grading_context_screen.dart';
import 'package:marking_prokect_v2/screens/grading/image_preview_screen.dart';
import 'package:marking_prokect_v2/screens/grading/result_screen.dart';
import 'package:marking_prokect_v2/screens/library/library_screen.dart';
import 'package:marking_prokect_v2/screens/login/login_screen.dart';
import 'package:marking_prokect_v2/screens/settings/settings_screen.dart';
import 'package:marking_prokect_v2/screens/students/student_profile_screen.dart';
import 'package:marking_prokect_v2/screens/classes/class_hub_screen.dart';
import 'package:marking_prokect_v2/screens/presets/create_preset_flow_screen.dart';
import 'package:marking_prokect_v2/screens/presets/preset_detail_screen.dart';
import 'package:marking_prokect_v2/screens/presets/preset_edit_screen.dart';
import 'package:marking_prokect_v2/widgets/bottom_nav_shell.dart';
import 'package:marking_prokect_v2/models/grading_preset.dart';

class AppRouter {
  static final _rootKey = GlobalKey<NavigatorState>();

  static final GoRouter router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: AppRoutes.login,
    routes: [
      GoRoute(path: AppRoutes.login, name: 'login', pageBuilder: (context, state) => const NoTransitionPage(child: LoginScreen())),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => BottomNavShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: AppRoutes.grading, name: 'grading', pageBuilder: (context, state) => const NoTransitionPage(child: GradingHomeScreen()))]),
          StatefulShellBranch(routes: [GoRoute(path: AppRoutes.dashboard, name: 'dashboard', pageBuilder: (context, state) => const NoTransitionPage(child: DashboardScreen()))]),
          StatefulShellBranch(routes: [GoRoute(path: AppRoutes.classes, name: 'classes', pageBuilder: (context, state) => const NoTransitionPage(child: ClassesMainScreen()))]),
          StatefulShellBranch(routes: [GoRoute(path: AppRoutes.library, name: 'library', pageBuilder: (context, state) => const NoTransitionPage(child: LibraryScreen()))]),
          StatefulShellBranch(routes: [GoRoute(path: AppRoutes.settings, name: 'settings', pageBuilder: (context, state) => const NoTransitionPage(child: SettingsScreen()))]),
        ],
      ),
      GoRoute(path: AppRoutes.imagePreview, name: 'imagePreview', parentNavigatorKey: _rootKey, pageBuilder: (context, state) => const MaterialPage(child: ImagePreviewScreen())),
      GoRoute(path: AppRoutes.gradingContext, name: 'gradingContext', parentNavigatorKey: _rootKey, pageBuilder: (context, state) => const MaterialPage(child: GradingContextScreen())),
      GoRoute(path: AppRoutes.result, name: 'result', parentNavigatorKey: _rootKey, pageBuilder: (context, state) {
        final submissionId = state.uri.queryParameters['submissionId'];
        return MaterialPage(child: ResultScreen(submissionId: submissionId));
      }),
      GoRoute(path: AppRoutes.classHub, name: 'classHub', parentNavigatorKey: _rootKey, pageBuilder: (context, state) {
        final classId = state.uri.queryParameters['classId'] ?? '';
        return MaterialPage(child: ClassHubScreen(classId: classId));
      }),
      GoRoute(path: AppRoutes.studentProfile, name: 'studentProfile', parentNavigatorKey: _rootKey, pageBuilder: (context, state) {
        final studentId = state.uri.queryParameters['studentId'] ?? '';
        final classId = state.uri.queryParameters['classId'];
        return MaterialPage(child: StudentProfileScreen(studentId: studentId, classId: classId));
      }),
      GoRoute(path: AppRoutes.presetFlow, name: 'presetFlow', parentNavigatorKey: _rootKey, pageBuilder: (context, state) {
        final classId = state.uri.queryParameters['classId'] ?? '';
        return MaterialPage(child: CreatePresetFlowScreen(classId: classId));
      }),
      GoRoute(path: AppRoutes.presetDetail, name: 'presetDetail', parentNavigatorKey: _rootKey, pageBuilder: (context, state) {
        final presetId = state.uri.queryParameters['presetId'] ?? '';
        return MaterialPage(child: PresetDetailScreen(presetId: presetId));
      }),
      GoRoute(path: AppRoutes.presetEdit, name: 'presetEdit', parentNavigatorKey: _rootKey, pageBuilder: (context, state) {
        final presetId = state.uri.queryParameters['presetId'];
        final extra = state.extra;
        if (extra is GradingPreset) return MaterialPage(child: PresetEditScreen(initialPreset: extra));
        return MaterialPage(child: PresetEditScreen(presetId: presetId ?? ''));
      }),
    ],
  );
}
