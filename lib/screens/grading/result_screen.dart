import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:marking_prokect_v2/models/submission.dart';
import 'package:marking_prokect_v2/services/students_service.dart';
import 'package:marking_prokect_v2/services/submissions_service.dart';
import 'package:marking_prokect_v2/theme.dart';
import 'package:provider/provider.dart';

class ResultScreen extends StatefulWidget {
  final String? submissionId;
  const ResultScreen({super.key, required this.submissionId});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> with SingleTickerProviderStateMixin {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final submissions = context.watch<SubmissionsService>();
    final sub = widget.submissionId == null ? null : submissions.getById(widget.submissionId!);
    final student = sub == null ? null : context.read<StudentsService>().getById(sub.studentId);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: () => context.pop(), icon: Icon(Icons.arrow_back_rounded, color: cs.primary)),
        title: const Text('Result'),
        actions: [IconButton(onPressed: () {}, icon: Icon(Icons.ios_share_rounded, color: AiMarkerColors.neutral))],
      ),
      body: SafeArea(
        child: sub == null
            ? Center(child: Text('Result not found', style: Theme.of(context).textTheme.bodyMedium))
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(999), border: Border.all(color: cs.outline.withValues(alpha: 0.22))),
                    child: Row(
                      children: [
                        _TabChip(label: 'Original', selected: _tab == 0, onTap: () => setState(() => _tab = 0)),
                        _TabChip(label: 'Annotated', selected: _tab == 1, onTap: () => setState(() => _tab = 1)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height: 260,
                    decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: cs.outline.withValues(alpha: 0.22))),
                    child: Stack(
                      children: [
                        Center(child: Icon(_tab == 0 ? Icons.image_rounded : Icons.auto_fix_high_rounded, size: 54, color: cs.primary.withValues(alpha: 0.45))),
                        if (_tab == 1) ...[
                          Positioned(left: 26, top: 36, child: _HighlightBox(color: AiMarkerColors.secondary.withValues(alpha: 0.18), border: AiMarkerColors.secondary)),
                          Positioned(right: 44, top: 90, child: _HighlightBox(color: AiMarkerColors.error.withValues(alpha: 0.16), border: AiMarkerColors.error)),
                          Positioned(
                            right: 14,
                            bottom: 14,
                            child: Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(shape: BoxShape.circle, color: _scoreColor(sub).withValues(alpha: 0.15), border: Border.all(color: _scoreColor(sub), width: 2)),
                              child: Center(child: Text('${sub.score.round()}', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: _scoreColor(sub), fontWeight: FontWeight.w900))),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${sub.score.round()}', style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w900)),
                      const SizedBox(width: 6),
                      Text('/${sub.maxScore.round()}', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AiMarkerColors.neutral)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(999)),
                        child: Text('${_pct(sub)}% · ${_band(sub)}', style: Theme.of(context).textTheme.labelMedium),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.star_rounded, color: Colors.amber.shade700, size: 18),
                      const SizedBox(width: 6),
                      Text('Max score auto-detected: ${sub.maxScore.round()}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _TriageBadge(submission: sub),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    _Tag(text: 'Scheme: ${sub.presetId.substring(0, 4)}', color: cs.primary.withValues(alpha: 0.10), textColor: cs.primary),
                    if (sub.overrideUsed) _Tag(text: 'One-time override', color: Colors.orange.withValues(alpha: 0.14), textColor: Colors.orange),
                    _Tag(text: 'Student: ${student?.name ?? ''}', color: cs.surfaceContainerHighest, textColor: AiMarkerColors.neutral),
                  ]),
                  const SizedBox(height: 14),
                  Text('AI Feedback', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  _FeedbackCard(title: 'What was done well', color: AiMarkerColors.secondary, body: 'Clear method + consistent units where shown. Good structure and neat presentation.'),
                  const SizedBox(height: 10),
                  _FeedbackCard(title: 'What was wrong', color: AiMarkerColors.error, body: 'Missing working on one multi-step question. Some labels/units need to be explicitly written.'),
                  if (sub.triageFlags.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _FeedbackCard(title: 'Triage flags', color: Colors.orange, body: sub.triageFlags.join('\n• '), prefixBullet: true),
                  ],
                  const SizedBox(height: 14),
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

  int _pct(Submission s) => s.maxScore == 0 ? 0 : ((s.score / s.maxScore) * 100).round();
  String _band(Submission s) {
    final p = _pct(s);
    if (p >= 85) return 'A';
    if (p >= 70) return 'B';
    if (p >= 55) return 'C';
    if (p >= 40) return 'D';
    return 'E';
  }

  Color _scoreColor(Submission s) {
    final p = _pct(s);
    if (p >= 75) return AiMarkerColors.secondary;
    if (p >= 50) return Colors.orange;
    return AiMarkerColors.error;
  }
}

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
          decoration: BoxDecoration(color: selected ? cs.surface : Colors.transparent, borderRadius: BorderRadius.circular(999), border: Border.all(color: selected ? cs.outline.withValues(alpha: 0.20) : Colors.transparent)),
          child: Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: selected ? null : AiMarkerColors.neutral)),
        ),
      ),
    );
  }
}

class _HighlightBox extends StatelessWidget {
  final Color color;
  final Color border;
  const _HighlightBox({required this.color, required this.border});

  @override
  Widget build(BuildContext context) {
    return Container(width: 110, height: 46, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10), border: Border.all(color: border.withValues(alpha: 0.8), width: 2)));
  }
}

class _TriageBadge extends StatelessWidget {
  final Submission submission;
  const _TriageBadge({required this.submission});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Color bg;
    Color fg;
    String title;
    String? subtitle;
    IconData icon;

    switch (submission.triageStatus) {
      case TriageStatus.graded:
        bg = AiMarkerColors.secondary.withValues(alpha: 0.12);
        fg = AiMarkerColors.secondary;
        title = '✓ Graded';
        subtitle = 'AI confidence ${submission.confidence}%';
        icon = Icons.check_circle_rounded;
        break;
      case TriageStatus.needsReview:
        bg = Colors.orange.withValues(alpha: 0.14);
        fg = Colors.orange;
        title = '⚠ Needs Review';
        subtitle = submission.triageFlags.isEmpty ? 'Confidence ${submission.confidence}% — please verify' : submission.triageFlags.first;
        icon = Icons.warning_rounded;
        break;
      case TriageStatus.unableToGrade:
        bg = AiMarkerColors.error.withValues(alpha: 0.10);
        fg = AiMarkerColors.error;
        title = '✗ Unable to Grade';
        subtitle = submission.triageFlags.isEmpty ? 'Image quality too low — retake photo' : submission.triageFlags.first;
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
          if (submission.triageStatus == TriageStatus.unableToGrade)
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
      decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: color.withValues(alpha: 0.22))),
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
