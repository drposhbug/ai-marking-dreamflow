import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:marking_prokect_v2/models/grading_preset.dart';
import 'package:marking_prokect_v2/services/auth_service.dart';
import 'package:marking_prokect_v2/services/presets_service.dart';
import 'package:marking_prokect_v2/theme.dart';
import 'package:provider/provider.dart';

class PresetEditScreen extends StatefulWidget {
  final String presetId;
  final GradingPreset? initialPreset;

  /// Edit an existing scheme.
  ///
  /// - Prefer passing [initialPreset] via `GoRouter` `extra` so built-in defaults
  ///   (which may not exist in Supabase) can still be edited.
  /// - [presetId] is kept as a fallback for deep links / legacy navigation.
  const PresetEditScreen({super.key, this.presetId = '', this.initialPreset});

  @override
  State<PresetEditScreen> createState() => _PresetEditScreenState();
}

class _PresetEditScreenState extends State<PresetEditScreen> {
  final _name = TextEditingController();
  final _notes = TextEditingController();
  double _harshness = 5;
  late GradingMode _mode;
  late Map<String, bool> _criteria;

  @override
  void initState() {
    super.initState();
    final preset = widget.initialPreset ?? context.read<PresetsService>().getById(widget.presetId);
    _mode = preset?.gradingMode ?? GradingMode.homework;
    _name.text = preset?.name ?? '';
    _notes.text = preset?.notes ?? '';
    _harshness = ((preset?.harshness ?? 5).clamp(1, 10)).toDouble();

    final labels = PresetsService.criteriaLabels(_mode);
    _criteria = {for (final l in labels) l: (preset?.criteria[l] == true)};
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final service = context.read<PresetsService>();
    final preset = widget.initialPreset ?? service.getById(widget.presetId);
    if (preset == null) return;

    final auth = context.read<AuthService>().currentUser;
    final isEditingBuiltInDefault = preset.isBuiltInDefault || (preset.isDefault && preset.teacherId.trim().isEmpty);
    final nextName = _name.text.trim().isEmpty ? preset.name : _name.text.trim();
    final nextNotes = _notes.text.trim();
    final nextHarshness = _harshness.round().clamp(1, 10);

    if (isEditingBuiltInDefault) {
      if (auth == null) {
        await _showSignInRequired(context);
        return;
      }
      await service.create(
        teacherId: auth.id,
        classId: '',
        name: nextName,
        mode: _mode,
        criteria: _criteria,
        harshness: nextHarshness,
        notes: nextNotes.isEmpty ? null : nextNotes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved as your custom version')));
      context.pop();
      return;
    }

    if (auth == null) {
      await _showSignInRequired(context);
      return;
    }

    await service.updatePreset(preset.copyWith(
      name: nextName,
      gradingMode: _mode,
      notes: nextNotes,
      harshness: nextHarshness,
      criteria: _criteria,
    ));

    if (!mounted) return;
    context.pop();
  }

  Future<void> _showSignInRequired(BuildContext context) async {
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
              Text('Sign in required', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text('Sign in to edit and save custom schemes.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AiMarkerColors.neutral, height: 1.45)),
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
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final preset = widget.initialPreset ?? context.watch<PresetsService>().getById(widget.presetId);

    if (preset == null) {
      return Scaffold(appBar: AppBar(title: const Text('Edit Scheme')), body: const Center(child: Text('Scheme not found')));
    }

    final isEditingBuiltInDefault = preset.isBuiltInDefault || (preset.isDefault && preset.teacherId.trim().isEmpty);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: () => context.pop(), icon: Icon(Icons.arrow_back_rounded, color: cs.primary)),
        title: const Text('Edit Scheme'),
        actions: [TextButton(style: TextButton.styleFrom(splashFactory: NoSplash.splashFactory, foregroundColor: cs.primary), onPressed: _save, child: const Text('Save'))],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
          children: [
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Scheme name')),
            const SizedBox(height: 12),
            DropdownButtonFormField<GradingMode>(
              value: _mode,
              decoration: const InputDecoration(labelText: 'Grading mode'),
              items: const [
                DropdownMenuItem(value: GradingMode.homework, child: Text('Homework')),
                DropdownMenuItem(value: GradingMode.testQuiz, child: Text('Test / Quiz')),
                DropdownMenuItem(value: GradingMode.labReport, child: Text('Lab Report')),
                DropdownMenuItem(value: GradingMode.englishEssay, child: Text('English / Essay')),
              ],
              onChanged: (v) {
                if (v == null) return;
                final labels = PresetsService.criteriaLabels(v);
                setState(() {
                  _mode = v;
                  _criteria = {for (final l in labels) l: (_criteria[l] == true)};
                });
              },
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: [
                    for (final label in PresetsService.criteriaLabels(_mode))
                      CheckboxListTile(
                        value: _criteria[label] == true,
                        onChanged: (v) => setState(() => _criteria = {..._criteria, label: v ?? false}),
                        title: Text(label),
                        controlAffinity: ListTileControlAffinity.leading,
                        checkboxShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Harshness: ${_harshness.round()}/10', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                    Slider(value: _harshness, min: 1, max: 10, divisions: 9, onChanged: (v) => setState(() => _harshness = v)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(controller: _notes, maxLines: 4, decoration: const InputDecoration(labelText: 'Notes', hintText: 'Custom instructions for AI...')),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: Colors.white),
              child: const Text('Save Changes'),
            ),
            const SizedBox(height: 10),
            if (!isEditingBuiltInDefault)
              OutlinedButton(
                onPressed: () async {
                  final presetNow = context.read<PresetsService>().getById(widget.presetId);
                  if (presetNow == null) return;
                  if (context.read<AuthService>().currentUser == null) {
                    await _showSignInRequired(context);
                    return;
                  }
                  await context.read<PresetsService>().delete(widget.presetId);
                  if (!mounted) return;
                  context.pop();
                },
                style: OutlinedButton.styleFrom(foregroundColor: AiMarkerColors.error, side: BorderSide(color: AiMarkerColors.error.withValues(alpha: 0.35))),
                child: const Text('Delete scheme'),
              ),
          ],
        ),
      ),
    );
  }
}
