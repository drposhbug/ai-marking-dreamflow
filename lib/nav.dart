import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:marking_prokect_v2/services/ai_grading_service.dart';
import 'package:marking_prokect_v2/app/app_routes.dart';
import 'package:marking_prokect_v2/screens/classes/classes_main_screen.dart';
import 'package:marking_prokect_v2/screens/dashboard/dashboard_screen.dart';
import 'package:marking_prokect_v2/screens/grading/grading_home_screen.dart';
import 'package:marking_prokect_v2/screens/grading/grading_context_screen.dart';
import 'package:marking_prokect_v2/screens/grading/pilot_review_screen.dart';
import 'package:marking_prokect_v2/screens/grading/result_screen.dart';
import 'package:marking_prokect_v2/screens/grading/ways_to_mark_screen.dart';
import 'package:marking_prokect_v2/screens/library/library_screen.dart';
import 'package:marking_prokect_v2/screens/login/login_screen.dart';
import 'package:marking_prokect_v2/screens/onboarding/onboarding_screen.dart';
import 'package:marking_prokect_v2/screens/import/import_responses_screen.dart';
import 'package:marking_prokect_v2/screens/import/prepare_test_screen.dart';
import 'package:marking_prokect_v2/screens/import/split_stack_screen.dart';
import 'package:marking_prokect_v2/screens/planning/planning_screen.dart';
import 'package:marking_prokect_v2/screens/plans/plans_screen.dart';
import 'package:marking_prokect_v2/screens/reports/report_comments_screen.dart';
import 'package:marking_prokect_v2/screens/settings/settings_screen.dart';
import 'package:marking_prokect_v2/screens/students/student_profile_screen.dart';
import 'package:marking_prokect_v2/screens/classes/class_analysis_screen.dart';
import 'package:marking_prokect_v2/screens/classes/class_hub_screen.dart';
import 'package:marking_prokect_v2/screens/classes/export_marks_screen.dart';
import 'package:marking_prokect_v2/screens/presets/create_preset_flow_screen.dart';
import 'package:marking_prokect_v2/screens/presets/preset_detail_screen.dart';
import 'package:marking_prokect_v2/screens/presets/preset_edit_screen.dart';
import 'package:marking_prokect_v2/widgets/bottom_nav_shell.dart';
import 'package:marking_prokect_v2/widgets/responsive.dart';
import 'package:marking_prokect_v2/models/grading_preset.dart';

class AppRouter {
  static final _rootKey = GlobalKey<NavigatorState>();

  // Every screen reaches the teacher through one of these two builders, so
  // the desktop content column is decided once here instead of in each of the
  // twenty-odd screens. On a phone the frame does nothing at all.
  static Page<void> _page(Widget child) => MaterialPage<void>(child: AppPageFrame(child: child));
  static Page<void> _instantPage(Widget child) => NoTransitionPage<void>(child: AppPageFrame(child: child));

  // Screens that are a run of cards rather than a run of sentences. They keep
  // the reading measure on a laptop and grow with a desk monitor, because a
  // card is not a paragraph and two of them side by side beats one tall
  // column with half the monitor empty beside it.
  static Page<void> _wideInstantPage(Widget child) => NoTransitionPage<void>(
        child: AppPageFrame(
          maxWidth: Breakpoints.maxWideContentWidth,
          widthFor: Breakpoints.wideContentWidthFor,
          child: child,
        ),
      );

  // Sign-in is one illustration beside one short form and the first thing a
  // teacher ever sees, so it fills the monitor instead of sitting in a
  // 960px column in the middle of it.
  static Page<void> _splashPage(Widget child) => NoTransitionPage<void>(
        child: AppPageFrame(
          maxWidth: Breakpoints.maxSplashWidth,
          widthFor: Breakpoints.splashWidthFor,
          child: child,
        ),
      );

