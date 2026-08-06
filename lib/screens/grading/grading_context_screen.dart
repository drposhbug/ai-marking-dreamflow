import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:marking_prokect_v2/services/drive_picker.dart';
import 'package:marking_prokect_v2/app/app_routes.dart';
import 'package:marking_prokect_v2/app/app_state.dart';
import 'package:marking_prokect_v2/models/grading_preset.dart';
import 'package:marking_prokect_v2/services/auth_service.dart';
import 'package:marking_prokect_v2/screens/grading/live_scan_screen.dart';
import 'package:marking_prokect_v2/services/ai_grading_service.dart';
import 'package:marking_prokect_v2/services/grading_queue_service.dart';
import 'package:marking_prokect_v2/services/classes_service.dart';
import 'package:marking_prokect_v2/services/presets_service.dart';
import 'package:marking_prokect_v2/services/students_service.dart';
import 'package:marking_prokect_v2/services/submissions_service.dart';
import 'package:marking_prokect_v2/theme.dart';
import 'package:provider/provider.dart';

/// Sentinel returned by the key sheet when the trash icon on a saved key is
/// tapped (vs. tapping the row to select it).
class _DeleteKey {
  final AnswerKeySummary key;
  const _DeleteKey(this.key);
}

class GradingContextScreen extends StatefulWidget {
  const GradingContextScreen({super.key});

  @override
  State<GradingContextScreen> createState() => _GradingContextScreenState();
}

