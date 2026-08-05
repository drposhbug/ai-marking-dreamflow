import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:marking_prokect_v2/app/app_state.dart';
import 'package:marking_prokect_v2/models/grading_preset.dart';
import 'package:marking_prokect_v2/models/submission.dart';
import 'package:marking_prokect_v2/services/ai_grading_service.dart';
import 'package:marking_prokect_v2/services/auth_service.dart';
import 'package:marking_prokect_v2/services/drive_service.dart';
import 'package:marking_prokect_v2/services/students_service.dart';
import 'package:marking_prokect_v2/services/submissions_service.dart';
import 'package:marking_prokect_v2/theme.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

class ResultScreen extends StatefulWidget {
  final String? submissionId;

  // Pass these directly when navigating from the grading flow
  // so the result is shown immediately without a DB round-trip.
  final AiGradeResult? gradeResult;
  final Uint8List? imageBytes;
  final List<Uint8List>? pageImages;

  const ResultScreen({
    super.key,
    required this.submissionId,
    this.gradeResult,
    this.imageBytes,
    this.pageImages,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  int _tab = 0;
  int _page = 0;

  // Teacher can toggle between levels and percentage after grading.
  late String _displayFormat;
  AiGradeResult? _result;

  /// Page images restored from disk when this result was reopened later
  /// (live grading passes them via the route instead).
  List<Uint8List>? _restoredPages;

  List<Uint8List> get _pages {
    final p = widget.pageImages;
    if (p != null && p.isNotEmpty) return p;
    final r = _restoredPages;
    if (r != null && r.isNotEmpty) return r;
    final single = widget.imageBytes;
    return single == null ? const [] : [single];
  }

  bool _exportingToDrive = false;

  /// KTCA-marked work: show the final grade as the category average (how
  /// Ontario marking works, and the server default) or as total marks —
  /// the teacher picks.
  bool _useCategoryAverage = true;
  static const _ktcaNames = ['Knowledge', 'Thinking', 'Communication', 'Application'];
  List<CriterionResult> _ktcaOf(AiGradeResult r) =>
      r.criteriaBreakdown.where((c) => _ktcaNames.contains(c.name) && c.maxScore > 0).toList(growable: false);

  @override
  void initState() {
    super.initState();
    _result = widget.gradeResult;
    // Reopened from the dashboard/history: rebuild the full result from
    // the submission's saved payload so old marks get the complete UI.
    if (_result == null && widget.submissionId != null) {
      final sub = context.read<SubmissionsService>().getById(widget.submissionId!);
      if (sub?.resultJson != null) {
        try {
          _result = AiGradeResult.fromJson(sub!.resultJson!);
        } catch (e) {
          debugPrint('Saved result restore failed: $e');
        }
      }
      // Page photos are kept on-device per submission — load them so the
      // Original/Annotated tabs work on reopen too.
      final paths = sub?.pageImagePaths ?? const [];
      if (!kIsWeb && paths.isNotEmpty && (widget.pageImages == null || widget.pageImages!.isEmpty)) {
        Future(() async {
          final loaded = <Uint8List>[];
          for (final p in paths) {
            try {
              final f = File(p);
              if (await f.exists()) loaded.add(await f.readAsBytes());
            } catch (_) {}
          }
          if (mounted && loaded.isNotEmpty) setState(() => _restoredPages = loaded);
        });
      }
    }
    _displayFormat = _result?.gradingFormat ?? 'percentage';
  }

  /// The marked result as a Google Doc in the teacher's Drive ("Markless"
  /// folder): score, feedback, per-question notes, and the transcription.
  Future<void> _saveToDrive(AiGradeResult result, String? studentName) async {
    setState(() => _exportingToDrive = true);
    try {
      final name = (studentName != null && studentName.trim().isNotEmpty)
          ? studentName.trim()
          : (result.studentNameOnPaper ?? 'Unnamed student');
      await DriveService().uploadMarkedResult(result: result, studentName: name);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Saved to Google Drive → Markless folder ✓'),
      ));
    } on DriveAuthException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Google Drive isn\'t connected — sign out, then sign in with Google to link Drive.'),
      ));
    } catch (e) {
      debugPrint('Drive export failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Drive export failed: $e')));
    } finally {
      if (mounted) setState(() => _exportingToDrive = false);
    }
  }

  /// "Teach the AI" — the teacher tells the AI what to do differently
  /// (e.g. "don't deduct for spelling in science"). Saved as a standing
  /// instruction that is sent with every future grade.
  Future<void> _teachTheAi() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Teach Mark'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tell your assistant what it should do differently. It will follow this on every future grade.',
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(hintText: "e.g. Don't deduct marks for spelling in science answers"),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Save')),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty || !mounted) return;
    final user = context.read<AuthService>().currentUser;
    if (user == null) return;
    await context.read<AppState>().addMarkingFeedback(teacherId: user.id, feedback: text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Got it — this will be followed from the next grade. Manage it in Settings → Marking Feedback.')),
    );
  }

  // ── Teacher overrides ───────────────────────────────────────────────

  // Must match levelFromPercentage() in the MARKING-PROCESS edge function.
  static (int?, String) _levelFor(double pct) {
    if (pct >= 95) return (4, 'Level 4+ (95–100%)');
    if (pct >= 80) return (4, 'Level 4 (80–94%)');
    if (pct >= 70) return (3, 'Level 3 (70–79%)');
    if (pct >= 60) return (2, 'Level 2 (60–69%)');
    if (pct >= 50) return (1, 'Level 1 (50–59%)');
    return (null, 'Below Level 1 (<50%)');
  }

  double? _num(String s) => double.tryParse(s.replaceAll(RegExp(r'[^0-9.]'), ''));

  /// Applies an updated result, recomputing displays, and saves the new
  /// score onto the stored submission.
  void _applyOverride(AiGradeResult updated) {
    final pct = updated.maxScore <= 0 ? 0.0 : (updated.rawScore / updated.maxScore * 100).clamp(0.0, 100.0);
    final (level, levelDisplay) = _levelFor(pct);
    final finalResult = updated.copyWith(
      percentage: pct,
      percentageDisplay: '${pct.round()}%',
      level: level,
      clearLevel: level == null,
      levelDisplay: levelDisplay,
    );
    setState(() => _result = finalResult);

    final sub = widget.submissionId == null ? null : context.read<SubmissionsService>().getById(widget.submissionId!);
    if (sub != null) {
      context.read<SubmissionsService>().update(
            sub.copyWith(
              score: finalResult.rawScore,
              maxScore: finalResult.maxScore,
              // Keep the saved payload in step so reopening shows the
              // override, not the original AI marks.
              resultJson: finalResult.toJson(),
              updatedAt: DateTime.now(),
            ),
          );
    }
  }

  /// No student matched at marking time — let the teacher link one now.
  Future<void> _linkStudent(Submission sub) async {
    final students = context.read<StudentsService>().students;
    final inClass = sub.classId.isEmpty ? students : students.where((s) => s.classId == sub.classId).toList();
    final pool = inClass.isEmpty ? students : inClass;
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: pool.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No students yet — add them in Classes (or scan an attendance sheet) and link this result afterwards.'),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Text('Whose test is this?', style: Theme.of(ctx).textTheme.titleMedium),
                  ),
                  for (final s in pool)
                    ListTile(
                      leading: CircleAvatar(
                        radius: 16,
                        child: Text(s.name.isEmpty ? '?' : s.name[0].toUpperCase()),
                      ),
                      title: Text(s.name),
                      onTap: () => Navigator.pop(ctx, s.id),
                    ),
                ],
              ),
      ),
    );
    if (picked == null || !mounted) return;
    final student = context.read<StudentsService>().getById(picked);
    await context.read<SubmissionsService>().update(sub.copyWith(
          studentId: picked,
          classId: sub.classId.isEmpty ? (student?.classId ?? '') : sub.classId,
          updatedAt: DateTime.now(),
        ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Linked to ${student?.name ?? 'student'} — it now shows on their profile.')),
    );
  }

  Future<void> _editAnnotation(QuestionAnnotation a) async {
    final result = _result;
    if (result == null) return;
    final idx = result.annotations.indexOf(a);
    if (idx < 0) return;

    final earned = TextEditingController(text: _num(a.earnedMark)?.toString() ?? a.earnedMark);
    final outOf = TextEditingController(text: _num(a.outOfMark)?.toString() ?? '');
    final feedback = TextEditingController(text: a.feedback);
    var correct = a.correct;

    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Edit ${a.questionLabel.isEmpty ? 'mark' : a.questionLabel}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: TextField(controller: earned, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Marks earned'))),
                  const SizedBox(width: 12),
                  Expanded(child: TextField(controller: outOf, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Out of'))),
                ],
              ),
              const SizedBox(height: 8),
              TextField(controller: feedback, decoration: const InputDecoration(labelText: 'Feedback')),
              SwitchListTile(
                value: correct,
                onChanged: (v) => setDialogState(() => correct = v),
                title: const Text('Fully correct'),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (save != true || !mounted) return;

    final newAnn = QuestionAnnotation(
      questionLabel: a.questionLabel,
      earnedMark: _num(earned.text)?.toString().replaceAll(RegExp(r'\.0$'), '') ?? earned.text.trim(),
      outOfMark: _num(outOf.text) == null ? a.outOfMark : '/${_num(outOf.text)!.toString().replaceAll(RegExp(r'\.0$'), '')}',
      correct: correct,
      feedback: feedback.text.trim(),
      pageIndex: a.pageIndex,
      positionTop: a.positionTop,
      positionLeft: a.positionLeft,
    );
    final anns = [...result.annotations];
    anns[idx] = newAnn;

    // Teacher turned a part mark (0.5) into a whole number — that's a
    // marking-style signal worth remembering, with their consent.
    final oldEarned = _num(a.earnedMark);
    final newEarned = _num(earned.text);
    if (oldEarned != null && newEarned != null && oldEarned != newEarned && oldEarned % 1 != 0 && newEarned % 1 == 0) {
      _offerWholeMarkPreference();
    }

    // Recompute the total from the per-question marks when they all parse.
    double earnedSum = 0, outOfSum = 0;
    var parseable = anns.isNotEmpty;
    for (final x in anns) {
      final e = _num(x.earnedMark);
      final o = _num(x.outOfMark);
      if (e == null || o == null || o <= 0) {
        parseable = false;
        break;
      }
      earnedSum += e;
      outOfSum += o;
    }

    _applyOverride(result.copyWith(
      annotations: anns,
      rawScore: parseable ? earnedSum : null,
      maxScore: parseable ? outOfSum : null,
    ));
  }

  /// One-time ask: should Mark stop giving part marks entirely? Saves as a
  /// standing Teach-Mark instruction that rides with every future grade.
  Future<void> _offerWholeMarkPreference() async {
    final auth = context.read<AuthService>().currentUser;
    if (auth == null) return;
    final app = context.read<AppState>();
    final already = app.markingFeedback.any((f) {
      final l = f.toLowerCase();
      return l.contains('part mark') || l.contains('whole mark') || l.contains('fractional');
    });
    if (already) return;

    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('No part marks?'),
        content: const Text(
            'You changed a part mark to a whole number. Should Mark stop giving part marks (0.25 / 0.5 / 0.75) and always score questions in whole marks?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep part marks')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Always whole marks')),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await app.addMarkingFeedback(
      teacherId: auth.id,
      feedback: 'Never award fractional part marks (0.25, 0.5, 0.75) — score every question in whole marks only.',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved — Mark will use whole marks on every future grade. Change it any time in Settings → Give feedback.')),
    );
  }

  Future<void> _editScore() async {
    final result = _result;
    if (result == null) return;
    final raw = TextEditingController(text: result.rawScore.toString().replaceAll(RegExp(r'\.0$'), ''));
    final max = TextEditingController(text: result.maxScore.toString().replaceAll(RegExp(r'\.0$'), ''));

    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Override score'),
        content: Row(
          children: [
            Expanded(child: TextField(controller: raw, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Score'))),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('/')),
            Expanded(child: TextField(controller: max, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Out of'))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (save != true || !mounted) return;

    final newRaw = _num(raw.text);
    final newMax = _num(max.text);
    if (newRaw == null || newMax == null || newMax <= 0) return;
    _applyOverride(result.copyWith(rawScore: newRaw, maxScore: newMax));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final submissions = context.watch<SubmissionsService>();
    final sub = widget.submissionId == null ? null : submissions.getById(widget.submissionId!);
    final student = sub == null ? null : context.read<StudentsService>().getById(sub.studentId);
    final result = _result;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: Icon(Icons.arrow_back_rounded, color: cs.primary),
        ),
        title: const Text('Result'),
        actions: [
          IconButton(
            onPressed: (_exportingToDrive || result == null) ? null : () => _saveToDrive(result, student?.name),
            tooltip: 'Save to Google Drive',
            icon: _exportingToDrive
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.add_to_drive_rounded, color: AiMarkerColors.neutral),
          ),
        ],
      ),
      body: SafeArea(
        child: (sub == null && result == null)
            ? Center(child: Text('Result not found', style: Theme.of(context).textTheme.bodyMedium))
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                children: [
                  // ── The grade, big and unmissable ─────────────────────
                  _HeroGrade(
                    result: result,
                    sub: sub,
                    displayFormat: _displayFormat,
                    useCategoryAverage: _useCategoryAverage,
                    isTest: sub?.gradingMode == GradingMode.testQuiz,
                    ktca: result == null ? const [] : _ktcaOf(result),
                    onToggleAverage: result != null && _ktcaOf(result).length >= 2
                        ? (v) => setState(() => _useCategoryAverage = v)
                        : null,
                    onEditScore: result == null ? null : _editScore,
                  ),
                  const SizedBox(height: 12),

                  // ── Tab switcher ──────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: cs.outline.withValues(alpha: 0.22)),
                    ),
                    child: Row(
                      children: [
                        _TabChip(label: 'Original', selected: _tab == 0, onTap: () => setState(() => _tab = 0)),
                        _TabChip(label: 'Annotated', selected: _tab == 1, onTap: () => setState(() => _tab = 1)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Image panel (swipe across pages) ──────────────────
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 260, maxHeight: 420),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        border: Border.all(color: cs.outline.withValues(alpha: 0.22)),
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                      child: _pages.isNotEmpty
                          ? SizedBox(
                              height: 420,
                              child: PageView.builder(
                                onPageChanged: (i) => setState(() => _page = i),
                                itemCount: _pages.length,
                                itemBuilder: (context, i) => _tab == 0
                                    ? Image.memory(_pages[i], fit: BoxFit.contain)
                                    : _AnnotatedImage(
                                        imageBytes: _pages[i],
                                        annotations: (result?.annotations ?? [])
                                            .where((a) => a.pageIndex == i)
                                            .toList(growable: false),
                                        onTapAnnotation: _editAnnotation,
                                      ),
                              ),
                            )
                          : Center(
                              child: Icon(
                                _tab == 0 ? Icons.image_rounded : Icons.auto_fix_high_rounded,
                                size: 54,
                                color: cs.primary.withValues(alpha: 0.45),
                              ),
                            ),
                    ),
                  ),
                  if (_pages.length > 1) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (int i = 0; i < _pages.length; i++)
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: i == _page ? 18 : 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: i == _page ? cs.primary : cs.outline.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        const SizedBox(width: 8),
                        Text(
                          'Page ${_page + 1} of ${_pages.length}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),

                  if (_tab == 1 && result != null && result.annotations.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Tap any mark on the page to change it',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral),
                      ),
                    ),

                  // ── Triage badge — only when something needs attention ──
                  if ((sub?.triageStatus ?? result?.triageStatus ?? TriageStatus.graded) != TriageStatus.graded) ...[
                    _TriageBadge(
                      triageStatus: sub?.triageStatus ?? (result != null ? result.triageStatus : TriageStatus.graded),
                      confidence: sub?.confidence ?? result?.confidence ?? 85,
                      triageFlags: sub?.triageFlags ?? result?.flags ?? [],
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ── Student (one tidy card, not a pile of chips) ──────
                  Card(
                    child: ListTile(
                      leading: Icon(
                        student == null ? Icons.person_add_alt_1_rounded : Icons.person_rounded,
                        color: cs.primary,
                      ),
                      title: Text(student?.name ?? 'No student linked', style: Theme.of(context).textTheme.titleSmall),
                      subtitle: Text(
                        [
                          if (result != null) result.detectedSubject,
                          if (sub?.overrideUsed == true) 'override used',
                          if (student == null) 'tap to link this test to a student',
                        ].join(' · '),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral),
                      ),
                      trailing: (sub != null && student == null)
                          ? FilledButton.tonal(onPressed: () => _linkStudent(sub), child: const Text('Link'))
                          : null,
                      onTap: (sub != null && student == null) ? () => _linkStudent(sub) : null,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── Marks — scoreboard only, for every kind of work ────
                  if (result != null) ...[
                    // Per-question scoreboard (tap a row to change the mark).
                    if (result.annotations.isNotEmpty) ...[
                      Card(
                        child: Column(
                          children: [
                            for (final a in result.annotations)
                              ListTile(
                                dense: true,
                                onTap: () => _editAnnotation(a),
                                leading: Icon(
                                  a.correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
                                  color: a.correct ? AiMarkerColors.secondary : AiMarkerColors.error,
                                  size: 20,
                                ),
                                title: Text(a.questionLabel.isEmpty ? 'Question' : a.questionLabel, style: Theme.of(context).textTheme.bodyMedium),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${a.earnedMark}${a.outOfMark}',
                                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                                    ),
                                    const SizedBox(width: 6),
                                    Icon(Icons.edit_rounded, size: 15, color: AiMarkerColors.neutral),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // Criteria appear ONLY when they carry marks: KTCA
                    // categories or a printed rubric. Never commentary.
                    ...(() {
                      final crits = _ktcaOf(result);
                      if (crits.isEmpty) return const <Widget>[];
                      return <Widget>[
                        Text('Categories', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 10),
                        ...crits.map((c) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _CriterionCard(criterion: c, displayFormat: _displayFormat),
                            )),
                      ];
                    })(),
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      onPressed: _teachTheAi,
                      icon: const Icon(Icons.school_rounded, size: 18),
                      label: const Text('Teach Mark — correct how it marks'),
                    ),
                  ],

                  if (sub != null && sub.triageFlags.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _FeedbackCard(title: 'Triage flags', color: Colors.orange, body: sub.triageFlags.join('\n• '), prefixBullet: true),
                  ],

                  const SizedBox(height: 18),

                  // ── Actions ───────────────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: (result == null && sub == null) ? null : () => _share(result, sub, student?.name),
                          icon: Icon(Icons.ios_share_rounded, color: cs.primary),
                          label: Text('Share', style: TextStyle(color: cs.primary)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => context.go('/dashboard'),
                          style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: Colors.white),
                          child: const Text('Save to Dashboard'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  /// Shares the marked result as plain text via the system share sheet
  /// (message, email, Classroom, wherever the teacher sends it).
  Future<void> _share(AiGradeResult? result, Submission? sub, String? studentName) async {
    final b = StringBuffer();
    if (result != null) {
      final name = (studentName?.trim().isNotEmpty == true) ? studentName!.trim() : (result.studentNameOnPaper ?? 'Student');
      b.writeln('$name — ${result.detectedSubject}');
      b.writeln(result.gradingFormat == 'levels' && result.levelDisplay != null
          ? '${result.levelDisplay} · ${result.percentageDisplay}'
          : '${result.percentageDisplay} (${result.rawScore.toStringAsFixed(result.rawScore % 1 == 0 ? 0 : 2)}/${result.maxScore.toStringAsFixed(result.maxScore % 1 == 0 ? 0 : 2)})');
      if (result.annotations.isNotEmpty) {
        b.writeln('\nQuestion marks:');
        for (final a in result.annotations) {
          b.writeln('${a.questionLabel.isEmpty ? 'Q' : a.questionLabel}: ${a.earnedMark}${a.outOfMark}');
        }
      }
      final ktca = _ktcaOf(result);
      if (ktca.isNotEmpty) {
        b.writeln('\nCategories:');
        for (final c in ktca) {
          b.writeln('${c.name}: ${c.score.toStringAsFixed(c.score % 1 == 0 ? 0 : 2)}/${c.maxScore.toStringAsFixed(c.maxScore % 1 == 0 ? 0 : 2)}');
        }
      }
      if (sub?.gradingMode != GradingMode.testQuiz && result.summary.isNotEmpty) {
        b.writeln('\n${result.summary}');
      }
    } else if (sub != null) {
      b.writeln('Marked result: ${sub.score.toStringAsFixed(sub.score % 1 == 0 ? 0 : 2)}/${sub.maxScore.toStringAsFixed(sub.maxScore % 1 == 0 ? 0 : 2)}');
      if (sub.feedback.trim().isNotEmpty) b.writeln('\n${sub.feedback.trim()}');
    }
    b.writeln('\nMarked with Markless');
    await Share.share(b.toString().trim(), subject: 'Marked result');
  }

}

// ── Hero grade: the final mark, big and unmissable ─────────────────────────

class _HeroGrade extends StatelessWidget {
  final AiGradeResult? result;
  final Submission? sub;
  final String displayFormat;
  final bool useCategoryAverage;
  final bool isTest;
  final List<CriterionResult> ktca;
  final ValueChanged<bool>? onToggleAverage;
  final VoidCallback? onEditScore;

  const _HeroGrade({
    required this.result,
    required this.sub,
    required this.displayFormat,
    required this.useCategoryAverage,
    required this.isTest,
    required this.ktca,
    required this.onToggleAverage,
    required this.onEditScore,
  });

  static String _levelFor(double pct) {
    if (pct >= 95) return 'Level 4+';
    if (pct >= 80) return 'Level 4';
    if (pct >= 70) return 'Level 3';
    if (pct >= 60) return 'Level 2';
    if (pct >= 50) return 'Level 1';
    return 'R';
  }

  static String _num(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 1);

  @override
  Widget build(BuildContext context) {
    double raw, max, pct;
    if (result != null) {
      raw = result!.rawScore;
      max = result!.maxScore;
      final totalPct = max > 0 ? raw / max * 100 : result!.percentage;
      final avgPct = ktca.length >= 2
          ? ktca.map((c) => c.score / c.maxScore * 100).reduce((a, b) => a + b) / ktca.length
          : result!.percentage;
      pct = (onToggleAverage != null && !useCategoryAverage) ? totalPct : (ktca.length >= 2 ? avgPct : result!.percentage);
    } else if (sub != null) {
      raw = sub!.score;
      max = sub!.maxScore;
      pct = max > 0 ? raw / max * 100 : 0;
    } else {
      return const SizedBox.shrink();
    }

    // Marks lead ("30 / 40"), percent rides along; level-scale work leads
    // with the level instead.
    final big = displayFormat == 'levels' ? _levelFor(pct) : '${_num(raw)} / ${_num(max)}';
    final sub2 = displayFormat == 'levels'
        ? '${_num(raw)} / ${_num(max)} · ${pct.round()}%'
        : '${pct.round()}%';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        gradient: const LinearGradient(
          colors: [AiMarkerColors.primary, AiMarkerColors.tertiary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          if (onEditScore != null)
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                onPressed: onEditScore,
                tooltip: 'Override the total',
                icon: Icon(Icons.edit_rounded, color: Colors.white.withValues(alpha: 0.85), size: 20),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
            child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(big, style: Theme.of(context).textTheme.displaySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(sub2, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.white.withValues(alpha: 0.9))),
          if (onToggleAverage != null) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _HeroChip(label: 'Category average', selected: useCategoryAverage, onTap: () => onToggleAverage!(true)),
                const SizedBox(width: 8),
                _HeroChip(label: 'Total marks', selected: !useCategoryAverage, onTap: () => onToggleAverage!(false)),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              useCategoryAverage
                  ? 'K/T/C/A categories weighted equally (Ontario style)'
                  : 'Marks earned out of total marks',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
            ),
          ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _HeroChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: selected ? 0.28 : 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: selected ? 0.7 : 0.25)),
        ),
        child: Text(
          label,
          style: TextStyle(color: Colors.white, fontWeight: selected ? FontWeight.w800 : FontWeight.w500, fontSize: 12),
        ),
      ),
    );
  }
}

// ── Annotated image with drawn marks ────────────────────────────────────────

class _AnnotatedImage extends StatelessWidget {
  final Uint8List imageBytes;
  final List<QuestionAnnotation> annotations;
  final void Function(QuestionAnnotation)? onTapAnnotation;

  const _AnnotatedImage({required this.imageBytes, required this.annotations, this.onTapAnnotation});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      return Stack(
        fit: StackFit.passthrough,
        children: [
          Image.memory(imageBytes, fit: BoxFit.contain, width: constraints.maxWidth),
          // Highlight boxes on the mistakes themselves — the AI points its
          // position at the erroneous line, this draws the teacher's eye.
          ...annotations.where((a) => !a.correct).map((a) => Positioned(
                left: (a.positionLeft * constraints.maxWidth - 46).clamp(0.0, constraints.maxWidth - 92),
                top: (a.positionTop * constraints.maxHeight - 17),
                child: IgnorePointer(
                  child: Container(
                    width: 92,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AiMarkerColors.error.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AiMarkerColors.error.withValues(alpha: 0.75), width: 2),
                    ),
                  ),
                ),
              )),
          // Short "what went wrong" note in the right margin beside each
          // mistake — kept off the student's writing so both stay readable.
          ...annotations.where((a) => !a.correct && a.feedback.trim().isNotEmpty).map((a) => Positioned(
                right: 4,
                top: (a.positionTop * constraints.maxHeight + 12).clamp(0.0, constraints.maxHeight - 40),
                child: IgnorePointer(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 130),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AiMarkerColors.error.withValues(alpha: 0.6)),
                    ),
                    child: Text(
                      a.feedback,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, height: 1.2, color: Color(0xFF8B1A1A), fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              )),
          // Marks live in the right margin at the answer's row — never on
          // top of the writing.
          ...annotations.map((a) => Positioned(
                right: 4,
                top: (a.positionTop * constraints.maxHeight - 12).clamp(0.0, constraints.maxHeight - 24),
                child: GestureDetector(
                  onTap: onTapAnnotation == null ? null : () => onTapAnnotation!(a),
                  child: _AnnotationMark(annotation: a),
                ),
              )),
        ],
      );
    });
  }
}

class _AnnotationMark extends StatelessWidget {
  final QuestionAnnotation annotation;
  const _AnnotationMark({required this.annotation});

  @override
  Widget build(BuildContext context) {
    final color = annotation.correct ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 3)],
      ),
      child: Text(
        '${annotation.questionLabel.isEmpty ? '' : '${annotation.questionLabel} '}${annotation.earnedMark}${annotation.outOfMark}',
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12),
      ),
    );
  }
}

