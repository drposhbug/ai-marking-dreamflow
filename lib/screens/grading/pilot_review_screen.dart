import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:marking_prokect_v2/app/app_routes.dart';
import 'package:marking_prokect_v2/app/app_state.dart';
import 'package:marking_prokect_v2/services/ai_grading_service.dart';
import 'package:marking_prokect_v2/services/anonymizer.dart';
import 'package:marking_prokect_v2/services/auth_service.dart';
import 'package:marking_prokect_v2/services/batch_marking.dart';
import 'package:marking_prokect_v2/services/grading_queue_service.dart';
import 'package:marking_prokect_v2/services/students_service.dart';
import 'package:marking_prokect_v2/services/submissions_service.dart';
import 'package:marking_prokect_v2/theme.dart';
import 'package:provider/provider.dart';

/// The check-the-first-one screen.
///
/// One paper of a class set has been marked. Before the same settings are
/// applied to the other twenty-nine, the teacher sees what it actually did
/// and either approves it or says — in their own words — what it got wrong.
/// A correction re-marks this paper so they can see the fix land, and then
/// travels with every remaining paper when they release the set.
///
/// This is the cheapest possible place to catch a wrong answer key or the
/// wrong grading mode: one paper and one credit, instead of thirty of each
/// plus an evening of undoing them.
class PilotReviewScreen extends StatefulWidget {
  final String jobId;
  const PilotReviewScreen({super.key, required this.jobId});

  @override
  State<PilotReviewScreen> createState() => _PilotReviewScreenState();
}

class _PilotReviewScreenState extends State<PilotReviewScreen> {
  final _note = TextEditingController();

  /// Corrections given so far, oldest first — each re-mark builds on the last.
  final List<String> _corrections = [];
  bool _remarking = false;

  @override
  void initState() {
    super.initState();
    // The plan and allowance, so each button can show what it costs before
    // it is pressed rather than after the credits are gone.
    Future.microtask(() async {
      final auth = context.read<AuthService>().currentUser;
      if (auth == null) return;
      try {
        final u = await AiGradingService().getUsage(teacherId: auth.id);
        if (mounted) setState(() => _usage = u);
      } catch (e) {
        debugPrint('PilotReview usage load failed: $e');
      }
    });
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  GradingJob? get _job {
    final jobs = context.read<GradingQueueService>().jobs;
    for (final j in jobs) {
      if (j.id == widget.jobId) return j;
    }
    return null;
  }

  Future<void> _remark() async {
    final text = _note.text.trim();
    final job = _job;
    if (text.isEmpty || job == null) return;
    setState(() {
      _remarking = true;
      _corrections.add(text);
    });
    _note.clear();
    try {
      await context.read<GradingQueueService>().remarkPilot(
            job: job,
            extraFeedback: [text],
            students: context.read<StudentsService>(),
            submissions: context.read<SubmissionsService>(),
          );
    } finally {
      if (mounted) setState(() => _remarking = false);
    }
  }

  /// Teaching the AI once is worth more than teaching it thirty times — a
  /// correction saved here applies to every future scan, not just this set.
  Future<void> _saveAsStanding() async {
    final auth = context.read<AuthService>().currentUser;
    if (auth == null || _corrections.isEmpty) return;
    final app = context.read<AppState>();
    await app.setMarkingFeedbackAll(teacherId: auth.id, feedback: [...app.markingFeedback, ..._corrections]);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved — Mark will follow this on every test from now on.')),
    );
  }

  UsageSummary? _usage;

  /// True when this plan may mark a whole set on the spot. The PILOT paper
  /// always marks live regardless — approving the first result before the
  /// rest go out is a safety check, not a premium feature.
  bool get _canMarkNow => _usage?.instantMarking ?? true;

  /// " · about 4% of this month" — the credit price of a choice, shown
  /// before it's made rather than discovered at the end of the month.
  String _costHint({required bool overnight, required int papers}) {
    final u = _usage;
    if (u == null || papers <= 0) return '';
    final pct = u.pctFor(papers, overnight: overnight);
    if (pct <= 0) return '';
    return ' · ~$pct% of credits';
  }
  bool _sending = false;

