import 'package:flutter/foundation.dart';
import 'package:marking_prokect_v2/models/teacher_class.dart';
import 'package:marking_prokect_v2/services/id_factory.dart';
import 'package:marking_prokect_v2/services/local_store.dart';

class ClassesService extends ChangeNotifier {
  static const _kKey = 'ai_marker.classes';
  final LocalStore _store;

  List<TeacherClass> _classes = const [];
  List<TeacherClass> get classes => _classes;

  ClassesService({LocalStore? store}) : _store = store ?? const LocalStore();

  // The demo/template classes older builds seeded automatically — matched by
  // exact name+period+room so real classes are never touched.
  static bool _isLegacySeed(TeacherClass c) {
    const seeds = {
      ('Year 10 Physics', 'P2', 'B12'),
      ('Year 10 Physics', 'P4', 'B12'),
      ('Year 11 Chemistry', 'P4', 'C03'),
      ('Year 12 English', 'P1', 'E02'),
    };
    return seeds.contains((c.name, c.period, c.room ?? ''));
  }

  Future<void> init({required String teacherId}) async {
    try {
      final raw = await _store.getString(_kKey);
      _classes = (raw == null || raw.isEmpty) ? const [] : TeacherClass.decodeList(raw);

      // One-time cleanup: drop the template classes seeded by old builds.
      final before = _classes.length;
      _classes = _classes.where((c) => !_isLegacySeed(c)).toList();
      if (_classes.length != before) await _persist();
    } catch (e) {
      debugPrint('ClassesService.init failed: $e');
      _classes = const [];
    } finally {
      notifyListeners();
    }
  }

  List<TeacherClass> bySubject(String subject, {required String teacherId}) => _classes.where((c) => c.teacherId == teacherId && c.subject.toLowerCase() == subject.toLowerCase()).toList();

  Future<TeacherClass> create({required String teacherId, required String name, required String subject, required String period, String? room, int? gradeLevel}) async {
    final now = DateTime.now();
    final created = TeacherClass(id: 'c_${IdFactory.newId()}', teacherId: teacherId, name: name, subject: subject, period: period, room: room, gradeLevel: gradeLevel, createdAt: now, updatedAt: now);
    _classes = [created, ..._classes];
    await _persist();
    notifyListeners();
    return created;
  }

  TeacherClass? getById(String id) => _classes.cast<TeacherClass?>().firstWhere((c) => c?.id == id, orElse: () => null);

  Future<void> update({required String id, String? name, String? subject, String? period, String? room, int? gradeLevel}) async {
    _classes = _classes
        .map((c) => c.id == id
            ? c.copyWith(name: name, subject: subject, period: period, room: room, gradeLevel: gradeLevel, updatedAt: DateTime.now())
            : c)
        .toList();
    await _persist();
    notifyListeners();
  }

  Future<void> delete(String id) async {
    _classes = _classes.where((c) => c.id != id).toList(growable: false);
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async => _store.setString(_kKey, TeacherClass.encodeList(_classes));
}