  static final GoRouter router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: AppRoutes.login,
    redirect: (context, state) {
      // OAuth deep-link callback (com.markless.app://login-callback?code=...):
      // supabase_flutter exchanges the code itself — the router just needs
      // to stay on the login screen, which finishes sign-in once the
      // session lands, instead of showing "Page Not Found".
      if (state.uri.host == 'login-callback' || state.uri.path.contains('login-callback')) {
        return AppRoutes.login;
      }
      return null;
    },
    routes: [
      GoRoute(path: AppRoutes.login, name: 'login', pageBuilder: (context, state) => _splashPage(const LoginScreen())),
      GoRoute(path: AppRoutes.onboarding, name: 'onboarding', pageBuilder: (context, state) => _instantPage(const OnboardingScreen())),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => BottomNavShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: AppRoutes.grading, name: 'grading', pageBuilder: (context, state) => _wideInstantPage(const GradingHomeScreen()))]),
          StatefulShellBranch(routes: [GoRoute(path: AppRoutes.dashboard, name: 'dashboard', pageBuilder: (context, state) => _instantPage(const DashboardScreen()))]),
          StatefulShellBranch(routes: [GoRoute(path: AppRoutes.classes, name: 'classes', pageBuilder: (context, state) => _wideInstantPage(const ClassesMainScreen()))]),
          StatefulShellBranch(routes: [GoRoute(path: AppRoutes.library, name: 'library', pageBuilder: (context, state) => _wideInstantPage(const LibraryScreen()))]),
          StatefulShellBranch(routes: [GoRoute(path: AppRoutes.settings, name: 'settings', pageBuilder: (context, state) => _instantPage(const SettingsScreen()))]),
        ],
      ),
      GoRoute(path: AppRoutes.planning, name: 'planning', parentNavigatorKey: _rootKey, pageBuilder: (context, state) => _page(const PlanningScreen())),
      GoRoute(path: AppRoutes.plans, name: 'plans', parentNavigatorKey: _rootKey, pageBuilder: (context, state) => _page(const PlansScreen())),
      GoRoute(path: AppRoutes.importResponses, name: 'importResponses', parentNavigatorKey: _rootKey, pageBuilder: (context, state) => _page(const ImportResponsesScreen())),
      GoRoute(path: AppRoutes.exportMarks, name: 'exportMarks', parentNavigatorKey: _rootKey, pageBuilder: (context, state) => _page(const ExportMarksScreen())),
      GoRoute(path: AppRoutes.waysToMark, name: 'waysToMark', parentNavigatorKey: _rootKey, pageBuilder: (context, state) => _page(const WaysToMarkScreen())),
      GoRoute(path: AppRoutes.reportComments, name: 'reportComments', parentNavigatorKey: _rootKey, pageBuilder: (context, state) => _page(const ReportCommentsScreen())),
      GoRoute(path: AppRoutes.prepareTest, name: 'prepareTest', parentNavigatorKey: _rootKey, pageBuilder: (context, state) => _page(const PrepareTestScreen())),
      GoRoute(path: AppRoutes.splitStack, name: 'splitStack', parentNavigatorKey: _rootKey, pageBuilder: (context, state) => _page(const SplitStackScreen())),
      GoRoute(path: AppRoutes.pilotReview, name: 'pilotReview', parentNavigatorKey: _rootKey, pageBuilder: (context, state) {
        final jobId = state.uri.queryParameters['jobId'] ?? '';
        return _page(PilotReviewScreen(jobId: jobId));
      }),
      GoRoute(path: AppRoutes.gradingContext, name: 'gradingContext', parentNavigatorKey: _rootKey, pageBuilder: (context, state) => _page(const GradingContextScreen())),
      GoRoute(path: AppRoutes.result, name: 'result', parentNavigatorKey: _rootKey, pageBuilder: (context, state) {
        final submissionId = state.uri.queryParameters['submissionId'];
        // The grading flow passes the live result and scanned pages via
        // extra so the result shows immediately without a DB round-trip.
        AiGradeResult? gradeResult;
        Uint8List? imageBytes;
        List<Uint8List>? pageImages;
        final extra = state.extra;
        if (extra is Map) {
          final gr = extra['gradeResult'];
          if (gr is AiGradeResult) gradeResult = gr;
          final ib = extra['imageBytes'];
          if (ib is Uint8List) imageBytes = ib;
          final pages = extra['pageImages'];
          if (pages is List) pageImages = pages.whereType<Uint8List>().toList(growable: false);
        }
        return _page(ResultScreen(
          submissionId: submissionId,
          gradeResult: gradeResult,
          imageBytes: imageBytes,
          pageImages: pageImages,
        ));
      }),
      GoRoute(path: AppRoutes.classHub, name: 'classHub', parentNavigatorKey: _rootKey, pageBuilder: (context, state) {
        final classId = state.uri.queryParameters['classId'] ?? '';
        return _page(ClassHubScreen(classId: classId));
      }),
      GoRoute(path: AppRoutes.classAnalysis, name: 'classAnalysis', parentNavigatorKey: _rootKey, pageBuilder: (context, state) {
        final classId = state.uri.queryParameters['classId'] ?? '';
        return _page(ClassAnalysisScreen(classId: classId));
      }),
      GoRoute(path: AppRoutes.studentProfile, name: 'studentProfile', parentNavigatorKey: _rootKey, pageBuilder: (context, state) {
        final studentId = state.uri.queryParameters['studentId'] ?? '';
        final classId = state.uri.queryParameters['classId'];
        return _page(StudentProfileScreen(studentId: studentId, classId: classId));
      }),
      GoRoute(path: AppRoutes.presetFlow, name: 'presetFlow', parentNavigatorKey: _rootKey, pageBuilder: (context, state) {
        final classId = state.uri.queryParameters['classId'] ?? '';
        return _page(CreatePresetFlowScreen(classId: classId));
      }),
      GoRoute(path: AppRoutes.presetDetail, name: 'presetDetail', parentNavigatorKey: _rootKey, pageBuilder: (context, state) {
        final presetId = state.uri.queryParameters['presetId'] ?? '';
        return _page(PresetDetailScreen(presetId: presetId));
      }),
      GoRoute(path: AppRoutes.presetEdit, name: 'presetEdit', parentNavigatorKey: _rootKey, pageBuilder: (context, state) {
        final presetId = state.uri.queryParameters['presetId'];
        final extra = state.extra;
        if (extra is GradingPreset) return _page(PresetEditScreen(initialPreset: extra));
        return _page(PresetEditScreen(presetId: presetId ?? ''));
      }),
    ],
  );
}
