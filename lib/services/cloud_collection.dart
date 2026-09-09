import 'package:flutter/foundation.dart';
import 'package:marking_prokect_v2/services/ai_grading_service.dart';
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

  /// Collections already fetched by bootstrap_sync (R19.3), waiting to be
  /// consumed by each service's first [fetch] instead of a network call.
  static final Map<String, List<Map<String, dynamic>>> _primed = {};

  static String _primeKey(String teacherId, String kind) => '$teacherId|$kind';

  /// R19.3: bootstrap_sync brought every collection back in the same round
  /// trip — prime them here so the three services' startup fetches are
  /// answered locally. Each primed list is consumed exactly once, so a
  /// later explicit refresh still asks the server.
  static void prime({required String teacherId, required Map<String, List<Map<String, dynamic>>> collections}) {
    for (final e in collections.entries) {
      _primed[_primeKey(teacherId, e.key)] = e.value;
    }
  }

  static Future<List<Map<String, dynamic>>> fetch({required String teacherId, required String kind}) async {
    final primed = _primed.remove(_primeKey(teacherId, kind));
    if (primed != null) return primed;
    final client = _client;
    if (client == null || teacherId.isEmpty) return const [];
    final Object? data;
    try {
      final res = await client.functions.invoke(
        'MARKING-PROCESS',
        body: {'action': 'get_collection', 'teacherId': teacherId, 'kind': kind},
      );
      data = res.data;
    } catch (e) {
      // R14 grace: a local-only account (no Supabase session) is refused by
      // the identity guard. Expected — there is nothing in the cloud for
      // this account, so an empty answer is the honest one.
      if (!AiGradingService.isCloudAuthRefusal(e)) rethrow;
      debugPrint('CloudCollection.fetch($kind): no Supabase session — staying local-only.');
      return const [];
    }
    if (data is Map && data['items'] is List) {
      return (data['items'] as List).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList(growable: false);
    }
    return const [];
  }

  static Future<void> save({required String teacherId, required String kind, required List<Map<String, dynamic>> items}) async {
    final client = _client;
    if (client == null || teacherId.isEmpty) return;
    try {
      await client.functions.invoke(
        'MARKING-PROCESS',
        body: {'action': 'save_collection', 'teacherId': teacherId, 'kind': kind, 'items': items},
      );
    } catch (e) {
      // R14 grace: see fetch() — a local-only account keeps its lists on
      // the device, quietly.
      if (!AiGradingService.isCloudAuthRefusal(e)) rethrow;
      debugPrint('CloudCollection.save($kind): no Supabase session — kept on this device only.');
    }
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
