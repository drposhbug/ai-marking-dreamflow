import 'package:flutter/foundation.dart';
import 'package:marking_prokect_v2/models/teacher_class.dart';
import 'package:marking_prokect_v2/services/cloud_collection.dart';
import 'package:marking_prokect_v2/services/id_factory.dart';
import 'package:marking_prokect_v2/services/local_store.dart';

class ClassesService extends ChangeNotifier {
  static const _kKey = 'ai_marker.classes';
  final LocalStore _store;

  List<TeacherClass> _classes = const [];
  List<TeacherClass> get classes => _classes;
  /// Classes another account left on this device: saved back, never shown.
  List<TeacherClass> _otherAccounts = const [];

  String _teacherId = '';
  // False until the stored list has been read. Persisting before that would
  // write the in-memory (empty) list over everything the teacher had.
  bool _loaded = false;

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
    _teacherId = teacherId;
    _otherAccounts = const [];
    try {
      final raw = await _store.getString(_kKey);
      _classes = (raw == null || raw.isEmpty) ? const [] : TeacherClass.decodeList(raw);
      _loaded = true;

      // One-time cleanup: drop the template classes seeded by old builds.
      final before = _classes.length;
      _classes = _classes.where((c) => !_isLegacySeed(c)).toList();
      var changed = _classes.length != before;

      // Only the signed-in teacher's classes are loaded. Another account's
      // classes stay on disk untouched and are never shown or synced here
      // (they used to be adopted by whoever signed in next).
      _otherAccounts = _classes.where((c) => c.teacherId != teacherId).toList();
      _classes = _classes.where((c) => c.teacherId == teacherId).toList();
      if (changed) await _persist();
    } catch (e) {
      debugPrint('ClassesService.init failed: $e');
      _classes = const [];
      _loaded = true;
    } finally {
      notifyListeners();
    }
    await _syncCloud();
  }

  /// Classes follow the account: anything this device is missing comes back
  /// from the cloud copy, and the merged list is pushed back so every phone
  /// the teacher signs in on ends up with the same set.
  Future<void> _syncCloud() async {
    if (_teacherId.isEmpty) return;
    try {
      final remote = await CloudCollection.fetch(teacherId: _teacherId, kind: CloudCollection.kClasses);
      final merged = CloudCollection.merge(_classes.map((c) => c.toJson()).toList(growable: false), remote);
      final restored = <TeacherClass>[];
      for (final row in merged) {
        try {
          final c = TeacherClass.fromJson(row);
          if (!_isLegacySeed(c)) restored.add(c.teacherId == _teacherId ? c : c.copyWith(teacherId: _teacherId));
        } catch (_) {}
      }
      restored.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final added = restored.length - _classes.length;
      _classes = restored;
      // _persist also pushes the merged list back, so a phone that was
      // offline contributes its classes to the account on the next launch.
      await _persist();
      notifyListeners();
      if (added > 0) debugPrint('ClassesService: restored $added class(es) from the cloud');
    } catch (e) {
      debugPrint('ClassesService cloud sync failed: $e');
    }
  }

  /// Reads the stored list when a mutation lands before [init] has run (a
  /// sign-in mid-session, say) so the save can't wipe the teacher's classes.
  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    try {
      final raw = await _store.getString(_kKey);
      if (raw != null && raw.isNotEmpty) _classes = TeacherClass.decodeList(raw);
    } catch (e) {
      debugPrint('ClassesService._ensureLoaded failed: $e');
    }
    _loaded = true;
  }

  List<TeacherClass> bySubject(String subject, {required String teacherId}) => _classes.where((c) => c.teacherId == teacherId && c.subject.toLowerCase() == subject.toLowerCase()).toList();

  Future<TeacherClass> create({required String teacherId, required String name, required String subject, required String period, String? room, int? gradeLevel}) async {
    await _ensureLoaded();
    if (_teacherId.isEmpty) _teacherId = teacherId;
    final now = DateTime.now();
    final created = TeacherClass(id: 'c_${IdFactory.newId()}', teacherId: teacherId, name: name, subject: subject, period: period, room: room, gradeLevel: gradeLevel, createdAt: now, updatedAt: now);
    _classes = [created, ..._classes];
    await _persist();
    notifyListeners();
    return created;
  }

  TeacherClass? getById(String id) => _classes.cast<TeacherClass?>().firstWhere((c) => c?.id == id, orElse: () => null);

  Future<void> update({required String id, String? name, String? subject, String? period, String? room, int? gradeLevel}) async {
    await _ensureLoaded();
    _classes = _classes
        .map((c) => c.id == id
            ? c.copyWith(name: name, subject: subject, period: period, room: room, gradeLevel: gradeLevel, updatedAt: DateTime.now())
            : c)
        .toList();
    await _persist();
    notifyListeners();
  }

  Future<void> delete(String id) async {
    await _ensureLoaded();
    _classes = _classes.where((c) => c.id != id).toList(growable: false);
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    await _store.setString(_kKey, TeacherClass.encodeList([..._classes, ..._otherAccounts]));
    CloudCollection.push(teacherId: _teacherId, kind: CloudCollection.kClasses, items: _classes.map((c) => c.toJson()).toList(growable: false));
  }
}
