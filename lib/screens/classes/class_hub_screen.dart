import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:marking_prokect_v2/app/app_routes.dart';
import 'package:marking_prokect_v2/models/grading_preset.dart';
import 'package:marking_prokect_v2/services/classes_service.dart';
import 'package:marking_prokect_v2/services/presets_service.dart';
import 'package:marking_prokect_v2/services/students_service.dart';
import 'package:marking_prokect_v2/services/submissions_service.dart';
import 'package:marking_prokect_v2/theme.dart';
import 'package:marking_prokect_v2/widgets/progress_ring.dart';
import 'package:provider/provider.dart';

class ClassHubScreen extends StatefulWidget {
  final String classId;
  const ClassHubScreen({super.key, required this.classId});

  @override
  State<ClassHubScreen> createState() => _ClassHubScreenState();
}

class _ClassHubScreenState extends State<ClassHubScreen> {
  int _tab = 0;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final klass = context.watch<ClassesService>().getById(widget.classId);
    final studentsService = context.watch<StudentsService>();
    final presetsService = context.watch<PresetsService>();
    final submissions = context.watch<SubmissionsService>().submissions;

    final students = studentsService.byClass(widget.classId);
    final classSubmissions = submissions.where((s) => s.classId == widget.classId).toList();
    final avg = classSubmissions.isEmpty
        ? 0.72
        : (classSubmissions.map((e) => e.maxScore == 0 ? 0.0 : (e.score / e.maxScore)).reduce((a, b) => a + b) / classSubmissions.length).clamp(0.0, 1.0).toDouble();

    final filteredStudents = students.where((s) => _search.text.trim().isEmpty || s.name.toLowerCase().contains(_search.text.trim().toLowerCase())).toList();

    final presets = presetsService.byClass(widget.classId);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: () => context.pop(), icon: Icon(Icons.arrow_back_rounded, color: cs.primary)),
        title: Text('${klass?.subject ?? 'Class'} · ${klass?.period ?? ''}'),
        actions: [IconButton(onPressed: () {}, icon: Icon(Icons.more_vert_rounded, color: AiMarkerColors.neutral))],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
          children: [
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Students')),
                ButtonSegment(value: 1, label: Text('Marking Schemes')),
              ],
              selected: {_tab},
              onSelectionChanged: (s) => setState(() => _tab = s.first),
            ),
            const SizedBox(height: 14),
            if (_tab == 0) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      ProgressRing(value: avg, size: 84, stroke: 10, label: '${(avg * 100).round()}%'),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Class Average', style: Theme.of(context).textTheme.titleSmall),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                _MiniStat(label: 'STUDENTS', value: '${students.length}'),
                                const SizedBox(width: 10),
                                _MiniStat(label: 'ASSIGNMENTS', value: '${classSubmissions.length}'),
                                const SizedBox(width: 10),
                                _MiniStat(label: 'LAST GRADED', value: classSubmissions.isEmpty ? '—' : '2d ago'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(controller: _search, onChanged: (_) => setState(() {}), decoration: InputDecoration(hintText: 'Search students...', prefixIcon: Icon(Icons.search_rounded, color: AiMarkerColors.neutral.withValues(alpha: 0.85)))),
              const SizedBox(height: 14),
              Text('Students', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              Card(
                child: Column(
                  children: [
                    for (final s in filteredStudents)
                      ListTile(
                        leading: CircleAvatar(backgroundColor: cs.primary.withValues(alpha: 0.12), child: Text(s.name.substring(0, 1), style: TextStyle(color: cs.primary, fontWeight: FontWeight.w800))),
                        title: Text(s.name, style: Theme.of(context).textTheme.titleSmall),
                        subtitle: Text('Last: Kinematics Quiz', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                        trailing: _TrendBadge(kind: _trendFor(s.id, classSubmissions)),
                        onTap: () => context.push('${AppRoutes.studentProfile}?studentId=${s.id}&classId=${widget.classId}'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 80),
            ] else ...[
              InkWell(
                splashFactory: NoSplash.splashFactory,
                onTap: () => context.push('${AppRoutes.presetFlow}?classId=${widget.classId}'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: cs.outline.withValues(alpha: 0.26), style: BorderStyle.solid), color: cs.surface),
                  child: Row(
                    children: [
                      Container(width: 40, height: 40, decoration: BoxDecoration(shape: BoxShape.circle, color: cs.primary.withValues(alpha: 0.10)), child: Icon(Icons.add_rounded, color: cs.primary)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Create New Scheme', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: cs.primary)),
                          const SizedBox(height: 2),
                          Text('Set up specific grading rules', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                        ]),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text('CLASS SCHEMES', style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.2, color: AiMarkerColors.neutral)),
              const SizedBox(height: 10),
              for (final p in presets) ...[
                _PresetListCard(preset: p),
                const SizedBox(height: 12),
              ],
            ],
          ],
        ),
      ),
      floatingActionButton: _tab == 0
          ? SizedBox(
              width: MediaQuery.of(context).size.width - 32,
              child: FilledButton.icon(
                onPressed: () {},
                style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl))),
                icon: const Icon(Icons.person_add_alt_rounded, color: Colors.white),
                label: const Text('Add Student'),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  TrendKind _trendFor(String studentId, List<dynamic> submissions) {
    final n = submissions.where((s) => s.studentId == studentId).length;
    if (n % 3 == 0) return TrendKind.improving;
    if (n % 3 == 1) return TrendKind.consistent;
    return TrendKind.attention;
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.1, color: AiMarkerColors.neutral)),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        ]),
      ),
    );
  }
}

