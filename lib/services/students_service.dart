import 'package:flutter/foundation.dart';
import 'package:marking_prokect_v2/models/student.dart';
import 'package:marking_prokect_v2/services/id_factory.dart';
import 'package:marking_prokect_v2/services/local_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StudentsService extends ChangeNotifier {
  static const _kKey = 'ai_marker.students';
  final LocalStore _store;

  List<Student> _students = const [];
  List<Student> get students => _students;

  StudentsService({LocalStore? store}) : _store = store ?? const LocalStore();

  SupabaseClient? get _client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  bool get _supabaseReady => _client != null;

  Future<void> init({required String teacherId, required List<String> classIds}) async {
    try {
      final raw = await _store.getString(_kKey);
      if (raw == null || raw.isEmpty) {
        _students = _seed(teacherId, classIds);
        await _persist();
      } else {
        _students = Student.decodeList(raw);
        if (_students.isEmpty) {
          _students = _seed(teacherId, classIds);
          await _persist();
        }
      }
    } catch (e) {
      debugPrint('StudentsService.init failed: $e');
      _students = _seed(teacherId, classIds);
    } finally {
      notifyListeners();
    }
  }

  List<Student> byClass(String classId) => _students.where((s) => s.classId == classId).toList();

  List<Student> search(String query, {required String teacherId}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _students.where((s) => s.teacherId == teacherId && (s.name.toLowerCase().contains(q) || s.studentId.toLowerCase().contains(q))).toList();
  }

  /// Server-backed autosuggest search. Uses Supabase when available.
  ///
  /// Falls back to local [search] if Supabase isn't configured.
  Future<List<Student>> searchRemote(String query, {required String teacherId, int limit = 8}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    if (!_supabaseReady) return search(q, teacherId: teacherId);

    try {
      // Try ILIKE on name; if the project doesn't allow it (RLS), we still fall back to local.
      final res = await _client!
          .from('students')
          .select()
          .eq('teacher_id', teacherId)
          .ilike('name', '%$q%')
          .limit(limit);
      final rows = (res as List?) ?? const [];
      final items = rows.whereType<Map>().map((m) => Student.fromJson(m.cast<String, dynamic>())).toList();
      return items;
    } catch (e) {
      debugPrint('StudentsService.searchRemote failed: $e');
      return search(q, teacherId: teacherId);
    }
  }

  Student? getById(String id) => _students.cast<Student?>().firstWhere((s) => s?.id == id, orElse: () => null);

  Future<Student> create({required String teacherId, required String classId, required String name, required String studentId, String? notes}) async {
    final now = DateTime.now();
    final created = Student(id: 's_${IdFactory.newId()}', teacherId: teacherId, classId: classId, name: name, studentId: studentId, notes: notes, createdAt: now, updatedAt: now);
    _students = [created, ..._students];
    await _persist();
    notifyListeners();
    return created;
  }

  Future<void> updateNotes({required String studentId, required String notes}) async {
    _students = _students.map((s) => s.id == studentId ? s.copyWith(notes: notes, updatedAt: DateTime.now()) : s).toList();
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async => _store.setString(_kKey, Student.encodeList(_students));

  List<Student> _seed(String teacherId, List<String> classIds) {
    if (classIds.isEmpty) return const [];
    final now = DateTime.now();
    String pick(int i) => classIds[i % classIds.length];
    return [
      Student(id: 's_${IdFactory.newId()}', teacherId: teacherId, classId: pick(0), name: 'Liam Chen', studentId: 'LC102', notes: 'Struggles with units but strong diagrams.', createdAt: now, updatedAt: now),
      Student(id: 's_${IdFactory.newId()}', teacherId: teacherId, classId: pick(0), name: 'Sofia Rodriguez', studentId: 'SR221', notes: null, createdAt: now, updatedAt: now),
      Student(id: 's_${IdFactory.newId()}', teacherId: teacherId, classId: pick(1), name: 'Marcus Thompson', studentId: 'MT077', notes: 'Needs clearer working.', createdAt: now, updatedAt: now),
      Student(id: 's_${IdFactory.newId()}', teacherId: teacherId, classId: pick(2), name: 'Aisha Kamara', studentId: 'AK510', notes: null, createdAt: now, updatedAt: now),
      Student(id: 's_${IdFactory.newId()}', teacherId: teacherId, classId: pick(3), name: 'Jamie Park', studentId: 'JP019', notes: null, createdAt: now, updatedAt: now),
    ];
  }
}
