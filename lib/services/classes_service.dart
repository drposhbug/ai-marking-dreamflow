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

  Future<void> init({required String teacherId}) async {
    try {
      final raw = await _store.getString(_kKey);
      if (raw == null || raw.isEmpty) {
        _classes = _seed(teacherId);
        await _persist();
      } else {
        _classes = TeacherClass.decodeList(raw);
        if (_classes.isEmpty) {
          _classes = _seed(teacherId);
          await _persist();
        }
      }
    } catch (e) {
      debugPrint('ClassesService.init failed: $e');
      _classes = _seed(teacherId);
    } finally {
      notifyListeners();
    }
  }

  List<TeacherClass> bySubject(String subject, {required String teacherId}) => _classes.where((c) => c.teacherId == teacherId && c.subject.toLowerCase() == subject.toLowerCase()).toList();

  Future<TeacherClass> create({required String teacherId, required String name, required String subject, required String period, String? room}) async {
    final now = DateTime.now();
    final created = TeacherClass(id: 'c_${IdFactory.newId()}', teacherId: teacherId, name: name, subject: subject, period: period, room: room, createdAt: now, updatedAt: now);
    _classes = [created, ..._classes];
    await _persist();
    notifyListeners();
    return created;
  }

  TeacherClass? getById(String id) => _classes.cast<TeacherClass?>().firstWhere((c) => c?.id == id, orElse: () => null);

  Future<void> _persist() async => _store.setString(_kKey, TeacherClass.encodeList(_classes));

  List<TeacherClass> _seed(String teacherId) {
    final now = DateTime.now();
    return [
      TeacherClass(id: 'c_${IdFactory.newId()}', teacherId: teacherId, name: 'Year 10 Physics', subject: 'Physics', period: 'P2', room: 'B12', createdAt: now, updatedAt: now),
      TeacherClass(id: 'c_${IdFactory.newId()}', teacherId: teacherId, name: 'Year 10 Physics', subject: 'Physics', period: 'P4', room: 'B12', createdAt: now, updatedAt: now),
      TeacherClass(id: 'c_${IdFactory.newId()}', teacherId: teacherId, name: 'Year 11 Chemistry', subject: 'Chemistry', period: 'P4', room: 'C03', createdAt: now, updatedAt: now),
      TeacherClass(id: 'c_${IdFactory.newId()}', teacherId: teacherId, name: 'Year 12 English', subject: 'English', period: 'P1', room: 'E02', createdAt: now, updatedAt: now),
    ];
  }
}