// ── Criterion card ───────────────────────────────────────────────────────────

class _CriterionCard extends StatelessWidget {
  final CriterionResult criterion;
  final String displayFormat;

  const _CriterionCard({required this.criterion, required this.displayFormat});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final scoreText = displayFormat == 'levels' && criterion.level != null
        ? 'Level ${criterion.level}'
        : '${criterion.score.round()}/${criterion.maxScore.round()}';
    final color = _levelColor(criterion.level);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(scoreText, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(criterion.name, style: Theme.of(context).textTheme.titleSmall),
                if (criterion.feedback.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(criterion.feedback, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _levelColor(int? level) {
    switch (level) {
      case 4: return const Color(0xFF2E7D32);
      case 3: return const Color(0xFF1565C0);
      case 2: return Colors.orange;
      case 1: return const Color(0xFFC62828);
      default: return AiMarkerColors.neutral;
    }
  }
}

// ── Shared widgets ───────────────────────────────────────────────────────────

class _TabChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? cs.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? cs.outline.withValues(alpha: 0.20) : Colors.transparent),
          ),
          child: Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: selected ? null : AiMarkerColors.neutral)),
        ),
      ),
    );
  }
}

class _TriageBadge extends StatelessWidget {
  final TriageStatus triageStatus;
  final int confidence;
  final List<String> triageFlags;

