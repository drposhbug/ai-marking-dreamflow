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

/// The two things an overnight batch asks the server for, behind one small
/// interface.
///
/// The part of this feature that has to be right happens at 3am on a phone
/// nobody is holding, so it has to be testable without a phone, a network,
/// or a night.
abstract class OvernightApi {
  Future<String> submit({required String teacherId, required List<Map<String, dynamic>> items});
  Future<BatchOutcome> status({required String teacherId, required String batchId});
}

class _LiveOvernightApi implements OvernightApi {
  const _LiveOvernightApi();

  @override
  Future<String> submit({required String teacherId, required List<Map<String, dynamic>> items}) =>
      AiGradingService().batchSubmit(teacherId: teacherId, items: items);

  @override
  Future<BatchOutcome> status({required String teacherId, required String batchId}) =>
      AiGradingService().batchStatus(teacherId: teacherId, batchId: batchId);
}

/// One paper waiting inside an overnight batch.
class OvernightPaper {
  final String customId;
  final String label;

  /// Where the scanned pages live on this phone, relative to the app's
  /// documents folder. The pages are NOT held in memory — the app will be
  /// closed for hours before the marks come back — and the folder itself is
  /// not written down, because iOS moves it out from under the app on every
  /// update. Resolve with [absolutePagePaths].
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
        pagePaths: (j['page_paths'] as List? ?? const []).map((e) => _relativeToDocuments(e.toString())).toList(),
        classId: (j['class_id'] ?? '').toString(),
        presetId: (j['preset_id'] ?? '').toString(),
        subject: (j['subject'] ?? '').toString(),
        mode: GradingMode.values.firstWhere((m) => m.name == (j['mode'] ?? 'testQuiz'), orElse: () => GradingMode.testQuiz),
        studentName: j['student_name']?.toString(),
      );

  /// Where the pages actually are, right now, on this phone.
  List<String> absolutePagePaths(Directory documents) =>
      [for (final p in pagePaths) '${documents.path}/$p'];

  /// Batches queued by earlier builds wrote down the full path. Keep only
  /// the part below the documents folder, so a set queued before an app
  /// update can still find its scans afterwards.
  static String _relativeToDocuments(String stored) {
    final normalised = stored.replaceAll('\\', '/');
    final i = normalised.lastIndexOf('overnight/');
    return i < 0 ? normalised : normalised.substring(i);
  }
}

/// One class set sent off for the night.
class OvernightBatch {
  final String batchId;
  final String teacherId;
  final String label;
  final DateTime submittedAt;
  final List<OvernightPaper> papers;

  /// Papers already saved into the gradebook. Written to disk the moment
  /// each one lands, so a phone that dies half way through filing thirty
  /// papers picks up at the eleventh rather than marking ten of them twice.
  final Set<String> filedIds;

  /// Papers this batch is never going to produce, and why. Kept rather than
  /// logged: a teacher who handed over thirty papers has to be told which
  /// three didn't come back.
  final Map<String, String> failures;

  /// When the batch stopped being something to wait for. Settled batches
  /// are not polled again and no longer count as "marking overnight", but
  /// they stay on disk while they still have papers that need re-marking.
  DateTime? settledAt;

  OvernightBatch({
    required this.batchId,
    required this.teacherId,
    required this.label,
    required this.submittedAt,
    required this.papers,
    Set<String>? filedIds,
    Map<String, String>? failures,
    this.settledAt,
  })  : filedIds = filedIds ?? <String>{},
        failures = failures ?? <String, String>{};

  /// Papers still owed a mark — not yet filed, and not given up on.
  List<OvernightPaper> get outstanding =>
      papers.where((p) => !filedIds.contains(p.customId) && !failures.containsKey(p.customId)).toList();

  bool get isFinished => outstanding.isEmpty;