enum TrendKind { improving, consistent, attention }

class _TrendBadge extends StatelessWidget {
  final TrendKind kind;
  const _TrendBadge({required this.kind});

  @override
  Widget build(BuildContext context) {
    late Color bg;
    late Color fg;
    late String text;
    late IconData icon;

    switch (kind) {
      case TrendKind.improving:
        bg = AiMarkerColors.secondary.withValues(alpha: 0.12);
        fg = AiMarkerColors.secondary;
        text = 'IMPROVING';
        icon = Icons.trending_up_rounded;
        break;
      case TrendKind.consistent:
        bg = Theme.of(context).colorScheme.surfaceContainerHighest;
        fg = AiMarkerColors.neutral;
        text = 'CONSISTENT';
        icon = Icons.trending_flat_rounded;
        break;
      case TrendKind.attention:
        bg = AiMarkerColors.error.withValues(alpha: 0.10);
        fg = AiMarkerColors.error;
        text = 'ATTENTION';
        icon = Icons.trending_down_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999), border: Border.all(color: fg.withValues(alpha: 0.22))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: fg),
        const SizedBox(width: 6),
        Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w900, letterSpacing: 0.4)),
      ]),
    );
  }
}

class _PresetListCard extends StatelessWidget {
  final GradingPreset preset;
  const _PresetListCard({required this.preset});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = switch (preset.gradingMode) {
      GradingMode.homework => AiMarkerColors.primary,
      GradingMode.testQuiz => AiMarkerColors.error,
      GradingMode.labReport => AiMarkerColors.secondary,
      GradingMode.englishEssay => AiMarkerColors.tertiary,
    };

    final enabled = preset.criteria.entries.where((e) => e.value == true).take(3).map((e) => e.key).toList();

    return InkWell(
      splashFactory: NoSplash.splashFactory,
      onTap: () => context.push('${AppRoutes.presetDetail}?presetId=${preset.id}'),
      child: Container(
        decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: cs.outline.withValues(alpha: 0.22))),
        child: Row(
          children: [
            Container(width: 4, height: 150, decoration: BoxDecoration(color: accent, borderRadius: const BorderRadius.only(topLeft: Radius.circular(AppRadius.lg), bottomLeft: Radius.circular(AppRadius.lg)))),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(preset.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
                        IconButton(onPressed: () => context.push('${AppRoutes.presetEdit}?presetId=${preset.id}'), icon: Icon(Icons.edit_rounded, color: AiMarkerColors.neutral)),
                        IconButton(onPressed: () {}, icon: Icon(Icons.delete_outline_rounded, color: AiMarkerColors.neutral)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(preset.notes, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      _Badge(text: _modeLabel(preset.gradingMode), color: accent.withValues(alpha: 0.12), textColor: accent),
                      for (final c in enabled) _Badge(text: '✓ $c', color: cs.surfaceContainerHighest, textColor: AiMarkerColors.neutral),
                    ]),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text('Harshness Level', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AiMarkerColors.neutral, letterSpacing: 0.8)),
                        const Spacer(),
                        Text('${_harshnessWord(preset.harshness)} (${preset.harshness}/10)', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: preset.harshness >= 7 ? AiMarkerColors.error : (preset.harshness <= 3 ? AiMarkerColors.secondary : Colors.orange), fontWeight: FontWeight.w900)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: preset.harshness / 10,
                        minHeight: 8,
                        color: preset.harshness >= 7 ? AiMarkerColors.error : (preset.harshness <= 3 ? AiMarkerColors.secondary : Colors.orange),
                        backgroundColor: cs.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: Text('Set as Default Scheme', style: Theme.of(context).textTheme.bodyMedium)),
                        Switch(value: preset.isDefault, onChanged: (v) => context.read<PresetsService>().setDefault(presetId: preset.id, isDefault: v), activeColor: cs.primary),
                      ],
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

  String _modeLabel(GradingMode m) => switch (m) {
    GradingMode.homework => 'Homework',
    GradingMode.testQuiz => 'Test/Quiz',
    GradingMode.labReport => 'Lab',
    GradingMode.englishEssay => 'English/Essay',
  };

  String _harshnessWord(int h) => h <= 3 ? 'Lenient' : (h <= 6 ? 'Balanced' : 'Strict');
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  final Color textColor;
  const _Badge({required this.text, required this.color, required this.textColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999), border: Border.all(color: textColor.withValues(alpha: 0.18))),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: textColor, fontWeight: FontWeight.w800)),
    );
  }
}
