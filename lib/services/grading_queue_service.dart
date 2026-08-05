import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:marking_prokect_v2/services/ai_grading_service.dart';
import 'package:marking_prokect_v2/services/drive_service.dart';
import 'package:marking_prokect_v2/services/id_factory.dart';
import 'package:marking_prokect_v2/services/students_service.dart';
import 'package:marking_prokect_v2/services/submissions_service.dart';

enum GradingJobStatus { marking, done, error }

/// One scan working its way through marking in the background.
class GradingJob {
  final String id;
  final DateTime createdAt;
  final List<Uint8List> pages;
  final AiGradeRequest req;
  String label;
  GradingJobStatus status;
  AiGradeResult? result;
  String? submissionId;
  String? error;

  GradingJob({
    required this.id,
    required this.createdAt,
    required this.pages,
    required this.req,
    required this.label,
    this.status = GradingJobStatus.marking,
  });
}

/// Marks scans in the background so the teacher can keep scanning the next
/// test instead of waiting. Each job grades, auto-links the student by the
/// name read off the paper, saves the submission, and pops a notification
/// when it's ready. Results are opened from the tray on the home screen.
class GradingQueueService extends ChangeNotifier {
  final GlobalKey<ScaffoldMessengerState>? messengerKey;

  GradingQueueService({this.messengerKey});

  final List<GradingJob> _jobs = [];
  List<GradingJob> get jobs => List.unmodifiable(_jobs);
  int get markingCount => _jobs.where((j) => j.status == GradingJobStatus.marking).length;

  void enqueue({
    required AiGradeRequest req,
    required List<Uint8List> pages,
    required StudentsService students,
    required SubmissionsService submissions,
    String? label,
  }) {
    final job = GradingJob(
      id: 'job_${IdFactory.newId()}',
      createdAt: DateTime.now(),
      pages: pages,
      req: req,
      label: (label != null && label.trim().isNotEmpty) ? label : _timeLabel(DateTime.now()),
    );
    _jobs.insert(0, job);
    notifyListeners();
    _run(job, req, students, submissions); // deliberately not awaited
  }

  static String _timeLabel(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return 'Scan $h:$m ${t.hour >= 12 ? 'PM' : 'AM'}';
  }

