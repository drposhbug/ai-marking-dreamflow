import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:marking_prokect_v2/services/overnight_page_store.dart';
import 'package:marking_prokect_v2/models/submission.dart';
import 'package:marking_prokect_v2/services/ai_grading_service.dart';
import 'package:marking_prokect_v2/services/local_store.dart';

class SubmissionsService extends ChangeNotifier {
  static const _kKey = 'ai_marker.submissions';
  // Deleted ids whose cloud copy may still exist (delete sent while offline) —
  // kept so the next cloud sync can't resurrect them, retried on init.
  static const _kDeletedKey = 'ai_marker.submissions.deleted';
  final LocalStore _store;

  List<Submission> _submissions = const [];
  List<Submission> get submissions => _submissions;
  /// Results other accounts left on this device: saved back as they were,
  /// never shown, never synced to the signed-in teacher's cloud.
  List<Submission> _otherAccounts = const [];
  Set<String> _pendingCloudDeletes = {};

  SubmissionsService({LocalStore? store}) : _store = store ?? const LocalStore();

  Future<void> init({required String teacherId, required List<String> studentIds, required List<String> classIds, required List<String> presetIds}) async {
    try {
      _otherAccounts = const [];
      final raw = await _store.getString(_kKey);
      if (raw == null || raw.isEmpty) {
        _submissions = const [];
      } else {
        try {
          final all = Submission.decodeList(raw);
          // Only the signed-in teacher's results are loaded. Results another
          // account left on this device are kept on disk, untouched, and
          // never shown or synced here: a shared school phone (or a guest
          // trying the app) must not inherit someone else's student work.
          // They used to be adopted by whoever signed in next.
          _submissions = all.where((s) => s.teacherId == teacherId).toList(growable: false);
          _otherAccounts = all.where((s) => s.teacherId != teacherId).toList(growable: false);
          debugPrint('SubmissionsService: loaded ${_submissions.length} result(s) from disk');
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
    try {
      final rawDeleted = await _store.getString(_kDeletedKey);
      if (rawDeleted != null && rawDeleted.isNotEmpty) {
        _pendingCloudDeletes = (jsonDecode(rawDeleted) as List).whereType<String>().toSet();
      }
    } catch (_) {
      _pendingCloudDeletes = {};
    }
    for (final id in _pendingCloudDeletes.toList()) {
      _cloudDelete(teacherId, id);
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
          if (!byId.containsKey(s.id) && !_pendingCloudDeletes.contains(s.id)) {
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

  /// Files a whole class set in one go.
  ///
  /// An imported form finishes thirty results at once. Saving them one at a
  /// time rewrote every result the teacher has ever had — annotations, the
  /// text read off each page and all — thirty times over, on the thread
  /// drawing the screen. By March that is seconds of the app locking up at
  /// exactly the moment she is watching it save and deciding it has hung.
  Future<List<Submission>> createAll(Iterable<Submission> items) async {
    final added = items.toList(growable: false);
    if (added.isEmpty) return added;
    // Reversed so the list is left exactly as a run of single creates would
    // leave it: newest first.
    _submissions = [...added.reversed, ..._submissions];
    await _persist();
    notifyListeners();
    for (final s in added) {
      _pushCloud(s);
    }
    return added;
  }

  Future<void> update(Submission submission) async {
    _submissions = _submissions.map((s) => s.id == submission.id ? submission : s).toList(growable: false);
    await _persist();
    notifyListeners();
    _pushCloud(submission);
  }

  /// Removes a marked result everywhere: this device, its saved page images,
  /// and the account's cloud copy (so it can't come back on the next sync).
  Future<void> delete(String id) async {
    final sub = getById(id);
    if (sub == null) return;
    _submissions = _submissions.where((s) => s.id != id).toList(growable: false);
    _pendingCloudDeletes.add(id);
    await _persist();
    await _persistDeleted();
    notifyListeners();
    if (!kIsWeb) {
      for (final p in sub.pageImagePaths) {
        try {
          await File(p).delete();
        } catch (_) {}
      }
    } else {
      // In a browser the pages sit in IndexedDB under "overnight/<paper>/pN";
      // the paper is the folder, and discarding it takes every page at once.
      final store = createOvernightPageStore();
      for (final paper in {for (final k in sub.pageImagePaths) if (k.split('/').length >= 3) k.split('/')[1]}) {
        await store.discard(paper);
      }
    }
    _cloudDelete(sub.teacherId, id);
  }

  /// Fire-and-forget: the tombstone only clears once the cloud copy is gone,
  /// so an offline delete gets retried on the next init.
  void _cloudDelete(String teacherId, String id) {
    AiGradingService().deleteSubmissionCloud(teacherId: teacherId, id: id).then((_) {
      _pendingCloudDeletes.remove(id);
      _persistDeleted();
    }).catchError((Object e) {
      debugPrint('Submission cloud delete failed (will retry on next launch): $e');
    });
  }

  Future<void> _persistDeleted() async => _store.setString(_kDeletedKey, jsonEncode(_pendingCloudDeletes.toList()));

  /// The written-out JSON for each result, remembered against the result
  /// itself. A submission never changes in place — an edit makes a new one —
  /// so its text is built once and reused after that. Weak keys, so results
  /// that have been deleted don't hold memory.
  final _encoded = Expando<String>('submission json');

  /// Byte-for-byte what [Submission.encodeList] writes, built by joining the
  /// per-result text instead of walking every result's whole object graph
  /// again. Saving one mark used to re-serialise the entire year's work.
  String _encodeAll() {
    final out = StringBuffer('[');
    final everyone = [..._submissions, ..._otherAccounts];
    for (var i = 0; i < everyone.length; i++) {
      if (i > 0) out.write(',');
      final s = everyone[i];
      out.write(_encoded[s] ??= jsonEncode(s.toJson()));
    }
    out.write(']');
    return out.toString();
  }

  Future<void> _persist() async => _store.setString(_kKey, _encodeAll());
}
