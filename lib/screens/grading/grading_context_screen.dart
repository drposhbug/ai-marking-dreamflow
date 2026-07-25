import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:marking_prokect_v2/app/app_routes.dart';
import 'package:marking_prokect_v2/app/app_state.dart';
import 'package:marking_prokect_v2/models/grading_preset.dart';
import 'package:marking_prokect_v2/services/auth_service.dart';
import 'package:marking_prokect_v2/models/student.dart';
import 'package:marking_prokect_v2/screens/grading/live_scan_screen.dart';
import 'package:marking_prokect_v2/services/ai_grading_service.dart';
import 'package:marking_prokect_v2/services/classes_service.dart';
import 'package:marking_prokect_v2/services/local_store.dart';
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
  final _pageController = PageController(viewportFraction: 0.92);
  int _currentPage = 0;
  String? _answerKeyId;
  String? _answerKeyName;

  bool _didHydrateImageFromRoute = false;

  @override
  void initState() {
    super.initState();
    final draft = context.read<AppState>().draft;
    if (draft.answerKeyId.isNotEmpty) {
      _answerKeyId = draft.answerKeyId;
      _answerKeyName = draft.answerKeyName.isEmpty ? 'Answer key' : draft.answerKeyName;
    }
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
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _retakePage(int index) async {
    final pages = await Navigator.of(context).push<List<ScannedPage>>(
      MaterialPageRoute(builder: (_) => const LiveScanScreen(singleShot: true)),
    );
    if (pages == null || pages.isEmpty || !mounted) return;
    context.read<AppState>().replacePage(index, pages.first);
  }

  void _removePage(int index) {
    final app = context.read<AppState>();
    app.removePage(index);
    final remaining = app.draft.pages.length;
    if (_currentPage >= remaining) {
      setState(() => _currentPage = remaining == 0 ? 0 : remaining - 1);
    }
  }

  Future<void> _chooseAnswerKey() async {
    final auth = context.read<AuthService>().currentUser;
    if (auth == null) return;

    List<AnswerKeySummary> keys = const [];
    try {
      keys = await AiGradingService().listAnswerKeys(teacherId: auth.id);
    } catch (e) {
      debugPrint('listAnswerKeys failed: $e');
    }
    if (!mounted) return;

    final choice = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
              child: Row(
                children: [
                  Expanded(child: Text('Answer key', style: Theme.of(ctx).textTheme.titleLarge)),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.document_scanner_rounded),
              title: const Text('Scan a new answer key'),
              subtitle: const Text('Read once, saved to the cloud, reused for every grade'),
              onTap: () => Navigator.pop(ctx, 'scan'),
            ),
            if (_answerKeyId != null)
              ListTile(
                leading: const Icon(Icons.link_off_rounded),
                title: const Text('Grade without a key'),
                onTap: () => Navigator.pop(ctx, 'none'),
              ),
            if (keys.isNotEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Text('SAVED KEYS', style: TextStyle(fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final k in keys)
                    ListTile(
                      leading: const Icon(Icons.key_rounded),
                      title: Text(k.name),
                      subtitle: Text([
                        if (k.subject != null && k.subject!.isNotEmpty) k.subject!,
                        if (k.totalMarks != null) '${k.totalMarks!.round()} marks',
                      ].join(' · ')),
                      onTap: () => Navigator.pop(ctx, k),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;

    if (choice == 'none') {
      setState(() {
        _answerKeyId = null;
        _answerKeyName = null;
      });
      context.read<AppState>().setAnswerKey();
    } else if (choice == 'scan') {
      await _scanAnswerKey(auth.id);
    } else if (choice is AnswerKeySummary) {
      setState(() {
        _answerKeyId = choice.id;
        _answerKeyName = choice.name;
      });
      context.read<AppState>().setAnswerKey(id: choice.id, name: choice.name);
    }
  }

  Future<void> _scanAnswerKey(String teacherId) async {
    final pages = await Navigator.of(context).push<List<ScannedPage>>(
      MaterialPageRoute(builder: (_) => const LiveScanScreen()),
    );
    if (pages == null || pages.isEmpty || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 18),
            Expanded(child: Text('Reading the answer key…\nThis happens only once.')),
          ],
        ),
      ),
    );
    try {
      final key = await AiGradingService().extractAnswerKey(
        teacherId: teacherId,
        pages: pages.map((p) => p.bytes).toList(growable: false),
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // close progress dialog
      setState(() {
        _answerKeyId = key.id;
        _answerKeyName = key.name;
      });
      context.read<AppState>().setAnswerKey(id: key.id, name: key.name);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Answer key saved: ${key.name}')),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not read the answer key: $e')),
      );
    }
  }

  static const _kAskLinkKey = 'ai_marker.ask_link_student.v1';

  static String _builtInIdForMode(GradingMode mode) => switch (mode) {
    GradingMode.homework => GradingPreset.builtInHomeworkId,
    GradingMode.testQuiz => GradingPreset.builtInTestId,
    GradingMode.labReport => GradingPreset.builtInLabId,
    GradingMode.englishEssay => GradingPreset.builtInEnglishId,
  };

  /// Offer to link the freshly graded result to a student, unless the
  /// teacher previously checked "Don't ask again".
  Future<Student?> _maybeAskLinkStudent() async {
    const store = LocalStore();
    final pref = await store.getString(_kAskLinkKey);
    if (pref == 'never' || !mounted) return null;

    var dontAsk = false;
    final wantsLink = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Link to a student?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('The work has been graded. Do you want to save this result to a student profile?'),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: dontAsk,
                onChanged: (v) => setDialogState(() => dontAsk = v ?? false),
                title: const Text("Don't ask again"),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Choose student')),
          ],
        ),
      ),
    );
    if (dontAsk) await store.setString(_kAskLinkKey, 'never');
    if (wantsLink != true || !mounted) return null;

    final students = context.read<StudentsService>().students;
    final classes = context.read<ClassesService>();
    return showModalBottomSheet<Student>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
              child: Row(
                children: [
                  Expanded(child: Text('Choose student', style: Theme.of(ctx).textTheme.titleLarge)),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
                ],
              ),
            ),
            Flexible(
              child: students.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No students yet — add students from the Classes tab.'),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final s in students)
                          ListTile(
                            leading: CircleAvatar(child: Text(s.name.isEmpty ? '?' : s.name.substring(0, 1))),
                            title: Text(s.name),
                            subtitle: Text(classes.getById(s.classId)?.name ?? s.studentId),
                            onTap: () => Navigator.pop(ctx, s),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _grade() async {
    final auth = context.read<AuthService>().currentUser;
    final draft = context.read<AppState>().draft;

    if (auth == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sign in first.')));
      return;
    }

    if (draft.imageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No image to grade — go back and scan an assignment.')));
      return;
    }

    // No answer key selected → warn that marks will be pure AI judgment.
    if (_answerKeyId == null) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('No answer key'),
          content: const Text(
              'Without an answer key, the marks are entirely the AI\'s own judgment — it works out the answers itself and can make mistakes.\n\nFor accurate, consistent marking, scan or pick your answer key first.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'grade'), child: const Text('Grade anyway')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'key'), child: const Text('Add answer key')),
          ],
        ),
      );
      if (!mounted) return;
      if (choice == 'key') {
        await _chooseAnswerKey();
        return; // key selected — teacher taps Grade again when ready
      }
      if (choice != 'grade') return; // dismissed
    }

    setState(() => _grading = true);
    try {
      // Student, class, and scheme are all optional now — grading works on
      // the scan alone, and the result can be linked to a student afterwards.
      final presetId = draft.presetId ?? _builtInIdForMode(draft.mode);
      final preStudent = draft.studentId == null ? null : context.read<StudentsService>().getById(draft.studentId!);

      final req = AiGradeRequest(
        teacherId: auth.id,
        studentId: draft.studentId ?? '',
        classId: draft.classId ?? '',
        presetId: presetId,
        subject: draft.detectedSubject ?? 'Subject',
        mode: draft.mode,
        criteria: _criteria,
        harshness: _harshness.round(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        overrideUsed: draft.oneTimeOverride,
        imageBytes: draft.imageBytes!,
        pageImages: draft.pages.map((p) => p.bytes).toList(growable: false),
        studentName: preStudent?.name,
        // Pass student grade from DB if available so the edge function
        // doesn't need to detect it from the image.
        studentGrade: null, // TODO: wire up from student model if you store grade level
        answerKeyId: _answerKeyId,
      );

      final ai = AiGradingService();
      final res = await ai.grade(req);
      if (!mounted) return;

      // No student selected before grading? Try the name the AI read off
      // the paper first; only ask when there's no clean roster match.
      var studentId = draft.studentId ?? '';
      var classId = draft.classId ?? '';
      if (studentId.isEmpty) {
        final paperName = res.studentNameOnPaper?.trim().toLowerCase() ?? '';
        if (paperName.isNotEmpty) {
          final matches = context
              .read<StudentsService>()
              .students
              .where((s) => s.name.trim().toLowerCase() == paperName)
              .toList();
          if (matches.length == 1) {
            studentId = matches.first.id;
            if (classId.isEmpty && matches.first.classId.trim().isNotEmpty) {
              classId = matches.first.classId;
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Linked to ${matches.first.name} — name read from the paper.')),
            );
          }
        }
      }
      if (studentId.isEmpty) {
        final linked = await _maybeAskLinkStudent();
        if (linked != null) {
          studentId = linked.id;
          if (classId.isEmpty && linked.classId.trim().isNotEmpty) classId = linked.classId;
        }
      }
      if (!mounted) return;

      final saveReq = AiGradeRequest(
        teacherId: auth.id,
        studentId: studentId,
        classId: classId,
        presetId: presetId,
        subject: draft.detectedSubject ?? 'Subject',
        mode: draft.mode,
        criteria: _criteria,
        harshness: _harshness.round(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        overrideUsed: draft.oneTimeOverride,
        imageBytes: draft.imageBytes!,
        studentName: preStudent?.name,
        studentGrade: null,
      );
      final submission = ai.toSubmission(req: saveReq, res: res);
      await context.read<SubmissionsService>().create(submission);

      if (!mounted) return;

      // Pass the live result and page images directly to ResultScreen so it
      // can show the annotated pages and real feedback immediately.
      context.push(
        '${AppRoutes.result}?submissionId=${submission.id}',
        extra: {
          'gradeResult': res,
          'imageBytes': draft.imageBytes,
          'pageImages': draft.pages.map((p) => p.bytes).toList(growable: false),
        },
      );
    } catch (e) {
      debugPrint('Grading failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Grading failed: $e')));
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
      body: Stack(
        children: [
          SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
          children: [
            if (draft.pages.isNotEmpty) ...[
              SizedBox(
                height: 300,
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  itemCount: draft.pages.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(draft.pages[i].bytes, fit: BoxFit.cover, gaplessPlayback: true),
                          Positioned(
                            top: 10,
                            left: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'Page ${i + 1}',
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 6,
                            right: 6,
                            child: IconButton(
                              onPressed: () => _removePage(i),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.black.withValues(alpha: 0.6),
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.close_rounded, size: 20),
                              tooltip: 'Remove page',
                            ),
                          ),
                          Positioned(
                            bottom: 10,
                            right: 10,
                            child: FilledButton.tonalIcon(
                              onPressed: () => _retakePage(i),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.black.withValues(alpha: 0.6),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                visualDensity: VisualDensity.compact,
                              ),
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              label: const Text('Retake', style: TextStyle(fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (int i = 0; i < draft.pages.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _currentPage ? 18 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: i == _currentPage ? cs.primary : cs.outline.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Text(
                    'Page ${_currentPage + 1} of ${draft.pages.length}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral),
                  ),
                ],
              ),
            ] else
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
            const SizedBox(height: 12),
            Card(
              child: InkWell(
                splashFactory: NoSplash.splashFactory,
                onTap: _grading ? null : _chooseAnswerKey,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(Icons.key_rounded, color: _answerKeyId != null ? cs.primary : AiMarkerColors.neutral),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _answerKeyName == null ? 'No answer key' : 'Answer key: $_answerKeyName',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _answerKeyName == null
                                  ? 'Tap to scan or pick one — marks strictly against your key'
                                  : 'Marking strictly against your key',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: AiMarkerColors.neutral.withValues(alpha: 0.8)),
                    ],
                  ),
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
          // Full-screen loading overlay while the AI marks the work.
          if (_grading)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.55),
                child: Center(
                  child: Card(
                    margin: const EdgeInsets.symmetric(horizontal: 40),
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 56,
                            height: 56,
                            child: CircularProgressIndicator(strokeWidth: 5, color: cs.primary),
                          ),
                          const SizedBox(height: 20),
                          Text('Marking with AI…', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 6),
                          Text(
                            'Reading the work and grading every question.\nThis usually takes 10–30 seconds.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _harshnessLabel(int v) => v <= 3 ? 'Lenient ($v/10)' : (v <= 6 ? 'Balanced ($v/10)' : 'Strict ($v/10)');
}