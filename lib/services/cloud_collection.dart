import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Account backup for the small setup lists — classes, students and the
/// student↔class links. Marked results already follow the account through
/// `submissions_cloud`; these lists used to live only on the phone, so a
/// wiped app (or a new phone) lost every class the teacher had made.
///
/// Each list is stored whole, as one JSON array per teacher + kind, and
/// merged by id on the way back in so a phone that was offline for a while
/// never drops work done elsewhere.
class CloudCollection {
  static const kClasses = 'classes';
  static const kStudents = 'students';
  static const kLinks = 'student_class_links';

  static SupabaseClient? get _client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> fetch({required String teacherId, required String kind}) async {
    final client = _client;
    if (client == null || teacherId.isEmpty) return const [];
    final res = await client.functions.invoke(
      'MARKING-PROCESS',
      body: {'action': 'get_collection', 'teacherId': teacherId, 'kind': kind},
    );
    final data = res.data;
    if (data is Map && data['items'] is List) {
      return (data['items'] as List).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList(growable: false);
    }
    return const [];
  }

  static Future<void> save({required String teacherId, required String kind, required List<Map<String, dynamic>> items}) async {
    final client = _client;
    if (client == null || teacherId.isEmpty) return;
    await client.functions.invoke(
      'MARKING-PROCESS',
      body: {'action': 'save_collection', 'teacherId': teacherId, 'kind': kind, 'items': items},
    );
  }

  /// Fire-and-forget backup — a failed push must never block the teacher or
  /// undo the local save that already happened.
  static void push({required String teacherId, required String kind, required List<Map<String, dynamic>> items}) {
    save(teacherId: teacherId, kind: kind, items: items).catchError((Object e) => debugPrint('CloudCollection push ($kind) failed: $e'));
  }

  /// Union of the phone's rows and the account's, keyed by id, with the most
  /// recently edited copy of a row winning.
  static List<Map<String, dynamic>> merge(List<Map<String, dynamic>> local, List<Map<String, dynamic>> remote) {
    final byId = <String, Map<String, dynamic>>{};
    for (final row in [...remote, ...local]) {
      final id = (row['id'] ?? '').toString();
      if (id.isEmpty) continue;
      final existing = byId[id];
      if (existing == null || !_updatedAt(row).isBefore(_updatedAt(existing))) byId[id] = row;
    }
    return byId.values.toList(growable: false);
  }

  static DateTime _updatedAt(Map<String, dynamic> row) =>
      DateTime.tryParse((row['updated_at'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
}
