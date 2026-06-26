import 'package:flutter/material.dart';
import 'package:marking_prokect_v2/app/app_bootstrap.dart';
import 'package:marking_prokect_v2/app/app_state.dart';
import 'package:marking_prokect_v2/nav.dart';
import 'package:marking_prokect_v2/services/auth_service.dart';
import 'package:marking_prokect_v2/services/classes_service.dart';
import 'package:marking_prokect_v2/services/presets_service.dart';
import 'package:marking_prokect_v2/services/supabase_hook.dart';
import 'package:marking_prokect_v2/services/student_class_links_service.dart';
import 'package:marking_prokect_v2/services/students_service.dart';
import 'package:marking_prokect_v2/services/submissions_service.dart';
import 'package:marking_prokect_v2/theme.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Main entry point for the application
///
/// This sets up:
/// - go_router navigation
/// - Material 3 theming with light/dark modes
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://zxikjizraeqejbsncqpg.supabase.co');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  if (supabaseAnonKey.isNotEmpty) {
    try {
      await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
    } catch (e) {
      // Keep the app usable in local-only mode if Supabase init fails.
      debugPrint('Supabase.initialize failed: $e');
    }
  } else {
    debugPrint('Supabase anon key missing. Running in local-only mode. Set SUPABASE_ANON_KEY via Dreamflow Supabase panel.');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider(create: (_) => ClassesService()),
        ChangeNotifierProvider(create: (_) => StudentsService()),
        ChangeNotifierProvider(create: (_) => StudentClassLinksService()),
        ChangeNotifierProvider(create: (_) => PresetsService()),
        ChangeNotifierProvider(create: (_) => SubmissionsService()),
        ChangeNotifierProvider(create: (_) => SupabaseHook()),
      ],
      child: AppBootstrap(
        child: Consumer<AppState>(
          builder: (context, appState, _) => MaterialApp.router(
            title: 'AI Marker',
            debugShowCheckedModeBanner: false,
            theme: lightTheme,
            darkTheme: darkTheme,
            themeMode: appState.themeMode,
            routerConfig: AppRouter.router,
          ),
        ),
      ),
    );
  }
}

