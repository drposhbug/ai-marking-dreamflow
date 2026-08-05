import 'dart:typed_data';
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:marking_prokect_v2/app/app_routes.dart';
import 'package:marking_prokect_v2/app/app_state.dart';
import 'package:marking_prokect_v2/models/teacher_class.dart';
import 'package:marking_prokect_v2/screens/grading/live_scan_screen.dart';
import 'package:marking_prokect_v2/screens/grading/web_image_picker.dart';
import 'package:marking_prokect_v2/services/document_processor.dart';
import 'package:marking_prokect_v2/services/drive_picker.dart';
import 'package:marking_prokect_v2/services/auth_service.dart';
import 'package:marking_prokect_v2/services/classes_service.dart';
import 'package:marking_prokect_v2/services/grading_queue_service.dart';
import 'package:marking_prokect_v2/services/students_service.dart';
import 'package:marking_prokect_v2/services/submissions_service.dart';
import 'package:marking_prokect_v2/theme.dart';
import 'package:marking_prokect_v2/widgets/pill.dart';
import 'package:marking_prokect_v2/widgets/teacher_topbar.dart';
import 'package:provider/provider.dart';

class GradingHomeScreen extends StatefulWidget {
  const GradingHomeScreen({super.key});

  @override
  State<GradingHomeScreen> createState() => _GradingHomeScreenState();
}

