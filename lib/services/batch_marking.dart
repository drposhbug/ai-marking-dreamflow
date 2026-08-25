import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:marking_prokect_v2/app/app_routes.dart';
import 'package:marking_prokect_v2/app/app_state.dart';
import 'package:marking_prokect_v2/services/ai_grading_service.dart';
import 'package:marking_prokect_v2/services/auth_service.dart';
import 'package:marking_prokect_v2/services/grading_queue_service.dart';
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
