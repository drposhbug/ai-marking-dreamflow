import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:marking_prokect_v2/models/ai_marker_user.dart';
import 'package:marking_prokect_v2/services/local_store.dart';
import 'package:marking_prokect_v2/services/supabase_hook.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService extends ChangeNotifier {
  static const _kCurrentUserKey = 'ai_marker.current_user';
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
      _currentUser = AiMarkerUser.fromJson(map);
      notifyListeners();
    } catch (e) {
      debugPrint('AuthService.init failed: $e');
    }
  }

  static Map<String, dynamic> _decode(String raw) => raw.isEmpty ? <String, dynamic>{} : (jsonDecode(raw) as Map).cast<String, dynamic>();

  /// Stable per-email account id: the same email always signs in to the same
  /// account (classes, answer keys, and settings survive sign-out/sign-in),
  /// and a new email auto-creates a fresh account — no separate sign-up step.
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

  Future<void> signInWithEmail({required String email, required String password}) async {
    // Local-only auth placeholder: signing in with a new email creates the
    // account automatically; a known email restores it (same stable id).
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

    // Best-effort: if Supabase is configured and the `users` row exists,
    // pull the real teacher name (and other profile fields).
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
    notifyListeners();
  }
}
