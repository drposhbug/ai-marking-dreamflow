import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:marking_prokect_v2/app/app_routes.dart';
import 'package:marking_prokect_v2/services/ai_grading_service.dart';
import 'package:marking_prokect_v2/services/auth_service.dart';
import 'package:marking_prokect_v2/services/classes_service.dart';
import 'package:marking_prokect_v2/services/students_service.dart';
import 'package:marking_prokect_v2/theme.dart';
import 'package:marking_prokect_v2/widgets/teacher_topbar.dart';
import 'package:provider/provider.dart';

class ClassesMainScreen extends StatefulWidget {
  const ClassesMainScreen({super.key});

  @override
  State<ClassesMainScreen> createState() => _ClassesMainScreenState();
}

class _ClassesMainScreenState extends State<ClassesMainScreen> {
  bool _editing = false;

  Future<void> _confirmDeleteClass(dynamic c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${c.name}?'),
        content: Text('${c.name} (${c.period}) will be removed. This cannot be undone.'),
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
    if (ok == true && mounted) {
      await context.read<ClassesService>().delete(c.id as String);
    }
  }

  Future<void> _openCreateSheet() async {
    // The sheet creates the class (and its students) itself and returns the
    // class name on success.
    final createdName = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _CreateClassSheet(),
    );
    if (createdName != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$createdName created.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final classes = context.watch<ClassesService>().classes;
    final students = context.watch<StudentsService>().students;

    final bySubject = <String, List<dynamic>>{};
    for (final c in classes) {
      bySubject.putIfAbsent(c.subject, () => []).add(c);
    }

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
          children: [
            TeacherTopbar(
              title: 'Classes',
              trailingIcon: _editing ? Icons.check_rounded : Icons.edit_rounded,
              onBell: () => setState(() => _editing = !_editing),
            ),
            const SizedBox(height: 14),
            for (final entry in bySubject.entries) ...[
              Text(entry.key.toUpperCase(), style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.2, color: AiMarkerColors.neutral)),
              const SizedBox(height: 10),
              for (final c in entry.value.cast())
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    splashFactory: NoSplash.splashFactory,
                    onTap: () => context.push('${AppRoutes.classHub}?classId=${c.id}'),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
                              child: Icon(Icons.bookmark_rounded, color: Theme.of(context).colorScheme.primary),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(child: Text(c.name, style: Theme.of(context).textTheme.titleMedium)),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(999)),
                                        child: Text(c.period, style: Theme.of(context).textTheme.labelMedium),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text('${students.where((s) => s.classId == c.id).length} students · Room ${c.room ?? '—'}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                                ],
                              ),
                            ),
                            if (_editing)
                              IconButton(
                                onPressed: () => _confirmDeleteClass(c),
                                icon: Icon(Icons.delete_rounded, color: AiMarkerColors.error),
                                tooltip: 'Delete class',
                              )
                            else
                              Icon(Icons.chevron_right_rounded, color: AiMarkerColors.neutral.withValues(alpha: 0.9)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
            ...[
              const SizedBox(height: 4),
              InkWell(
                splashFactory: NoSplash.splashFactory,
                onTap: _openCreateSheet,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)),
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_rounded, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Add Class',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CreateClassSheet extends StatefulWidget {
  const _CreateClassSheet();

  @override
  State<_CreateClassSheet> createState() => _CreateClassSheetState();
}

class _CreateClassSheetState extends State<_CreateClassSheet> {
  final _room = TextEditingController();
  final _studentName = TextEditingController();
  String _subject = 'Physics';
  String _period = 'P1';
  int? _gradeLevel;

  final List<RosterEntry> _students = [];
  final ImagePicker _picker = ImagePicker();
  bool _scanning = false;
  bool _creating = false;

  /// Classes name themselves — "Physics P1" — no typing needed.
  String get _autoName => '$_subject $_period';

  @override
  void dispose() {
    _room.dispose();
    _studentName.dispose();
    super.dispose();
  }

