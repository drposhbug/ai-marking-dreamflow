import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:marking_prokect_v2/models/submission.dart';
import 'package:marking_prokect_v2/services/classes_service.dart';
import 'package:marking_prokect_v2/services/students_service.dart';
import 'package:marking_prokect_v2/services/submissions_service.dart';
import 'package:marking_prokect_v2/theme.dart';
import 'package:marking_prokect_v2/widgets/time_ago.dart';
import 'package:provider/provider.dart';

class StudentProfileScreen extends StatelessWidget {
  final String studentId;
  final String? classId;
  const StudentProfileScreen({super.key, required this.studentId, required this.classId});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final student = context.watch<StudentsService>().getById(studentId);
    final klass = classId == null ? null : context.watch<ClassesService>().getById(classId!);
    final submissions = context.watch<SubmissionsService>().byStudent(studentId);

    if (student == null) {
      return Scaffold(appBar: AppBar(title: const Text('Student Profile')), body: const Center(child: Text('Student not found')));
    }

    final avg = submissions.isEmpty ? 0.72 : (submissions.map((s) => s.maxScore == 0 ? 0 : (s.score / s.maxScore)).reduce((a, b) => a + b) / submissions.length).clamp(0, 1);
    final flags = submissions.where((s) => s.triageStatus == TriageStatus.needsReview).length;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: () => context.pop(), icon: Icon(Icons.arrow_back_rounded, color: cs.primary)),
        title: const Text('Student Profile'),
        actions: [IconButton(onPressed: () {}, icon: Icon(Icons.more_vert_rounded, color: AiMarkerColors.neutral))],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    CircleAvatar(radius: 40, backgroundColor: cs.primary.withValues(alpha: 0.12), child: Text(student.name.substring(0, 1), style: TextStyle(color: cs.primary, fontWeight: FontWeight.w900, fontSize: 26))),
                    const SizedBox(height: 10),
                    Text(student.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text(klass == null ? '' : '${klass.name} · ${klass.period}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () {},
                      icon: Icon(Icons.mail_outline_rounded, color: cs.primary),
                      label: Text('Message', style: TextStyle(color: cs.primary)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _StatCard(label: 'Avg Score', value: '${(avg * 100).round()}%', icon: Icons.show_chart_rounded, accent: cs.primary)),
                const SizedBox(width: 12),
                Expanded(child: _StatCard(label: 'Total Submissions', value: '${submissions.length}', icon: Icons.fact_check_rounded, accent: AiMarkerColors.tertiary)),
              ],
            ),
            const SizedBox(height: 12),
            _FlagCard(flags: flags),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: Text('Past Submissions', style: Theme.of(context).textTheme.titleMedium)),
                TextButton(style: TextButton.styleFrom(splashFactory: NoSplash.splashFactory, foregroundColor: cs.primary), onPressed: () {}, child: const Text('View All')),
              ],
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  for (final s in submissions.take(4))
                    ListTile(
                      title: Text(_assignmentName(s), style: Theme.of(context).textTheme.titleSmall),
                      subtitle: Text('${timeAgo(s.createdAt)} · ${_harshnessWordFromConfidence(s.confidence)}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                      trailing: _ScoreCircle(score: s.score, max: s.maxScore),
                      onTap: () {},
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [Icon(Icons.note_alt_rounded, color: cs.primary), const SizedBox(width: 10), Expanded(child: Text('Teacher Notes', style: Theme.of(context).textTheme.titleMedium))]),
                    const SizedBox(height: 10),
                    Text('“${student.notes ?? 'No notes yet.'}”', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic, color: AiMarkerColors.neutral)),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final updated = await showModalBottomSheet<String>(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (ctx) => _NotesEditor(initial: student.notes ?? ''),
                        );
                        if (updated == null) return;
                        await context.read<StudentsService>().updateNotes(studentId: student.id, notes: updated);
                      },
                      icon: Icon(Icons.edit_rounded, color: cs.primary),
                      label: Text('Edit Notes', style: TextStyle(color: cs.primary)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _assignmentName(Submission s) => switch (s.gradingMode) {
    _ => 'Unit ${s.createdAt.day} ${s.subject} Assignment',
  };

  String _harshnessWordFromConfidence(int c) => c >= 92 ? 'Lenient' : (c >= 85 ? 'Balanced' : 'Strict');
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color accent;

  const _StatCard({required this.label, required this.value, required this.icon, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Icon(icon, color: accent), const Spacer(), Container(width: 72, height: 22, decoration: BoxDecoration(color: accent.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(999)))]),
            const SizedBox(height: 12),
            Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
            const SizedBox(height: 6),
            Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }
}

class _FlagCard extends StatelessWidget {
  final int flags;
  const _FlagCard({required this.flags});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.flag_rounded, color: flags == 0 ? cs.primary : AiMarkerColors.error),
            const SizedBox(width: 10),
            Expanded(child: Text('Flag Count', style: Theme.of(context).textTheme.titleSmall)),
            Text('$flags', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(width: 10),
            if (flags > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: AiMarkerColors.error.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(999), border: Border.all(color: AiMarkerColors.error.withValues(alpha: 0.22))),
                child: Text('Attention Needed', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AiMarkerColors.error, fontWeight: FontWeight.w900)),
              ),
          ],
        ),
      ),
    );
  }
}

class _ScoreCircle extends StatelessWidget {
  final double score;
  final double max;
  const _ScoreCircle({required this.score, required this.max});

  @override
  Widget build(BuildContext context) {
    final pct = max == 0 ? 0 : (score / max);
    final color = pct >= 0.75 ? AiMarkerColors.secondary : (pct >= 0.5 ? Colors.orange : AiMarkerColors.error);

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.10), border: Border.all(color: color, width: 2)),
      child: Center(child: Text(max == 0 ? '—' : '${score.round()}/${max.round()}', textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w900))),
    );
  }
}

class _NotesEditor extends StatefulWidget {
  final String initial;
  const _NotesEditor({required this.initial});

  @override
  State<_NotesEditor> createState() => _NotesEditorState();
}

class _NotesEditorState extends State<_NotesEditor> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(color: cs.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [Expanded(child: Text('Edit Notes', style: Theme.of(context).textTheme.titleLarge)), IconButton(onPressed: () => context.pop(), icon: Icon(Icons.close_rounded, color: AiMarkerColors.neutral))]),
            const SizedBox(height: 10),
            TextField(controller: _controller, maxLines: 6, decoration: const InputDecoration(hintText: 'Add notes about this student...')),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () => context.pop(_controller.text.trim()),
              style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: Colors.white),
              child: const Text('Save Notes'),
            ),
          ],
        ),
      ),
    );
  }
}
