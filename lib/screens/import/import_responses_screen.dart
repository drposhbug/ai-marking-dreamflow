import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:marking_prokect_v2/app/app_routes.dart';
import 'package:marking_prokect_v2/app/app_state.dart';
import 'package:marking_prokect_v2/models/grading_preset.dart';
import 'package:marking_prokect_v2/models/student.dart';
import 'package:marking_prokect_v2/models/submission.dart';
import 'package:marking_prokect_v2/models/teacher_class.dart';
import 'package:marking_prokect_v2/services/ai_grading_service.dart';
import 'package:marking_prokect_v2/services/anonymizer.dart';
import 'package:marking_prokect_v2/services/auth_service.dart';
import 'package:marking_prokect_v2/services/classes_service.dart';
import 'package:marking_prokect_v2/services/csv_import.dart';
import 'package:marking_prokect_v2/services/id_factory.dart';
import 'package:marking_prokect_v2/services/import_run.dart';
import 'package:marking_prokect_v2/services/student_class_links_service.dart';
import 'package:marking_prokect_v2/services/students_service.dart';
import 'package:marking_prokect_v2/services/submissions_service.dart';
import 'package:marking_prokect_v2/theme.dart';
import 'package:provider/provider.dart';

/// Import a Google Form's responses (or any CSV) and mark the whole class
/// at once: multiple choice is checked on the phone for free, written
/// answers go to the AI — one call per question, so every student's answer
/// is judged by the same reading.
class ImportResponsesScreen extends StatefulWidget {
  const ImportResponsesScreen({super.key});

  @override
  State<ImportResponsesScreen> createState() => _ImportResponsesScreenState();
}

class _ImportResponsesScreenState extends State<ImportResponsesScreen> {
  ParsedSheet? _sheet;
  String _fileName = '';
  String? _classId;
  bool _marking = false;

