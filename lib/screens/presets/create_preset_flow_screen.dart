import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:marking_prokect_v2/models/grading_preset.dart';
import 'package:marking_prokect_v2/services/auth_service.dart';
import 'package:marking_prokect_v2/services/presets_service.dart';
import 'package:marking_prokect_v2/theme.dart';
import 'package:provider/provider.dart';

class CreatePresetFlowScreen extends StatefulWidget {
  final String classId;
  const CreatePresetFlowScreen({super.key, required this.classId});

  @override
  State<CreatePresetFlowScreen> createState() => _CreatePresetFlowScreenState();
}

class _CreatePresetFlowScreenState extends State<CreatePresetFlowScreen> {
  int _step = 0;
  final _name = TextEditingController();
  GradingMode _mode = GradingMode.homework;
  late Map<String, bool> _criteria;
  double _harshness = 5;
  final _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    _criteria = {for (final c in PresetsService.criteriaLabels(_mode)) c: true};
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final auth = context.read<AuthService>().currentUser;
    if (auth == null) {
      final cs = Theme.of(context).colorScheme;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Sign in to create custom schemes', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text('You can still use and tweak the built-in defaults, but saving new custom schemes requires an account.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AiMarkerColors.neutral, height: 1.45)),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: () {
                    ctx.pop();
                    context.go('/login');
                  },
                  style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(52)),
                  child: const Text('Go to Sign In'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => ctx.pop(),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), side: BorderSide(color: cs.outline.withValues(alpha: 0.45))),
                  child: Text('Cancel', style: TextStyle(color: cs.primary)),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }

    await context.read<PresetsService>().create(
      teacherId: auth.id,
      classId: widget.classId,
      name: _name.text.trim().isEmpty ? 'New Scheme' : _name.text.trim(),
      mode: _mode,
      criteria: _criteria,
      harshness: _harshness.round(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );

    if (!mounted) return;
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: () => context.pop(), icon: Icon(Icons.arrow_back_rounded, color: cs.primary)),
        title: const Text('Create New Scheme'),
        actions: [IconButton(onPressed: () => context.pop(), icon: Icon(Icons.close_rounded, color: AiMarkerColors.neutral))],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 10),
            _ProgressDots(step: _step),
            const SizedBox(height: 14),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Padding(
                  key: ValueKey(_step),
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
                  child: _stepWidget(context),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: FilledButton(
                onPressed: () async {
                  if (_step < 4) {
                    setState(() => _step++);
                  } else {
                    await _save();
                  }
                },
                style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(52)),
                child: Text(_step < 4 ? 'Continue' : 'Save Scheme'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepWidget(BuildContext context) {
    return switch (_step) {
      0 => _StepName(controller: _name),
      1 => _StepMode(
          mode: _mode,
          onSelect: (m) {
            setState(() {
              _mode = m;
              _criteria = {for (final c in PresetsService.criteriaLabels(m)) c: true};
            });
          },
        ),
      2 => _StepCriteria(criteria: _criteria, onChange: (next) => setState(() => _criteria = next)),
      3 => _StepHarshness(value: _harshness, onChange: (v) => setState(() => _harshness = v)),
      _ => _StepNotes(controller: _notes),
    };
  }
}

class _ProgressDots extends StatelessWidget {
  final int step;
  const _ProgressDots({required this.step});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < 5; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == step ? 18 : 8,
            height: 8,
            decoration: BoxDecoration(color: i <= step ? cs.primary : cs.outline.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(999)),
          ),
      ],
    );
  }
}

class _StepName extends StatelessWidget {
  final TextEditingController controller;
  const _StepName({required this.controller});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Name your scheme', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text('Give this marking configuration a memorable name.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AiMarkerColors.neutral)),
        const SizedBox(height: 18),
        TextField(controller: controller, decoration: const InputDecoration(labelText: 'Scheme Name', hintText: 'e.g., Year 10 Math Test Strict')),
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: cs.primary.withValues(alpha: 0.12))),
          child: Row(children: [Icon(Icons.lightbulb_rounded, color: cs.primary), const SizedBox(width: 10), Expanded(child: Text('Tip: include year + topic + strictness so it’s easy to reuse.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)))]),
        ),
      ],
    );
  }
}

