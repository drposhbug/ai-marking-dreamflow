import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:marking_prokect_v2/app/app_routes.dart';
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
  Future<void> _openCreateSheet() async {
    final created = await showModalBottomSheet<_CreateClassResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _CreateClassSheet(),
    );

    final teacherId = context.read<AuthService>().currentUser?.id;
    if (created == null || teacherId == null) return;

    await context.read<ClassesService>().create(
      teacherId: teacherId,
      name: created.name,
      subject: created.subject,
      period: created.period,
      room: created.room,
    );
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
            TeacherTopbar(title: 'Classes', trailingIcon: Icons.add_rounded, onBell: _openCreateSheet),
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
                            Icon(Icons.chevron_right_rounded, color: AiMarkerColors.neutral.withValues(alpha: 0.9)),
                          ],
                        ),
                      ),
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

class _CreateClassResult {
  final String name;
  final String subject;
  final String period;
  final String? room;

  const _CreateClassResult({required this.name, required this.subject, required this.period, required this.room});
}

class _CreateClassSheet extends StatefulWidget {
  const _CreateClassSheet();

  @override
  State<_CreateClassSheet> createState() => _CreateClassSheetState();
}

class _CreateClassSheetState extends State<_CreateClassSheet> {
  final _name = TextEditingController(text: 'Year 10 Physics');
  final _room = TextEditingController();
  String _subject = 'Physics';
  String _period = 'P1';

  @override
  void dispose() {
    _name.dispose();
    _room.dispose();
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
                Expanded(child: Text('Create class', style: Theme.of(context).textTheme.titleLarge)),
                IconButton(onPressed: () => context.pop(), icon: Icon(Icons.close_rounded, color: AiMarkerColors.neutral)),
              ],
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField(
              value: _subject,
              items: const ['Physics', 'Chemistry', 'Biology', 'Math', 'English'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) => setState(() => _subject = v.toString()),
              decoration: const InputDecoration(labelText: 'Subject'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField(
              value: _period,
              items: const ['P1', 'P2', 'P3', 'P4', 'P5', 'P6'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) => setState(() => _period = v.toString()),
              decoration: const InputDecoration(labelText: 'Period'),
            ),
            const SizedBox(height: 12),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Class name')),
            const SizedBox(height: 12),
            TextField(controller: _room, decoration: const InputDecoration(labelText: 'Room (optional)')),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.pop(_CreateClassResult(name: _name.text.trim(), subject: _subject, period: _period, room: _room.text.trim().isEmpty ? null : _room.text.trim())),
              style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: Colors.white),
              child: const Text('Create Class'),
            ),
          ],
        ),
      ),
    );
  }
}