class _GradingHomeScreenState extends State<GradingHomeScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<_StudentSuggestion> _studentHits = const [];

  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _handlePickedFile(XFile? image) async {
    if (image == null) return;
    try {
      final Uint8List bytes = await image.readAsBytes();
      // Gallery photos get the same scanner treatment as live scans:
      // EXIF/sideways rotation, straightening, contrast, and sharpening.
      final processed = await DocumentProcessor.processPage(bytes);
      if (!mounted) return;
      context.read<AppState>().setImageBytes(bytes: processed, fileName: image.name);
      context.push(AppRoutes.gradingContext, extra: {'imageBytes': processed, 'fileName': image.name});
    } catch (e) {
      debugPrint('Failed to read picked image bytes: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not read image.')));
    }
  }

  /// Asks which class the scan is for so grading automatically uses that
  /// class's grade level. Returns false when the teacher dismisses the sheet
  /// (cancels the scan). Skipped silently when no classes exist yet.
  Future<bool> _askWhichClass() async {
    final classes = context.read<ClassesService>().classes;
    if (classes.isEmpty) return true;
    final draft = context.read<AppState>().draft;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ClassPickerSheet(classes: classes, currentId: draft.classId),
    );
    if (picked == null || !mounted) return false;
    final app = context.read<AppState>();
    app.setStudentClassPreset(classId: picked); // '' = no class
    if (picked.isNotEmpty) {
      final k = classes.cast<TeacherClass?>().firstWhere((c) => c?.id == picked, orElse: () => null);
      if (k?.gradeLevel != null) app.setGradeLevel(k!.gradeLevel!);
    }
    return true;
  }

  Future<void> _pickFromCamera() async {
    final ok = await _askWhichClass();
    if (!ok || !mounted) return;
    try {
      // Live auto-scan camera: holds the preview open and auto-captures
      // each page once it's held steady, so the teacher can keep sliding
      // assignments through. Returns every captured page when the teacher
      // taps Done; an empty list means the scan was cancelled.
      if (!mounted) return;
      final pages = await Navigator.of(context).push<List<ScannedPage>>(
        MaterialPageRoute(builder: (_) => const LiveScanScreen()),
      );
      if (pages == null || pages.isEmpty) return;
      if (!mounted) return;
      context.read<AppState>().setPages(pages);
      context.push(AppRoutes.gradingContext);
    } catch (e) {
      debugPrint('Pick from camera failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open camera.')));
    }
  }

  /// Multi-select images via the system document picker (Drive included);
  /// each one gets the full scanner treatment.
  Future<List<ScannedPage>> _pickPagesFromFiles() async {
    final res = await FilePicker.pickFiles(type: FileType.image, allowMultiple: true, withData: true);
    if (res == null || res.files.isEmpty) return const [];
    final pages = <ScannedPage>[];
    for (final f in res.files) {
      final bytes = f.bytes;
      if (bytes == null) continue;
      final processed = await DocumentProcessor.processPage(bytes);
      pages.add(ScannedPage(bytes: processed, fileName: f.name));
    }
    return pages;
  }

  Future<void> _pickFromGallery() async {
    final ok = await _askWhichClass();
    if (!ok || !mounted) return;
    try {
      if (kIsWeb) {
        final picked = await pickWebImage(captureEnvironmentCamera: false);
        if (picked == null) return;
        final processed = await DocumentProcessor.processPage(picked.bytes);
        if (!mounted) return;
        context.read<AppState>().setImageBytes(bytes: processed, fileName: picked.name);
        context.push(AppRoutes.gradingContext, extra: {'imageBytes': processed, 'fileName': picked.name});
        return;
      }

      final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      await _handlePickedFile(image);
    } catch (e) {
      debugPrint('Pick from gallery failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open gallery.')));
    }
  }

  /// Assignment pages straight from the Google Drive app's own picker;
  /// falls back to the system file picker when Drive isn't installed.
  /// Multi-select supported; every page gets the scanner treatment.
  Future<void> _pickFromDrive() async {
    final ok = await _askWhichClass();
    if (!ok || !mounted) return;
    try {
      List<ScannedPage> pages;
      try {
        final picked = await DrivePicker.pickImages();
        pages = <ScannedPage>[];
        for (final f in picked) {
          final processed = await DocumentProcessor.processPage(f.bytes);
          pages.add(ScannedPage(bytes: processed, fileName: f.name));
        }
      } on DrivePickerUnavailable {
        pages = await _pickPagesFromFiles();
      }
      if (pages.isEmpty || !mounted) return;
      context.read<AppState>().setPages(pages);
      context.push(AppRoutes.gradingContext);
    } catch (e) {
      debugPrint('Pick from Drive failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open Google Drive.')));
    }
  }

  void _onSearchChanged(String value) {
    final auth = context.read<AuthService>();
    final teacherId = auth.currentUser?.id;
    if (teacherId == null) return;

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 160), () async {
      final students = context.read<StudentsService>();
      final res = await students.searchRemote(value, teacherId: teacherId);
      if (!mounted) return;
      setState(() {
        _studentHits = res.map((s) => _StudentSuggestion(studentId: s.id, name: s.name, studentCode: s.studentId, classId: s.classId)).toList(growable: false);
      });
    });
  }

  void _selectStudent(_StudentSuggestion s) {
    final app = context.read<AppState>();
    final classId = s.classId.trim().isEmpty ? app.draft.classId : s.classId;
    app.setStudentClassPreset(studentId: s.studentId, classId: classId);
    // The student's class carries the grade level the AI marks at.
    if (classId != null && classId.trim().isNotEmpty) {
      final k = context.read<ClassesService>().getById(classId);
      if (k?.gradeLevel != null) app.setGradeLevel(k!.gradeLevel!);
    }
    setState(() => _studentHits = const []);
    _search.text = s.name;
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    final state = context.watch<AppState>();
    final classes = context.watch<ClassesService>().classes;
    final queue = context.watch<GradingQueueService>();
    final selectedClass = (state.draft.classId == null || state.draft.classId!.isEmpty)
        ? null
        : classes.cast<TeacherClass?>().firstWhere((c) => c?.id == state.draft.classId, orElse: () => null);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
          children: [
            TeacherTopbar(title: 'Markless', onBell: () {}),
            const SizedBox(height: 14),
            Text('Good morning,', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AiMarkerColors.neutral)),
            const SizedBox(height: 2),
            Text('${user?.name.isNotEmpty == true ? user!.name : 'Teacher'} 👋', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: _pickFromCamera,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  gradient: const LinearGradient(colors: [AiMarkerColors.primary, AiMarkerColors.tertiary], begin: Alignment.topLeft, end: Alignment.bottomRight),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.18), border: Border.all(color: Colors.white.withValues(alpha: 0.22))),
                      child: const Icon(Icons.photo_camera_rounded, color: Colors.white),
                    ),
                    const SizedBox(height: 10),
                    Text('Scan Assignment', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white)),
                    const SizedBox(height: 4),
                    Text('Take a photo to start grading', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.9))),
                    const SizedBox(height: 12),
                    // Answer keys live in the Answers tab — the card keeps
                    // one clean row of import sources.
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        PillButton(
                          label: 'From Gallery',
                          icon: Icons.photo_library_rounded,
                          background: Colors.white.withValues(alpha: 0.16),
                          foreground: Colors.white,
                          onTap: _pickFromGallery,
                        ),
                        const SizedBox(width: 10),
                        PillButton(
                          label: 'From Drive',
                          icon: Icons.add_to_drive_rounded,
                          background: Colors.white.withValues(alpha: 0.16),
                          foreground: Colors.white,
                          onTap: _pickFromDrive,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: InkWell(
                splashFactory: NoSplash.splashFactory,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                onTap: () => context.push(AppRoutes.planning),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(color: AiMarkerColors.tertiary.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
                        child: const Icon(Icons.event_note_rounded, color: AiMarkerColors.tertiary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Plan with Mark', style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 2),
                            Text('Draft a lesson plan, quiz, assignment, or worksheet in seconds.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: AiMarkerColors.neutral.withValues(alpha: 0.9)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded, color: Theme.of(context).colorScheme.secondary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Your assistant reads the assignment type, grade level, and whether to mark for completion or correctness — just scan.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            if (queue.jobs.isNotEmpty) ...[
              Row(
                children: [
                  Expanded(child: Text('Marking', style: Theme.of(context).textTheme.titleMedium)),
                  if (queue.markingCount > 0)
                    Text('${queue.markingCount} in progress', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                ],
              ),
              const SizedBox(height: 10),
              Card(
                child: Column(
                  children: [
                    for (final job in queue.jobs.take(8))
                      ListTile(
                        leading: job.status == GradingJobStatus.marking
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                            : Icon(
                                job.status == GradingJobStatus.done ? Icons.check_circle_rounded : Icons.error_rounded,
                                color: job.status == GradingJobStatus.done ? AiMarkerColors.secondary : AiMarkerColors.error,
                              ),
                        title: Text(job.label, style: Theme.of(context).textTheme.titleSmall),
                        subtitle: Text(
                          job.status == GradingJobStatus.marking
                              ? 'Marking…'
                              : job.status == GradingJobStatus.done
                                  ? '${job.result?.primaryDisplay ?? 'Done'} — tap to view'
                                  : 'Failed — tap to retry',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral),
                        ),
                        trailing: job.status == GradingJobStatus.marking
                            ? null
                            : IconButton(
                                icon: Icon(Icons.close_rounded, color: AiMarkerColors.neutral, size: 20),
                                onPressed: () => queue.remove(job.id),
                                tooltip: 'Dismiss',
                              ),
                        onTap: job.status == GradingJobStatus.done
                            ? () => context.push(
                                  '${AppRoutes.result}?submissionId=${job.submissionId}',
                                  extra: {
                                    'gradeResult': job.result,
                                    'imageBytes': job.pages.isEmpty ? null : job.pages.first,
                                    'pageImages': job.pages,
                                  },
                                )
                            : job.status == GradingJobStatus.error
                                ? () => queue.retry(job.id, students: context.read<StudentsService>(), submissions: context.read<SubmissionsService>())
                                : null,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],
            Text('STUDENT INFO', style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.2, color: AiMarkerColors.neutral)),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    TextField(
                      controller: _search,
                      onChanged: _onSearchChanged,
                      decoration: InputDecoration(
                        hintText: 'Enter student name or scan...',
                        prefixIcon: Icon(Icons.search_rounded, color: AiMarkerColors.neutral.withValues(alpha: 0.8)),
                        suffixIcon: IconButton(onPressed: () => _search.clear(), icon: Icon(Icons.close_rounded, color: AiMarkerColors.neutral.withValues(alpha: 0.8))),
                      ),
                    ),
                    if (_studentHits.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _StudentSearchResults(items: _studentHits, onSelect: _selectStudent),
                    ],
                    const SizedBox(height: 12),
                    _ClassRow(
                      label: selectedClass == null
                          ? 'Which class? Tap to choose'
                          : '${selectedClass.name} · ${selectedClass.period}${selectedClass.gradeLevel != null ? ' · Grade ${selectedClass.gradeLevel}' : ''}',
                      hasClass: selectedClass != null,
                      onTap: () => _askWhichClass(),
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
}

class _StudentSearchResults extends StatelessWidget {
  final List<_StudentSuggestion> items;
  final ValueChanged<_StudentSuggestion> onSelect;

  const _StudentSearchResults({required this.items, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.22))),
      child: Column(
        children: [
          for (final s in items.take(6))
            ListTile(
              leading: CircleAvatar(backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12), child: Text(s.name.isEmpty ? '?' : s.name.substring(0, 1), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700))),
              title: Text(s.name, style: Theme.of(context).textTheme.titleSmall),
              subtitle: Text(s.studentCode, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
              trailing: Icon(Icons.north_east_rounded, color: AiMarkerColors.neutral.withValues(alpha: 0.85)),
              onTap: () => onSelect(s),
            ),
        ],
      ),
    );
  }
}

class _StudentSuggestion {
  final String studentId;
  final String name;
  final String studentCode;
  final String classId;
  const _StudentSuggestion({required this.studentId, required this.name, required this.studentCode, required this.classId});
}

class _ClassRow extends StatelessWidget {
  final String label;
  final bool hasClass;
  final VoidCallback onTap;

  const _ClassRow({required this.label, required this.hasClass, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      splashFactory: NoSplash.splashFactory,
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 46),
        decoration: BoxDecoration(
          color: hasClass ? cs.primary.withValues(alpha: 0.10) : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: hasClass ? cs.primary.withValues(alpha: 0.3) : cs.outline.withValues(alpha: 0.22)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(Icons.groups_rounded, color: hasClass ? cs.primary : AiMarkerColors.neutral),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 12, color: hasClass ? cs.primary : null),
              ),
            ),
            Icon(Icons.keyboard_arrow_down_rounded, color: AiMarkerColors.neutral.withValues(alpha: 0.9)),
          ],
        ),
      ),
    );
  }
}

