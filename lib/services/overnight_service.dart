import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:marking_prokect_v2/models/grading_preset.dart';
import 'package:marking_prokect_v2/models/submission.dart';
import 'package:marking_prokect_v2/services/ai_grading_service.dart';
import 'package:marking_prokect_v2/services/id_factory.dart';
import 'package:marking_prokect_v2/services/local_store.dart';
import 'package:marking_prokect_v2/services/students_service.dart';
import 'package:marking_prokect_v2/services/submissions_service.dart';
import 'package:path_provider/path_provider.dart';

/// One paper waiting inside an overnight batch.
class OvernightPaper {
  final String customId;
  final String label;

  /// Where the scanned pages live on this phone. The pages are NOT held in
  /// memory — the app will be closed for hours before the marks come back.
  final List<String> pagePaths;
  final String classId;
  final String presetId;
  final String subject;
  final GradingMode mode;
  final String? studentName;

  const OvernightPaper({
    required this.customId,
    required this.label,
    required this.pagePaths,
    required this.classId,
    required this.presetId,
    required this.subject,
    required this.mode,
    this.studentName,
  });

  Map<String, dynamic> toJson() => {
        'custom_id': customId,
        'label': label,
        'page_paths': pagePaths,
        'class_id': classId,
        'preset_id': presetId,
        'subject': subject,
        'mode': mode.name,
        if (studentName != null) 'student_name': studentName,
      };

  factory OvernightPaper.fromJson(Map<String, dynamic> j) => OvernightPaper(
        customId: (j['custom_id'] ?? '').toString(),
        label: (j['label'] ?? '').toString(),
        pagePaths: (j['page_paths'] as List? ?? const []).map((e) => e.toString()).toList(),
        classId: (j['class_id'] ?? '').toString(),
        presetId: (j['preset_id'] ?? '').toString(),
        subject: (j['subject'] ?? '').toString(),
        mode: GradingMode.values.firstWhere((m) => m.name == (j['mode'] ?? 'testQuiz'), orElse: () => GradingMode.testQuiz),
        studentName: j['student_name']?.toString(),
      );
}

/// One class set sent off for the night.
class OvernightBatch {
  final String batchId;
  final String teacherId;
  final String label;
  final DateTime submittedAt;
  final List<OvernightPaper> papers;

  const OvernightBatch({
    required this.batchId,
    required this.teacherId,
    required this.label,
    required this.submittedAt,
    required this.papers,
  });

  Map<String, dynamic> toJson() => {
        'batch_id': batchId,
        'teacher_id': teacherId,
        'label': label,
        'submitted_at': submittedAt.toIso8601String(),
        'papers': papers.map((p) => p.toJson()).toList(),
      };

  factory OvernightBatch.fromJson(Map<String, dynamic> j) => OvernightBatch(
        batchId: (j['batch_id'] ?? '').toString(),
        teacherId: (j['teacher_id'] ?? '').toString(),
        label: (j['label'] ?? 'Class set').toString(),
        submittedAt: DateTime.tryParse((j['submitted_at'] ?? '').toString()) ?? DateTime.now(),
        papers: (j['papers'] as List? ?? const [])
            .whereType<Map>()
            .map((m) => OvernightPaper.fromJson(m.cast<String, dynamic>()))
            .toList(),
      );
}

/// "Scan the lot before bed, wake up to marked papers."
///
/// A class set goes to the Batch API instead of being marked one paper at a
/// time: half the price, and the teacher isn't waiting for it. Several sets
/// can be in flight at once — English tonight, Physics ten minutes later —
/// each tracked separately.
///
/// The app will be closed while this runs, so nothing lives in memory: the
/// scanned pages are written to disk and the batch list is persisted. On the
/// next launch the batches are polled and any that finished are filed away.
class OvernightService extends ChangeNotifier {
  static const _kKey = 'ai_marker.overnight_batches';
  final LocalStore _store;

  OvernightService({LocalStore? store}) : _store = store ?? const LocalStore();

  List<OvernightBatch> _batches = const [];
  List<OvernightBatch> get batches => _batches;
  int get pendingPapers => _batches.fold(0, (n, b) => n + b.papers.length);

  bool _checking = false;
  bool get checking => _checking;

  Future<void> init() async {
    try {
      final raw = await _store.getString(_kKey);
      if (raw != null && raw.isNotEmpty) {
        _batches = (jsonDecode(raw) as List)
            .whereType<Map>()
            .map((m) => OvernightBatch.fromJson(m.cast<String, dynamic>()))
            .toList();
      }
    } catch (e) {
      debugPrint('OvernightService.init failed: $e');
      _batches = const [];
    }
    notifyListeners();
  }

