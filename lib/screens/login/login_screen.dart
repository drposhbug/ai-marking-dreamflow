import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
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
import 'package:marking_prokect_v2/widgets/paper.dart';
import 'package:marking_prokect_v2/widgets/responsive.dart';
import 'package:provider/provider.dart';
import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' show AuthState, OAuthProvider;

/// The widest the sign-in half of the sheet is allowed to get. Email,
/// password and three buttons need about this much and nothing beyond it —
/// a field stretched across a monitor looks like a mistake.
const double _signInHalfMax = 560;

/// How much bigger this sheet is than the one that fitted the old 960px
/// column, and the interpolation that spends it. Both live in [Breakpoints]
/// with the rest of the app's sizing numbers so they can be tested.
const _growth = Breakpoints.sheetGrowthFor;
const _at = Breakpoints.grown;

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

  StreamSubscription<AuthState>? _authSub;
  bool _adopting = false;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthService>();
    auth.enabledOAuthProviders().then((p) {
      if (mounted) setState(() => _providers = p);
    });
    // A session may already exist (stay signed in from a previous run) or
    // land mid-frame (OAuth deep link the router bounced back here) —
    // adopt it and continue instead of asking for the password again.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _prefillEmailFromSite();
      _adoptSessionIfAny();
    });
    _authSub = auth.authStateChanges?.listen((s) {
      if (s.session != null) _adoptSessionIfAny();
    });
  }

  /// The marketing site has no backend, so its sign-in section can only
  /// hand the teacher's address across in the link it opens the app with
  /// (`?email=...`). Fill it in so she does not type it twice.
  ///
  /// It is a prefill and nothing more: a URL is not proof of who anyone
  /// is, so this never touches the password, never signs anything in, and
  /// never overwrites an address she or her browser already put there.
  /// The value is somebody's text off a link, so anything that is not
  /// plainly an email address is dropped rather than shown to her.
  void _prefillEmailFromSite() {
    if (!kIsWeb || _email.text.isNotEmpty) return;
    String? raw;
    try {
      raw = GoRouterState.of(context).uri.queryParameters['email'];
    } catch (_) {
      // No router above us (a test harness, say) — the address bar still
      // answers below.
    }
    // The app is served under a hash route, so the site's query sits on
    // the page URL ahead of the '#/login' the router sees.
    if (raw == null || raw.isEmpty) raw = Uri.base.queryParameters['email'];
    final email = (raw ?? '').trim();
    if (email.isEmpty || email.length > 254) return;
    if (!RegExp(r'^[^@\s]+@[^@\s.]+(\.[^@\s.]+)+$').hasMatch(email)) return;
    _email.text = email;
  }

  /// Completes sign-in from an already-established Supabase session.
  Future<void> _adoptSessionIfAny() async {
    if (_adopting || _loading || !mounted) return;
    _adopting = true;
    try {
      final auth = context.read<AuthService>();
      if (!await auth.adoptSupabaseSession()) return;
      if (!mounted) return;
      final restoredDone = await _restoreProfile(auth);
      if (!mounted) return;
      await _routeAfterSignIn(auth, restoredDone: restoredDone);
    } catch (e) {
      debugPrint('Session adopt failed: $e');
    } finally {
      _adopting = false;
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
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
      final cloudName = AuthService.normalizeAutoName(p.name, user.email);
      await auth.updateProfile(
        name: cloudName.isEmpty ? null : cloudName,
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
    // Even a "done" account must have the basics: the school picks the
    // curriculum, the name goes on feedback. Any sign-in (email, Google,
    // Apple) with those missing runs the short setup first.
    final needsInfo = user != null && (user.school.trim().isEmpty || user.name.trim().isEmpty);
    context.go(((done == '1' || restoredDone) && !needsInfo) ? AppRoutes.grading : AppRoutes.onboarding);
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
  /// walks through the full intro afterwards. The sheet can also hand off
  /// to Google sign-in ('google') for teachers nudged that way.
  Future<void> _openCreateAccount() async {
    final outcome = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => _CreateAccountSheet(initialEmail: _email.text.trim(), googleAvailable: _providers.contains('google')),
    );
    if (outcome == null || !mounted) return;
    if (outcome == 'google') return _oauth(OAuthProvider.google);
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
    } catch (e) {
      // The profile writes above are cloud calls, and dev mode exists to get
      // into the app WITHOUT a working backend. Failing them must not strand
      // you on the login screen: the local sign-in has already happened.
      debugPrint('Dev mode profile setup failed (continuing anyway): $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    // Outside the try on purpose, so a dead backend cannot strand you here.
    if (!mounted) return;
    if (context.read<AuthService>().currentUser != null) context.go(AppRoutes.grading);
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
    return LayoutBuilder(
      builder: (context, constraints) {
        // Two shapes, from the app's own breakpoints: a phone gets one
        // column, a desk gets the sheet with the marking beside the form.
        final layout = Breakpoints.layoutFor(constraints.maxWidth);
        final tones = PaperTones.of(context);
        return layout == AppLayout.expanded ? _deskLayout(context, tones) : _pageLayout(context, tones);
      },
    );
  }

  /// Phone. The screen is the page: paper out to the edges, the red margin
  /// rule of an exercise book running its whole height, and everything
  /// written to the right of that rule.
  Widget _pageLayout(BuildContext context, PaperTones tones) {
    const gutter = 22.0;
    return Scaffold(
      backgroundColor: tones.paper,
      // Expand, not the default: a loose Stack lets the scroll view shrink
      // to its content, and then the rule stops halfway down the page.
      body: Stack(
        fit: StackFit.expand,
        children: [
          // The rule runs the height of the page whether or not there is
          // writing beside it -- that is what makes it a page rather than a
          // divider between two boxes.
          Positioned(
            left: gutter,
            top: 0,
            bottom: 0,
            width: 1,
            child: ColoredBox(color: tones.pen.withValues(alpha: 0.45)),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, page) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(gutter + 16, 26, 20, 28),
                child: ConstrainedBox(
                  // Sits in the middle of the page when it fits, the way it
                  // always has, and scrolls from the top when it does not.
                  constraints: BoxConstraints(minHeight: page.maxHeight > 54 ? page.maxHeight - 54 : 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _wordmark(context),
                          const SizedBox(height: 18),
                          _promise(context, tones, fontSize: 22),
                          const SizedBox(height: 26),
                          ..._signInColumn(context, tones, heading: false),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Desk. One sheet of paper on the page colour, with the margin rule as
  /// the seam: what the marking gives back on one side of it, sign-in on
  /// the other. A 1440px browser used to be a small box marooned in grey.
  Widget _deskLayout(BuildContext context, PaperTones tones) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, outer) {
            final room = outer.maxHeight.isFinite ? outer.maxHeight - 56 : 0.0;
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: room < 0 ? 0 : room),
                child: Center(
                  child: PaperSheet(
                    raised: true,
                    child: LayoutBuilder(
                      builder: (context, sheet) {
                        final width = sheet.maxWidth;
                        // Half and half until the sheet outgrows the form.
                        // Past that the form stops growing: a 700px slot for
                        // a password is worse than a 500px one, not better,
                        // so everything extra goes to the marking, the gap
                        // and plain paper.
                        final signIn = width * 0.5 > _signInHalfMax ? _signInHalfMax : width * 0.5;
                        final seam = (width - signIn).roundToDouble();
                        // A bigger sheet wants bigger margins, the way a
                        // bigger page does. 38 at the size it has always
                        // been, up to 72 on a 27" monitor.
                        final pad = (width * 0.042).clamp(30.0, 72.0);
                        final gap = pad * 0.8;
                        final grow = _growth(width);
                        // The display face, on the same ramp the site's hero
                        // runs: 27 in a laptop window, 46 on a monitor. The
                        // measure is kept in ems, not pixels, so the sentence
                        // still breaks over two lines however big it gets.
                        final display = _at(27, 46, grow);
                        // A floor, not a cap: below it the panel takes the
                        // room it has, which is what it does today.
                        final promiseMeasure = display * 18;
                        return ConstrainedBox(
                          // A page's proportion is a floor, not a shape. Once
                          // the writing on it has grown too, the writing is
                          // what decides the height and there is no band of
                          // blank paper left over.
                          constraints: BoxConstraints(minHeight: _sheetFloor(width, room)),
                          child: Stack(
                            // The writing sits in the middle of the page, not
                            // at the top of it with the rest of the sheet
                            // blank underneath.
                            alignment: Alignment.center,
                            children: [
                              Positioned(
                                left: seam,
                                top: 0,
                                bottom: 0,
                                width: 1,
                                child: ColoredBox(color: tones.pen.withValues(alpha: 0.45)),
                              ),
                              // Centred against the taller half, so the form
                              // sits in the page rather than stranded at the
                              // top of it with blank paper underneath.
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: seam,
                                    child: Padding(
                                      padding: EdgeInsets.fromLTRB(pad, pad, gap, pad),
                                      // Centred in its half rather than pushed
                                      // against the rule, so the extra paper
                                      // reads as margin on both sides instead
                                      // of a gap somebody forgot to fill.
                                      child: Center(
                                        child: ConstrainedBox(
                                          constraints: BoxConstraints(maxWidth: promiseMeasure),
                                          child: _promisePanel(context, tones, grow: grow),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Padding(
                                      padding: EdgeInsets.fromLTRB(gap, pad, pad, pad),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: _signInColumn(context, tones, heading: true, grow: grow),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// The shortest the sheet may be.
  ///
  /// It stops a wide sheet from becoming a strip when there is little on it,
  /// and it is deliberately below what the grown writing actually needs, so
  /// on a monitor the content sets the height and the sheet ends where the
  /// writing ends.
  double _sheetFloor(double width, double room) {
    if (room <= 0) return 0;
    final wants = width * 0.5;
    final ceiling = room * 0.86;
    return wants > ceiling ? ceiling : wants;
  }

  Widget _wordmark(BuildContext context, {double scale = 1}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MarklessMark(size: 32 * scale),
          SizedBox(width: 11 * scale),
          Text('UMarkless', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 22 * scale, letterSpacing: -0.7 * scale)),
        ],
      );

  /// The line she read on the way in, in the same words.
  ///
  /// The red rule that used to sit under the last three words is gone.
  /// Accenting one phrase of a headline is the most templated move there is,
  /// and a hand-drawn underline on a sign-in screen was working hard to be
  /// liked rather than helping anyone sign in.
  Widget _promise(BuildContext context, PaperTones tones, {required double fontSize}) => Text(
        'Marking eats your evenings. UMarkless takes the first pass.',
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: fontSize, height: 1.14, letterSpacing: -0.7),
      );

  /// The wide window's other half: what she gets for signing in, drawn on
  /// the same paper the site is drawn on.
  ///
  /// [grow] is how much bigger than a laptop window this sheet is. Every
  /// measurement here is written in terms of it, so the panel fills the paper
  /// it is given instead of sitting small in the top corner of it.
  Widget _promisePanel(BuildContext context, PaperTones tones, {double grow = 0}) {
    final display = _at(27, 46, grow);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _wordmark(context, scale: _at(1, 1.55, grow)),
        SizedBox(height: _at(28, 44, grow)),
        _promise(context, tones, fontSize: display),
        SizedBox(height: _at(14, 22, grow)),
        Text(
          'Question-by-question marks, a written reason for every deduction, and feedback a student will read.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: _at(14, 19, grow), color: AiMarkerColors.neutral, height: 1.5),
        ),
        // A drawing of a marked paper used to sit here, captioned "an
        // illustration of what comes back, not a screenshot". A picture that
        // needs a label saying it is not real is doing publicity, and
        // publicity has no job on a sign-in screen: whoever is reading it has
        // already decided. What is left says what the product is, for someone
        // arriving from a link, and then gets out of the way.
      ],
    );
  }

  /// Sign-in itself. One list, used by both layouts, so a phone and a
  /// laptop can never drift into offering different ways in.
  ///
  /// [grow] spends a wide sheet's extra height on the form's own rhythm —
  /// taller fields, more air between them — rather than leaving it as blank
  /// paper under a form floating at the top of the page. The fields
  /// themselves never get wider: the column that holds them is capped.
  List<Widget> _signInColumn(BuildContext context, PaperTones tones, {required bool heading, double grow = 0}) {
    final cs = Theme.of(context).colorScheme;
    final field = EdgeInsets.symmetric(horizontal: _at(16, 20, grow), vertical: _at(14, 26, grow));
    final button = EdgeInsets.symmetric(horizontal: _at(18, 24, grow), vertical: _at(14, 26, grow));
    return [
      if (heading) ...[
        Text('Sign in', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: _at(22, 30, grow))),
        SizedBox(height: _at(18, 47, grow)),
      ],
      AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.username, AutofillHints.email],
              // Fields are ruled onto the paper rather than floated on it:
              // a white box on a warm sheet loses its own edges.
              decoration: InputDecoration(hintText: 'teacher@school.edu', labelText: 'Email', fillColor: tones.shade, contentPadding: field),
            ),
            SizedBox(height: _at(12, 20, grow)),
            TextField(
              controller: _password,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => _loading ? null : _signIn(),
              decoration: InputDecoration(
                hintText: 'Password',
                labelText: 'Password',
                fillColor: tones.shade,
                contentPadding: field,
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: AiMarkerColors.neutral),
                ),
              ),
            ),
          ],
        ),
      ),
      SizedBox(height: _at(14, 34, grow)),
      FilledButton(
        onPressed: _loading ? null : _signIn,
        style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: Colors.white, padding: button),
        child: _loading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Sign In'),
      ),
      SizedBox(height: _at(10, 20, grow)),
      OutlinedButton(
        onPressed: _loading ? null : _openCreateAccount,
        style: OutlinedButton.styleFrom(padding: button),
        child: Text('Create Account', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700)),
      ),
      if (_oauthButtons.isNotEmpty) ...[
        SizedBox(height: _at(16, 28, grow)),
        Row(
          children: [
            Expanded(child: Divider(color: tones.rule)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text('or continue with', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
            ),
            Expanded(child: Divider(color: tones.rule)),
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
      SizedBox(height: _at(20, 38, grow)),
      Text(
        'Signing in with the same account always brings back your name, school, and marking preferences.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral),
      ),
      // Debug builds only. This signs in to a local-only account
      // that never syncs, so a teacher who tapped it in a shipped
      // build would do a term's marking and find none of it on
      // her next device -- quite apart from handing anyone who
      // installed the app a way straight past sign-up.
      if (kDebugMode) ...[
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _loading ? null : _devMode,
            icon: Icon(Icons.build_rounded, size: 16, color: AiMarkerColors.neutral),
            label: Text('Developer mode — skip sign-in & setup', style: TextStyle(color: AiMarkerColors.neutral)),
          ),
        ),
      ],
    ];
  }
}

/// Email + password + confirm in one dedicated sheet, so account creation
/// has its own clear validation instead of borrowing the sign-in fields.
class _CreateAccountSheet extends StatefulWidget {
  final String initialEmail;
  final bool googleAvailable;
  const _CreateAccountSheet({required this.initialEmail, required this.googleAvailable});

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
      Navigator.of(context).pop('created');
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
                IconButton(onPressed: () => Navigator.of(context).pop(), icon: Icon(Icons.close_rounded, color: AiMarkerColors.neutral)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Your password is stored securely, and your name, school, and marking preferences stay with the account.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral),
            ),
            if (widget.googleAvailable) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cs.primary.withValues(alpha: 0.15)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.tips_and_updates_rounded, size: 18, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tip: signing in with your school Google account also connects Google Drive automatically. You can link Google later in Settings too.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.35),
                      ),
                    ),
                    TextButton(
                      onPressed: _creating ? null : () => Navigator.of(context).pop('google'),
                      child: const Text('Use Google'),
                    ),
                  ],
                ),
              ),
            ],
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
              child: _creating ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Create Account'),
            ),
          ],
        ),
      ),
    );
  }
}
