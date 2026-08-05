import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:marking_prokect_v2/app/app_routes.dart';
import 'package:marking_prokect_v2/services/ai_grading_service.dart';
import 'package:marking_prokect_v2/models/submission.dart';
import 'package:marking_prokect_v2/models/teacher_class.dart';
import 'package:marking_prokect_v2/services/auth_service.dart';
import 'package:marking_prokect_v2/services/classes_service.dart';
import 'package:marking_prokect_v2/services/students_service.dart';
import 'package:marking_prokect_v2/services/submissions_service.dart';
import 'package:marking_prokect_v2/theme.dart';
import 'package:marking_prokect_v2/widgets/progress_ring.dart';
import 'package:marking_prokect_v2/widgets/time_ago.dart';
import 'package:provider/provider.dart';

class ClassHubScreen extends StatefulWidget {
  final String classId;
  const ClassHubScreen({super.key, required this.classId});

  @override
  State<ClassHubScreen> createState() => _ClassHubScreenState();
}

class _ClassHubScreenState extends State<ClassHubScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _openAddStudentSheet() async {
    final result = await showModalBottomSheet<_NewStudentResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _AddStudentSheet(),
    );
    if (result == null || !mounted) return;

    final teacherId = context.read<AuthService>().currentUser?.id;
    if (teacherId == null) return;

    // Auto-generate a student code from initials when none was given.
    final code = result.code.isNotEmpty
        ? result.code
        : '${result.name.trim().split(RegExp(r'\s+')).map((w) => w[0].toUpperCase()).join()}${DateTime.now().millisecondsSinceEpoch % 1000}';

    await context.read<StudentsService>().create(
      teacherId: teacherId,
      classId: widget.classId,
      name: result.name,
      studentId: code,
      notes: result.notes,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${result.name} added to the class.')));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final klass = context.watch<ClassesService>().getById(widget.classId);
    final studentsService = context.watch<StudentsService>();
    final submissions = context.watch<SubmissionsService>().submissions;

    final students = studentsService.byClass(widget.classId);
    final classSubmissions = submissions.where((s) => s.classId == widget.classId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final scored = classSubmissions.where((s) => s.maxScore > 0).toList();
    final avg = scored.isEmpty
        ? 0.0
        : (scored.map((e) => e.score / e.maxScore).reduce((a, b) => a + b) / scored.length).clamp(0.0, 1.0).toDouble();

    final filteredStudents = students.where((s) => _search.text.trim().isEmpty || s.name.toLowerCase().contains(_search.text.trim().toLowerCase())).toList();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: () => context.pop(), icon: Icon(Icons.arrow_back_rounded, color: cs.primary)),
        title: Text('${klass?.subject ?? 'Class'} · ${klass?.period ?? ''}'),
        actions: [
          IconButton(
            tooltip: 'Edit class',
            onPressed: klass == null ? null : () => _openEditClassSheet(klass),
            icon: Icon(Icons.more_vert_rounded, color: AiMarkerColors.neutral),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
          children: [
            ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          ProgressRing(value: avg, size: 84, stroke: 10, label: scored.isEmpty ? '—' : '${(avg * 100).round()}%'),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Class Average', style: Theme.of(context).textTheme.titleMedium),
                                const SizedBox(height: 4),
                                Text(
                                  scored.isEmpty
                                      ? 'No marked work yet — scan the first assignment to see stats.'
                                      : 'Across ${scored.length} marked submission${scored.length == 1 ? '' : 's'}.',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.35),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Full-width row: the three boxes share the card evenly.
                      Row(
                        children: [
                          _MiniStat(label: 'STUDENTS', value: '${students.length}'),
                          const SizedBox(width: 10),
                          _MiniStat(label: 'ASSIGNMENTS', value: '${classSubmissions.length}'),
                          const SizedBox(width: 10),
                          _MiniStat(label: 'LAST GRADED', value: classSubmissions.isEmpty ? '—' : timeAgo(classSubmissions.first.createdAt)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // The marked work itself — teachers look for it HERE, in the
              // class, not just on the dashboard.
              if (classSubmissions.isNotEmpty) ...[
                Text('Assignments', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                Card(
                  child: Column(
                    children: [
                      for (final s in classSubmissions.take(10))
                        ListTile(
                          dense: true,
                          leading: Icon(Icons.description_rounded, color: cs.primary, size: 20),
                          title: Text(
                            s.studentId.isEmpty
                                ? '${s.subject} · unlinked'
                                : '${s.subject} · ${studentsService.getById(s.studentId)?.name ?? 'Student'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          subtitle: Text(timeAgo(s.createdAt), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                          trailing: Text(
                            s.maxScore > 0 ? '${(s.score / s.maxScore * 100).round()}%' : '—',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w900),
                          ),
                          onTap: () => context.push('${AppRoutes.result}?submissionId=${s.id}'),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(controller: _search, onChanged: (_) => setState(() {}), decoration: InputDecoration(hintText: 'Search students...', prefixIcon: Icon(Icons.search_rounded, color: AiMarkerColors.neutral.withValues(alpha: 0.85)))),
              const SizedBox(height: 14),
              Text('Students', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              Card(
                child: Column(
                  children: [
                    for (final s in filteredStudents)
                      ListTile(
                        leading: CircleAvatar(backgroundColor: cs.primary.withValues(alpha: 0.12), child: Text(s.name.isEmpty ? '?' : s.name.substring(0, 1), style: TextStyle(color: cs.primary, fontWeight: FontWeight.w800))),
                        title: Text(s.name, style: Theme.of(context).textTheme.titleSmall),
                        subtitle: Text(_lastMarkLabel(s.id, classSubmissions), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                        trailing: _TrendBadge(kind: _trendFor(s.id, classSubmissions)),
                        onTap: () => context.push('${AppRoutes.studentProfile}?studentId=${s.id}&classId=${widget.classId}'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 80),
            ],
          ],
        ),
      ),
      floatingActionButton: SizedBox(
        width: MediaQuery.of(context).size.width - 32,
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _openAddStudentSheet,
                style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl))),
                icon: const Icon(Icons.person_add_alt_rounded, color: Colors.white),
                label: const Text('Add Student'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: _scanAttendance,
                style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl))),
                icon: const Icon(Icons.photo_camera_rounded),
                label: const Text('Scan Attendance'),
              ),
            ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  /// Most recent marked work for this student, e.g. "Last: Physics · 2d ago".
  String _lastMarkLabel(String studentId, List<Submission> submissions) {
    final own = submissions.where((s) => s.studentId == studentId).toList();
    if (own.isEmpty) return 'No marks yet';
    final last = own.first; // submissions are pre-sorted newest first
    return 'Last: ${last.subject} · ${timeAgo(last.createdAt)}';
  }

  /// Real trend: compares the student's two most recent percentages.
  TrendKind _trendFor(String studentId, List<Submission> submissions) {
    final own = submissions.where((s) => s.studentId == studentId && s.maxScore > 0).toList();
    if (own.length < 2) return TrendKind.consistent;
    final latest = own[0].score / own[0].maxScore;
    final previous = own[1].score / own[1].maxScore;
    final diff = latest - previous;
    if (diff >= 0.05) return TrendKind.improving;
    if (diff <= -0.05) return TrendKind.attention;
    return TrendKind.consistent;
  }

  Future<void> _openEditClassSheet(TeacherClass klass) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _EditClassSheet(klass: klass),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Class updated.')));
    }
  }

  /// Scan an attendance sheet and add every new name to THIS class — for
  /// teachers who skipped it during class creation.
  Future<void> _scanAttendance() async {
    final teacherId = context.read<AuthService>().currentUser?.id;
    if (teacherId == null) return;

    ImageSource? source = ImageSource.gallery;
    if (!kIsWeb) {
      source = await showModalBottomSheet<ImageSource>(
        context: context,
        backgroundColor: Theme.of(context).colorScheme.surface,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(leading: const Icon(Icons.photo_camera_rounded), title: const Text('Take a photo'), onTap: () => Navigator.pop(context, ImageSource.camera)),
              ListTile(leading: const Icon(Icons.photo_library_rounded), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(context, ImageSource.gallery)),
            ],
          ),
        ),
      );
      if (source == null) return;
    }

    try {
      final XFile? image = await ImagePicker().pickImage(source: source, imageQuality: 85);
      if (image == null || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reading names off the attendance sheet…')));
      final bytes = await image.readAsBytes();
      final found = await AiGradingService().extractRoster(pages: [bytes]);
      if (!mounted) return;

      final students = context.read<StudentsService>();
      final existing = students.byClass(widget.classId).map((s) => s.name.trim().toLowerCase()).toSet();
      var added = 0;
      for (final r in found) {
        if (existing.contains(r.name.trim().toLowerCase())) continue;
        final code = r.studentId ??
            '${r.name.trim().split(RegExp(r'\s+')).map((w) => w[0].toUpperCase()).join()}${DateTime.now().millisecondsSinceEpoch % 1000}';
        await students.create(teacherId: teacherId, classId: widget.classId, name: r.name, studentId: code);
        added++;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(added == 0 ? 'No new names found on that photo.' : 'Added $added student${added == 1 ? '' : 's'} from the attendance sheet.')),
      );
    } catch (e) {
      debugPrint('ClassHub._scanAttendance failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not read the attendance sheet — try a clearer photo.')));
    }
  }
}

class _EditClassSheet extends StatefulWidget {
  final TeacherClass klass;
  const _EditClassSheet({required this.klass});

  @override
  State<_EditClassSheet> createState() => _EditClassSheetState();
}

class _EditClassSheetState extends State<_EditClassSheet> {
  late final TextEditingController _name = TextEditingController(text: widget.klass.name);
  late final TextEditingController _subject = TextEditingController(text: widget.klass.subject);
  late final TextEditingController _room = TextEditingController(text: widget.klass.room ?? '');
  late String _period = widget.klass.period;
  late int? _gradeLevel = widget.klass.gradeLevel;
  bool _saving = false;

  static final _periods = [for (var p = 1; p <= 12; p++) 'P$p'];

  @override
  void dispose() {
    _name.dispose();
    _subject.dispose();
    _room.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await context.read<ClassesService>().update(
            id: widget.klass.id,
            name: _name.text.trim(),
            subject: _subject.text.trim().isEmpty ? 'General' : _subject.text.trim(),
            period: _period,
            room: _room.text.trim().isEmpty ? null : _room.text.trim(),
            gradeLevel: _gradeLevel,
          );
      if (!mounted) return;
      context.pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${widget.klass.name}?'),
        content: const Text('The class will be removed. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AiMarkerColors.error, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<ClassesService>().delete(widget.klass.id);
    if (!mounted) return;
    context.pop(false); // close sheet
    context.pop(); // leave the class hub — the class is gone
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Keep the dropdown valid even for periods outside P1–P12 (old data).
    final periods = _periods.contains(_period) ? _periods : [..._periods, _period];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(color: cs.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Edit class', style: Theme.of(context).textTheme.titleLarge)),
                  IconButton(onPressed: () => context.pop(), icon: Icon(Icons.close_rounded, color: AiMarkerColors.neutral)),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Class name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _subject,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Subject'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _period,
                      items: [for (final p in periods) DropdownMenuItem(value: p, child: Text(p))],
                      onChanged: (v) => setState(() => _period = v ?? _period),
                      decoration: const InputDecoration(labelText: 'Period'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int?>(
                      value: _gradeLevel,
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('Not set')),
                        for (var g = 1; g <= 13; g++) DropdownMenuItem<int?>(value: g, child: Text('Grade $g')),
                      ],
                      onChanged: (v) => setState(() => _gradeLevel = v),
                      decoration: const InputDecoration(labelText: 'Grade level'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(controller: _room, decoration: const InputDecoration(labelText: 'Room (optional)')),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving || _name.text.trim().isEmpty ? null : _save,
                style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: Colors.white),
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save changes'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _saving ? null : _delete,
                icon: Icon(Icons.delete_outline_rounded, color: AiMarkerColors.error, size: 20),
                label: Text('Delete class', style: TextStyle(color: AiMarkerColors.error)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    // Equal-height, centered boxes; FittedBox keeps labels like STUDENTS on
    // one line by scaling down instead of wrapping.
    return Expanded(
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label, maxLines: 1, style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 0.6, color: AiMarkerColors.neutral)),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, maxLines: 1, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            ),
          ],
        ),
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

class _NewStudentResult {
  final String name;
  final String code;
  final String? notes;
  const _NewStudentResult({required this.name, required this.code, this.notes});
}

class _AddStudentSheet extends StatefulWidget {
  const _AddStudentSheet();

  @override
  State<_AddStudentSheet> createState() => _AddStudentSheetState();
}

class _AddStudentSheetState extends State<_AddStudentSheet> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _notes = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(color: cs.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('Add student', style: Theme.of(context).textTheme.titleLarge)),
                IconButton(onPressed: () => Navigator.pop(context), icon: Icon(Icons.close_rounded, color: AiMarkerColors.neutral)),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Student name'),
            ),
            const SizedBox(height: 12),
            TextField(controller: _code, decoration: const InputDecoration(labelText: 'Student ID (optional)')),
            const SizedBox(height: 12),
            TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Notes (optional)')),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _name.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(
                        context,
                        _NewStudentResult(
                          name: _name.text.trim(),
                          code: _code.text.trim(),
                          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
                        ),
                      ),
              style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: Colors.white),
              child: const Text('Add Student'),
            ),
          ],
        ),
      ),
    );
  }
}

