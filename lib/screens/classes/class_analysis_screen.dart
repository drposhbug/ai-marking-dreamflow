import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:marking_prokect_v2/models/student.dart';
import 'package:marking_prokect_v2/services/class_analysis.dart';
import 'package:marking_prokect_v2/services/classes_service.dart';
import 'package:marking_prokect_v2/services/students_service.dart';
import 'package:marking_prokect_v2/services/submissions_service.dart';
import 'package:marking_prokect_v2/theme.dart';
import 'package:provider/provider.dart';

/// What the CLASS got wrong, once the whole set is marked.
///
/// Thirty result screens tell a teacher thirty things they mostly already
/// knew. This tells them the one thing they can act on: the question the
/// room fell over on, what they fell over on, and roughly what to do about
/// it on Monday. It reads marks that were already paid for — opening it
/// never costs a credit, so it is safe to open every time.
class ClassAnalysisScreen extends StatefulWidget {
  final String classId;
  const ClassAnalysisScreen({super.key, required this.classId});

  @override
  State<ClassAnalysisScreen> createState() => _ClassAnalysisScreenState();
}

class _ClassAnalysisScreenState extends State<ClassAnalysisScreen> {
  /// Which class set is open. Null means the most recent one — the set the
  /// teacher has almost always just finished marking.
  String? _setId;

  /// Null on the class view, a student key on the per-student view.
  String? _studentKey;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final klass = context.watch<ClassesService>().getById(widget.classId);
    final submissions = context.watch<SubmissionsService>().submissions;
    final studentsService = context.watch<StudentsService>();

    final sets = ClassAnalysis.setsFor(submissions: submissions, classId: widget.classId);
    final set = sets.isEmpty ? null : sets.firstWhere((s) => s.id == _setId, orElse: () => sets.first);
    final insight = set == null ? null : ClassAnalysis.analyse(set.papers);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: () => context.pop(), icon: Icon(Icons.arrow_back_rounded, color: cs.primary)),
        title: const Text('Class analysis'),
      ),
      body: SafeArea(
        child: set == null || insight == null
            ? _EmptyState(className: klass?.name ?? 'this class')
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                children: [
                  if (sets.length > 1) ...[
                    _SetPicker(
                      sets: sets,
                      selectedId: set.id,
                      onPick: (id) => setState(() {
                        _setId = id;
                        _studentKey = null;
                      }),
                    ),
                    const SizedBox(height: 12),
                  ],
                  _Headline(set: set, insight: insight),
                  const SizedBox(height: 12),
                  _ViewSwitch(
                    students: _studentsIn(set.papers.map(ClassAnalysis.keyOf).toList(), studentsService),
                    selected: _studentKey,
                    onPick: (key) => setState(() => _studentKey = key),
                  ),
                  const SizedBox(height: 12),
                  if (_studentKey != null)
                    _StudentView(
                      insight: insight,
                      studentKey: _studentKey!,
                      name: _nameFor(_studentKey!, studentsService),
                    )
                  else
                    _ClassView(insight: insight),
                ],
              ),
      ),
    );
  }

  /// Papers in the set that belong to a student on the roster. An unlinked
  /// paper still counts towards the class numbers, it just has no name to
  /// put in the picker.
  List<Student> _studentsIn(List<String> keys, StudentsService service) {
    final out = <Student>[];
    for (final k in keys) {
      final s = service.getById(k);
      if (s != null) out.add(s);
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  String _nameFor(String key, StudentsService service) => service.getById(key)?.name ?? 'This paper';
}

class _EmptyState extends StatelessWidget {
  final String className;
  const _EmptyState({required this.className});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insights_rounded, size: 44, color: AiMarkerColors.neutral.withValues(alpha: 0.6)),
            const SizedBox(height: 14),
            Text('Nothing to break down yet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Mark a set of papers for $className and this fills in — which question the class fell over on, and what to do about it.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

/// Which set of papers is being looked at. Only shown once a class has been
/// marked more than once — a teacher with one test does not need a picker.
class _SetPicker extends StatelessWidget {
  final List<MarkedSet> sets;
  final String selectedId;
  final ValueChanged<String> onPick;

  const _SetPicker({required this.sets, required this.selectedId, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: sets.length,
        separatorBuilder: (context, i) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final s = sets[i];
          return ChoiceChip(
            label: Text('${s.subject} · ${_shortDate(s.markedAt)}'),
            selected: s.id == selectedId,
            onSelected: (_) => onPick(s.id),
          );
        },
      ),
    );
  }
}

