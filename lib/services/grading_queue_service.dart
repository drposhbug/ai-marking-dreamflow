import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:marking_prokect_v2/services/overnight_page_store.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:marking_prokect_v2/services/anonymizer.dart';
import 'package:marking_prokect_v2/services/ai_grading_service.dart';
import 'package:marking_prokect_v2/services/drive_service.dart';
import 'package:marking_prokect_v2/services/id_factory.dart';
import 'package:marking_prokect_v2/services/page_fingerprint.dart';
import 'package:marking_prokect_v2/services/students_service.dart';
import 'package:marking_prokect_v2/services/submissions_service.dart';

/// Marks one paper. Injectable so the queue's behaviour when marking is
/// slow, or never answers at all, can be tested without a network.
typedef Grader = Future<AiGradeResult> Function(AiGradeRequest req);

/// `held` = marked-pilot-first: the rest of a class set waits for the
/// teacher to confirm the first paper marked correctly, so a bad key or the
/// wrong mode costs one paper instead of thirty.
enum GradingJobStatus { marking, held, done, error }

/// One scan working its way through marking in the background.
class GradingJob {
  final String id;
  final DateTime createdAt;
  final List<Uint8List> pages;
  /// Mutable so a re-marked pilot keeps the corrected instructions for any
  /// further re-mark.
  AiGradeRequest req;
  String label;
  GradingJobStatus status;
  AiGradeResult? result;
  String? submissionId;
  String? error;
  // Whether to announce a learned answer key for this job (batch pilots
  // stay quiet — the batch announces once for the whole set).
  bool notifyLearnedKey = true;

  /// What actually happened to the student's name on the copy that was
  /// sent. Set the moment the pages go up, and shown to the teacher — a
  /// paper that went out with the name on it must not be a silent event.
  NameHiding nameHiding = NameHiding.notFound;

  /// True when these pages already went through the browser's redaction
  /// review and came out covered.
  ///
  /// Without this the report lies in the one case that matters most. A
  /// teacher who painted over a name the reader missed hands up a page whose
  /// `Name:` label is itself under the black box — so the second pass finds
  /// no label, reports nothing covered, and the app tells her the name went
  /// out uncovered when she is looking at proof that it did not.
  bool namesCoveredAlready = false;

  /// Completes when this job finishes (done or error) — lets a batch wait
  /// for its pilot paper before releasing the rest.
  final Completer<void> _done = Completer<void>();
  Future<void> get done => _done.future;
  void _markDone() {
    if (!_done.isCompleted) _done.complete();
  }

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

  /// How many papers may be up in the air at once.
  ///
  /// Releasing a class set used to fire all thirty uploads simultaneously —
  /// thirty multi-megabyte photo sets leaving one phone on school wifi. What
  /// came back was a scatter of failures the teacher had to open every paper
  /// to understand. Three at a time takes marginally longer and fails in a
  /// way that can be read: "four papers failed, tap to retry".
  static const maxConcurrentMarking = 3;

  final Grader _grader;

  GradingQueueService({this.messengerKey, Grader? grader})
      : _grader = grader ?? _liveGrader;

  static Future<AiGradeResult> _liveGrader(AiGradeRequest req) => AiGradingService().grade(req);

  /// Whether names get blacked out before upload. Set from AppState when a
  /// job is queued, so the queue does not need a BuildContext.
  bool anonymizeUploads = true;

  /// Papers currently being marked, and the ones waiting for a turn.
  int _marking = 0;
  final List<Completer<void>> _waitingForSlot = [];

  Future<void> _takeSlot() {
    if (_marking < maxConcurrentMarking) {
      _marking++;
      return Future<void>.value();
    }
    final c = Completer<void>();
    _waitingForSlot.add(c);
    return c.future;
  }

  /// Hands the slot straight to whoever is next rather than releasing and
  /// re-taking it, so the count can never drift.
  void _freeSlot() {
    if (_waitingForSlot.isNotEmpty) {
      _waitingForSlot.removeAt(0).complete();
      return;
    }
    _marking--;
  }