  Future<void> _run(GradingJob job, AiGradeRequest req, StudentsService students, SubmissionsService submissions) async {
    try {
      final ai = AiGradingService();
      final res = await ai.grade(req);

      // Auto-link by the name read off the paper when no student was chosen.
      // Class students are tried first, full name then first name — a lone
      // "Oscar" on the page still links when the class has exactly one Oscar.
      var studentId = req.studentId;
      var classId = req.classId;
      final paperName = res.studentNameOnPaper?.trim() ?? '';
      if (studentId.isEmpty && paperName.isNotEmpty) {
        String norm(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
        final target = norm(paperName);
        final targetFirst = target.split(' ').first;
        final inClass = classId.isEmpty
            ? students.students
            : students.students.where((s) => s.classId == classId).toList();
        final pools = [if (!identical(inClass, students.students)) inClass, students.students];
        for (final pool in pools) {
          var matches = pool.where((s) => norm(s.name) == target).toList();
          if (matches.isEmpty) {
            matches = pool.where((s) => norm(s.name).split(' ').first == targetFirst).toList();
          }
          if (matches.length == 1) {
            studentId = matches.first.id;
            if (classId.isEmpty && matches.first.classId.trim().isNotEmpty) {
              classId = matches.first.classId;
            }
            break;
          }
          if (matches.length > 1) break; // ambiguous — leave for the teacher
        }
      }
      if (paperName.isNotEmpty && (job.label.startsWith('Scan') || job.label.isEmpty)) {
        job.label = paperName;
      }

      final saveReq = AiGradeRequest(
        teacherId: req.teacherId,
        studentId: studentId,
        classId: classId,
        presetId: req.presetId,
        subject: req.subject,
        mode: req.mode,
        criteria: req.criteria,
        harshness: req.harshness,
        notes: req.notes,
        overrideUsed: req.overrideUsed,
        imageBytes: req.imageBytes,
        studentName: req.studentName,
        studentGrade: req.studentGrade,
        gradeLevel: req.gradeLevel,
        region: req.region,
      );
      var submission = ai.toSubmission(req: saveReq, res: res);
      // Keep the scanned pages on-device so the teacher can reopen the
      // original and annotated views later (too heavy for the cloud copy).
      final imagePaths = await _savePagesLocally(submission.id, job.pages);
      if (imagePaths.isNotEmpty) submission = submission.copyWith(pageImagePaths: imagePaths);
      await submissions.create(submission);

      job.status = GradingJobStatus.done;
      job.result = res;
      job.submissionId = submission.id;
      notifyListeners();
      final unmatchedName = studentId.isEmpty && paperName.isNotEmpty;
      messengerKey?.currentState?.showSnackBar(
        SnackBar(content: Text(unmatchedName
            ? '${job.label} is marked (${res.primaryDisplay}) — no student called "$paperName" yet; open it to create or link them.'
            : '${job.label} is marked (${res.primaryDisplay}) — open it from the Marking tray.')),
      );
      _maybeAutoSaveToDrive(job, res); // deliberately not awaited
    } catch (e) {
      debugPrint('GradingQueueService job failed: $e');
      job.status = GradingJobStatus.error;
      job.error = e.toString();
      notifyListeners();
      messengerKey?.currentState?.showSnackBar(
        SnackBar(
          duration: e is UsageLimitException ? const Duration(seconds: 7) : const Duration(seconds: 4),
          content: Text(e is UsageLimitException
              ? e.message
              : 'Marking failed for ${job.label} — tap it in the tray to retry.'),
        ),
      );
    }
  }

  /// Writes the scanned pages to the app's documents folder so reopened
  /// results can show the original/annotated views.
  Future<List<String>> _savePagesLocally(String submissionId, List<Uint8List> pages) async {
    if (kIsWeb) return const [];
    try {
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/marked');
      if (!await folder.exists()) await folder.create(recursive: true);
      final paths = <String>[];
      for (var i = 0; i < pages.length; i++) {
        final f = File('${folder.path}/${submissionId}_$i.jpg');
        await f.writeAsBytes(pages[i]);
        paths.add(f.path);
      }
      return paths;
    } catch (e) {
      debugPrint('Saving marked pages locally failed: $e');
      return const [];
    }
  }

  /// Opt-in (Settings → Auto-save to Google Drive): every marked result is
  /// exported to the teacher's Drive automatically, with a notification so
  /// they always know a copy went there.
  Future<void> _maybeAutoSaveToDrive(GradingJob job, AiGradeResult res) async {
    try {
      final drive = DriveService();
      if (!await drive.autoSaveEnabled(job.req.teacherId)) return;
      if (!drive.isConnected) return;
      final paperName = res.studentNameOnPaper?.trim() ?? '';
      await drive.uploadMarkedResult(result: res, studentName: paperName.isNotEmpty ? paperName : job.label);
      messengerKey?.currentState?.showSnackBar(
        SnackBar(content: Text('${job.label}: marked copy saved to Google Drive → Markless folder.')),
      );
    } catch (e) {
      debugPrint('Drive auto-save failed: $e');
      messengerKey?.currentState?.showSnackBar(
        SnackBar(content: Text('${job.label}: couldn\'t auto-save to Google Drive — you can retry from the result screen.')),
      );
    }
  }

  /// Re-runs a failed job with its original request.
  void retry(String id, {required StudentsService students, required SubmissionsService submissions}) {
    final job = _jobs.cast<GradingJob?>().firstWhere((j) => j?.id == id, orElse: () => null);
    if (job == null || job.status != GradingJobStatus.error) return;
    job.status = GradingJobStatus.marking;
    job.error = null;
    notifyListeners();
    _run(job, job.req, students, submissions);
  }

  void remove(String id) {
    _jobs.removeWhere((j) => j.id == id);
    notifyListeners();
  }
}