String _shortDate(DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${months[d.month - 1]}';
}

class _Headline extends StatelessWidget {
  final MarkedSet set;
  final ClassInsight insight;

  const _Headline({required this.set, required this.insight});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final weak = insight.weakest;
    final worst = weak.isEmpty ? null : weak.first;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${set.subject} · ${_shortDate(set.markedAt)}', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '${insight.papers} paper${insight.papers == 1 ? '' : 's'}'
              '${insight.averagePercent == null ? '' : ', class average ${insight.averagePercent}%'}'
              ' · ${insight.questions.length} question${insight.questions.length == 1 ? '' : 's'}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.4),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (worst == null ? AiMarkerColors.secondary : cs.primary).withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Text(
                worst == null
                    ? 'No question fell below ${ClassAnalysis.weakBelowPercent}% — nothing here needs reteaching.'
                    : 'Start with ${worst.label}: ${worst.averagePercent}% across the class. ${worst.whatWentWrong}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4),
              ),
            ),
            if (insight.awaitingTeacher.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.flag_outlined, size: 16, color: AiMarkerColors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${insight.awaitingTeacher.map((q) => q.label).join(', ')} still need marking by hand — those marks are left out of every percentage here rather than counted as zero.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.4),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Whole class, or one student against it.
class _ViewSwitch extends StatelessWidget {
  final List<Student> students;
  final String? selected;
  final ValueChanged<String?> onPick;

  const _ViewSwitch({required this.students, required this.selected, required this.onPick});

  @override
  Widget build(BuildContext context) {
    if (students.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        Expanded(child: Text('View', style: Theme.of(context).textTheme.titleMedium)),
        Flexible(
          child: DropdownButton<String>(
            value: selected,
            isExpanded: true,
            alignment: Alignment.centerRight,
            hint: const Text('Whole class'),
            underline: const SizedBox.shrink(),
            items: [
              const DropdownMenuItem<String>(value: null, child: Text('Whole class')),
              for (final s in students)
                DropdownMenuItem<String>(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: onPick,
          ),
        ),
      ],
    );
  }
}

class _ClassView extends StatelessWidget {
  final ClassInsight insight;
  const _ClassView({required this.insight});

  @override
  Widget build(BuildContext context) {
    if (insight.questions.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            'These papers were marked as a whole rather than question by question, so there is nothing to rank. A test with numbered questions or marked sections breaks down here.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Worst first', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AiMarkerColors.neutral)),
        const SizedBox(height: 8),
        for (final q in insight.questions) ...[
          _QuestionCard(question: q),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// One question: how the class did, what went wrong, and what to do.
///
/// The reteach paragraph is folded away rather than printed on every row.
/// A teacher scanning fifteen questions for the two that matter should not
/// have to read fifteen paragraphs to find them.
class _QuestionCard extends StatelessWidget {
  final QuestionInsight question;
  const _QuestionCard({required this.question});

  @override
  Widget build(BuildContext context) {
    final q = question;
    final reteach = q.reteach;
    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ScoreChip(question: q),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(child: Text(q.label, style: Theme.of(context).textTheme.titleSmall, overflow: TextOverflow.ellipsis)),
                  if (q.category != null) ...[
                    const SizedBox(width: 8),
                    _CategoryPill(category: q.category!),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                q.whatWentWrong,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4),
              ),
              const SizedBox(height: 4),
              Text(
                _detail(q),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral),
              ),
            ],
          ),
        ),
      ],
    );

    return Card(
      child: reteach.isEmpty
          ? Padding(padding: const EdgeInsets.all(12), child: header)
          : Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                title: header,
                children: [_ReteachNote(label: q.label, text: reteach)],
              ),
            ),
    );
  }

  /// The counts under the one-liner, worded so a teacher never has to guess
  /// whether a missing question was counted against the class.
  static String _detail(QuestionInsight q) {
    final bits = <String>[];
    if (q.hasMarks) {
      bits.add('${q.fullMarks} of ${q.attempted} full marks');
      if (q.outOf > 0) bits.add('${_mark(q.averageMark)} / ${_mark(q.outOf)} average');
    }
    if (q.teacherMarked > 0) bits.add('${q.teacherMarked} for you to mark');
    if (q.notSeen > 0) bits.add('${q.notSeen} paper${q.notSeen == 1 ? '' : 's'} without it');
    return bits.join(' · ');
  }

  static String _mark(double v) =>
      v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