  Future<void> _scanAttendance() async {
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
      final XFile? image = await _picker.pickImage(source: source, imageQuality: 85);
      if (image == null || !mounted) return;
      setState(() => _scanning = true);
      final bytes = await image.readAsBytes();
      final found = await AiGradingService().extractRoster(pages: [bytes]);
      if (!mounted) return;
      final existing = _students.map((s) => s.name.toLowerCase()).toSet();
      final fresh = found.where((s) => !existing.contains(s.name.toLowerCase())).toList();
      setState(() => _students.addAll(fresh));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(fresh.isEmpty
              ? 'No new names found on that photo.'
              : 'Added ${fresh.length} student${fresh.length == 1 ? '' : 's'} from the attendance sheet.'),
        ),
      );
    } catch (e) {
      debugPrint('_CreateClassSheet._scanAttendance failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read the attendance sheet. Try a clearer photo, or add students below.')),
      );
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _addStudentManually() {
    final name = _studentName.text.trim();
    if (name.isEmpty) return;
    if (!_students.any((s) => s.name.toLowerCase() == name.toLowerCase())) {
      setState(() => _students.add(RosterEntry(name: name)));
    }
    _studentName.clear();
  }

  Future<void> _create() async {
    final teacherId = context.read<AuthService>().currentUser?.id;
    final name = _autoName;
    if (teacherId == null) return;

    setState(() => _creating = true);
    try {
      final created = await context.read<ClassesService>().create(
        teacherId: teacherId,
        name: name,
        subject: _subject,
        period: _period,
        room: _room.text.trim().isEmpty ? null : _room.text.trim(),
        gradeLevel: _gradeLevel,
      );
      if (!mounted) return;
      final students = context.read<StudentsService>();
      for (final s in _students) {
        final code = s.studentId ??
            '${s.name.trim().split(RegExp(r'\s+')).map((w) => w[0].toUpperCase()).join()}${DateTime.now().millisecondsSinceEpoch % 1000}';
        await students.create(teacherId: teacherId, classId: created.id, name: s.name, studentId: code);
      }
      if (!mounted) return;
      context.pop(name);
    } catch (e) {
      debugPrint('_CreateClassSheet._create failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not create the class. Please try again.')));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
        decoration: BoxDecoration(color: cs.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Create class', style: Theme.of(context).textTheme.titleLarge)),
                  IconButton(onPressed: () => context.pop(), icon: Icon(Icons.close_rounded, color: AiMarkerColors.neutral)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Named automatically: $_autoName',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField(
                      value: _subject,
                      items: const ['Physics', 'Chemistry', 'Biology', 'Science', 'Math', 'English', 'History', 'Geography', 'French', 'Art', 'Music', 'General']
                          .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                          .toList(),
                      onChanged: (v) => setState(() => _subject = v.toString()),
                      decoration: const InputDecoration(labelText: 'Subject'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField(
                      value: _period,
                      items: [for (var p = 1; p <= 12; p++) DropdownMenuItem(value: 'P$p', child: Text('P$p'))],
                      onChanged: (v) => setState(() => _period = v.toString()),
                      decoration: const InputDecoration(labelText: 'Period'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
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
                  const SizedBox(width: 12),
                  Expanded(child: TextField(controller: _room, decoration: const InputDecoration(labelText: 'Room (optional)'))),
                ],
              ),
              const SizedBox(height: 16),
              Text('Students', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                'Snap your attendance sheet to fill the roster, or add students one by one.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral),
              ),
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                onPressed: _scanning ? null : _scanAttendance,
                icon: _scanning
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.photo_camera_rounded),
                label: Text(_scanning ? 'Reading names…' : 'Scan attendance sheet'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _studentName,
                      textCapitalization: TextCapitalization.words,
                      onSubmitted: (_) => _addStudentManually(),
                      decoration: const InputDecoration(labelText: 'Student name'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filled(onPressed: _addStudentManually, icon: const Icon(Icons.add_rounded), tooltip: 'Add student'),
                ],
              ),
              if (_students.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (var i = 0; i < _students.length; i++)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 15,
                      backgroundColor: cs.primary.withValues(alpha: 0.12),
                      child: Text(_students[i].name.isEmpty ? '?' : _students[i].name[0].toUpperCase(), style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                    title: Text(_students[i].name, style: Theme.of(context).textTheme.bodyMedium),
                    trailing: IconButton(
                      icon: Icon(Icons.close_rounded, color: AiMarkerColors.neutral, size: 20),
                      onPressed: () => setState(() => _students.removeAt(i)),
                    ),
                  ),
              ],
              const SizedBox(height: 14),
              FilledButton(
                onPressed: _creating ? null : _create,
                style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: Colors.white),
                child: _creating
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_students.isEmpty ? 'Create $_autoName' : 'Create $_autoName with ${_students.length} student${_students.length == 1 ? '' : 's'}'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