class _ClassPickerSheet extends StatelessWidget {
  final List<TeacherClass> classes;
  final String? currentId;
  const _ClassPickerSheet({required this.classes, required this.currentId});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(color: cs.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('Which class is this for?', style: Theme.of(context).textTheme.titleLarge)),
                IconButton(onPressed: () => context.pop(), icon: Icon(Icons.close_rounded, color: AiMarkerColors.neutral)),
              ],
            ),
            Text(
              'Marking follows the class\'s grade level automatically.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral),
            ),
            const SizedBox(height: 6),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final c in classes)
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                        child: Icon(Icons.bookmark_rounded, color: cs.primary, size: 20),
                      ),
                      title: Text(c.name, style: Theme.of(context).textTheme.titleSmall),
                      subtitle: Text(
                        '${c.period}${c.gradeLevel != null ? ' · Grade ${c.gradeLevel}' : ''}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral),
                      ),
                      trailing: c.id == currentId ? Icon(Icons.check_circle_rounded, color: cs.primary) : Icon(Icons.chevron_right_rounded, color: AiMarkerColors.neutral.withValues(alpha: 0.8)),
                      onTap: () => context.pop(c.id),
                    ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                      child: Icon(Icons.block_rounded, color: AiMarkerColors.neutral, size: 20),
                    ),
                    title: Text('No class — just grade it', style: Theme.of(context).textTheme.titleSmall),
                    onTap: () => context.pop(''),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