  Future<void> _pickCsv() async {
    try {
      // FileType.any: Sheets/Drive exports often arrive with no extension
      // and a custom filter greys them out. The parser sorts out the rest.
      final res = await FilePicker.pickFiles(type: FileType.any, withData: true);
      final f = res?.files.firstOrNull;
      final bytes = f?.bytes;
      if (f == null || bytes == null) return;
      final rows = CsvImport.parse(utf8.decode(bytes, allowMalformed: true));
      final sheet = CsvImport.analyze(rows);
      if (!mounted) return;
      if (sheet.rows.isEmpty || sheet.questions.isEmpty) {
        _snack('That file has no student responses. Export the form\'s responses as CSV and try again.');
        return;
      }
      setState(() {
        _sheet = sheet;
        _fileName = f.name;
      });
    } catch (e) {
      debugPrint('CSV pick failed: $e');
      _snack('Couldn\'t read that file as a spreadsheet.');
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  /// The MC columns still missing a correct answer — marking is blocked
  /// until each has one (or the teacher switches the column type).
  List<ImportColumn> get _mcMissingKey =>
      (_sheet?.questions ?? const []).where((q) => q.kind == ImportColumnKind.multipleChoice && q.correctAnswer.trim().isEmpty).toList();

  Future<void> _mark() async {
    final sheet = _sheet;
    final auth = context.read<AuthService>().currentUser;
    if (sheet == null || auth == null) return;
    final classId = _classId;
    if (classId == null) return _snack('Pick the class these responses belong to.');
    if (_mcMissingKey.isNotEmpty) {
      return _snack('Set the correct answer for: ${_mcMissingKey.map((q) => q.header).take(3).join(", ")}');
    }
    final included = sheet.questions.where((q) => q.kind != ImportColumnKind.skip).toList();
    if (included.isEmpty) return _snack('Every question is set to Skip — nothing to mark.');

    final classes = context.read<ClassesService>();
    final students = context.read<StudentsService>();
    final links = context.read<StudentClassLinksService>();
    final submissions = context.read<SubmissionsService>();
    final appState = context.read<AppState>();
    final klass = classes.getById(classId);
    final subject = klass?.subject ?? 'General';

    const checkpoints = ImportCheckpoints();
    final importId = ImportCheckpoints.idFor(classId: classId, headers: sheet.headers);
    final alreadyFiled = (await checkpoints.load(importId)).filed;
    if (!mounted) return;
    // A file this class has already been marked from. Running it again would
    // buy every written answer a second time and leave two results under each
    // child's name, so ask — and make the safe answer the easy one.
    if (sheet.rows.isNotEmpty && alreadyFiled.length >= sheet.rows.length) {
      final again = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Already marked'),
          content: Text('These ${sheet.rows.length} responses have already been marked into '
              '${klass?.name ?? 'this class'} and are on your dashboard. Marking them again '
              'costs credits for the written questions and gives every student a second result.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Mark again')),
            FilledButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('See the results')),
          ],
        ),
      );
      if (again != true) {
        if (mounted) context.go(AppRoutes.dashboard);
        return;
      }
      await checkpoints.forget(importId);
    }
    if (!mounted) return;

    // Answers are already anonymous — they go up keyed by row number, never
    // by name. Scrub any name a student typed into their own answer (signing
    // an essay, naming a classmate) as well.
    final rosterNames = [
      for (var r = 0; r < sheet.rows.length; r++) sheet.studentName(r),
      ...students.byClass(classId).map((s) => s.name),
    ];
    final maxScore = included.fold<double>(0, (s, q) => s + q.marks);
    final written = included.where((q) => q.kind != ImportColumnKind.multipleChoice).toList();
    final ai = AiGradingService();
    final built = <int, Submission>{};

    setState(() => _marking = true);
    var stopRequested = false;
    var label = written.isEmpty ? 'Saving results…' : 'Marking the written answers…';
    var fraction = 0.0;
    // Nullable, and reassigned on every rebuild: the first count can land
    // before the dialog has had a frame to build in, and the builder runs
    // again each time it is refreshed.
    StateSetter? refresh;

    // Held as a route rather than closed through the builder's context, for
    // the reason blocking_progress.dart spells out: a run that finishes
    // before the dialog has painted leaves nothing to pop with.
    final navigator = Navigator.of(context, rootNavigator: true);
    final progressRoute = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        // Back must not take the dialog away from a run that is still going.
        // This is the whole of defect two: a teacher who walked out mid-import
        // never found out whether it had worked, so she ran it again and paid
        // twice. Stop is the way out, and it keeps everything already done.
        canPop: false,
        child: AlertDialog(
          content: StatefulBuilder(builder: (ctx, setInner) {
            refresh = setInner;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: LinearProgressIndicator(value: fraction == 0 ? null : fraction),
                ),
                const SizedBox(height: 10),
                Text(
                  'You can stop. Everything marked so far is kept, and running this file '
                  'again picks up where it left off without charging twice.',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral),
                ),
              ],
            );
          }),
          actions: [
            TextButton(onPressed: () => stopRequested = true, child: const Text('Stop')),
          ],
        ),
      ),
    );
    unawaited(navigator.push(progressRoute));

    try {
      final outcome = await runImport(
        sheet: sheet,
        questions: included,
        importId: importId,
        checkpoints: checkpoints,
        onProgress: (p) {
          label = p.phase == ImportPhase.marking
              ? 'Marking "${p.question}" (${p.done} of ${p.total})…'
              : 'Saving ${p.done} of ${p.total} students…';
          fraction = p.total == 0 ? 0 : p.done / p.total;
          refresh?.call(() {});
        },
        isStopped: () => stopRequested,
        markQuestion: (q, rows) async {
          final answers = <Map<String, dynamic>>[];
          for (final r in rows) {
            final raw = q.index < sheet.rows[r].length ? sheet.rows[r][q.index].trim() : '';
            final text = appState.anonymizeUploads ? Anonymizer.scrubNames(raw, rosterNames) : raw;
            answers.add({'i': r, 'text': text.isEmpty ? '(no answer)' : text});
          }
          final res = await ai.markResponses(
            teacherId: auth.id,
            subject: subject,
            gradeLevel: klass?.gradeLevel,
            harshness: appState.defaultHarshness,
            questions: [
              {
                'label': q.header,
                'prompt': q.header,
                'kind': q.kind == ImportColumnKind.paragraph ? 'paragraph' : 'short',
                'maxMarks': q.marks,
                if (q.keyAnswer.trim().isNotEmpty) 'keyAnswer': q.keyAnswer.trim(),
                'answers': answers,
              }
            ],
          );
          // One question per call, so the marks come back as the only entry.
          final byRow = res.isEmpty ? const <int, Map<String, dynamic>>{} : res.first;
          return {
            for (final r in rows)
              r: ImportRowMark(
                (byRow[r]?['score'] as num?)?.toDouble() ?? 0,
                byRow[r]?['correct'] == true,
                (byRow[r]?['feedback'] ?? '').toString(),
              ),
          };
        },
        prepareRow: (r, rowMarks) async {
          final name = sheet.studentName(r);
          // Re-read the roster each row so two rows with the same name share
          // one student instead of creating a duplicate.
          var student = students.byClass(classId).cast<Student?>().firstWhere(
                (s) => s!.name.trim().toLowerCase() == name.trim().toLowerCase(),
                orElse: () => null,
              );
          student ??= await students.create(teacherId: auth.id, classId: classId, name: name, studentId: '');
          await links.upsert(studentId: student.id, classId: classId, subject: subject);

          final score = rowMarks.values.fold<double>(0, (s, m) => s + m.score);
          final breakdown = [
            for (final q in included)
              CriterionResult(
                name: q.header.length > 60 ? '${q.header.substring(0, 57)}…' : q.header,
                score: rowMarks[q.index]?.score ?? 0,
                maxScore: q.marks,
                feedback: rowMarks[q.index]?.feedback ?? '',
              ),
          ];
          final full = [for (final q in included) if (rowMarks[q.index]?.correct ?? false) q.header];
          final weak = [
            for (final q in included)
              if (!(rowMarks[q.index]?.correct ?? true) && (rowMarks[q.index]?.score ?? 0) <= q.marks / 2) q.header,
          ];
          final pct = maxScore <= 0 ? 0.0 : (score / maxScore * 100);

          final result = AiGradeResult(
            detectedSubject: subject,
            detectedGrade: klass?.gradeLevel,
            provider: 'import',
            studentNameOnPaper: name,
            gradingFormat: 'percentage',
            percentage: pct,
            percentageDisplay: '${pct.round()}%',
            level: null,
            levelDisplay: null,
            rawScore: score,
            maxScore: maxScore,
            summary: 'Imported from $_fileName — ${score.toStringAsFixed(score.truncateToDouble() == score ? 0 : 1)}/${maxScore.toStringAsFixed(maxScore.truncateToDouble() == maxScore ? 0 : 1)}. '
                '${weak.isEmpty ? 'Solid across the board.' : 'Review: ${weak.take(2).join(", ")}.'}',
            strengths: full.take(3).toList(),
            improvements: weak.take(3).toList(),
            criteriaBreakdown: breakdown,
            annotations: const [],
            rawText: '',
            confidence: written.isEmpty ? 98 : 88,
            flags: const [],
            triageStatus: TriageStatus.graded,
          );

          final now = DateTime.now();
          final id = 'sub_${IdFactory.newId()}';
          built[r] = Submission(
            id: id,
            teacherId: auth.id,
            studentId: student.id,
            classId: classId,
            presetId: GradingPreset.builtInTestId,
            subject: subject,
            gradingMode: GradingMode.testQuiz,
            score: score,
            maxScore: maxScore,
            feedback: result.summary,
            triageStatus: TriageStatus.graded,
            overrideUsed: false,
            triageFlags: const [],
            confidence: result.confidence,
            createdAt: now,
            updatedAt: now,
            resultJson: result.toJson(),
          );
          return id;
        },
        fileRows: (rows) => submissions.createAll([for (final r in rows) built[r]!]),
      );

      if (!mounted) return;
      if (progressRoute.isActive) navigator.removeRoute(progressRoute);
      _snack(_outcomeMessage(outcome));
      // A stopped run stays put, so finishing it is one more tap rather than
      // finding her way back to this screen.
      if (!outcome.stopped && outcome.saved > 0) context.go(AppRoutes.dashboard);
    } on UsageLimitException catch (e) {
      // The spinner comes down first, so the reason is the thing she is
      // looking at rather than something behind a dialog.
      if (progressRoute.isActive) navigator.removeRoute(progressRoute);
      if (mounted) _snack(e.message);
    } catch (e) {
      debugPrint('Import marking failed: $e');
      if (progressRoute.isActive) navigator.removeRoute(progressRoute);
      if (mounted) {
        _snack('Marking didn\'t finish: ${e.toString().replaceFirst('Exception: ', '')} '
            'Run this file again to carry on — you won\'t be charged twice.');
      }
    } finally {
      if (progressRoute.isActive) navigator.removeRoute(progressRoute);
      if (mounted) setState(() => _marking = false);
    }
  }

  /// What actually happened, in the terms the teacher was worried about:
  /// who is marked, who was already done, and what is left.
  String _outcomeMessage(ImportRunOutcome o) {
    final parts = <String>[];
    if (o.saved > 0) parts.add('Marked ${o.saved} student${o.saved == 1 ? '' : 's'}');
    if (o.alreadySaved > 0) parts.add('${o.alreadySaved} were already marked from this file');
    if (o.failed > 0) parts.add('${o.failed} couldn\'t be filed');
    if (o.stopped) {
      return '${parts.isEmpty ? 'Stopped' : '${parts.join(' · ')} — stopped there'}. '
          'Run this file again to finish the rest; the marks already bought are kept.';
    }
    if (parts.isEmpty) return 'Nothing left to mark in this file.';
    return '${parts.join(' · ')} — they\'re on your dashboard.';
  }

  @override
  Widget build(BuildContext context) {
    final sheet = _sheet;
    final classes = context.watch<ClassesService>().classes;

    // Leaving mid-run is blocked rather than allowed-and-recovered: the work
    // is credits being spent, and a teacher who walks away from it has no way
    // of knowing what she has bought. Stop, in the progress dialog, is the
    // honest exit — it keeps what is done and says so.
    return PopScope(
      canPop: !_marking,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _marking ? null : () => context.pop(),
          ),
          title: const Text('Import responses'),
        ),
        body: sheet == null ? _pickerBody() : _mappingBody(sheet, classes),
        bottomNavigationBar: sheet == null
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: FilledButton.icon(
                    onPressed: _marking ? null : _mark,
                    icon: _marking
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.checklist_rounded),
                    label: Text(_marking ? 'Marking…' : 'Mark ${sheet.rows.length} students'),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _pickerBody() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: AiMarkerColors.secondary.withValues(alpha: 0.10),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.bolt_rounded, color: AiMarkerColors.secondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('The fastest way to mark', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(
                        'Nothing to photograph, nothing to line up, no handwriting to read. If you can set a quiz as a Google Form, this is the way to run it — a class set comes back marked in about a minute, and the multiple choice costs no credits.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.45),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('From a Google Form', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  '1. Open your form → Responses → the Sheets icon.\n'
                  '2. In Sheets: File → Download → Comma-separated values (.csv).\n'
                  '3. Pick that file below.\n\n'
                  'Any spreadsheet works, as long as each row is one student.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.5),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _pickCsv,
          icon: const Icon(Icons.upload_file_rounded),
          label: const Text('Choose CSV file'),
        ),
        const SizedBox(height: 10),
        Text(
          'Multiple choice is marked on your phone for free. Only written answers use marking credits — and each question is marked across the whole class in one pass, so it\'s consistent.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.4),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _mappingBody(ParsedSheet sheet, List<TeacherClass> classes) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        Card(
          child: ListTile(
            leading: Icon(Icons.table_chart_rounded, color: cs.primary),
            title: Text(_fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${sheet.rows.length} students · ${sheet.questions.length} questions'
                '${sheet.nameColumn >= 0 ? ' · names from "${sheet.headers[sheet.nameColumn]}"' : ' · no name column found'}'),
            trailing: TextButton(onPressed: _marking ? null : _pickCsv, child: const Text('Change')),
          ),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          // Keyed so a class created on this screen shows as picked.
          key: ValueKey(_classId),
          initialValue: _classId,
          decoration: const InputDecoration(labelText: 'Class', border: OutlineInputBorder()),
          items: [for (final c in classes) DropdownMenuItem(value: c.id, child: Text(c.label))],
          onChanged: _marking ? null : (v) => setState(() => _classId = v),
        ),
        // A brand-new teacher reaches this screen from onboarding with no
        // class yet, and used to be told to go to a Classes tab onboarding
        // doesn't have. Marking creates the students from the name column,
        // so a class is all that is missing — make it here.
        if (classes.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              onPressed: _marking ? null : _createClassHere,
              icon: const Icon(Icons.add_rounded),
              label: Text('Create a class for these ${sheet.rows.length} students'),
            ),
          ),
        const SizedBox(height: 16),
        Text('QUESTIONS', style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.2, color: AiMarkerColors.neutral)),
        const SizedBox(height: 8),
        for (final q in sheet.questions) _questionCard(sheet, q),
      ],
    );
  }

  /// Makes the class the responses will be filed into, without leaving the
  /// screen. The students themselves are added when the file is marked.
  Future<void> _createClassHere() async {
    final auth = context.read<AuthService>().currentUser;
    if (auth == null) return;
    final subject = TextEditingController();
    final period = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New class'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: subject, autofocus: true, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Subject', hintText: 'e.g. Science')),
            const SizedBox(height: 8),
            TextField(controller: period, decoration: const InputDecoration(labelText: 'Period (optional)', hintText: 'e.g. 2')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create class')),
        ],
      ),
    );
    final s = subject.text.trim();
    final p = period.text.trim();
    subject.dispose();
    period.dispose();
    if (ok != true || s.isEmpty || !mounted) return;
    final klass = await context.read<ClassesService>().create(
          teacherId: auth.id,
          name: p.isEmpty ? s : '$s $p',
          subject: s,
          period: p,
        );
    if (!mounted) return;
    setState(() => _classId = klass.id);
    _snack('Created ${klass.label}. The students are added when you mark.');
  }

  Widget _questionCard(ParsedSheet sheet, ImportColumn q) {
    final cs = Theme.of(context).colorScheme;
    final options = q.distinctAnswers(sheet.rows);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(q.header, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                for (final (kind, label) in const [
                  (ImportColumnKind.multipleChoice, 'Multiple choice'),
                  (ImportColumnKind.shortAnswer, 'Short answer'),
                  (ImportColumnKind.paragraph, 'Paragraph'),
                  (ImportColumnKind.skip, 'Skip'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: q.kind == kind,
                    onSelected: _marking ? null : (_) => setState(() => q.kind = kind),
                  ),
              ],
            ),
            if (q.kind == ImportColumnKind.multipleChoice) ...[
              const SizedBox(height: 10),
              Text('Correct answer', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final o in options.take(8))
                    ChoiceChip(
                      label: Text(o.length > 40 ? '${o.substring(0, 37)}…' : o),
                      selected: q.correctAnswer == o,
                      selectedColor: cs.primary.withValues(alpha: 0.18),
                      onSelected: _marking ? null : (_) => setState(() => q.correctAnswer = o),
                    ),
                ],
              ),
            ],
            if (q.kind == ImportColumnKind.shortAnswer || q.kind == ImportColumnKind.paragraph) ...[
              const SizedBox(height: 10),
              TextFormField(
                initialValue: q.keyAnswer,
                decoration: const InputDecoration(
                  labelText: 'Model answer (optional — helps the AI mark your way)',
                  border: OutlineInputBorder(),
                ),
                minLines: 1,
                maxLines: 3,
                enabled: !_marking,
                onChanged: (v) => q.keyAnswer = v,
              ),
            ],
            if (q.kind != ImportColumnKind.skip) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('Marks:', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
                    onPressed: _marking || q.marks <= 0.5 ? null : () => setState(() => q.marks = q.marks - (q.marks <= 1 ? 0.5 : 1)),
                  ),
                  Text(q.marks.truncateToDouble() == q.marks ? q.marks.toStringAsFixed(0) : q.marks.toStringAsFixed(1),
                      style: Theme.of(context).textTheme.titleSmall),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                    onPressed: _marking ? null : () => setState(() => q.marks = q.marks + (q.marks < 1 ? 0.5 : 1)),
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