class _GradingContextScreenState extends State<GradingContextScreen> {
  bool _grading = false;
  late Map<String, bool> _criteria;
  double _harshness = 5;
  double _gradeLevel = 6;
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
    _gradeLevel = draft.gradeLevel.clamp(1, 13).toDouble();
    // A selected class carries its own grade level — use it automatically.
    final klass = (draft.classId == null || draft.classId!.isEmpty) ? null : context.read<ClassesService>().getById(draft.classId!);
    if (klass?.gradeLevel != null) _gradeLevel = klass!.gradeLevel!.clamp(1, 13).toDouble();
    _notes.text = (preset?.notes ?? draft.notes);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().setMode(mode, criteria: _criteria, harshness: _harshness.round());
      context.read<AppState>().setGradeLevel(_gradeLevel.round());
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
            ListTile(
              leading: const Icon(Icons.add_to_drive_rounded),
              title: const Text('From Google Drive'),
              subtitle: const Text('Pick a photo or PDF of the key from Drive or Files'),
              onTap: () => Navigator.pop(ctx, 'drive'),
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
                      trailing: IconButton(
                        tooltip: 'Delete this key',
                        icon: Icon(Icons.delete_outline_rounded, size: 20, color: AiMarkerColors.neutral.withValues(alpha: 0.8)),
                        onPressed: () => Navigator.pop(ctx, _DeleteKey(k)),
                      ),
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
    } else if (choice == 'drive') {
      await _importKeyFromDrive(auth.id);
    } else if (choice is _DeleteKey) {
      await _deleteAnswerKey(auth.id, choice.key);
    } else if (choice is AnswerKeySummary) {
      setState(() {
        _answerKeyId = choice.id;
        _answerKeyName = choice.name;
      });
      context.read<AppState>().setAnswerKey(id: choice.id, name: choice.name);
    }
  }

  /// Clears the selected key from this draft — marking goes judgment-based.
  void _clearAnswerKey() {
    setState(() {
      _answerKeyId = null;
      _answerKeyName = null;
    });
    context.read<AppState>().setAnswerKey();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Answer key removed for this marking — it stays in your saved keys.')),
    );
  }

  Future<void> _deleteAnswerKey(String teacherId, AnswerKeySummary key) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${key.name}"?'),
        content: const Text(
            'The key is deleted for good — Mark won\'t remember it.\n\nMarking this test again without its key costs noticeably more credits (the answers have to be worked out from scratch) and is less consistent. Keep keys until the whole class set is marked.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AiMarkerColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete key'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await AiGradingService().deleteAnswerKey(teacherId: teacherId, id: key.id);
      if (_answerKeyId == key.id) _clearAnswerKey();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Deleted "${key.name}".')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not delete the key: $e')));
    }
  }

  Future<void> _scanAnswerKey(String teacherId) async {
    final pages = await Navigator.of(context).push<List<ScannedPage>>(
      MaterialPageRoute(builder: (_) => const LiveScanScreen()),
    );
    if (pages == null || pages.isEmpty || !mounted) return;
    await _extractKeyFromPages(teacherId, pages);
  }

  /// Key document straight from the Drive app's picker (Files as fallback) —
  /// photos or PDFs, same as the Answers tab.
  Future<void> _importKeyFromDrive(String teacherId) async {
    final pages = <ScannedPage>[];
    try {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 18),
              Expanded(child: Text('Loading from Google Drive…')),
            ],
          ),
        ),
      );
      DriveImport import;
      try {
        import = await DrivePicker.importScannedPages();
      } finally {
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
      }
      if (!mounted || import.cancelled) return;
      if (import.pages.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          duration: Duration(seconds: 6),
          content: Text('That file couldn\'t be read — pick a photo or a PDF of the key. For a Google Doc, use Share → Save as PDF in Drive first.'),
        ));
        return;
      }
      pages.addAll(import.pages);
    } on DrivePickerUnavailable {
      final res = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'bmp', 'heic', 'pdf'],
        allowMultiple: true,
        withData: true,
      );
      if (res == null || res.files.isEmpty || !mounted) return;
      for (final f in res.files) {
        final bytes = f.bytes;
        if (bytes == null) continue;
        pages.addAll(await pagesFromPickedFile(name: f.name, mime: '', bytes: bytes));
      }
    }
    if (pages.isEmpty || !mounted) return;
    await _extractKeyFromPages(teacherId, pages);
  }

  Future<void> _extractKeyFromPages(String teacherId, List<ScannedPage> pages) async {
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

  static String _builtInIdForMode(GradingMode mode) => switch (mode) {
    GradingMode.homework => GradingPreset.builtInHomeworkId,
    GradingMode.testQuiz => GradingPreset.builtInTestId,
    GradingMode.labReport => GradingPreset.builtInLabId,
    GradingMode.englishEssay => GradingPreset.builtInEnglishId,
  };

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

    // No answer key selected → warn that marks are judgment-based. Written
    // work (essays, labs) has no key to route cheap, so it burns the most
    // credits — the honest moment to point heavy essay-markers at Pro.
    if (_answerKeyId == null) {
      final isWritten = draft.mode == GradingMode.englishEssay || draft.mode == GradingMode.labReport;
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(isWritten ? 'Marking written work' : 'No answer key'),
          content: Text(isWritten
              ? 'Essays and written answers take the deepest reading, so they use the most marking credits per page.\n\nIf you mark writing regularly, the Pro plan\'s bigger credit pool is the best fit.'
              : 'Without an answer key, your assistant works out the answers itself and can make mistakes.\n\nFor accurate, consistent marking, scan or pick your answer key first.'),
          actions: [
            if (isWritten)
              TextButton(onPressed: () => Navigator.pop(ctx, 'plans'), child: const Text('See plans')),
            TextButton(onPressed: () => Navigator.pop(ctx, 'grade'), child: const Text('Grade anyway')),
            if (!isWritten)
              FilledButton(onPressed: () => Navigator.pop(ctx, 'key'), child: const Text('Add answer key'))
            else
              FilledButton(onPressed: () => Navigator.pop(ctx, 'grade'), child: const Text('Mark it')),
          ],
        ),
      );
      if (!mounted) return;
      if (choice == 'key') {
        await _chooseAnswerKey();
        return; // key selected — teacher taps Grade again when ready
      }
      if (choice == 'plans') {
        context.push(AppRoutes.settings);
        return;
      }
      if (choice != 'grade') return; // dismissed
    }

    setState(() => _grading = true);
    try {
      // Student, class, and scheme are all optional — marking works on the
      // scan alone, and the student is auto-linked from the name on the paper.
      final presetId = draft.presetId ?? _builtInIdForMode(draft.mode);
      final preStudent = draft.studentId == null ? null : context.read<StudentsService>().getById(draft.studentId!);
      final regionId = context.read<AppState>().region;
      final teacherFeedback = context.read<AppState>().markingFeedback;
      final pages = draft.pages.map((p) => p.bytes).toList(growable: false);

      final req = AiGradeRequest(
        teacherId: auth.id,
        studentId: draft.studentId ?? '',
        classId: draft.classId ?? '',
        presetId: presetId,
        subject: draft.detectedSubject ?? 'Subject',
        mode: draft.mode,
        // Criteria checkboxes are gone — marking rules handle style: strict
        // per-question for tests, completion only for homework, blanks = 0.
        criteria: const {},
        harshness: _harshness.round(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        overrideUsed: draft.oneTimeOverride,
        imageBytes: draft.imageBytes!,
        pageImages: pages,
        studentName: preStudent?.name,
        studentGrade: null,
        gradeLevel: _gradeLevel.round(),
        region: regionId,
        teacherFeedback: teacherFeedback,
        answerKeyId: _answerKeyId,
      );

      // Marking runs in the background so the teacher can keep scanning —
      // the queue auto-links the student, saves the submission, and notifies
      // when the result is ready in the home-screen tray.
      context.read<GradingQueueService>().enqueue(
            req: req,
            pages: pages,
            students: context.read<StudentsService>(),
            submissions: context.read<SubmissionsService>(),
            label: preStudent?.name,
          );

      // Keep the class, grade level, and answer key for the next paper in
      // the pile — only the scanned pages and student reset.
      context.read<AppState>().prepareNextScan();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marking in the background — keep scanning. You\'ll be notified when it\'s ready.')),
      );
      context.go(AppRoutes.grading);
    } finally {
      if (mounted) setState(() => _grading = false);
    }
  }

  /// Full-screen, pinch-zoomable preview of the scanned pages so the
  /// teacher can check exactly what Mark will be looking at.
  void _expandPage(int index) {
    final pages = context.read<AppState>().draft.pages;
    if (pages.isEmpty) return;
    var current = index.clamp(0, pages.length - 1);
    final pc = PageController(initialPage: current);
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.94),
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog.fullscreen(
          backgroundColor: Colors.transparent,
          child: Stack(
            children: [
              PageView.builder(
                controller: pc,
                onPageChanged: (i) => setDialogState(() => current = i),
                itemCount: pages.length,
                itemBuilder: (context, i) => InteractiveViewer(
                  maxScale: 6,
                  child: Center(child: Image.memory(pages[i].bytes, fit: BoxFit.contain, gaplessPlayback: true)),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(999)),
                        child: Text(
                          'Page ${current + 1} of ${pages.length} — pinch to zoom',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: IconButton.styleFrom(backgroundColor: Colors.black.withValues(alpha: 0.6), foregroundColor: Colors.white),
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).then((_) => pc.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final draft = context.watch<AppState>().draft;
    final student = draft.studentId == null ? null : context.watch<StudentsService>().getById(draft.studentId!);
    final klass = draft.classId == null ? null : context.watch<ClassesService>().getById(draft.classId!);

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
                          GestureDetector(
                            onTap: () => _expandPage(i),
                            child: Image.memory(draft.pages[i].bytes, fit: BoxFit.cover, gaplessPlayback: true),
                          ),
                          Positioned(
                            bottom: 10,
                            left: 10,
                            child: IgnorePointer(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.zoom_in_rounded, color: Colors.white, size: 16),
                                    SizedBox(width: 4),
                                    Text('Tap to inspect', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                            ),
                          ),
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
                          Text(klass == null ? 'Select class' : '${klass.name} · ${klass.period}${klass.gradeLevel != null ? ' · Grade ${klass.gradeLevel}' : ''}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
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
            // Blue and unmissable until a key is attached — a key is the
            // single biggest accuracy lever, so it must not look optional.
            Card(
              color: _answerKeyId == null ? cs.primary.withValues(alpha: 0.08) : null,
              shape: _answerKeyId == null
                  ? RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      side: BorderSide(color: cs.primary.withValues(alpha: 0.55), width: 1.4),
                    )
                  : null,
              child: InkWell(
                splashFactory: NoSplash.splashFactory,
                onTap: _grading ? null : _chooseAnswerKey,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(Icons.key_rounded, color: cs.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _answerKeyName == null ? 'No answer key' : 'Answer key: $_answerKeyName',
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: _answerKeyId == null ? cs.primary : null,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _answerKeyName == null
                                  ? 'Scan, pick a saved key, or pull one from Google Drive'
                                  : 'Marking strictly against your key',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral),
                            ),
                          ],
                        ),
                      ),
                      if (_answerKeyId == null)
                        FilledButton(
                          onPressed: _grading ? null : _chooseAnswerKey,
                          style: FilledButton.styleFrom(
                            backgroundColor: cs.primary,
                            foregroundColor: Colors.white,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('Add key'),
                        )
                      else ...[
                        IconButton(
                          tooltip: 'Remove the key for this marking',
                          onPressed: _grading ? null : _clearAnswerKey,
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.close_rounded, size: 20, color: AiMarkerColors.neutral.withValues(alpha: 0.9)),
                        ),
                        Icon(Icons.chevron_right_rounded, color: AiMarkerColors.neutral.withValues(alpha: 0.8)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Grade level expectations', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [Text('Grade 1', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)), const Spacer(), Text('Grade 12', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral))]),
                    Slider(
                      value: _gradeLevel,
                      min: 1,
                      max: 13,
                      divisions: 12,
                      label: 'Grade ${_gradeLevel.round()}',
                      onChanged: (v) {
                        setState(() => _gradeLevel = v);
                        context.read<AppState>().setGradeLevel(v.round());
                      },
                    ),
                    Text('Marking at Grade ${_gradeLevel.round()} expectations', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w800)),
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
              label: _grading ? const Text('Sending...') : const Text('Mark it →'),
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
                          Text('Sending for marking…', style: Theme.of(context).textTheme.titleMedium),
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

}