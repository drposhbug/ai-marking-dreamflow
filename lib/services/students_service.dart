import 'package:flutter/foundation.dart';
import 'package:marking_prokect_v2/models/student.dart';
import 'package:marking_prokect_v2/services/cloud_collection.dart';
import 'package:marking_prokect_v2/services/id_factory.dart';
import 'package:marking_prokect_v2/services/local_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StudentsService extends ChangeNotifier {
  static const _kKey = 'ai_marker.students';
  final LocalStore _store;

  List<Student> _students = const [];
  List<Student> get students => _students;

  String _teacherId = '';
  // False until the stored list has been read — see ClassesService.
  bool _loaded = false;

  StudentsService({LocalStore? store}) : _store = store ?? const LocalStore();

  SupabaseClient? get _client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  bool get _supabaseReady => _client != null;

  // Codes of the demo students that older builds seeded automatically —
  // used to purge them from devices that still have them stored.
  static const _legacySeedCodes = {'LC102', 'SR221', 'MT077', 'AK510', 'JP019'};

  Future<void> init({required String teacherId, required List<String> classIds}) async {
    _teacherId = teacherId;
    try {
      final raw = await _store.getString(_kKey);
      _students = (raw == null || raw.isEmpty) ? const [] : Student.decodeList(raw);
      _loaded = true;

      // One-time cleanup: drop the demo/template students seeded by old builds.
      final before = _students.length;
      _students = _students.where((s) => !_legacySeedCodes.contains(s.studentId)).toList();
      var changed = _students.length != before;

      // Same adoption as classes/submissions: students created under another
      // sign-in on this device follow the current teacher.
      var adopted = 0;
      _students = _students.map((s) {
        if (s.teacherId == teacherId) return s;
        adopted++;
        return s.copyWith(teacherId: teacherId, updatedAt: DateTime.now());
      }).toList();
      if (adopted > 0) {
        changed = true;
        debugPrint('StudentsService: adopted $adopted student(s) from other sign-ins on this device');
      }
      if (changed) await _persist();
    } catch (e) {
      debugPrint('StudentsService.init failed: $e');
      _students = const [];
      _loaded = true;
    } finally {
      notifyListeners();
    }
    await _syncCloud();
  }

  /// Students follow the account the same way classes do.
  Future<void> _syncCloud() async {
    if (_teacherId.isEmpty) return;
    try {
      final remote = await CloudCollection.fetch(teacherId: _teacherId, kind: CloudCollection.kStudents);
      final merged = CloudCollection.merge(_students.map((s) => s.toJson()).toList(growable: false), remote);
      final restored = <Student>[];
      for (final row in merged) {
        try {
          final s = Student.fromJson(row);
          if (_legacySeedCodes.contains(s.studentId)) continue;
          restored.add(s.teacherId == _teacherId ? s : s.copyWith(teacherId: _teacherId));
        } catch (_) {}
      }
      final added = restored.length - _students.length;
      _students = restored;
      await _persist();
      notifyListeners();
      if (added > 0) debugPrint('StudentsService: restored $added student(s) from the cloud');
    } catch (e) {
      debugPrint('StudentsService cloud sync failed: $e');
    }
  }

  /// Guards a mutation that lands before [init] ran — see ClassesService.
  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    try {
      final raw = await _store.getString(_kKey);
      if (raw != null && raw.isNotEmpty) _students = Student.decodeList(raw);
    } catch (e) {
      debugPrint('StudentsService._ensureLoaded failed: $e');
    }
    _loaded = true;
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
    await _ensureLoaded();
    if (_teacherId.isEmpty) _teacherId = teacherId;
    final now = DateTime.now();
    final created = Student(id: 's_${IdFactory.newId()}', teacherId: teacherId, classId: classId, name: name, studentId: studentId, notes: notes, createdAt: now, updatedAt: now);
    _students = [created, ..._students];
    await _persist();
    notifyListeners();
    return created;
  }

  /// Files a student into a class (e.g. right after linking a scanned
  /// result to a newly created student).
  Future<void> assignToClass({required String studentId, required String classId}) async {
    await _ensureLoaded();
    _students = _students.map((s) => s.id == studentId ? s.copyWith(classId: classId, updatedAt: DateTime.now()) : s).toList();
    await _persist();
    notifyListeners();
  }

  Future<void> updateNotes({required String studentId, required String notes}) async {
    await _ensureLoaded();
    _students = _students.map((s) => s.id == studentId ? s.copyWith(notes: notes, updatedAt: DateTime.now()) : s).toList();
    await _persist();
    notifyListeners();
  }

  /// Remembers how a student is referred to in drafted report comments.
  ///
  /// Kept on the student so a teacher sets it once, not once per term and
  /// not again on their next device.
  Future<void> updatePronoun({required String studentId, required String pronoun}) async {
    await _ensureLoaded();
    _students = _students
        .map((s) => s.id == studentId ? s.copyWith(pronoun: pronoun, updatedAt: DateTime.now()) : s)
        .toList();
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    await _store.setString(_kKey, Student.encodeList(_students));
    CloudCollection.push(teacherId: _teacherId, kind: CloudCollection.kStudents, items: _students.map((s) => s.toJson()).toList(growable: false));
  }
}
