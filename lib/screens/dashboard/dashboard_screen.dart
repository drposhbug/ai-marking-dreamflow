import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:marking_prokect_v2/app/app_routes.dart';
import 'package:marking_prokect_v2/models/grading_preset.dart';
import 'package:marking_prokect_v2/models/submission.dart';
import 'package:marking_prokect_v2/services/auth_service.dart';
import 'package:marking_prokect_v2/services/classes_service.dart';
import 'package:marking_prokect_v2/services/local_store.dart';
import 'package:marking_prokect_v2/services/students_service.dart';
import 'package:marking_prokect_v2/services/submissions_service.dart';
import 'package:marking_prokect_v2/theme.dart';
import 'package:marking_prokect_v2/widgets/progress_ring.dart';
import 'package:marking_prokect_v2/widgets/teacher_topbar.dart';
import 'package:marking_prokect_v2/widgets/time_ago.dart';
import 'package:provider/provider.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const _kSelectedClassKeyPrefix = 'ai_marker.dashboard.selected_class.v1.';

  final _search = TextEditingController();
  GradingMode? _filter;

  final _store = const LocalStore();
  String? _selectedClassId;
  String? _loadedForTeacherId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final teacherId = context.read<AuthService>().currentUser?.id;
    if (teacherId == null || _loadedForTeacherId == teacherId) return;
    _loadedForTeacherId = teacherId;
    _loadSelectedClass(teacherId);
  }

  Future<void> _loadSelectedClass(String teacherId) async {
    try {
      final raw = await _store.getString('$_kSelectedClassKeyPrefix$teacherId');
      if (!mounted) return;
      setState(() => _selectedClassId = (raw ?? '').trim().isEmpty ? null : raw!.trim());
    } catch (e) {
      debugPrint('Dashboard: failed to load selected class: $e');
    }
  }

  Future<void> _setSelectedClass({required String teacherId, required String classId}) async {
    setState(() => _selectedClassId = classId);
    try {
      await _store.setString('$_kSelectedClassKeyPrefix$teacherId', classId);
    } catch (e) {
      debugPrint('Dashboard: failed to persist selected class: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
      final teacherId = context.watch<AuthService>().currentUser?.id;
      final submissionsService = context.watch<SubmissionsService>();
      final studentsService = context.read<StudentsService>();
      final classesService = context.watch<ClassesService>();

      final teacherClasses = teacherId == null ? const [] : classesService.classes.where((c) => c.teacherId == teacherId).toList();
      if (teacherId != null && teacherClasses.isNotEmpty) {
        final desiredId = teacherClasses.any((c) => c.id == _selectedClassId) ? _selectedClassId : teacherClasses.first.id;
        if (desiredId != null && desiredId != _selectedClassId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _selectedClassId = desiredId);
          });
        }
      }

      final selectedClass = (_selectedClassId == null) ? null : classesService.getById(_selectedClassId!);

      final classSubmissions = (teacherId == null || _selectedClassId == null)
          ? const <Submission>[]
          : submissionsService.submissions.where((s) => s.teacherId == teacherId && s.classId == _selectedClassId).toList();

      final sortedSubmissions = (classSubmissions.isNotEmpty)
          ? (List<Submission>.from(classSubmissions)..sort((a, b) => b.createdAt.compareTo(a.createdAt)))
          : const <Submission>[];

      final visible = sortedSubmissions.where((s) {
        if (_filter != null && s.gradingMode != _filter) return false;
        final q = _search.text.trim().toLowerCase();
        if (q.isEmpty) return true;
        final student = studentsService.getById(s.studentId);
        return (student?.name.toLowerCase().contains(q) ?? false);
      }).toList();

      final graded = sortedSubmissions.where((s) => s.triageStatus == TriageStatus.graded).length;
      final flagged = sortedSubmissions.where((s) => s.triageStatus == TriageStatus.needsReview).length;
      final overrides = sortedSubmissions.where((s) => s.overrideUsed).length;

      final scoreRows = sortedSubmissions.where((s) => s.maxScore > 0).toList();
      final avg = scoreRows.isEmpty
          ? 0.0
          : (scoreRows.map((e) => (e.score / e.maxScore)).reduce((a, b) => a + b) / scoreRows.length).clamp(0.0, 1.0).toDouble();

      return Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
            children: [
              TeacherTopbar(title: 'Dashboard', leadingIcon: Icons.menu_rounded, onLeading: () {}, trailingIcon: Icons.filter_alt_rounded, onBell: () {}),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.lg), gradient: const LinearGradient(colors: [AiMarkerColors.primary, AiMarkerColors.tertiary], begin: Alignment.topLeft, end: Alignment.bottomRight)),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Class Average', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.white.withValues(alpha: 0.92))),
                          const SizedBox(height: 4),
                          if (teacherClasses.length <= 1)
                            Text(selectedClass?.name ?? 'Your class', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white))
                          else
                            _ClassSelector(
                              value: _selectedClassId,
                              items: teacherClasses.map((c) => _ClassOption(id: c.id, label: c.name)).toList(),
                              onChanged: (id) {
                                if (id == null || teacherId == null) return;
                                _setSelectedClass(teacherId: teacherId, classId: id);
                              },
                            ),
                          const SizedBox(height: 14),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            _StatChip(label: '$graded graded', icon: Icons.check_circle_rounded, color: Colors.white.withValues(alpha: 0.16)),
                            _StatChip(label: '$flagged flagged ⚠', icon: Icons.warning_rounded, color: Colors.orange.withValues(alpha: 0.20)),
                            _StatChip(label: '$overrides overrides', icon: Icons.edit_rounded, color: Colors.white.withValues(alpha: 0.16)),
                          ]),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    ProgressRing(value: avg, size: 86, stroke: 10, label: '${(avg * 100).round()}%'),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (teacherId != null && teacherClasses.isNotEmpty && sortedSubmissions.isEmpty)
                _DashboardEmptyState(onGradeFirst: () => context.go(AppRoutes.grading))
              else ...[
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(hintText: 'Search student...', prefixIcon: Icon(Icons.search_rounded, color: AiMarkerColors.neutral.withValues(alpha: 0.85))),
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 8, children: [
                  _FilterChip(label: 'All', selected: _filter == null, onTap: () => setState(() => _filter = null)),
                  _FilterChip(label: 'Homework', selected: _filter == GradingMode.homework, onTap: () => setState(() => _filter = GradingMode.homework)),
                  _FilterChip(label: 'Test', selected: _filter == GradingMode.testQuiz, onTap: () => setState(() => _filter = GradingMode.testQuiz)),
                  _FilterChip(label: 'Lab', selected: _filter == GradingMode.labReport, onTap: () => setState(() => _filter = GradingMode.labReport)),
                  _FilterChip(label: 'Essay', selected: _filter == GradingMode.englishEssay, onTap: () => setState(() => _filter = GradingMode.englishEssay)),
                ]),
                const SizedBox(height: 14),
                Text('RECENT SUBMISSIONS', style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.2, color: AiMarkerColors.neutral)),
                const SizedBox(height: 10),
                Card(
                  child: Column(
                    children: [
                      for (final s in visible.take(12)) _SubmissionRow(submission: s),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    } catch (e, st) {
      debugPrint('Dashboard build failed: $e\n$st');
      final cs = Theme.of(context).colorScheme;
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.dashboard_customize_rounded, size: 44, color: cs.primary),
                  const SizedBox(height: 12),
                  Text('Dashboard is loading', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(
                    'If this keeps happening, try reopening the app.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AiMarkerColors.neutral, height: 1.35),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
  }
}

class _ClassOption {
  final String id;
  final String label;

  const _ClassOption({required this.id, required this.label});
}

class _ClassSelector extends StatelessWidget {
  final String? value;
  final List<_ClassOption> items;
  final ValueChanged<String?> onChanged;

  const _ClassSelector({required this.value, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999), border: Border.all(color: Colors.white.withValues(alpha: 0.18))),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          dropdownColor: AiMarkerColors.darkCard,
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white.withValues(alpha: 0.92)),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
          items: [
            for (final o in items)
              DropdownMenuItem<String>(
                value: o.id,
                child: Text(o.label, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _DashboardEmptyState extends StatelessWidget {
  final VoidCallback onGradeFirst;

  const _DashboardEmptyState({required this.onGradeFirst});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(shape: BoxShape.circle, color: cs.primary.withValues(alpha: 0.10), border: Border.all(color: cs.primary.withValues(alpha: 0.20))),
              child: Icon(Icons.inbox_rounded, color: cs.primary, size: 30),
            ),
            const SizedBox(height: 12),
            Text('No submissions yet', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text('Start grading to see your class stats', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AiMarkerColors.neutral, height: 1.35)),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onGradeFirst,
              style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: Colors.white),
              icon: const Icon(Icons.arrow_forward_rounded, color: Colors.white),
              label: const Text('Grade First Assignment →'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _StatChip({required this.label, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999), border: Border.all(color: Colors.white.withValues(alpha: 0.18))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: Colors.white),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.white)),
      ]),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? cs.primary : cs.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? cs.primary : cs.outline.withValues(alpha: 0.22)),
        ),
        child: Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: selected ? Colors.white : AiMarkerColors.neutral)),
      ),
    );
  }
}