  Future<void> _persist() async => _store.setString(_kKey, jsonEncode(_batches.map((b) => b.toJson()).toList()));

  /// Writes a paper's pages somewhere they'll survive the app closing, and
  /// returns the paths.
  Future<List<String>> stashPages(String customId, List<Uint8List> pages) async {
    try {
      final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/overnight/$customId');
      await dir.create(recursive: true);
      final paths = <String>[];
      for (var i = 0; i < pages.length; i++) {
        final f = File('${dir.path}/p$i.jpg');
        await f.writeAsBytes(pages[i], flush: true);
        paths.add(f.path);
      }
      return paths;
    } catch (e) {
      debugPrint('OvernightService.stashPages failed: $e');
      return const [];
    }
  }

  /// Sends a class set off for the night. [items] carries everything the
  /// server needs to mark each paper; [papers] is what this device needs to
  /// file the results when they come back.
  Future<OvernightBatch> submit({
    required String teacherId,
    required String label,
    required List<Map<String, dynamic>> items,
    required List<OvernightPaper> papers,
  }) async {
    final batchId = await AiGradingService().batchSubmit(teacherId: teacherId, items: items);
    final batch = OvernightBatch(
      batchId: batchId,
      teacherId: teacherId,
      label: label,
      submittedAt: DateTime.now(),
      papers: papers,
    );
    _batches = [batch, ..._batches];
    await _persist();
    notifyListeners();
    return batch;
  }


  /// Polls every batch in flight and files whatever has finished. Safe to
  /// call on every app launch; does nothing when there's nothing pending.
  Future<int> checkNow({
    required String teacherId,
    required StudentsService students,
    required SubmissionsService submissions,
  }) async {
    if (_batches.isEmpty || _checking) return 0;
    _checking = true;
    notifyListeners();
    var filed = 0;
    try {
      final ai = AiGradingService();
      final done = <String>[];
      for (final batch in [..._batches]) {
        if (batch.teacherId != teacherId) continue;
        try {
          final outcome = await ai.batchStatus(teacherId: teacherId, batchId: batch.batchId);
          if (!outcome.isEnded) continue;
          for (final paper in batch.papers) {
            final res = outcome.results[paper.customId];
            if (res == null) {
              // A paper that failed is reported, never silently dropped —
              // its pages stay on disk so it can be marked again.
              debugPrint('Overnight: ${paper.label} failed — ${outcome.failures[paper.customId] ?? 'no result'}');
              continue;
            }
            await _fileResult(paper: paper, res: res, teacherId: teacherId, students: students, submissions: submissions);
            filed++;
          }
          done.add(batch.batchId);
        } catch (e) {
          debugPrint('Overnight batch ${batch.batchId} check failed: $e');
        }
      }
      if (done.isNotEmpty) {
        _batches = _batches.where((b) => !done.contains(b.batchId)).toList();
        await _persist();
      }
    } finally {
      _checking = false;
      notifyListeners();
    }
    return filed;
  }

  /// Saves one marked paper as a submission, linking it to a student by the
  /// name read off the page when the app has one.
  Future<void> _fileResult({
    required OvernightPaper paper,
    required AiGradeResult res,
    required String teacherId,
    required StudentsService students,
    required SubmissionsService submissions,
  }) async {
    final name = (paper.studentName ?? res.studentNameOnPaper ?? '').trim();
    var studentId = '';
    var classId = paper.classId;
    if (name.isNotEmpty) {
      String norm(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      final pool = classId.isEmpty
          ? students.students
          : students.students.where((s) => s.classId == classId).toList();
      final matches = pool.where((s) => norm(s.name) == norm(name)).toList();
      if (matches.length == 1) {
        studentId = matches.first.id;
        if (classId.isEmpty) classId = matches.first.classId;
      }
    }

    final now = DateTime.now();
    await submissions.create(Submission(
      id: 'sub_${IdFactory.newId()}',
      teacherId: teacherId,
      studentId: studentId,
      classId: classId,
      presetId: paper.presetId,
      subject: paper.subject.isEmpty ? res.detectedSubject : paper.subject,
      gradingMode: paper.mode,
      score: res.rawScore,
      maxScore: res.maxScore,
      feedback: res.summary,
      triageStatus: res.triageStatus,
      overrideUsed: false,
      triageFlags: res.flags,
      confidence: res.confidence,
      createdAt: now,
      updatedAt: now,
      resultJson: res.toJson(),
      pageImagePaths: paper.pagePaths,
    ));
  }

  /// Forgets a batch the teacher no longer wants waiting on them. The pages
  /// stay on disk — dropping the tracking must not delete their scans.
  Future<void> forget(String batchId) async {
    _batches = _batches.where((b) => b.batchId != batchId).toList();
    await _persist();
    notifyListeners();
  }
}