class _ScoreChip extends StatelessWidget {
  final QuestionInsight question;
  const _ScoreChip({required this.question});

  @override
  Widget build(BuildContext context) {
    final q = question;
    final color = !q.hasMarks
        ? AiMarkerColors.warning
        : q.averagePercent >= ClassAnalysis.weakBelowPercent
            ? AiMarkerColors.secondary
            : q.averagePercent >= 40
                ? AiMarkerColors.warning
                : AiMarkerColors.error;
    return Container(
      width: 52,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        q.hasMarks ? '${q.averagePercent}%' : '—',
        style: Theme.of(context).textTheme.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  final String category;
  const _CategoryPill({required this.category});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        category,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// The suggestion, clearly labelled as a suggestion.
///
/// Copy rather than anything cleverer: it goes into whatever the teacher
/// plans in, and no plan the app writes should feel like it owns Monday.
class _ReteachNote extends StatelessWidget {
  final String label;
  final String text;
  const _ReteachNote({required this.label, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AiMarkerColors.neutral.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Reteach idea', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AiMarkerColors.neutral)),
              ),
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: text));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label reteach note copied')));
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copy'),
              ),
            ],
          ),
          Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45)),
        ],
      ),
    );
  }
}

/// One student read against the class they sat with.
class _StudentView extends StatelessWidget {
  final ClassInsight insight;
  final String studentKey;
  final String name;

  const _StudentView({required this.insight, required this.studentKey, required this.name});

  @override
  Widget build(BuildContext context) {
    final gaps = ClassAnalysis.gapsFor(insight, studentKey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (gaps.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                '$name went the way the class went — nothing they missed that the room got, and nothing they got that the room missed.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4),
              ),
            ),
          ),
        if (gaps.missedWhatClassGot.isNotEmpty) ...[
          Text('Missed, when most of the class got it', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Worth a word with $name rather than a lesson for everyone.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.4),
          ),
          const SizedBox(height: 8),
          for (final q in gaps.missedWhatClassGot) ...[
            _GapRow(question: q, colour: AiMarkerColors.error, trailing: '${q.percentCorrect}% of the class got it'),
            const SizedBox(height: 8),
          ],
        ],
        if (gaps.gotWhatClassMissed.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('Got it, when most of the class did not', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Worth saying out loud — and $name is who to ask when you reteach it.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.4),
          ),
          const SizedBox(height: 8),
          for (final q in gaps.gotWhatClassMissed) ...[
            _GapRow(question: q, colour: AiMarkerColors.secondary, trailing: 'only ${q.percentCorrect}% of the class did'),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

class _GapRow extends StatelessWidget {
  final QuestionInsight question;
  final Color colour;
  final String trailing;

  const _GapRow({required this.question, required this.colour, required this.trailing});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 4, height: 40, decoration: BoxDecoration(color: colour, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: Text(question.label, style: Theme.of(context).textTheme.titleSmall, overflow: TextOverflow.ellipsis)),
                      if (question.category != null) ...[
                        const SizedBox(width: 8),
                        _CategoryPill(category: question.category!),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(question.whatWentWrong, style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4)),
                  const SizedBox(height: 4),
                  Text(trailing, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
