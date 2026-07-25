import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:marking_prokect_v2/app/app_state.dart';
import 'package:marking_prokect_v2/models/submission.dart';
import 'package:marking_prokect_v2/services/ai_grading_service.dart';
import 'package:marking_prokect_v2/services/auth_service.dart';
import 'package:marking_prokect_v2/services/students_service.dart';
import 'package:marking_prokect_v2/services/submissions_service.dart';
import 'package:marking_prokect_v2/theme.dart';
import 'package:provider/provider.dart';

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

  List<Uint8List> get _pages {
    final p = widget.pageImages;
    if (p != null && p.isNotEmpty) return p;
    final single = widget.imageBytes;
    return single == null ? const [] : [single];
  }

  @override
  void initState() {
    super.initState();
    _result = widget.gradeResult;
    _displayFormat = _result?.gradingFormat ?? 'percentage';
  }

  void _toggleFormat() {
    setState(() {
      _displayFormat = _displayFormat == 'levels' ? 'percentage' : 'levels';
      if (_result != null) {
        _result = _result!.withFormat(_displayFormat);
      }
    });
  }

  /// "Teach the AI" — the teacher tells the AI what to do differently
  /// (e.g. "don't deduct for spelling in science"). Saved as a standing
  /// instruction that is sent with every future grade.
  Future<void> _teachTheAi() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Teach MarkMate'),
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

  static (int?, String) _levelFor(double pct) {
    if (pct >= 80) return (4, 'Level 4 (80–100%)');
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
            sub.copyWith(score: finalResult.rawScore, maxScore: finalResult.maxScore, updatedAt: DateTime.now()),
          );
    }
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
            onPressed: () {},
            icon: Icon(Icons.ios_share_rounded, color: AiMarkerColors.neutral),
          ),
        ],
      ),
      body: SafeArea(
        child: (sub == null && result == null)
            ? Center(child: Text('Result not found', style: Theme.of(context).textTheme.bodyMedium))
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                children: [
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

                  // ── Score row ─────────────────────────────────────────
                  _ScoreRow(
                    result: result,
                    sub: sub,
                    displayFormat: _displayFormat,
                    onToggleFormat: _toggleFormat,
                    onEditScore: result == null ? null : _editScore,
                  ),
                  const SizedBox(height: 6),

                  // ── Provider / detected info ──────────────────────────
                  if (result != null) ...[
                    Row(
                      children: [
                        Icon(Icons.auto_awesome_rounded, size: 14, color: AiMarkerColors.neutral),
                        const SizedBox(width: 6),
                        Text(
                          'Graded by ${_providerLabel(result.provider)} · ${result.detectedSubject} · ${result.detectedGrade != null ? 'Grade ${result.detectedGrade}' : 'Grade unknown'}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],

                  // ── Triage badge ──────────────────────────────────────
                  _TriageBadge(
                    triageStatus: sub?.triageStatus ?? (result != null ? result.triageStatus : TriageStatus.graded),
                    confidence: sub?.confidence ?? result?.confidence ?? 85,
                    triageFlags: sub?.triageFlags ?? result?.flags ?? [],
                  ),
                  const SizedBox(height: 12),

                  // ── Tags ──────────────────────────────────────────────
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    if (result != null)
                      _Tag(text: result.detectedSubject, color: cs.primary.withValues(alpha: 0.10), textColor: cs.primary),
                    if (student != null)
                      _Tag(text: 'Student: ${student.name}', color: cs.surfaceContainerHighest, textColor: AiMarkerColors.neutral),
                    if (sub?.overrideUsed == true)
                      _Tag(text: 'One-time override', color: Colors.orange.withValues(alpha: 0.14), textColor: Colors.orange),
                  ]),
                  const SizedBox(height: 18),

                  // ── AI Feedback ───────────────────────────────────────
                  Text('Feedback', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),

                  if (result != null) ...[
                    // Summary
                    if (result.summary.isNotEmpty)
                      _FeedbackCard(title: 'Summary', color: cs.primary, body: result.summary),
                    const SizedBox(height: 10),

                    // Strengths
                    if (result.strengths.isNotEmpty)
                      _FeedbackCard(
                        title: 'What was done well',
                        color: AiMarkerColors.secondary,
                        body: result.strengths.map((s) => '• $s').join('\n'),
                      ),
                    const SizedBox(height: 10),

                    // Improvements
                    if (result.improvements.isNotEmpty)
                      _FeedbackCard(
                        title: 'What to improve',
                        color: AiMarkerColors.error,
                        body: result.improvements.map((s) => '• $s').join('\n'),
                      ),
                    const SizedBox(height: 14),

                    // Criteria breakdown
                    if (result.criteriaBreakdown.isNotEmpty) ...[
                      Text('Criteria Breakdown', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 10),
                      ...result.criteriaBreakdown.map((c) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _CriterionCard(criterion: c, displayFormat: _displayFormat),
                          )),
                    ],
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      onPressed: _teachTheAi,
                      icon: const Icon(Icons.school_rounded, size: 18),
                      label: const Text('Teach MarkMate — correct how it marks'),
                    ),
                  ] else ...[
                    // Fallback to stored feedback when no live result
                    _FeedbackCard(title: 'What was done well', color: AiMarkerColors.secondary, body: 'Clear method + consistent units where shown.'),
                    const SizedBox(height: 10),
                    _FeedbackCard(title: 'What to improve', color: AiMarkerColors.error, body: 'Show working more explicitly on multi-step questions.'),
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
                          onPressed: () {},
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

  String _providerLabel(String provider) {
    switch (provider) {
      case 'claude': return 'Claude';
      case 'gemini': return 'Gemini';
      case 'openai': return 'GPT-4o';
      default: return provider;
    }
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
          ...annotations.map((a) => Positioned(
                left: a.positionLeft * constraints.maxWidth - 18,
                top: a.positionTop * constraints.maxHeight - 12,
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
        annotation.earnedMark,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13),
      ),
    );
  }
}

// ── Score row with format toggle ─────────────────────────────────────────────

class _ScoreRow extends StatelessWidget {
  final AiGradeResult? result;
  final Submission? sub;
  final String displayFormat;
  final VoidCallback onToggleFormat;
  final VoidCallback? onEditScore;

  const _ScoreRow({required this.result, required this.sub, required this.displayFormat, required this.onToggleFormat, this.onEditScore});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Primary display value
    final String primary;
    final String secondary;

    if (result != null) {
      if (displayFormat == 'levels' && result!.levelDisplay != null) {
        primary = result!.levelDisplay!;
        secondary = result!.percentageDisplay;
      } else {
        primary = result!.percentageDisplay;
        secondary = result!.levelDisplay ?? '';
      }
    } else if (sub != null) {
      final pct = sub!.maxScore == 0 ? 0 : ((sub!.score / sub!.maxScore) * 100).round();
      primary = '$pct%';
      secondary = '';
    } else {
      primary = '—';
      secondary = '';
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(primary, style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w900)),
                  if (onEditScore != null)
                    IconButton(
                      onPressed: onEditScore,
                      icon: Icon(Icons.edit_rounded, size: 20, color: AiMarkerColors.neutral),
                      tooltip: 'Override score',
                    ),
                ],
              ),
              if (result != null)
                Text('${_trim(result!.rawScore)}/${_trim(result!.maxScore)}${secondary.isNotEmpty ? ' · $secondary' : ''}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral))
              else if (secondary.isNotEmpty)
                Text(secondary, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
            ],
          ),
        ),
        // Format toggle button — only show when we have both formats available
        if (result != null && result!.level != null)
          GestureDetector(
            onTap: onToggleFormat,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: cs.outline.withValues(alpha: 0.30)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.swap_horiz_rounded, size: 16, color: cs.primary),
                  const SizedBox(width: 6),
                  Text(
                    displayFormat == 'levels' ? 'Show %' : 'Show Level',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(color: cs.primary, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  static String _trim(double v) => v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1);
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

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  final Color textColor;
  const _Tag({required this.text, required this.color, required this.textColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999), border: Border.all(color: textColor.withValues(alpha: 0.18))),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: textColor, fontWeight: FontWeight.w800)),
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
