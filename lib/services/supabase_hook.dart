import 'package:flutter/foundation.dart';
import 'package:marking_prokect_v2/models/grading_preset.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase integration hook.
///
/// Everything here goes through the MARKING-PROCESS edge function rather
/// than straight at the tables: the teacher profile lives in `profiles`,
/// which is row-level-secured, so the function's service role is what may
/// read and write it. (Earlier builds talked to a `users` table that never
/// existed on this project — every call failed silently, which is why the
/// default mode/harshness never followed the account.)
///
/// If Supabase isn't configured (missing anon key or init failure), we keep
/// the app usable in local-only mode.
class SupabaseHook extends ChangeNotifier {
  SupabaseClient? get _client {
    try {
      // Accessing Supabase.instance.client throws if initialize() was never called.
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  bool get isConfigured => _client != null;

  Future<void> updateUserPreferences({required String userId, GradingMode? defaultMode, int? defaultHarshness}) async {
    final client = _client;
    if (client == null || userId.trim().isEmpty) {
      debugPrint('Supabase not configured. Skipping profile preference update for $userId.');
      return;
    }
    if (defaultMode == null && defaultHarshness == null) return;

    try {
      await client.functions.invoke('MARKING-PROCESS', body: {
        'action': 'save_profile',
        'teacherId': userId,
        if (defaultMode != null) 'defaultMode': defaultMode.name,
        if (defaultHarshness != null) 'defaultHarshness': defaultHarshness,
      });
    } catch (e) {
      debugPrint('Supabase updateUserPreferences failed: $e');
    }
  }

  /// The teacher's saved profile row (name, school, region, default mode and
  /// harshness). Empty when Supabase isn't configured or nothing is saved yet.
  Future<Map<String, dynamic>> fetchProfile({required String teacherId}) async {
    final client = _client;
    if (client == null || teacherId.trim().isEmpty) return const {};
    try {
      final res = await client.functions.invoke('MARKING-PROCESS', body: {'action': 'get_profile', 'teacherId': teacherId});
      final data = res.data;
      final profile = data is Map ? data['profile'] : null;
      return profile is Map ? profile.cast<String, dynamic>() : const {};
    } catch (err) {
      debugPrint('Supabase fetchProfile failed: $err');
      return const {};
    }
  }
}