class _StepMode extends StatelessWidget {
  final GradingMode mode;
  final ValueChanged<GradingMode> onSelect;
  const _StepMode({required this.mode, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Select grading mode', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text('Pick how you want AI to interpret the work.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AiMarkerColors.neutral)),
        const SizedBox(height: 16),
        _ModeBigCard(title: 'Homework', subtitle: 'Completion %', icon: Icons.menu_book_rounded, color: AiMarkerColors.primary, selected: mode == GradingMode.homework, onTap: () => onSelect(GradingMode.homework)),
        const SizedBox(height: 12),
        _ModeBigCard(title: 'Test / Quiz', subtitle: 'x / total', icon: Icons.quiz_rounded, color: AiMarkerColors.error, selected: mode == GradingMode.testQuiz, onTap: () => onSelect(GradingMode.testQuiz)),
        const SizedBox(height: 12),
        _ModeBigCard(title: 'Lab Report', subtitle: 'Rubric score', icon: Icons.science_rounded, color: AiMarkerColors.secondary, selected: mode == GradingMode.labReport, onTap: () => onSelect(GradingMode.labReport)),
        const SizedBox(height: 12),
        _ModeBigCard(title: 'English / Essay', subtitle: 'Grade band', icon: Icons.auto_stories_rounded, color: AiMarkerColors.tertiary, selected: mode == GradingMode.englishEssay, onTap: () => onSelect(GradingMode.englishEssay)),
      ],
    );
  }
}

class _ModeBigCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ModeBigCard({required this.title, required this.subtitle, required this.icon, required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      splashFactory: NoSplash.splashFactory,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: selected ? color : cs.outline.withValues(alpha: 0.22), width: selected ? 1.6 : 1)),
        child: Row(
          children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: color)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 2), Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral))])),
            if (selected) Container(width: 24, height: 24, decoration: BoxDecoration(color: color, shape: BoxShape.circle), child: const Icon(Icons.check_rounded, size: 16, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

class _StepCriteria extends StatelessWidget {
  final Map<String, bool> criteria;
  final ValueChanged<Map<String, bool>> onChange;
  const _StepCriteria({required this.criteria, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('What should AI check?', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text('All items are enabled by default — turn off anything you don’t want.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AiMarkerColors.neutral)),
        const SizedBox(height: 14),
        Expanded(
          child: Card(
            child: ListView(
              padding: const EdgeInsets.all(10),
              children: [
                for (final e in criteria.entries)
                  CheckboxListTile(
                    value: e.value == true,
                    onChanged: (v) => onChange({...criteria, e.key: v ?? false}),
                    title: Text(e.key),
                    controlAffinity: ListTileControlAffinity.leading,
                    checkboxShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StepHarshness extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChange;
  const _StepHarshness({required this.value, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = value.round();
    final label = v <= 3 ? 'Lenient' : (v <= 6 ? 'Balanced' : 'Strict');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('How strict should marking be?', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text('This adjusts how harshly errors are penalized.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AiMarkerColors.neutral)),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [Text('Lenient', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)), const Spacer(), Text('Strict', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral))]),
                Slider(value: value, min: 0, max: 10, divisions: 10, onChanged: onChange),
                Row(
                  children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: v <= 3 ? AiMarkerColors.secondary : (v <= 6 ? Colors.orange : AiMarkerColors.error), shape: BoxShape.circle)),
                    const SizedBox(width: 10),
                    Text('$label ($v/10)', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                    const Spacer(),
                    Text(v <= 3 ? 'More forgiving' : (v <= 6 ? 'Balanced' : 'Exam-style'), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(value: v / 10, minHeight: 8, color: v <= 3 ? AiMarkerColors.secondary : (v <= 6 ? Colors.orange : AiMarkerColors.error), backgroundColor: cs.surfaceContainerHighest),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StepNotes extends StatelessWidget {
  final TextEditingController controller;
  const _StepNotes({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Anything specific to watch for?', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text('Add context like “prioritize units” or “ignore minor spelling”.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AiMarkerColors.neutral)),
        const SizedBox(height: 14),
        Expanded(child: TextField(controller: controller, maxLines: null, expands: true, decoration: const InputDecoration(hintText: 'Write custom instructions for AI...'))),
      ],
    );
  }
}