  /// Half price, and the teacher isn't waiting for it. They've just seen the
  /// pilot, so the set isn't going out unchecked.
  Future<void> _overnight() async {
    final queue = context.read<GradingQueueService>();
    final n = queue.heldJobs.length;
    if (n == 0) return;
    setState(() => _sending = true);
    try {
      final sent = await sendHeldOvernight(
        context: context,
        label: _job?.req.subject ?? 'Class set',
        extraFeedback: _corrections,
      );
      if (!mounted) return;
      if (sent == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Couldn\'t queue those for overnight marking — they\'re still held in the tray.')),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          // "Open it in the morning", not "they'll be waiting for you": the
          // marking really does run with the app closed, but nothing pushes
          // the results back — they are filed the next time she opens up.
          content: Text('$sent papers are marking overnight — you can close the app. Open Markless in the morning and the marks are waiting.'),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }


  void _approve() {
    context.read<GradingQueueService>().releaseHeld(
          students: context.read<StudentsService>(),
          submissions: context.read<SubmissionsService>(),
          extraFeedback: _corrections,
        );
    Navigator.of(context).pop(true);
  }

  void _hold() => Navigator.of(context).pop(false);

  @override
  Widget build(BuildContext context) {
    final queue = context.watch<GradingQueueService>();
    final job = _job;
    final res = job?.result;
    final remaining = queue.heldJobs.length;
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      // Leaving without deciding must not silently mark the class — the
      // papers stay held and the tray keeps offering to release them.
      canPop: true,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Check the first one'),
          leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: _hold),
        ),
        body: job == null
            ? const Center(child: Text('That paper is no longer in the queue.'))
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  Text(
                    'This is the first paper of $remaining more. If it marked the way you would, send the rest.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45),
                  ),
                  const SizedBox(height: 14),
                  if (_remarking || job.status == GradingJobStatus.marking)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 36),
                      child: Center(
                        child: Column(
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 14),
                            Text('Marking it again with your note…'),
                          ],
                        ),
                      ),
                    )
                  else if (job.status == GradingJobStatus.error)
                    Card(
                      color: AiMarkerColors.error.withValues(alpha: 0.10),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          'This paper didn\'t mark: ${job.error ?? 'unknown error'}\n\n'
                          'Don\'t release the rest until it does — they\'d fail the same way.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.45),
                        ),
                      ),
                    )
                  else if (res != null) ...[
                    _ScoreCard(job: job),
                    const SizedBox(height: 12),
                    // The pilot is where the teacher decides whether the
                    // other twenty-nine go the same way — so if this one's
                    // name went up uncovered, say it here, not afterwards.
                    if (!job.nameHiding.hidesTheName) ...[
                      _NameHidingCard(hiding: job.nameHiding, remaining: remaining),
                      const SizedBox(height: 12),
                    ],
                    if (res.flags.isNotEmpty) ...[
                      Card(
                        color: AiMarkerColors.warning.withValues(alpha: 0.10),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Flagged for you', style: Theme.of(context).textTheme.titleSmall),
                              const SizedBox(height: 6),
                              for (final f in res.flags.take(4))
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 3),
                                  child: Text('• $f',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.35)),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (res.criteriaBreakdown.isNotEmpty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('How it broke down', style: Theme.of(context).textTheme.titleSmall),
                              const SizedBox(height: 8),
                              for (final c in res.criteriaBreakdown.take(8))
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(c.name, style: Theme.of(context).textTheme.bodyMedium),
                                            if (c.feedback.trim().isNotEmpty)
                                              Text(c.feedback,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(color: AiMarkerColors.neutral, height: 1.35)),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text('${_n(c.score)}/${_n(c.maxScore)}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(fontWeight: FontWeight.w800, color: cs.primary)),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    if (job.submissionId != null)
                      OutlinedButton.icon(
                        onPressed: () => context.push('${AppRoutes.result}?submissionId=${job.submissionId}'),
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: const Text('Open the full marked paper'),
                      ),
                  ],
                  const SizedBox(height: 18),
                  Text('NOT QUITE RIGHT?',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(letterSpacing: 1.2, color: AiMarkerColors.neutral)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _note,
                    minLines: 2,
                    maxLines: 4,
                    enabled: !_remarking,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'e.g. "Don\'t take marks off for spelling in science"\n'
                          'or "Q3 needed units — that should be half a mark, not one"',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _remarking ? null : _remark,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Mark it again'),
                      ),
                      const SizedBox(width: 8),
                      if (_corrections.isNotEmpty)
                        Expanded(
                          child: Text('${_corrections.length} correction${_corrections.length == 1 ? '' : 's'} will apply to the whole set',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                        ),
                    ],
                  ),
                  if (_corrections.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    TextButton.icon(
                      onPressed: _saveAsStanding,
                      icon: const Icon(Icons.push_pin_rounded, size: 16),
                      label: const Text('Also remember this for every future test'),
                    ),
                  ],
                ],
              ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Overnight leads: it costs the teacher about a fifth of the
                // credits and costs us about a fifth of the money, so the
                // cheap route is the one the button points at.
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: (_remarking || _sending || job?.status != GradingJobStatus.done) ? null : _overnight,
                    icon: _sending
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.bedtime_rounded, size: 18),
                    label: Text('Mark $remaining overnight${_costHint(overnight: true, papers: remaining)}'),
                  ),
                ),
                const SizedBox(height: 8),
                if (_canMarkNow)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: (_remarking || _sending || job?.status != GradingJobStatus.done) ? null : _approve,
                      icon: const Icon(Icons.bolt_rounded, size: 18),
                      label: Text('Mark $remaining now${_costHint(overnight: false, papers: remaining)}'),
                    ),
                  )
                else
                  // Instant marking is what the paid tiers buy. Say so
                  // plainly rather than showing a button that fails.
                  InkWell(
                    onTap: () => context.push(AppRoutes.plans),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.bolt_rounded, size: 16, color: AiMarkerColors.neutral),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Marking a whole set on the spot is part of Pro — it uses about five times the credits.',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.35),
                            ),
                          ),
                          Text('See plans',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.w700,
                                  )),
                        ],
                      ),
                    ),
                  ),
                TextButton(onPressed: _sending ? null : _hold, child: const Text('Not yet — hold them')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _n(double v) => v.truncateToDouble() == v ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

/// Says what happened to the student's name on the paper that was just
/// sent, in the same amber the screen already uses for "check this".
class _NameHidingCard extends StatelessWidget {
  final NameHiding hiding;
  final int remaining;

  const _NameHidingCard({required this.hiding, required this.remaining});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AiMarkerColors.warning.withValues(alpha: 0.10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.visibility_off_outlined, size: 18, color: AiMarkerColors.warning),
                const SizedBox(width: 8),
                Expanded(child: Text(hiding.headline, style: Theme.of(context).textTheme.titleSmall)),
              ],
            ),
            const SizedBox(height: 6),
            Text(hiding.detail, style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.35)),
            if (remaining > 0) ...[
              const SizedBox(height: 6),
              Text(
                'The other $remaining paper${remaining == 1 ? '' : 's'} will go the same way if you release them.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.35),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  final GradingJob job;
  const _ScoreCard({required this.job});

  @override
  Widget build(BuildContext context) {
    final res = job.result!;
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(job.label, style: Theme.of(context).textTheme.titleMedium)),
                Text(res.primaryDisplay,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: cs.primary)),
              ],
            ),
            const SizedBox(height: 2),
            Text('${_PilotReviewScreenState._n(res.rawScore)} out of ${_PilotReviewScreenState._n(res.maxScore)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
            if (res.summary.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(res.summary, style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.45)),
            ],
          ],
        ),
      ),
    );
  }
}