  final List<GradingJob> _jobs = [];
  List<GradingJob> get jobs => List.unmodifiable(_jobs);
  int get markingCount => _jobs.where((j) => j.status == GradingJobStatus.marking).length;

  GradingJob enqueue({
    required AiGradeRequest req,
    required List<Uint8List> pages,
    required StudentsService students,
    required SubmissionsService submissions,
    String? label,
    bool notifyLearnedKey = true,
    bool namesCoveredAlready = false,
  }) {
    final job = GradingJob(
      id: 'job_${IdFactory.newId()}',
      createdAt: DateTime.now(),
      pages: pages,
      req: req,
      label: (label != null && label.trim().isNotEmpty) ? label : _timeLabel(DateTime.now()),
    );
    job.notifyLearnedKey = notifyLearnedKey;
    job.namesCoveredAlready = namesCoveredAlready;
    _jobs.insert(0, job);
    notifyListeners();
    _run(job, req, students, submissions); // deliberately not awaited
    return job;

  }
  /// Default job label when the teacher has not named the paper.
  String _timeLabel(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return 'Scan $h:$m ${t.hour >= 12 ? 'PM' : 'AM'}';
  }

  /// Asked after the pilot paper marks, before the rest of the set is sent.
  /// Returning false holds the remaining papers instead of marking them.
  /// Set by the UI layer, which is the only place that can show a dialog.
  Future<bool> Function(GradingJob pilot, int remaining)? confirmFleet;

  /// Told when a single paper, marked without a key, has taught one. The
  /// setup screen selects it for the next paper, so a teacher marking one
  /// paper at a time gets the class-set behaviour: every paper after the
  /// first is marked against the same answers instead of the marker working
  /// them out again — the difference between a borderline answer landing
  /// the same way on every paper and landing either way.
  void Function(String keyId, String keyName)? onKeyLearned;

  /// Papers waiting on the teacher's OK, in the order they were scanned.
  List<GradingJob> get heldJobs => _jobs.where((j) => j.status == GradingJobStatus.held).toList();