class _SubmissionRow extends StatelessWidget {
  final Submission submission;

  const _SubmissionRow({required this.submission});

  @override
  Widget build(BuildContext context) {
    final students = context.read<StudentsService>();
    final student = students.getById(submission.studentId);

    final pct = submission.maxScore == 0 ? 0 : (submission.score / submission.maxScore);
    final scoreColor = pct >= 0.75 ? AiMarkerColors.secondary : (pct >= 0.5 ? Colors.orange : AiMarkerColors.error);

    return InkWell(
      splashFactory: NoSplash.splashFactory,
      onTap: () => context.push('${AppRoutes.result}?submissionId=${submission.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: scoreColor.withValues(alpha: 0.12),
              child: Text(
                (student?.name.isNotEmpty ?? false) ? student!.name.substring(0, 1) : '?',
                style: TextStyle(color: scoreColor, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(student?.name ?? 'Student', style: Theme.of(context).textTheme.titleSmall)),
                      if (submission.triageStatus == TriageStatus.needsReview)
                        Icon(Icons.warning_rounded, size: 18, color: Colors.orange),
                      if (submission.overrideUsed)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999), border: Border.all(color: Colors.orange.withValues(alpha: 0.25))),
                          child: Text('OVERRIDE', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.orange, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('${submission.subject} · ${_modeLabel(submission.gradingMode)} · ${timeAgo(submission.createdAt)}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              submission.maxScore == 0 ? '—' : '${submission.score.round()}/${submission.maxScore.round()}',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(color: scoreColor, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }

  String _modeLabel(GradingMode m) => switch (m) {
    GradingMode.homework => 'Homework',
    GradingMode.testQuiz => 'Test',
    GradingMode.labReport => 'Lab',
    GradingMode.englishEssay => 'Essay',
  };
}
