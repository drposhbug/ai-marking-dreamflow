import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:marking_prokect_v2/models/ai_marker_user.dart';
import 'package:marking_prokect_v2/services/local_store.dart';
import 'package:marking_prokect_v2/services/supabase_hook.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService extends ChangeNotifier {
  static const _kCurrentUserKey = 'ai_marker.current_user';
  // Must match main.dart's Supabase.initialize values.
  static const _supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://zxikjizraeqejbsncqpg.supabase.co');
  static const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  final LocalStore _store;

  AiMarkerUser? _currentUser;
  AiMarkerUser? get currentUser => _currentUser;

  bool get isSignedIn => _currentUser != null;

  AuthService({LocalStore? store}) : _store = store ?? const LocalStore();

  Future<void> init() async {
    try {
      final raw = await _store.getString(_kCurrentUserKey);
      if (raw == null || raw.isEmpty) return;
      final map = (await compute(_decode, raw)).cast<String, dynamic>();
      if (map.isEmpty) return;
      var user = AiMarkerUser.fromJson(map);
      // Migration: older builds auto-derived the full email name ("Oscar Cs
      // Lee"); teachers go by their last name, so shorten it to "Lee".
      final normalized = normalizeAutoName(user.name, user.email);
      if (normalized != user.name) {
        user = user.copyWith(name: normalized, updatedAt: DateTime.now());
        await _store.setString(_kCurrentUserKey, jsonEncode(user.toJson()));
      }
      _currentUser = user;
      notifyListeners();
    } catch (e) {
      debugPrint('AuthService.init failed: $e');
    }
  }

  /// Collapses an auto-derived full name ("Oscar Cs Lee" from the email)
  /// down to the last name teachers actually go by. Names the teacher
  /// typed themselves pass through untouched.
  static String normalizeAutoName(String name, String email) {
    final n = name.trim();
    if (n.isNotEmpty && n == defaultNameFor(email) && n.contains(' ')) return lastNameOf(n);
    return n;
  }

  static Map<String, dynamic> _decode(String raw) => raw.isEmpty ? <String, dynamic>{} : (jsonDecode(raw) as Map).cast<String, dynamic>();

  SupabaseClient? get _supabase {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Stable per-email account id — used only by the local fallback (no
  /// Supabase configured) and by developer mode.
  static String stableIdFor(String email) {
    final slug = email.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return 'u_$slug';
  }

  /// The auto-derived display name for an email — used to tell "name the
  /// teacher actually typed" apart from "placeholder we generated".
  static String defaultNameFor(String email) {
    final local = email.split('@').first.replaceAll(RegExp(r'[._\-]+'), ' ').trim();
    if (local.isEmpty) return 'Teacher';
    return local.split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
  }

  /// Real sign-in: fails when the account doesn't exist or the password is
  /// wrong. Passwords and accounts live in Supabase Auth.
  Future<void> signInWithEmail({required String email, required String password}) async {
    final client = _supabase;
    if (client == null) return _localSignIn(email); // no cloud configured
    try {
      final res = await client.auth.signInWithPassword(email: email.trim(), password: password);
      final u = res.user;
      if (u == null) throw Exception('Sign in failed — try again.');
      await _setUser(id: u.id, email: email.trim());
    } on AuthException catch (e) {
      throw Exception(_friendlyAuthError(e));
    } catch (e) {
      if (_looksOffline(e)) throw Exception('Can\'t reach the server — check your internet connection and try again.');
      rethrow;
    }
  }

  /// Real sign-up: creates the account (password stored by Supabase Auth).
  Future<void> createAccount({required String email, required String password}) async {
    final client = _supabase;
    if (client == null) return _localSignIn(email);
    try {
      final res = await client.auth.signUp(email: email.trim(), password: password);
      var u = res.user;
      if (res.session == null) {
        // Email confirmation may be enabled on the project — try signing
        // straight in; if that's blocked, tell the teacher to confirm.
        try {
          final signIn = await client.auth.signInWithPassword(email: email.trim(), password: password);
          u = signIn.user;
        } on AuthException {
          throw Exception('Account created — check your email to confirm it, then sign in.');
        }
      }
      if (u == null) throw Exception('Could not create the account — try again.');
      await _setUser(id: u.id, email: email.trim());
    } on AuthException catch (e) {
      throw Exception(_friendlyAuthError(e));
    } catch (e) {
      if (_looksOffline(e)) throw Exception('Can\'t reach the server — check your internet connection and try again.');
      rethrow;
    }
  }

  /// Network-level failures (no connection, DNS blocked) rather than a
  /// wrong password — surfaced as a connection message, not an auth one.
  static bool _looksOffline(Object e) {
    final s = e.toString();
    return s.contains('SocketException') || s.contains('Failed host lookup') || s.contains('ClientException') || s.contains('Connection refused') || s.contains('Connection timed out');
  }

  /// Which OAuth providers are switched on in the Supabase dashboard
  /// ('google', 'apple', 'azure', ...). Empty when none are or the endpoint
  /// can't be reached — the login screen only shows buttons that will
  /// actually work, so enabling a provider server-side is all it takes.
  Future<Set<String>> enabledOAuthProviders() async {
    if (_supabase == null || _supabaseAnonKey.isEmpty) return const {};
    try {
      final res = await http
          .get(Uri.parse('$_supabaseUrl/auth/v1/settings'), headers: {'apikey': _supabaseAnonKey})
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return const {};
      final map = (jsonDecode(res.body) as Map).cast<String, dynamic>();
      final external = (map['external'] as Map?)?.cast<String, dynamic>() ?? const {};
      return external.entries.where((e) => e.value == true).map((e) => e.key).toSet();
    } catch (e) {
      debugPrint('AuthService.enabledOAuthProviders failed: $e');
      return const {};
    }
  }

  static String _providerLabel(OAuthProvider p) {
    if (p == OAuthProvider.azure) return 'Microsoft';
    final n = p.name;
    return '${n[0].toUpperCase()}${n.substring(1)}';
  }

  /// OAuth sign-in (Google / Apple) via the system browser. The redirect
  /// deep link (com.markless.app://login-callback) is caught by
  /// supabase_flutter, which completes the session; we wait for it here.
  /// Requires the provider to be enabled in the Supabase dashboard.
  Future<void> signInWithProvider(OAuthProvider provider) async {
    final client = _supabase;
    if (client == null) throw Exception('Cloud sign-in isn\'t available in this build.');
    // Pre-flight: a disabled provider would otherwise dump the teacher on a
    // raw 400 error page in the browser.
    final enabled = await enabledOAuthProviders();
    if (enabled.isNotEmpty && !enabled.contains(provider.name)) {
      throw Exception('${_providerLabel(provider)} sign-in isn\'t switched on for the server yet — use email & password for now.');
    }
    final completer = Completer<void>();
    late final StreamSubscription<AuthState> sub;
    sub = client.auth.onAuthStateChange.listen((state) {
      if (state.session != null && !completer.isCompleted) completer.complete();
    });
    try {
      await client.auth.signInWithOAuth(provider, redirectTo: 'com.markless.app://login-callback');
      await completer.future.timeout(
        const Duration(minutes: 3),
        onTimeout: () => throw Exception('Sign-in wasn\'t completed — try again.'),
      );
      final u = client.auth.currentUser;
      if (u == null) throw Exception('Sign in failed — try again.');
      await _setUser(id: u.id, email: u.email ?? '');
    } on AuthException catch (e) {
      throw Exception(_friendlyAuthError(e));
    } catch (e) {
      if (_looksOffline(e)) throw Exception('Can\'t reach the server — check your internet connection and try again.');
      rethrow;
    } finally {
      await sub.cancel();
    }
  }

  /// Auth events from Supabase (null when no cloud is configured).
  Stream<AuthState>? get authStateChanges => _supabase?.auth.onAuthStateChange;

  /// Display name provided by the OAuth provider (Google/Apple) for the
  /// current session, or null for email/local accounts.
  String? get oauthFullName {
    final meta = _supabase?.auth.currentUser?.userMetadata;
    final n = ((meta?['full_name'] ?? meta?['name']) ?? '').toString().trim();
    return n.isEmpty ? null : n;
  }

  /// Last word of a full name — used to suggest "Ms. Lee"-style teacher
  /// names without ever guessing a gendered title.
  static String lastNameOf(String fullName) {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? fullName.trim() : parts.last;
  }

  /// True when a Supabase session already exists — a persisted "stay signed
  /// in" from a previous run, or an OAuth callback that completed while the
  /// router was busy elsewhere. Ensures the local user matches the session.
  Future<bool> adoptSupabaseSession() async {
    final u = _supabase?.auth.currentUser;
    if (u == null) return false;
    if (_currentUser?.id != u.id) {
      await _setUser(id: u.id, email: u.email ?? '');
    }
    return true;
  }

  /// Developer mode / no-cloud fallback: local account, no password checks.
  Future<void> signInLocal({required String email}) => _localSignIn(email);

  static String _friendlyAuthError(AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('provider') && (m.contains('not enabled') || m.contains('disabled'))) {
      return 'That sign-in provider isn\'t switched on for the server yet — use email and password for now.';
    }
    if (m.contains('invalid login')) return 'Wrong password — or no account with that email yet. Use Create Account first.';
    if (m.contains('already registered') || m.contains('already been registered')) {
      return 'That email already has an account — use Sign In instead.';
    }
    if (m.contains('at least 6') || m.contains('password should')) return 'Password must be at least 6 characters.';
    if (m.contains('confirm')) return 'Please confirm your email first — check your inbox.';
    if (m.contains('invalid format') || m.contains('valid email')) return 'That doesn\'t look like a valid email address.';
    return e.message;
  }

  Future<void> _setUser({required String id, required String email}) async {
    final now = DateTime.now();
    // Keep locally saved profile details when the same account signs back in.
    final prior = _currentUser;
    final samePerson = prior != null && (prior.id == id || prior.email.toLowerCase() == email.toLowerCase());
    _currentUser = AiMarkerUser(
      id: id,
      email: email,
      // New accounts start with just the last name — from the OAuth
      // provider's real name when available, else derived from the email.
      name: samePerson ? normalizeAutoName(prior.name, email) : lastNameOf(oauthFullName ?? defaultNameFor(email)),
      school: samePerson ? prior.school : '',
      title: samePerson ? prior.title : 'Teacher',
      avatarUrl: samePerson ? prior.avatarUrl : null,
      createdAt: samePerson ? prior.createdAt : now,
      updatedAt: now,
    );
    await _store.setString(_kCurrentUserKey, jsonEncode(_currentUser!.toJson()));
    notifyListeners();
    await _trySyncProfileFromSupabase();
  }

  Future<void> _localSignIn(String email) async {
    final now = DateTime.now();
    _currentUser = AiMarkerUser(
      id: stableIdFor(email),
      email: email,
      name: defaultNameFor(email),
      school: '',
      title: 'Teacher',
      avatarUrl: null,
      createdAt: now,
      updatedAt: now,
    );
    await _store.setString(_kCurrentUserKey, jsonEncode(_currentUser!.toJson()));
    notifyListeners();
    await _trySyncProfileFromSupabase();
  }

  Future<void> _trySyncProfileFromSupabase() async {
    final user = _currentUser;
    if (user == null) return;

    SupabaseClient? client;
    try {
      client = Supabase.instance.client;
    } catch (_) {
      client = null;
    }
    if (client == null) return;

    try {
      final hook = SupabaseHook();
      final row = await hook.fetchUserByEmail(user.email);
      if (row.isEmpty) return;

      final firstName = (row['first_name'] ?? row['firstName'] ?? '').toString().trim();
      final lastName = (row['last_name'] ?? row['lastName'] ?? '').toString().trim();
      final title = (row['title'] ?? '').toString().trim();
      final school = (row['school'] ?? '').toString().trim();

      final displayName = [title, firstName, lastName].where((e) => e.trim().isNotEmpty).join(' ').trim();
      final next = user.copyWith(
        name: displayName.isEmpty ? user.name : displayName,
        title: title.isEmpty ? user.title : title,
        school: school.isEmpty ? user.school : school,
        updatedAt: DateTime.now(),
      );
      _currentUser = next;
      await _store.setString(_kCurrentUserKey, jsonEncode(next.toJson()));
      notifyListeners();
    } catch (e) {
      debugPrint('AuthService._trySyncProfileFromSupabase failed: $e');
    }
  }

  Future<void> updateProfile({String? name, String? school, String? title, String? avatarUrl}) async {
    final user = _currentUser;
    if (user == null) return;
    final next = user.copyWith(name: name ?? user.name, school: school ?? user.school, title: title ?? user.title, avatarUrl: avatarUrl ?? user.avatarUrl, updatedAt: DateTime.now());
    _currentUser = next;
    try {
      await _store.setString(_kCurrentUserKey, jsonEncode(next.toJson()));
    } catch (e) {
      debugPrint('AuthService.updateProfile persist failed: $e');
    }
    notifyListeners();
  }

  Future<void> signOut() async {
    _currentUser = null;
    await _store.setString(_kCurrentUserKey, '');
    try {
      await _supabase?.auth.signOut();
    } catch (e) {
      debugPrint('Supabase signOut failed: $e');
    }
    notifyListeners();
  }
}