  /// Class-set marking, cost-aware and check-first: the FIRST paper marks
  /// alone (the pilot). If it was keyless graded work, the AI saves the
  /// answers it derived as a reusable key, and every remaining paper marks
  /// against that key on the cheap deterministic route (~10× cheaper).
  ///
  /// The rest of the set only goes out once the teacher has seen that first
  /// result. A wrong answer key, the wrong grading mode or a misread paper
  /// then costs ONE paper and one credit, not thirty of each — and thirty
  /// wrong marks are far more work to undo than one.
  Future<void> enqueueBatch({
    required List<AiGradeRequest> reqs,
    required List<List<Uint8List>> pagesList,
    required List<String?> labels,
    required StudentsService students,
    required SubmissionsService submissions,
  }) async {
    if (reqs.isEmpty) return;
    final pilot = enqueue(
      req: reqs.first,
      pages: pagesList.first,
      students: students,
      submissions: submissions,
      label: labels.first,
      notifyLearnedKey: reqs.length == 1,
    );
    if (reqs.length == 1) return;

    // The rest of the set goes into the tray NOW, held, before anything is
    // waited on. They used to be built after the pilot came back, which
    // meant that while the pilot was in the air — or hung on a school wifi
    // that accepts the connection and then answers nothing — twenty-nine
    // scanned papers existed only as local variables inside this function.
    // Not in the tray, not on disk, nowhere a teacher could see or retry
    // them. Force-quitting the stuck app took all thirty scans with it.
    final held = <GradingJob>[];
    for (var i = 1; i < reqs.length; i++) {
      final job = GradingJob(
        id: 'job_${IdFactory.newId()}',
        createdAt: DateTime.now(),
        pages: pagesList[i],
        req: reqs[i],
        label: (labels[i] ?? '').trim().isNotEmpty ? labels[i]! : 'Paper ${i + 1}',
        status: GradingJobStatus.held,
      );
      held.add(job);
      _jobs.insert(0, job);
    }
    notifyListeners();

    await pilot.done;

    final keyId = pilot.result?.learnedKeyId;
    final keyName = pilot.result?.learnedKeyName;

    // The pilot may have derived the answer key. Give it to the papers
    // waiting, so they mark against it cheaply the way they always did.
    if (keyId != null) {
      for (final job in held) {
        final r = job.req;
        if (r.answerKeyId == null || r.answerKeyId!.isEmpty) job.req = r.withAnswerKey(keyId);
      }
    }

    if (keyId != null) {
      messengerKey?.currentState?.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text('Learned "$keyName" from the first paper — the rest of this set will mark against it (cheaper and more consistent). It\'s saved with your answer keys.'),
        ),
      );
    }

    // The pilot failing is the strongest possible signal not to send 29 more.
    final ask = confirmFleet;
    if (pilot.status == GradingJobStatus.error) {
      messengerKey?.currentState?.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text('The first paper didn\'t mark, so the other ${held.length} are on hold. Fix the problem and release them from the tray — nothing was lost.'),
        ),
      );
      return;
    }
    if (ask == null) {
      // No UI attached to ask: mark them rather than stranding the set.
      releaseHeld(students: students, submissions: submissions, jobs: held);
      return;
    }
    final go = await ask(pilot, held.length);
    if (go) {
      releaseHeld(students: students, submissions: submissions, jobs: held);
    } else {
      messengerKey?.currentState?.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text('${held.length} papers are on hold in the tray. Change what you need and release them when you\'re happy.'),
        ),
      );
    }
  }

  /// The same request with extra standing instructions from the teacher —
  /// the "mark it this way instead" notes typed on the pilot review screen.
  static AiGradeRequest _withFeedback(AiGradeRequest r, List<String> extra) {
    if (extra.isEmpty) return r;
    final merged = <String>[...(r.teacherFeedback ?? const []), ...extra];
    return AiGradeRequest(
      teacherId: r.teacherId,
      studentId: r.studentId,
      classId: r.classId,
      presetId: r.presetId,
      subject: r.subject,
      mode: r.mode,
      criteria: r.criteria,
      harshness: r.harshness,
      overrideUsed: r.overrideUsed,
      imageBytes: r.imageBytes,
      pageImages: r.pageImages,
      notes: r.notes,
      studentGrade: r.studentGrade,
      gradeLevel: r.gradeLevel,
      region: r.region,
      teacherFeedback: merged,
      formatOverride: r.formatOverride,
      studentName: r.studentName,
      answerKeyId: r.answerKeyId,
      includeTranscription: r.includeTranscription,
    );
  }

  /// Marks the pilot paper again with the teacher's correction applied.
  /// Same pages, same everything else — only the instructions change — so
  /// the teacher can see whether their note actually fixed what bothered
  /// them before the whole class is marked the same way.
  Future<void> remarkPilot({
    required GradingJob job,
    required List<String> extraFeedback,
    required StudentsService students,
    required SubmissionsService submissions,
  }) async {
    final revised = _withFeedback(job.req, extraFeedback);
    job.status = GradingJobStatus.marking;
    job.error = null;
    notifyListeners();
    // Replaces the job's request so a further re-mark builds on this one.
    _jobs[_jobs.indexOf(job)] = job;
    await _run(job, revised, students, submissions, replaceSubmission: true);
  }

  /// Sends held papers off to be marked. Called when the teacher approves
  /// the pilot, or later from the tray.
  /// [extraFeedback] carries the corrections the teacher typed while
  /// reviewing the pilot, so the rest of the class is marked the way they
  /// just asked for — not the way the first attempt got it wrong.
  void releaseHeld({
    required StudentsService students,
    required SubmissionsService submissions,
    List<GradingJob>? jobs,
    List<String> extraFeedback = const [],
  }) {
    final list = jobs ?? heldJobs;
    for (final job in list) {
      if (job.status != GradingJobStatus.held) continue;
      job.status = GradingJobStatus.marking;
      _run(job, _withFeedback(job.req, extraFeedback), students, submissions); // deliberately not awaited
    }
    if (list.isNotEmpty) notifyListeners();
  }

  /// Drops held papers the teacher has decided not to mark.
  void discardHeld() {
    _jobs.removeWhere((j) => j.status == GradingJobStatus.held);
    notifyListeners();
  }

  /// The same request with different page images — used to swap in the
  /// redacted copies without disturbing anything else about the job.
  static AiGradeRequest _withPages(AiGradeRequest r, List<Uint8List> pages) => AiGradeRequest(
        teacherId: r.teacherId,
        studentId: r.studentId,
        classId: r.classId,
        presetId: r.presetId,
        subject: r.subject,
        mode: r.mode,
        criteria: r.criteria,
        harshness: r.harshness,
        overrideUsed: r.overrideUsed,
        imageBytes: pages.isEmpty ? r.imageBytes : pages.first,
        pageImages: pages.isEmpty ? r.pageImages : pages,
        notes: r.notes,
        studentGrade: r.studentGrade,
        gradeLevel: r.gradeLevel,
        region: r.region,
        teacherFeedback: r.teacherFeedback,
        formatOverride: r.formatOverride,
        studentName: r.studentName,
        answerKeyId: r.answerKeyId,
        includeTranscription: r.includeTranscription,
      );

  Future<void> _run(GradingJob job, AiGradeRequest req, StudentsService students, SubmissionsService submissions, {bool replaceSubmission = false}) async {
    // A re-marked pilot keeps its corrected instructions for the next round.
    job.req = req;
    // Waits its turn when the whole class was released at once. The job is
    // already in the tray showing "marking", so a teacher sees the set
    // working through rather than nothing happening.
    await _takeSlot();
    try {
      final ai = AiGradingService();

      // Read the name on this device and black it out of the copy that goes
      // up for marking. The marker grades the work; who wrote it stays here.
      // job.pages keeps the ORIGINAL pages so the teacher still sees the
      // real paper, name and all, when they open the result.
      var uploadReq = req;
      String? localName;
      var anyRedacted = false;
      if (anonymizeUploads && Anonymizer.available) {
        final set = await Anonymizer.pageSet(job.pages);
        localName = set.nameOnPaper;
        // A page already covered in the browser review has nothing left for
        // this pass to find, and that is a success rather than a miss.
        anyRedacted = set.anyRedacted || job.namesCoveredAlready;
        uploadReq = _withPages(req, set.pages);
      }
      // Recorded before the request goes out, so whatever the teacher is
      // shown afterwards describes what really left the device.
      job.nameHiding = Anonymizer.outcome(settingOn: anonymizeUploads, anyRedacted: anyRedacted);
      notifyListeners();

      final res = await _grader(uploadReq);

      // Auto-link by the name read off the paper when no student was chosen.
      // Class students are tried first, full name then first name — a lone
      // "Oscar" on the page still links when the class has exactly one Oscar.
      var studentId = req.studentId;
      var classId = req.classId;
      // The name read HERE wins: with redaction on, the marker never saw
      // one. Falls back to the model's read for un-redacted pages.
      final paperName = (localName?.trim().isNotEmpty ?? false) ? localName!.trim() : (res.studentNameOnPaper?.trim() ?? '');
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
      // Re-marking the pilot REPLACES its result. Without this, correcting
      // the marking three times would leave the student with three
      // submissions and the teacher deleting two of them by hand.
      final priorId = replaceSubmission ? job.submissionId : null;
      if (priorId != null) submission = submission.copyWith(id: priorId);
      // Keep the scanned pages on-device so the teacher can reopen the
      // original and annotated views later (too heavy for the cloud copy).
      final imagePaths = await _savePagesLocally(submission.id, job.pages);
      if (imagePaths.isNotEmpty) submission = submission.copyWith(pageImagePaths: imagePaths);
      // Fingerprints travel with the result so a later rescan of the same
      // class set can recognise this paper and skip re-marking it.
      final prints = await PageFingerprint.ofAll(job.pages);
      final hashes = [for (final p in prints) if (p != null && !p.isBlankish) p.hex];
      if (hashes.isNotEmpty) submission = submission.copyWith(pageHashes: hashes);
      if (priorId != null) {
        await submissions.update(submission);
      } else {
        await submissions.create(submission);
      }

      job.status = GradingJobStatus.done;
      job.result = res;
      job.submissionId = submission.id;
      notifyListeners();
      final unmatchedName = studentId.isEmpty && paperName.isNotEmpty;
      final methodFlags = res.annotations.where((a) => a.correct && a.methodNote.trim().isNotEmpty).length;
      final flagNote = methodFlags > 0
          ? ' $methodFlags question${methodFlags == 1 ? '' : 's'} solved with a different method — check the blue notes.'
          : '';
      messengerKey?.currentState?.showSnackBar(
        SnackBar(content: Text(unmatchedName
            ? '${job.label} is marked (${res.primaryDisplay}) — no student called "$paperName" yet; open it to create or link them.$flagNote'
            : '${job.label} is marked (${res.primaryDisplay}) — open it from the Marking tray.$flagNote')),
      );
      if (job.notifyLearnedKey && res.learnedKeyId != null) {
        final picked = onKeyLearned != null;
        onKeyLearned?.call(res.learnedKeyId!, res.learnedKeyName ?? 'Learned key');
        messengerKey?.currentState?.showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 8),
            content: Text(picked
                ? 'Answer key learned from this paper ("${res.learnedKeyName}") and picked for your next paper, so the rest of the class is marked the same way. Scanning a different test? Remove it on the setup screen.'
                : 'Answer key learned from this paper and saved ("${res.learnedKeyName}") — pick it for the rest of the class to mark cheaper and more consistently.'),
          ),
        );
      }
      _maybeAutoSaveToDrive(job, res); // deliberately not awaited
      job._markDone();
    } catch (e) {
      debugPrint('GradingQueueService job failed: $e');
      job.status = GradingJobStatus.error;
      job.error = e.toString();
      job._markDone();
      notifyListeners();
      messengerKey?.currentState?.showSnackBar(
        SnackBar(
          duration: e is UsageLimitException ? const Duration(seconds: 7) : const Duration(seconds: 4),
          content: Text(e is UsageLimitException
              ? e.message
              : 'Marking failed for ${job.label} — tap it in the tray to retry.'),
        ),
      );
    } finally {
      // Whatever happened, the next paper gets its turn.
      _freeSlot();
    }
  }

  /// Writes the scanned pages to the app's documents folder so reopened
  /// results can show the original/annotated views.
  Future<List<String>> _savePagesLocally(String submissionId, List<Uint8List> pages) async {
    // A browser keeps them in IndexedDB, under the same keys overnight
    // marking files its pages by, so the result screen reads both alike.
    if (kIsWeb) {
      try {
        return await createOvernightPageStore().write('marked-$submissionId', pages);
      } catch (e) {
        debugPrint('Saving marked pages in the browser failed: $e');
        return const [];
      }
    }
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
      // job.label already carries the name read off the paper (set in _run),
      // which is the only place it exists once redaction is on.
      final paperName = res.studentNameOnPaper?.trim() ?? '';
      await drive.uploadMarkedResult(result: res, studentName: paperName.isNotEmpty ? paperName : job.label);
      messengerKey?.currentState?.showSnackBar(
        SnackBar(content: Text('${job.label}: marked copy saved to Google Drive → UMarkless folder.')),
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
