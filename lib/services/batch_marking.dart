import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:marking_prokect_v2/app/app_routes.dart';
import 'package:marking_prokect_v2/app/app_state.dart';
import 'package:marking_prokect_v2/models/grading_preset.dart';
import 'package:marking_prokect_v2/services/ai_grading_service.dart';
import 'package:marking_prokect_v2/services/anonymizer.dart';
import 'package:marking_prokect_v2/services/auth_service.dart';
import 'package:marking_prokect_v2/services/grading_queue_service.dart';
import 'package:marking_prokect_v2/services/id_factory.dart';
import 'package:marking_prokect_v2/services/overnight_service.dart';
import 'package:marking_prokect_v2/services/page_fingerprint.dart';
import 'package:marking_prokect_v2/services/students_service.dart';
import 'package:marking_prokect_v2/services/submissions_service.dart';
import 'package:provider/provider.dart';

/// Queues one background marking job per student for a class set.
///
/// Shared by every route that produces a stack of papers at once — files
/// picked from Drive, and a copier PDF split back into individual tests —
/// so they all get the same pilot-then-fleet cost behaviour: the first paper
/// marks alone and learns the answer key, the rest mark against it cheaply.
///
/// [studentNames] is positional with [groups]; a non-null entry is passed to
/// the marker as the name on that paper (read off a "Name:" field on the
/// device), which saves the AI re-reading it and lets the result link itself
/// to the right student.
int enqueueStudentGroups({
  required BuildContext context,
  required List<List<Uint8List>> groups,
  List<String?>? studentNames,
  List<String?>? labels,
}) {
  final auth = context.read<AuthService>().currentUser;
  if (auth == null || groups.isEmpty) return 0;
  final app = context.read<AppState>();
  final draft = app.draft;
  final students = context.read<StudentsService>();
  final submissions = context.read<SubmissionsService>();
  final queue = context.read<GradingQueueService>();
  queue.anonymizeUploads = app.anonymizeUploads;
  attachFleetConfirmation(context);

  final reqs = <AiGradeRequest>[];
  final pagesList = <List<Uint8List>>[];
  final jobLabels = <String?>[];
  for (var i = 0; i < groups.length; i++) {
    final bytes = groups[i];
    if (bytes.isEmpty) continue;
    final name = (studentNames != null && i < studentNames.length) ? studentNames[i] : null;
    reqs.add(AiGradeRequest(
      teacherId: auth.id,
      studentId: '',
      classId: draft.classId ?? '',
      presetId: draft.presetId ?? '',
      subject: draft.detectedSubject ?? 'Subject',
      mode: draft.mode,
      criteria: const {},
      harshness: draft.harshness,
      notes: null,
      overrideUsed: draft.oneTimeOverride,
      imageBytes: bytes.first,
      pageImages: bytes,
      studentName: (name != null && name.trim().isNotEmpty) ? name.trim() : null,
      studentGrade: null,
      gradeLevel: draft.gradeLevel,
      region: app.region,
      teacherFeedback: app.markingFeedback,
      answerKeyId: draft.answerKeyId.isEmpty ? null : draft.answerKeyId,
    ));
    pagesList.add(bytes);
    final label = (labels != null && i < labels.length) ? labels[i] : null;
    jobLabels.add(label ?? (name != null && name.trim().isNotEmpty ? name.trim() : 'Student ${i + 1}'));
  }
  if (reqs.isEmpty) return 0;

  queue.enqueueBatch(reqs: reqs, pagesList: pagesList, labels: jobLabels, students: students, submissions: submissions);
  return reqs.length;
}

/// The check-the-first-one gate. Once the pilot paper has marked, the
/// teacher is taken to a screen showing what it actually did, where they can
/// approve the set or type a correction and have it marked again.
///
/// Wired here rather than in the queue because only the UI layer can
/// navigate. Returns false when they close it — the remaining papers stay
/// held in the tray rather than being marked or thrown away.
void attachFleetConfirmation(BuildContext context) {
  final queue = context.read<GradingQueueService>();
  final navContext = context;
  queue.confirmFleet = (pilot, remaining) async {
    if (!navContext.mounted) return true;
    await navContext.push<bool>("${AppRoutes.pilotReview}?jobId=${pilot.id}");
    // Always false: the screen releases the set itself on approval, so the
    // teacher's typed corrections travel with the remaining papers.
    // Returning true here would mark them a second time, uncorrected.
    return false;
  };
}

