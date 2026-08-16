import 'package:flutter/foundation.dart';
import 'package:marking_prokect_v2/models/student_class_link.dart';
import 'package:marking_prokect_v2/services/cloud_collection.dart';
import 'package:marking_prokect_v2/services/id_factory.dart';
import 'package:marking_prokect_v2/services/local_store.dart';

class StudentClassLinksService extends ChangeNotifier {
  static const _kKey = 'ai_marker.student_class_links';
  final LocalStore _store;

  List<StudentClassLink> _links = const [];
  List<StudentClassLink> get links => _links;

  String _teacherId = '';
  // False until the stored list has been read — see ClassesService.
  bool _loaded = false;

  StudentClassLinksService({LocalStore? store}) : _store = store ?? const LocalStore();

  Future<void> init({required String teacherId}) async {
    _teacherId = teacherId;
    try {
      final raw = await _store.getString(_kKey);
      if (raw == null || raw.isEmpty) {
        _links = const [];
      } else {
        _links = StudentClassLink.decodeList(raw);
      }
      _loaded = true;
    } catch (e) {
      debugPrint('StudentClassLinksService.init failed: $e');
      _links = const [];
      _loaded = true;
    } finally {
      notifyListeners();
    }
    await _syncCloud();
  }

  /// Which student sits in which class follows the account too — without it
  /// restored classes and students would come back unconnected.
  Future<void> _syncCloud() async {
    if (_teacherId.isEmpty) return;
    try {
      final remote = await CloudCollection.fetch(teacherId: _teacherId, kind: CloudCollection.kLinks);
      final merged = CloudCollection.merge(_links.map((l) => l.toJson()).toList(growable: false), remote);
      final restored = <StudentClassLink>[];
      for (final row in merged) {
        try {
          restored.add(StudentClassLink.fromJson(row));
        } catch (_) {}
      }
      final added = restored.length - _links.length;
      _links = restored;
      await _persist();
      notifyListeners();
      if (added > 0) debugPrint('StudentClassLinksService: restored $added link(s) from the cloud');
    } catch (e) {
      debugPrint('StudentClassLinksService cloud sync failed: $e');
    }
  }

  /// Guards a mutation that lands before [init] ran — see ClassesService.
  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    try {
      final raw = await _store.getString(_kKey);
      if (raw != null && raw.isNotEmpty) _links = StudentClassLink.decodeList(raw);
    } catch (e) {
      debugPrint('StudentClassLinksService._ensureLoaded failed: $e');
    }
    _loaded = true;
  }

  StudentClassLink? findFor({required String studentId, required String subject}) => _links.cast<StudentClassLink?>().firstWhere(
    (l) => l?.studentId == studentId && l?.subject.toLowerCase() == subject.toLowerCase(),
    orElse: () => null,
  );

  Future<StudentClassLink> upsert({required String studentId, required String classId, required String subject}) async {
    await _ensureLoaded();
    final now = DateTime.now();
    final existing = findFor(studentId: studentId, subject: subject);
    if (existing == null) {
      final created = StudentClassLink(id: 'l_${IdFactory.newId()}', studentId: studentId, classId: classId, subject: subject, confirmedAt: now, createdAt: now, updatedAt: now);
      _links = [created, ..._links];
      await _persist();
      notifyListeners();
      return created;
    }

    final updated = existing.copyWith(classId: classId, confirmedAt: now, updatedAt: now);
    _links = _links.map((l) => l.id == updated.id ? updated : l).toList();
    await _persist();
    notifyListeners();
    return updated;
  }

  Future<void> _persist() async {
    await _store.setString(_kKey, StudentClassLink.encodeList(_links));
    CloudCollection.push(teacherId: _teacherId, kind: CloudCollection.kLinks, items: _links.map((l) => l.toJson()).toList(growable: false));
  }
}
