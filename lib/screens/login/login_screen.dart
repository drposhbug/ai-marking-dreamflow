import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:marking_prokect_v2/app/app_routes.dart';
import 'package:marking_prokect_v2/app/app_state.dart';
import 'package:marking_prokect_v2/screens/onboarding/onboarding_screen.dart';
import 'package:marking_prokect_v2/services/auth_service.dart';
import 'package:marking_prokect_v2/services/local_store.dart';
import 'package:marking_prokect_v2/theme.dart';
import 'package:provider/provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController(text: 'teacher@school.edu');
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// [createAccount] always walks through the full intro (name, school,
  /// classes); plain sign-in only shows it if this account never finished it.
  Future<void> _signIn({bool createAccount = false}) async {
    setState(() => _loading = true);
    try {
      final auth = context.read<AuthService>();
      await auth.signInWithEmail(email: _email.text.trim(), password: _password.text);
      if (!mounted) return;
      final user = auth.currentUser;
      if (createAccount && user != null) {
        // Reset the done-flag so the intro runs even for a returning email.
        await const LocalStore().setString(OnboardingScreen.doneKey(user.id), '');
      }
      if (!mounted) return;
      final done = user == null ? '1' : await const LocalStore().getString(OnboardingScreen.doneKey(user.id));
      if (!mounted) return;
      context.go(!createAccount && done == '1' ? AppRoutes.grading : AppRoutes.onboarding);
    } catch (e) {
      debugPrint('Login failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sign in failed.')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Developer shortcut: instant dev account, onboarding skipped, sensible
  /// defaults set — straight to the app for feature testing.
  Future<void> _devMode() async {
    setState(() => _loading = true);
    try {
      final auth = context.read<AuthService>();
      await auth.signInWithEmail(email: 'dev@markless.app', password: 'dev');
      if (!mounted) return;
      final user = auth.currentUser;
      if (user != null) {
        await const LocalStore().setString(OnboardingScreen.doneKey(user.id), '1');
        if (!mounted) return;
        final app = context.read<AppState>();
        if (app.region.isEmpty) await app.setRegion(teacherId: user.id, regionId: 'ca-on');
        if (!mounted) return;
        if (app.school.isEmpty) await app.setSchool(teacherId: user.id, school: 'Dev Test School');
        await auth.updateProfile(name: 'Dev Teacher', school: 'Dev Test School');
      }
      if (!mounted) return;
      context.go(AppRoutes.grading);
    } catch (e) {
      debugPrint('Dev mode sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.center,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: cs.primary.withValues(alpha: 0.10),
                        border: Border.all(color: cs.primary.withValues(alpha: 0.20)),
                      ),
                      child: Icon(Icons.school_rounded, color: cs.primary, size: 32),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text('Markless', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: cs.primary)),
                  const SizedBox(height: 6),
                  Text('Mark less. Teach more. ✨', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AiMarkerColors.neutral)),
                  const SizedBox(height: 22),
                  TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(hintText: 'teacher@school.edu', labelText: 'Email')),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      hintText: 'Password',
                      labelText: 'Password',
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: AiMarkerColors.neutral),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      style: TextButton.styleFrom(foregroundColor: cs.primary, splashFactory: NoSplash.splashFactory),
                      onPressed: () {},
                      child: const Text('Forgot password?'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: _loading ? null : () => _signIn(),
                    style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: Colors.white),
                    child: _loading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Sign In'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: _loading ? null : () => _signIn(createAccount: true),
                    child: Text('Create Account', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(child: Divider(color: cs.outline.withValues(alpha: 0.35))),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('or continue with', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral))),
                      Expanded(child: Divider(color: cs.outline.withValues(alpha: 0.35))),
                    ],
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _signIn,
                    icon: Icon(Icons.g_mobiledata_rounded, color: cs.primary),
                    label: const Text('Sign in with Google'),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Signing in with the same email always brings back your classes and answer keys.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral),
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: _loading ? null : _devMode,
                    icon: Icon(Icons.build_rounded, size: 16, color: AiMarkerColors.neutral),
                    label: Text('Developer mode — skip sign-in & setup', style: TextStyle(color: AiMarkerColors.neutral)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
