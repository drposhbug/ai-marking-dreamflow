import 'package:flutter/foundation.dart';
import 'package:marking_prokect_v2/models/submission.dart';
import 'package:marking_prokect_v2/services/ai_grading_service.dart';
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
      } else {
        try {
          _submissions = Submission.decodeList(raw);
          debugPrint('SubmissionsService: loaded ${_submissions.length} result(s) from disk');
          // Marks made on this device under another sign-in (dev mode, a
          // test account) belong to the teacher holding the phone — adopt
          // them so they show in the dashboard/classes instead of being
          // silently filtered out.
          final adopted = <Submission>[];
          _submissions = _submissions.map((s) {
            if (s.teacherId == teacherId) return s;
            final a = s.copyWith(teacherId: teacherId, updatedAt: DateTime.now());
            adopted.add(a);
            return a;
          }).toList(growable: false);
          if (adopted.isNotEmpty) {
            await _persist();
            debugPrint('SubmissionsService: adopted ${adopted.length} result(s) from other sign-ins on this device');
            for (final s in adopted) {
              _pushCloud(s);
            }
          }
        } catch (e) {
          // NEVER lose data: park the unreadable raw for recovery instead
          // of overwriting it with an empty list later.
          debugPrint('SubmissionsService decode failed — raw backed up: $e');
          await _store.setString('$_kKey.backup', raw);
          _submissions = const [];
        }
      }
    } catch (e) {
      debugPrint('SubmissionsService.init failed: $e');
      _submissions = const [];
    } finally {
      notifyListeners();
    }
    // Cloud copy: marked results follow the account — signing back in (or
    // onto a new phone) restores anything this device doesn't have.
    try {
      final cloud = await AiGradingService().listSubmissionsCloud(teacherId: teacherId);
      final byId = {for (final s in _submissions) s.id: s};
      var added = 0;
      for (final m in cloud) {
        try {
          final s = Submission.fromJson(m);
          if (!byId.containsKey(s.id)) {
            byId[s.id] = s;
            added++;
          }
        } catch (_) {}
      }
      if (added > 0) {
        _submissions = byId.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        await _persist();
        notifyListeners();
        debugPrint('SubmissionsService: restored $added result(s) from the cloud');
      }
    } catch (e) {
      debugPrint('SubmissionsService cloud sync failed: $e');
    }
  }

  /// Fire-and-forget cloud push — a failed push never blocks marking.
  void _pushCloud(Submission s) {
    AiGradingService()
        .saveSubmissionCloud(teacherId: s.teacherId, submission: s.toJson())
        .catchError((Object e) => debugPrint('Submission cloud push failed: $e'));
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
    _pushCloud(submission);
    return submission;
  }

  Future<void> update(Submission submission) async {
    _submissions = _submissions.map((s) => s.id == submission.id ? submission : s).toList(growable: false);
    await _persist();
    notifyListeners();
    _pushCloud(submission);
  }

  Future<void> _persist() async => _store.setString(_kKey, Submission.encodeList(_submissions));
}
