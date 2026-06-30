import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:marking_prokect_v2/app/app_routes.dart';
import 'package:marking_prokect_v2/app/app_state.dart';
import 'package:marking_prokect_v2/models/grading_preset.dart';
import 'package:marking_prokect_v2/services/auth_service.dart';
import 'package:marking_prokect_v2/services/ai_grading_service.dart';
import 'package:marking_prokect_v2/services/classes_service.dart';
import 'package:marking_prokect_v2/services/presets_service.dart';
import 'package:marking_prokect_v2/services/students_service.dart';
import 'package:marking_prokect_v2/services/submissions_service.dart';
import 'package:marking_prokect_v2/theme.dart';
import 'package:provider/provider.dart';

class GradingContextScreen extends StatefulWidget {
  const GradingContextScreen({super.key});

  @override
  State<GradingContextScreen> createState() => _GradingContextScreenState();
}

class _GradingContextScreenState extends State<GradingContextScreen> {
  bool _grading = false;
  late Map<String, bool> _criteria;
  double _harshness = 5;
  final _notes = TextEditingController();

  bool _didHydrateImageFromRoute = false;

  @override
  void initState() {
    super.initState();
    final draft = context.read<AppState>().draft;
    final preset = draft.presetId == null ? null : context.read<PresetsService>().getById(draft.presetId!);
    final mode = preset?.gradingMode ?? draft.mode;
    final labels = PresetsService.criteriaLabels(mode);
    final baseCriteria = preset?.criteria ?? {for (final l in labels) l: true};
    _criteria = {for (final l in labels) l: (baseCriteria[l] == true)};
    _harshness = (preset?.harshness ?? draft.harshness).clamp(1, 10).toDouble();
    _notes.text = (preset?.notes ?? draft.notes);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().setMode(mode, criteria: _criteria, harshness: _harshness.round());
      context.read<AppState>().setNotes(_notes.text);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didHydrateImageFromRoute) return;
    _didHydrateImageFromRoute = true;

    final extra = GoRouterState.of(context).extra;
    final app = context.read<AppState>();
    if (app.draft.imageBytes != null) return;

    if (extra is Map) {
      final bytes = extra['imageBytes'];
      final fileName = extra['fileName'];
      if (bytes is Uint8List) {
        app.setImageBytes(bytes: bytes, fileName: fileName is String ? fileName : null);
      }
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _grade() async {
    final auth = context.read<AuthService>().currentUser;
    final draft = context.read<AppState>().draft;
    if (auth == null || draft.studentId == null || draft.classId == null || draft.presetId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select student, class, and marking scheme first.')));
      return;
    }

    setState(() => _grading = true);
    try {
      final req = AiGradeRequest(
        teacherId: auth.id,
        studentId: draft.studentId!,
        classId: draft.classId!,
        presetId: draft.presetId!,
        subject: draft.detectedSubject ?? 'Subject',
        mode: draft.mode,
        criteria: _criteria,
        harshness: _harshness.round(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        overrideUsed: draft.oneTimeOverride,
      );

      final ai = AiGradingService();
      final res = await ai.grade(req);
      final submission = ai.toSubmission(req: req, res: res);
      await context.read<SubmissionsService>().create(submission);

      if (!mounted) return;
      context.push('${AppRoutes.result}?submissionId=${submission.id}');
    } catch (e) {
      debugPrint('Grading failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Grading failed.')));
    } finally {
      if (mounted) setState(() => _grading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final draft = context.watch<AppState>().draft;
    final student = draft.studentId == null ? null : context.watch<StudentsService>().getById(draft.studentId!);
    final klass = draft.classId == null ? null : context.watch<ClassesService>().getById(draft.classId!);
    final preset = draft.presetId == null ? null : context.watch<PresetsService>().getById(draft.presetId!);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: () => context.pop(), icon: Icon(Icons.arrow_back_rounded, color: cs.primary)),
        title: const Text('Grading Setup'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
          children: [
            if (draft.imageBytes != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Image.memory(draft.imageBytes!, fit: BoxFit.cover),
                ),
              )
            else
              Container(
                height: 220,
                decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: cs.outline.withValues(alpha: 0.22))),
                child: Center(child: Text('No image selected', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AiMarkerColors.neutral))),
              ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    CircleAvatar(radius: 18, backgroundColor: cs.primary.withValues(alpha: 0.12), child: Text(student?.name.substring(0, 1) ?? '?', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w800))),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(student?.name ?? 'Student', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 2),
                          Text(klass == null ? 'Select class' : '${klass.name} · ${klass.period}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                        ],
                      ),
                    ),
                    if (draft.detectedSubject != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999), border: Border.all(color: cs.primary.withValues(alpha: 0.18))),
                        child: Text(draft.detectedSubject!, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w800)),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.verified_rounded, color: cs.secondary),
                    const SizedBox(width: 10),
                    Expanded(child: Text(preset == null ? 'Marking scheme not loaded' : 'Marking scheme loaded: ${preset.name}', style: Theme.of(context).textTheme.titleSmall)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('What to grade on', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: [
                    for (final entry in _criteria.entries)
                      CheckboxListTile(
                        value: entry.value,
                        onChanged: (v) {
                          setState(() => _criteria = {..._criteria, entry.key: v ?? false});
                          context.read<AppState>().setCriteria(_criteria);
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(entry.key, style: Theme.of(context).textTheme.bodyMedium),
                        activeColor: cs.primary,
                        checkboxShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Harshness', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [Text('Lenient', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)), const Spacer(), Text('Strict', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral))]),
                    Slider(
                      value: _harshness,
                      min: 1,
                      max: 10,
                      divisions: 9,
                      label: _harshnessLabel(_harshness.round()),
                      onChanged: (v) {
                        setState(() => _harshness = v);
                        context.read<AppState>().setHarshness(v.round());
                      },
                    ),
                    Text(_harshnessLabel(_harshness.round()), style: Theme.of(context).textTheme.labelLarge?.copyWith(color: _harshness.round() >= 7 ? AiMarkerColors.error : (_harshness.round() <= 3 ? AiMarkerColors.secondary : Colors.orange), fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _notes,
              maxLines: 4,
              onChanged: (v) => context.read<AppState>().setNotes(v),
              decoration: const InputDecoration(labelText: 'Anything specific to watch for?', hintText: 'e.g., Be extra strict on units and significant figures.'),
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Apply to this assignment only', style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 2),
                          Text("Changes won't save to your scheme", style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                        ],
                      ),
                    ),
                    Switch(
                      value: draft.oneTimeOverride,
                      onChanged: (v) => context.read<AppState>().setOneTimeOverride(v),
                      activeColor: cs.secondary,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _grading ? null : _grade,
              style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: Colors.white),
              icon: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
              label: _grading ? const Text('Grading...') : const Text('Grade with AI →'),
            ),
          ],
        ),
      ),
    );
  }

  String _harshnessLabel(int v) => v <= 3 ? 'Lenient ($v/10)' : (v <= 6 ? 'Balanced ($v/10)' : 'Strict ($v/10)');
}
