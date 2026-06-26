import 'package:flutter/foundation.dart';
import 'package:marking_prokect_v2/models/submission.dart';
import 'package:marking_prokect_v2/services/local_store.dart';

class SubmissionsService extends ChangeNotifier {
  static const _kKey = 'ai_marker.submissions';
  final LocalStore _store;

  List<Submission> _submissions = const [];
  List<Submission> get submissions => _submissions;

  SubmissionsService({LocalStore? store}) : _store = store ?? const LocalStore();

  Future<void> init({required String teacherId, required List<String> studentIds, required List<String> classIds, required List<String> presetIds}) async {
    try {
      final raw = await _store.getString(_kKey);
      if (raw == null || raw.isEmpty) {
        _submissions = const [];
        await _persist();
      } else {
        _submissions = Submission.decodeList(raw);
      }
    } catch (e) {
      debugPrint('SubmissionsService.init failed: $e');
      _submissions = const [];
    } finally {
      notifyListeners();
    }
  }

  List<Submission> recent({required String teacherId, int limit = 20}) {
    final list = _submissions.where((s) => s.teacherId == teacherId).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list.take(limit).toList();
  }

  List<Submission> byStudent(String studentId) {
    final list = _submissions.where((s) => s.studentId == studentId).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Submission? getById(String id) => _submissions.cast<Submission?>().firstWhere((s) => s?.id == id, orElse: () => null);

  Future<Submission> create(Submission submission) async {
    _submissions = [submission, ..._submissions];
    await _persist();
    notifyListeners();
    return submission;
  }

  Future<void> _persist() async => _store.setString(_kKey, Submission.encodeList(_submissions));
}
