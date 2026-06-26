import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:marking_prokect_v2/app/app_routes.dart';
import 'package:marking_prokect_v2/services/auth_service.dart';
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

  Future<void> _signIn() async {
    setState(() => _loading = true);
    try {
      await context.read<AuthService>().signInWithEmail(email: _email.text.trim(), password: _password.text);
      if (!mounted) return;
      context.go(AppRoutes.grading);
    } catch (e) {
      debugPrint('Login failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sign in failed.')));
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
                  Text('AI Marker', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: cs.primary)),
                  const SizedBox(height: 6),
                  Text('Smart grading for brilliant teachers ✨', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AiMarkerColors.neutral)),
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
                    onPressed: _loading ? null : _signIn,
                    style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: Colors.white),
                    child: _loading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Sign In'),
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
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('New to AI Marker? ', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                      TextButton(
                        style: TextButton.styleFrom(foregroundColor: cs.primary, splashFactory: NoSplash.splashFactory),
                        onPressed: () {},
                        child: const Text('Contact your admin'),
                      ),
                    ],
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