  Map<String, dynamic> toJson() => {
        'batch_id': batchId,
        'teacher_id': teacherId,
        'label': label,
        'submitted_at': submittedAt.toIso8601String(),
        'papers': papers.map((p) => p.toJson()).toList(),
        'filed_ids': filedIds.toList(),
        'failures': failures,
        if (settledAt != null) 'settled_at': settledAt!.toIso8601String(),
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
        filedIds: (j['filed_ids'] as List? ?? const []).map((e) => e.toString()).toSet(),
        failures: (j['failures'] as Map? ?? const {}).map((k, v) => MapEntry(k.toString(), v.toString())),
        settledAt: DateTime.tryParse((j['settled_at'] ?? '').toString()),
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
  static const storageKey = 'ai_marker.overnight_batches';
  final LocalStore _store;
  final OvernightApi _api;
  final Future<Directory> Function() _documentsDir;

  OvernightService({LocalStore? store, OvernightApi? api, Future<Directory> Function()? documentsDir})
      : _store = store ?? const LocalStore(),
        _api = api ?? const _LiveOvernightApi(),
        _documentsDir = documentsDir ?? getApplicationDocumentsDirectory;

  /// Anthropic gives a batch 24 hours to finish. A set still unfinished well
  /// past that is never going to arrive, and a card promising marks in the
  /// morning would go on lying about it every launch.
  static const staleAfter = Duration(hours: 36);

  List<OvernightBatch> _all = const [];

  /// Sets genuinely still being marked — what the home screen counts.
  List<OvernightBatch> get batches => _all.where((b) => b.settledAt == null).toList();

  /// Sets that are over but left papers unmarked. Kept, with their scans, so
  /// nothing a teacher handed over disappears without them being told.
  List<OvernightBatch> get needsAttention =>
      _all.where((b) => b.settledAt != null && b.failures.isNotEmpty).toList();

  int get pendingPapers => batches.fold(0, (n, b) => n + b.outstanding.length);

  OvernightReport? _lastReport;

  /// What the most recent check did. Set by [checkNow] and never restored
  /// from disk — it describes this morning, not every morning since.
  OvernightReport? get lastReport => _lastReport;

  bool _checking = false;
  bool get checking => _checking;

  Future<void> init() async {
    try {
      final raw = await _store.getString(storageKey);
      if (raw != null && raw.isNotEmpty) {
        _all = (jsonDecode(raw) as List)
            .whereType<Map>()
            .map((m) => OvernightBatch.fromJson(m.cast<String, dynamic>()))
            .toList();
      }
    } catch (e) {
      debugPrint('OvernightService.init failed: $e');
      _all = const [];
    }
    notifyListeners();
  }

  Future<void> _persist() async => _store.setString(storageKey, jsonEncode(_all.map((b) => b.toJson()).toList()));

  /// Writes a paper's pages somewhere they'll survive the app closing, and
  /// returns where they went.
  ///
  /// The documents folder, not the temporary one: the OS is free to empty
  /// the temporary folder whenever it wants space back, and it would be
  /// doing exactly that overnight while the app sits closed.
  ///
  /// The paths returned are relative to that folder. iOS hands the app a
  /// new container after every update and moves the documents into it, so
  /// an absolute path written down at bedtime can point nowhere by morning.
  Future<List<String>> stashPages(String customId, List<Uint8List> pages) async {
    try {
      final root = await _documentsDir();
      final dir = Directory('${root.path}/overnight/$customId');
      await dir.create(recursive: true);
      final paths = <String>[];
      for (var i = 0; i < pages.length; i++) {
        await File('${dir.path}/p$i.jpg').writeAsBytes(pages[i], flush: true);
        paths.add('overnight/$customId/p$i.jpg');
      }
      return paths;
    } catch (e) {
      debugPrint('OvernightService.stashPages failed: $e');
      return const [];
    }
  }

  /// Removes pages stashed for a paper that never made it into a batch, so
  /// a failed send doesn't leave a class set's scans on the phone forever.
  Future<void> discardStash(String customId) async {
    try {
      final dir = Directory('${(await _documentsDir()).path}/overnight/$customId');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('OvernightService.discardStash failed: $e');
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
    final batchId = await _api.submit(teacherId: teacherId, items: items);
    final batch = OvernightBatch(
      batchId: batchId,
      teacherId: teacherId,
      label: label,
      submittedAt: DateTime.now(),
      papers: papers,
    );
    _all = [batch, ..._all];
    await _persist();
    notifyListeners();
    return batch;
  }


  /// Polls every batch still in flight and files whatever has finished.
  /// Safe to call on every app launch; does nothing when there's nothing
  /// pending, and safe to call again straight afterwards.
  ///
  /// Three things it must never do, because each one costs a teacher real
  /// work: file the same paper twice, let one paper's problem cost the
  /// other twenty-nine their marks, or drop a paper without saying so.
  Future<int> checkNow({
    required String teacherId,
    required StudentsService students,
    required SubmissionsService submissions,
  }) async {
    if (_checking) return 0;
    final waiting = _all.where((b) => b.settledAt == null && b.teacherId == teacherId).toList();
    if (waiting.isEmpty) return 0;
    _checking = true;
    notifyListeners();

    var filed = 0;
    final unfinished = <String>[];
    var stillMarking = false;
    try {
      final root = await _documentsDir().catchError((Object e) {
        debugPrint('OvernightService: no documents folder — $e');
        return Directory('');
      });

      for (final batch in waiting) {
        BatchOutcome outcome;
        try {
          outcome = await _api.status(teacherId: teacherId, batchId: batch.batchId);
        } catch (e) {
          // A flat phone, no signal, or a session that expired overnight.
          // None of those mean the marking failed, so leave the batch alone
          // and try again on the next launch — nothing is lost by waiting.
          debugPrint('Overnight batch ${batch.batchId} could not be checked: $e');
          stillMarking = true;
          continue;
        }

        if (!outcome.isEnded) {
          if (DateTime.now().difference(batch.submittedAt) > staleAfter) {
            for (final paper in batch.outstanding) {
              batch.failures[paper.customId] = 'Didn\'t come back in time';
              unfinished.add(paper.label);
            }
            batch.settledAt = DateTime.now();
            await _persist();
            notifyListeners();
          } else {
            stillMarking = true;
          }
          continue;
        }

        for (final paper in batch.outstanding) {
          final res = outcome.results[paper.customId];
          if (res == null) {
            // The batch is over and this paper isn't in it: an expired or
            // errored request. Recorded against the batch rather than
            // logged, so the teacher can be told which paper it was — and
            // its scan stays on the phone to be marked again.
            batch.failures[paper.customId] = outcome.failures[paper.customId] ?? 'Didn\'t come back';
            unfinished.add(paper.label);
            continue;
          }
          try {
            await _fileResult(
              paper: paper,
              res: res,
              root: root,
              teacherId: teacherId,
              students: students,
              submissions: submissions,
            );
            // Written down before the next paper is started. A phone killed
            // half way through filing thirty papers reopens knowing which
            // ones are already in the gradebook.
            batch.filedIds.add(paper.customId);
            await _persist();
            filed++;
          } catch (e) {
            // Left outstanding on purpose: this paper is re-tried on the
            // next check, and the twenty-nine after it still get filed now.
            debugPrint('Overnight: couldn\'t file ${paper.label} — $e');
            stillMarking = true;
          }
        }

        if (batch.isFinished) batch.settledAt = DateTime.now();
        await _persist();
        notifyListeners();
      }

      // A set with every paper filed has nothing left to say. One that left
      // papers behind stays, with its scans, until the teacher deals with it.
      final spent = _all.where((b) => b.settledAt != null && b.failures.isEmpty).map((b) => b.batchId).toSet();
      if (spent.isNotEmpty) {
        _all = _all.where((b) => !spent.contains(b.batchId)).toList();
        await _persist();
      }
    } finally {
      _lastReport = OvernightReport(filed: filed, unfinished: unfinished, stillMarking: stillMarking);
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
    required Directory root,
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
      pageImagePaths: paper.absolutePagePaths(root),
    ));
  }

  /// Forgets a batch the teacher no longer wants waiting on them. The pages
  /// stay on disk — dropping the tracking must not delete their scans.
  Future<void> forget(String batchId) async {
    _all = _all.where((b) => b.batchId != batchId).toList();
    await _persist();
    notifyListeners();
  }
}

/// What the last check actually did, so a teacher can be told the truth in
/// the morning instead of just a number.
class OvernightReport {
  /// Papers that came back marked and are now in the gradebook.
  final int filed;

  /// Papers that are never coming back, labelled the way the teacher named
  /// them — "3 papers failed" is no use when you handed over thirty.
  final List<String> unfinished;

  /// Something is still outstanding: a set still being marked, one that
  /// couldn't be reached, or a paper that couldn't be saved just yet. All
  /// three mean "check again later", not "something went wrong".
  final bool stillMarking;

  const OvernightReport({this.filed = 0, this.unfinished = const [], this.stillMarking = false});
}
