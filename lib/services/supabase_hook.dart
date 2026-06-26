import 'package:flutter/foundation.dart';
import 'package:marking_prokect_v2/models/grading_preset.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase integration hook.
///
/// Notes:
/// - If Supabase isn't configured (missing anon key or init failure), we keep the app usable
///   in local-only mode.
class SupabaseHook extends ChangeNotifier {
  SupabaseClient? get _client => Supabase.instance.client;

  bool get isConfigured {
    try {
      // Accessing Supabase.instance.client throws if initialize() was never called.
      Supabase.instance.client;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> updateUserPreferences({required String userId, GradingMode? defaultMode, int? defaultHarshness}) async {
    if (!isConfigured) {
      debugPrint('Supabase not configured. Skipping users preference update for $userId.');
      return;
    }

    final updates = <String, dynamic>{};
    if (defaultMode != null) updates['default_mode'] = defaultMode.name;
    if (defaultHarshness != null) updates['default_harshness'] = defaultHarshness;
    if (updates.isEmpty) return;

    try {
      await _client!.from('users').update(updates).eq('id', userId);
    } catch (e) {
      debugPrint('Supabase updateUserPreferences failed: $e');
    }
  }

  Future<void> updateUserProfileByEmail({required String email, String? displayName, String? title, String? school, String? firstName, String? lastName}) async {
    final e = email.trim().toLowerCase();
    if (e.isEmpty || !isConfigured) return;

    final updates = <String, dynamic>{};
    if (displayName != null) updates['name'] = displayName;
    if (title != null) updates['title'] = title;
    if (school != null) updates['school'] = school;
    if (firstName != null) updates['first_name'] = firstName;
    if (lastName != null) updates['last_name'] = lastName;
    if (updates.isEmpty) return;

    try {
      await _client!.from('users').update(updates).eq('email', e);
    } catch (err) {
      debugPrint('Supabase updateUserProfileByEmail failed: $err');
    }
  }

  /// Fetches a teacher profile row from Supabase `users` table by email.
  ///
  /// Returns an empty map if Supabase isn't configured or no row is found.
  Future<Map<String, dynamic>> fetchUserByEmail(String email) async {
    final e = email.trim().toLowerCase();
    if (e.isEmpty || !isConfigured) return const {};
    try {
      final res = await _client!.from('users').select().eq('email', e).limit(1);
      final rows = (res as List?) ?? const [];
      final first = rows.isEmpty ? null : rows.first;
      return first is Map ? first.cast<String, dynamic>() : const {};
    } catch (err) {
      debugPrint('Supabase fetchUserByEmail failed: $err');
      return const {};
    }
  }
}
