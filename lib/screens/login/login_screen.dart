import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:marking_prokect_v2/app/app_routes.dart';
import 'package:marking_prokect_v2/app/app_state.dart';
import 'package:marking_prokect_v2/screens/onboarding/onboarding_screen.dart';
import 'package:marking_prokect_v2/services/ai_grading_service.dart';
import 'package:marking_prokect_v2/services/auth_service.dart';
import 'package:marking_prokect_v2/services/local_store.dart';
import 'package:marking_prokect_v2/theme.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show OAuthProvider;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  /// OAuth providers the server actually has switched on — buttons only
  /// render for these, so a disabled provider can't dead-end the teacher.
  Set<String> _providers = const {};

  @override
  void initState() {
    super.initState();
    context.read<AuthService>().enabledOAuthProviders().then((p) {
      if (mounted) setState(() => _providers = p);
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Pulls the account's saved cloud profile (name, school, region, marking
  /// preferences) so an existing account gets its data back on any device.
  /// Returns true when the profile is complete — onboarding can be skipped.
  Future<bool> _restoreProfile(AuthService auth) async {
    final user = auth.currentUser;
    if (user == null) return false;
    try {
      final p = await AiGradingService().getProfile(teacherId: user.id);
      if (p == null || !mounted) return false;
      final app = context.read<AppState>();
      await auth.updateProfile(
        name: p.name.isEmpty ? null : p.name,
        school: p.school.isEmpty ? null : p.school,
      );
      if (!mounted) return false;
      if (p.region.isNotEmpty) await app.setRegion(teacherId: user.id, regionId: p.region);
      if (!mounted) return false;
      if (p.school.isNotEmpty) await app.setSchool(teacherId: user.id, school: p.school);
      if (!mounted) return false;
      if (p.markingFeedback.isNotEmpty) {
        await app.setMarkingFeedbackAll(teacherId: user.id, feedback: p.markingFeedback);
      }
      if (p.isComplete) {
        await const LocalStore().setString(OnboardingScreen.doneKey(user.id), '1');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Profile restore failed: $e');
      return false;
    }
  }

  Future<void> _routeAfterSignIn(AuthService auth, {required bool restoredDone}) async {
    final user = auth.currentUser;
    final done = user == null ? '1' : await const LocalStore().getString(OnboardingScreen.doneKey(user.id));
    if (!mounted) return;
    context.go((done == '1' || restoredDone) ? AppRoutes.grading : AppRoutes.onboarding);
  }

  /// Sign-in requires an existing account with the right password. On
  /// success the account's saved cloud profile is restored first.
  Future<void> _signIn() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || !email.contains('@')) return _snack('Enter your email address.');
    if (password.isEmpty) return _snack('Enter your password.');

    setState(() => _loading = true);
    try {
      final auth = context.read<AuthService>();
      await auth.signInWithEmail(email: email, password: password);
      // Let Android's password manager offer to save these credentials.
      TextInput.finishAutofillContext();
      if (!mounted) return;
      final restoredDone = await _restoreProfile(auth);
      if (!mounted) return;
      await _routeAfterSignIn(auth, restoredDone: restoredDone);
    } catch (e) {
      debugPrint('Login failed: $e');
      if (!mounted) return;
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Create Account opens its own sheet (email, password, confirm) so it
  /// never trips over half-filled sign-in fields; a new account always
  /// walks through the full intro afterwards.
  Future<void> _openCreateAccount() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => _CreateAccountSheet(initialEmail: _email.text.trim()),
    );
    if (created != true || !mounted) return;
    final auth = context.read<AuthService>();
    final user = auth.currentUser;
    if (user != null) {
      await const LocalStore().setString(OnboardingScreen.doneKey(user.id), '');
    }
    if (!mounted) return;
    context.go(AppRoutes.onboarding);
  }

  Future<void> _oauth(OAuthProvider provider) async {
    setState(() => _loading = true);
    try {
      final auth = context.read<AuthService>();
      await auth.signInWithProvider(provider);
      if (!mounted) return;
      final restoredDone = await _restoreProfile(auth);
      if (!mounted) return;
      await _routeAfterSignIn(auth, restoredDone: restoredDone);
    } catch (e) {
      debugPrint('OAuth sign-in failed: $e');
      if (!mounted) return;
      _snack(e.toString().replaceFirst('Exception: ', ''));
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
      await auth.signInLocal(email: 'dev@markless.app');
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

  /// One button per provider the server has enabled (Google, Microsoft,
  /// Apple) — enabling one in the Supabase dashboard is all it takes for
  /// its button to appear here on the next app open.
  List<Widget> get _oauthButtons => [
        if (_providers.contains('google'))
          OutlinedButton.icon(
            onPressed: _loading ? null : () => _oauth(OAuthProvider.google),
            icon: const Icon(Icons.g_mobiledata_rounded, size: 26),
            label: const Text('Google'),
          ),
        if (_providers.contains('azure'))
          OutlinedButton.icon(
            onPressed: _loading ? null : () => _oauth(OAuthProvider.azure),
            icon: const Icon(Icons.grid_view_rounded, size: 18),
            label: const Text('Microsoft'),
          ),
        if (_providers.contains('apple'))
          OutlinedButton.icon(
            onPressed: _loading ? null : () => _oauth(OAuthProvider.apple),
            icon: const Icon(Icons.apple_rounded, size: 22),
            label: const Text('Apple'),
          ),
      ];

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
                  AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.username, AutofillHints.email],
                          decoration: const InputDecoration(hintText: 'teacher@school.edu', labelText: 'Email'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _password,
                          obscureText: _obscure,
                          autofillHints: const [AutofillHints.password],
                          onSubmitted: (_) => _loading ? null : _signIn(),
                          decoration: InputDecoration(
                            hintText: 'Password',
                            labelText: 'Password',
                            suffixIcon: IconButton(
                              onPressed: () => setState(() => _obscure = !_obscure),
                              icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: AiMarkerColors.neutral),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: _loading ? null : _signIn,
                    style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: Colors.white),
                    child: _loading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Sign In'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: _loading ? null : _openCreateAccount,
                    child: Text('Create Account', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700)),
                  ),
                  if (_oauthButtons.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text('or continue with', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        for (var i = 0; i < _oauthButtons.length; i++) ...[
                          if (i > 0) const SizedBox(width: 10),
                          Expanded(child: _oauthButtons[i]),
                        ],
                      ],
                    ),
                  ],
                  const SizedBox(height: 18),
                  Text(
                    'Signing in with the same account always brings back your name, school, and marking preferences.',
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

/// Email + password + confirm in one dedicated sheet, so account creation
/// has its own clear validation instead of borrowing the sign-in fields.
class _CreateAccountSheet extends StatefulWidget {
  final String initialEmail;
  const _CreateAccountSheet({required this.initialEmail});

  @override
  State<_CreateAccountSheet> createState() => _CreateAccountSheetState();
}

class _CreateAccountSheetState extends State<_CreateAccountSheet> {
  late final TextEditingController _email = TextEditingController(text: widget.initialEmail);
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _creating = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || !email.contains('@')) return setState(() => _error = 'Enter your email address.');
    if (password.length < 6) return setState(() => _error = 'Password must be at least 6 characters.');
    if (password != _confirm.text) return setState(() => _error = 'Passwords don\'t match.');

    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      await context.read<AuthService>().createAccount(email: email, password: password);
      // Let Android's password manager offer to save the new credentials.
      TextInput.finishAutofillContext();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('Create account failed: $e');
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('Create your account', style: Theme.of(context).textTheme.titleLarge)),
                IconButton(onPressed: () => Navigator.of(context).pop(false), icon: Icon(Icons.close_rounded, color: AiMarkerColors.neutral)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Your password is stored securely, and your name, school, and marking preferences stay with the account.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral),
            ),
            const SizedBox(height: 14),
            AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofocus: widget.initialEmail.isEmpty,
                    autofillHints: const [AutofillHints.username, AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Email', hintText: 'teacher@school.edu'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: 'Password (6+ characters)',
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: AiMarkerColors.neutral),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirm,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.newPassword],
                    onSubmitted: (_) => _creating ? null : _create(),
                    decoration: const InputDecoration(labelText: 'Confirm password'),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.error, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _creating ? null : _create,
              style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
              child: _creating
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Create Account'),
            ),
          ],
        ),
      ),
    );
  }
}
