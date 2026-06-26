import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:marking_prokect_v2/app/app_routes.dart';
import 'package:marking_prokect_v2/models/grading_preset.dart';
import 'package:marking_prokect_v2/services/classes_service.dart';
import 'package:marking_prokect_v2/services/presets_service.dart';
import 'package:marking_prokect_v2/theme.dart';
import 'package:provider/provider.dart';

class PresetDetailScreen extends StatelessWidget {
  final String presetId;
  const PresetDetailScreen({super.key, required this.presetId});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final preset = context.watch<PresetsService>().getById(presetId);

    if (preset == null) {
      return Scaffold(appBar: AppBar(title: const Text('Scheme')), body: const Center(child: Text('Scheme not found')));
    }

    final klass = context.watch<ClassesService>().getById(preset.classId);
    final accent = switch (preset.gradingMode) {
      GradingMode.homework => AiMarkerColors.primary,
      GradingMode.testQuiz => AiMarkerColors.error,
      GradingMode.labReport => AiMarkerColors.secondary,
      GradingMode.englishEssay => AiMarkerColors.tertiary,
    };

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: () => context.pop(), icon: Icon(Icons.arrow_back_rounded, color: cs.primary)),
        title: Text(preset.name),
        actions: [
          TextButton(style: TextButton.styleFrom(splashFactory: NoSplash.splashFactory, foregroundColor: cs.primary), onPressed: () => context.push('${AppRoutes.presetEdit}?presetId=${preset.id}'), child: const Text('Edit')),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Icon(Icons.class_rounded, color: cs.primary),
                          const SizedBox(width: 10),
                          Expanded(child: Text(klass == null ? 'Class' : '${klass.name} · ${klass.period}', style: Theme.of(context).textTheme.titleSmall)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999), border: Border.all(color: accent.withValues(alpha: 0.18))),
                            child: Text(_modeLabel(preset.gradingMode), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: accent, fontWeight: FontWeight.w900)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Criteria', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          for (final e in preset.criteria.entries)
                            Row(
                              children: [
                                Icon(e.value == true ? Icons.check_circle_rounded : Icons.circle_outlined, color: e.value == true ? AiMarkerColors.secondary : AiMarkerColors.neutral, size: 18),
                                const SizedBox(width: 10),
                                Expanded(child: Text(e.key, style: Theme.of(context).textTheme.bodyMedium)),
                              ],
                            ),
                        ].expand((w) sync* {
                          yield w;
                          yield const SizedBox(height: 10);
                        }).toList()..removeLast(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Harshness', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text('${_harshnessWord(preset.harshness)} (${preset.harshness}/10)', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900))),
                              Container(width: 10, height: 10, decoration: BoxDecoration(color: preset.harshness >= 7 ? AiMarkerColors.error : (preset.harshness <= 3 ? AiMarkerColors.secondary : Colors.orange), shape: BoxShape.circle)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: preset.harshness / 10,
                              minHeight: 8,
                              color: preset.harshness >= 7 ? AiMarkerColors.error : (preset.harshness <= 3 ? AiMarkerColors.secondary : Colors.orange),
                              backgroundColor: cs.surfaceContainerHighest,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (preset.notes.trim().isNotEmpty) ...[
                    Text('Custom notes', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Card(child: Padding(padding: const EdgeInsets.all(14), child: Text(preset.notes, style: Theme.of(context).textTheme.bodyMedium))),
                    const SizedBox(height: 12),
                  ],
                  Text('Last modified', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                  const SizedBox(height: 4),
                  Text('${preset.updatedAt}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: FilledButton(
                onPressed: () => context.go('/grading'),
                style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(52)),
                child: const Text('Use This Scheme →'),
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
    GradingMode.labReport => 'Lab Report',
    GradingMode.englishEssay => 'English/Essay',
  };

  String _harshnessWord(int h) => h <= 3 ? 'Lenient' : (h <= 6 ? 'Balanced' : 'Strict');
}