/// Sends the papers a teacher has approved off for overnight marking
/// instead of marking them one at a time now.
///
/// Everything the server needs is built from the same held jobs the live
/// path would have used, so an overnight paper is marked identically to a
/// live one — only the timing and the price differ.
Future<int> sendHeldOvernight({
  required BuildContext context,
  required String label,
  List<String> extraFeedback = const [],
}) async {
  final auth = context.read<AuthService>().currentUser;
  final queue = context.read<GradingQueueService>();
  final overnight = context.read<OvernightService>();
  final app = context.read<AppState>();
  if (auth == null) return 0;

  final held = queue.heldJobs;
  if (held.isEmpty) return 0;

  final items = <Map<String, dynamic>>[];
  final papers = <OvernightPaper>[];
  for (final job in held) {
    final customId = 'ov_${IdFactory.newId()}';
    // Redact names before the pages ever leave, exactly as the live path
    // does — an overnight paper must not be less private than a live one.
    var pages = job.pages;
    String? localName = job.req.studentName;
    if (app.anonymizeUploads) {
      final (clean, found) = await Anonymizer.pages(job.pages);
      pages = clean;
      localName ??= found;
    }
    final paths = await overnight.stashPages(customId, job.pages);
    if (paths.isEmpty) continue;

    final r = job.req;
    items.add({
      'customId': customId,
      'imagesBase64': pages.map(base64Encode).toList(growable: false),
      'mediaType': 'image/jpeg',
      'mode': r.mode.name,
      'maxScore': _maxScoreFor(r.mode),
      'harshness': r.harshness,
      'criteria': const <String>[],
      if (r.studentGrade != null) 'studentGrade': r.studentGrade,
      if (r.gradeLevel != null) 'expectationGrade': r.gradeLevel,
      if (r.region != null && r.region!.isNotEmpty) 'region': r.region,
      'teacherFeedback': [...(r.teacherFeedback ?? const <String>[]), ...extraFeedback],
      if (r.answerKeyId != null && r.answerKeyId!.isNotEmpty) 'answerKeyId': r.answerKeyId,
    });
    papers.add(OvernightPaper(
      customId: customId,
      label: job.label,
      pagePaths: paths,
      classId: r.classId,
      presetId: r.presetId,
      subject: r.subject,
      mode: r.mode,
      studentName: localName,
    ));
  }
  if (items.isEmpty) return 0;

  await overnight.submit(teacherId: auth.id, label: label, items: items, papers: papers);
  // The queue copies are done with — the batch owns these papers now, and
  // their pages are safely on disk.
  queue.discardHeld();
  return items.length;
}

/// Mirrors the server's fallback totals so an overnight request carries the
/// same maxScore the live path would have used.
int _maxScoreFor(GradingMode mode) => switch (mode) {
      GradingMode.homework => 100,
      GradingMode.testQuiz => 25,
      GradingMode.labReport => 40,
      GradingMode.englishEssay => 25,
    };

/// Files any overnight marking that finished while the app was closed.
/// Called on launch — this is how a teacher wakes up to marked papers.
Future<int> checkOvernight(BuildContext context) async {
  final auth = context.read<AuthService>().currentUser;
  if (auth == null) return 0;
  final overnight = context.read<OvernightService>();
  return overnight.checkNow(
    teacherId: auth.id,
    students: context.read<StudentsService>(),
    submissions: context.read<SubmissionsService>(),
  );
}

/// Drops papers that were already marked for this class.
///
/// The case this exists for: a teacher whose stack split badly fixes the
/// order and rescans the whole lot. Without this they pay to mark the
/// papers that came out fine the first time, and then delete the duplicate
/// results by hand. Matching is by page fingerprint, computed on the
/// device — no credits, no uploads.
///
/// Returns the indexes of [groups] that are new.
Future<List<int>> dropAlreadyMarked({
  required BuildContext context,
  required List<List<Uint8List>> groups,
  String? classId,
}) async {
  final submissions = context.read<SubmissionsService>().submissions;
  final known = <PageFingerprint>[];
  for (final s in submissions) {
    if (classId != null && classId.isNotEmpty && s.classId != classId) continue;
    for (final h in s.pageHashes) {
      // Detail isn't stored; assume a real page. A stored hash only exists
      // because a paper was actually marked.
      known.add(PageFingerprint(h, 32));
    }
  }
  if (known.isEmpty) return [for (var i = 0; i < groups.length; i++) i];

  final keep = <int>[];
  for (var i = 0; i < groups.length; i++) {
    if (groups[i].isEmpty) continue;
    final first = await PageFingerprint.of(groups[i].first);
    final seen = first != null && known.any((k) => k.matches(first));
    if (!seen) keep.add(i);
  }
  return keep;
}
