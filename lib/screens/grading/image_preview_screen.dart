import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:marking_prokect_v2/app/app_routes.dart';
import 'package:marking_prokect_v2/app/app_state.dart';
import 'package:marking_prokect_v2/models/grading_preset.dart';
import 'package:marking_prokect_v2/services/auth_service.dart';
import 'package:marking_prokect_v2/services/classes_service.dart';
import 'package:marking_prokect_v2/services/ai_grading_service.dart';
import 'package:marking_prokect_v2/services/presets_service.dart';
import 'package:marking_prokect_v2/services/student_class_links_service.dart';
import 'package:marking_prokect_v2/services/students_service.dart';
import 'package:marking_prokect_v2/theme.dart';
import 'package:provider/provider.dart';

class ImagePreviewScreen extends StatefulWidget {
  const ImagePreviewScreen({super.key});

  @override
  State<ImagePreviewScreen> createState() => _ImagePreviewScreenState();
}

class _ImagePreviewScreenState extends State<ImagePreviewScreen> {
  bool _loading = true;
  String? _subject;
  String? _studentName;
  double? _maxScore;
  String? _pickedClassId;

  @override
  void initState() {
    super.initState();
    _analyze();
  }

  Future<void> _analyze() async {
    await Future<void>.delayed(const Duration(milliseconds: 900));

    final draft = context.read<AppState>().draft;
    final subject = switch (draft.mode) {
      _ => 'Physics',
    };

    final students = context.read<StudentsService>().students;
    final student = students.isEmpty ? null : students[Random().nextInt(students.length)];

    setState(() {
      _subject = subject;
      _studentName = student?.name;
      _maxScore = switch (draft.mode) {
        GradingMode.homework => 100,
        GradingMode.testQuiz => 25,
        GradingMode.labReport => 40,
        GradingMode.englishEssay => 25,
      };
    });

    context.read<AppState>().setDetections(subject: _subject, studentName: _studentName, maxScore: _maxScore);

    // Smart class detection
    final auth = context.read<AuthService>().currentUser;
    if (auth == null || student == null) {
      setState(() => _loading = false);
      return;
    }

    final link = context.read<StudentClassLinksService>().findFor(studentId: student.id, subject: subject);
    final classesService = context.read<ClassesService>();

    if (link != null) {
      _pickedClassId = link.classId;
    } else {
      final matches = classesService.bySubject(subject, teacherId: auth.id);
      if (matches.length == 1) {
        _pickedClassId = matches.first.id;
      } else if (matches.length > 1) {
        _pickedClassId = await _showClassPicker(matches.map((c) => _ClassPick(c.id, '${c.name} · ${c.period}', c.room)).toList());
        if (_pickedClassId != null) {
          await context.read<StudentClassLinksService>().upsert(studentId: student.id, classId: _pickedClassId!, subject: subject);
        }
      }
    }

    if (_pickedClassId != null) {
      final presetsService = context.read<PresetsService>();
      final fallback = presetsService.defaultForClass(_pickedClassId!, mode: draft.mode);
      context.read<AppState>().setStudentClassPreset(studentId: student.id, classId: _pickedClassId, presetId: fallback?.id);
    }

    // Auto-detect scheme (best effort). If not signed in, still works using built-in schemes.
    final afterClassDraft = context.read<AppState>().draft;
    if (afterClassDraft.autoDetectScheme && afterClassDraft.imageBytes != null) {
      try {
        final presetsService = context.read<PresetsService>();
        final schemes = presetsService.builtInSchemes;
        final detector = AiGradingService();
        final detectedId = await detector.detectScheme(imageBytes: afterClassDraft.imageBytes!, mode: afterClassDraft.mode, schemes: schemes);
        if (detectedId != null && mounted) {
          context.read<AppState>().setStudentClassPreset(presetId: detectedId);
        }
      } catch (e) {
        debugPrint('ImagePreviewScreen auto-detect failed: $e');
      }
    }

    setState(() => _loading = false);
  }

  Future<String?> _showClassPicker(List<_ClassPick> options) async {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return Container(
          decoration: BoxDecoration(color: cs.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [Expanded(child: Text('Which class is this for?', style: Theme.of(ctx).textTheme.titleLarge)), IconButton(onPressed: () => ctx.pop(), icon: Icon(Icons.close_rounded, color: AiMarkerColors.neutral))]),
              const SizedBox(height: 10),
              for (final o in options)
                ListTile(
                  title: Text(o.title, style: Theme.of(ctx).textTheme.titleSmall),
                  subtitle: Text(o.room == null ? '' : 'Room ${o.room}', style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                  trailing: Icon(Icons.north_east_rounded, color: AiMarkerColors.neutral.withValues(alpha: 0.85)),
                  onTap: () => ctx.pop(o.classId),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final draft = context.watch<AppState>().draft;

    return Scaffold(
      appBar: AppBar(title: const Text('Image Preview'), leading: IconButton(onPressed: () => context.pop(), icon: Icon(Icons.arrow_back_rounded, color: cs.primary))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
          children: [
            if (draft.imageBytes != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: Image.memory(draft.imageBytes!, fit: BoxFit.cover),
              )
            else
              Container(
                height: 240,
                decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: cs.outline.withValues(alpha: 0.22))),
                child: Center(child: Text('No image selected', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AiMarkerColors.neutral))),
              ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: _loading
                    ? Row(
                        children: [
                          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(width: 10),
                          Text('Analyzing...', style: Theme.of(context).textTheme.titleSmall),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(spacing: 10, runSpacing: 10, children: [
                            _Badge(text: _subject == null ? 'Subject: —' : 'Subject: $_subject', color: cs.primary.withValues(alpha: 0.12), textColor: cs.primary),
                            _Badge(text: _studentName == null ? 'Student: —' : 'Student: $_studentName', color: cs.surfaceContainerHighest, textColor: AiMarkerColors.neutral),
                            _Badge(text: _maxScore == null ? 'Max score: —' : 'Max score: ${_maxScore!.round()}', color: Colors.amber.withValues(alpha: 0.12), textColor: Colors.orange),
                          ]),
                          const SizedBox(height: 12),
                          if (draft.classId != null)
                            Text('Class auto-selected ✓', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.secondary, fontWeight: FontWeight.w700))
                          else
                            Text('Class not selected yet', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _loading
                  ? null
                  : () {
                      final draft = context.read<AppState>().draft;
                      final bytes = draft.imageBytes;
                      if (bytes != null) {
                        context.push(AppRoutes.gradingContext, extra: {'imageBytes': bytes, 'fileName': draft.imageFileName});
                      } else {
                        context.push(AppRoutes.gradingContext);
                      }
                    },
              style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: Colors.white),
              child: const Text('Continue to Grading Context'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClassPick {
  final String classId;
  final String title;
  final String? room;
  const _ClassPick(this.classId, this.title, this.room);
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  final Color textColor;
  const _Badge({required this.text, required this.color, required this.textColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999), border: Border.all(color: textColor.withValues(alpha: 0.18))),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: textColor, fontWeight: FontWeight.w800)),
    );
  }
}
