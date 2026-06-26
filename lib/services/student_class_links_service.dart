import 'package:flutter/foundation.dart';
import 'package:marking_prokect_v2/models/student_class_link.dart';
import 'package:marking_prokect_v2/services/id_factory.dart';
import 'package:marking_prokect_v2/services/local_store.dart';

class StudentClassLinksService extends ChangeNotifier {
  static const _kKey = 'ai_marker.student_class_links';
  final LocalStore _store;

  List<StudentClassLink> _links = const [];
  List<StudentClassLink> get links => _links;

  StudentClassLinksService({LocalStore? store}) : _store = store ?? const LocalStore();

  Future<void> init() async {
    try {
      final raw = await _store.getString(_kKey);
      if (raw == null || raw.isEmpty) {
        _links = const [];
      } else {
        _links = StudentClassLink.decodeList(raw);
      }
    } catch (e) {
      debugPrint('StudentClassLinksService.init failed: $e');
      _links = const [];
    } finally {
      notifyListeners();
    }
  }

  StudentClassLink? findFor({required String studentId, required String subject}) => _links.cast<StudentClassLink?>().firstWhere(
    (l) => l?.studentId == studentId && l?.subject.toLowerCase() == subject.toLowerCase(),
    orElse: () => null,
  );

  Future<StudentClassLink> upsert({required String studentId, required String classId, required String subject}) async {
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

  Future<void> _persist() async => _store.setString(_kKey, StudentClassLink.encodeList(_links));
}