  const _TriageBadge({required this.triageStatus, required this.confidence, required this.triageFlags});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Color bg, fg;
    String title;
    String? subtitle;
    IconData icon;

    switch (triageStatus) {
      case TriageStatus.graded:
        bg = AiMarkerColors.secondary.withValues(alpha: 0.12);
        fg = AiMarkerColors.secondary;
        title = '✓ Graded';
        subtitle = 'Marking confidence $confidence%';
        icon = Icons.check_circle_rounded;
        break;
      case TriageStatus.needsReview:
        bg = Colors.orange.withValues(alpha: 0.14);
        fg = Colors.orange;
        title = '⚠ Needs Review';
        subtitle = triageFlags.isEmpty ? 'Confidence $confidence% — please verify' : triageFlags.first;
        icon = Icons.warning_rounded;
        break;
      case TriageStatus.unableToGrade:
        bg = AiMarkerColors.error.withValues(alpha: 0.10);
        fg = AiMarkerColors.error;
        title = '✗ Unable to Grade';
        subtitle = triageFlags.isEmpty ? 'Image quality too low — retake photo' : triageFlags.first;
        icon = Icons.cancel_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: fg.withValues(alpha: 0.22))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: fg, fontWeight: FontWeight.w900)),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.85))),
                ],
              ],
            ),
          ),
          if (triageStatus == TriageStatus.unableToGrade)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: fg, splashFactory: NoSplash.splashFactory),
              onPressed: () {},
              child: const Text('Retake Photo'),
            ),
        ],
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  final String title;
  final Color color;
  final String body;
  final bool prefixBullet;

  const _FeedbackCard({required this.title, required this.color, required this.body, this.prefixBullet = false});

  @override
  Widget build(BuildContext context) {
    final text = prefixBullet ? '• $body' : body;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
