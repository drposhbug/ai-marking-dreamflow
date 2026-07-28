import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:marking_prokect_v2/app/app_state.dart';
import 'package:marking_prokect_v2/models/teacher_class.dart';
import 'package:marking_prokect_v2/services/ai_grading_service.dart';
import 'package:marking_prokect_v2/services/auth_service.dart';
import 'package:marking_prokect_v2/services/classes_service.dart';
import 'package:marking_prokect_v2/services/local_store.dart';
import 'package:marking_prokect_v2/theme.dart';
import 'package:provider/provider.dart';

/// Planning assistant: describe what you need and Mark drafts a
/// classroom-ready lesson plan, assignment, quiz, or worksheet.
class PlanningScreen extends StatefulWidget {
  const PlanningScreen({super.key});

  @override
  State<PlanningScreen> createState() => _PlanningScreenState();
}

class _SavedPlan {
  final String title;
  final String content;
  final DateTime createdAt;

  const _SavedPlan({required this.title, required this.content, required this.createdAt});

  Map<String, dynamic> toJson() => {'title': title, 'content': content, 'created_at': createdAt.toIso8601String()};

  factory _SavedPlan.fromJson(Map<String, dynamic> j) => _SavedPlan(
        title: (j['title'] ?? '').toString(),
        content: (j['content'] ?? '').toString(),
        createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()) ?? DateTime.now(),
      );
}

class _PlanningScreenState extends State<PlanningScreen> {
  static const _kinds = ['Lesson plan', 'Test', 'Quiz', 'Assignment', 'Worksheet'];

  final _topic = TextEditingController();
  String _kind = _kinds.first;
  String? _classId;
  bool _generating = false;
  GeneratedPlan? _result;
  List<_SavedPlan> _history = const [];

  String _plansKey(String teacherId) => 'ai_marker.plans.v1.$teacherId';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadHistory());
  }

  @override
  void dispose() {
    _topic.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final user = context.read<AuthService>().currentUser;
    if (user == null) return;
    try {
      final raw = await const LocalStore().getString(_plansKey(user.id));
      if (raw == null || raw.isEmpty) return;
      final items = (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((m) => _SavedPlan.fromJson(m.cast<String, dynamic>()))
          .toList();
      if (mounted) setState(() => _history = items);
    } catch (e) {
      debugPrint('PlanningScreen._loadHistory failed: $e');
    }
  }

  Future<void> _persistHistory() async {
    final user = context.read<AuthService>().currentUser;
    if (user == null) return;
    await const LocalStore().setString(_plansKey(user.id), jsonEncode(_history.map((p) => p.toJson()).toList()));
  }

  Future<void> _generate() async {
    final topic = _topic.text.trim();
    if (topic.isEmpty || _generating) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _generating = true;
      _result = null;
    });
    try {
      final app = context.read<AppState>();
      final klass = _classId == null ? null : context.read<ClassesService>().getById(_classId!);
      final plan = await AiGradingService().generatePlan(
        topic: topic,
        kind: _kind.toLowerCase(),
        gradeLevel: klass?.gradeLevel ?? app.draft.gradeLevel,
        subject: klass?.subject,
        region: app.region,
      );
      if (!mounted) return;
      setState(() {
        _result = plan;
        _history = [_SavedPlan(title: plan.title, content: plan.content, createdAt: DateTime.now()), ..._history].take(25).toList();
      });
      await _persistHistory();
    } catch (e) {
      debugPrint('PlanningScreen._generate failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not create that — try again in a moment.')));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _copy(String content) async {
    await Clipboard.setData(ClipboardData(text: content));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied — paste it anywhere.')));
  }

  void _openSaved(_SavedPlan plan) {
    setState(() => _result = GeneratedPlan(title: plan.title, content: plan.content));
  }

  Future<void> _deleteSaved(int index) async {
    setState(() => _history = [..._history]..removeAt(index));
    await _persistHistory();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final classes = context.watch<ClassesService>().classes;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: () => context.pop(), icon: Icon(Icons.arrow_back_rounded, color: cs.primary)),
        title: const Text('Planning'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          children: [
            Text(
              'Tell Mark what you need and get a classroom-ready draft — plans, quizzes, assignments, worksheets.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.4),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final k in _kinds)
                  ChoiceChip(
                    label: Text(k),
                    selected: _kind == k,
                    onSelected: (_) => setState(() => _kind = k),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (classes.isNotEmpty) ...[
              DropdownButtonFormField<String?>(
                value: _classId,
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('No class — general')),
                  for (final TeacherClass c in classes)
                    DropdownMenuItem<String?>(
                      value: c.id,
                      child: Text('${c.name}${c.gradeLevel != null ? ' · Grade ${c.gradeLevel}' : ''}'),
                    ),
                ],
                onChanged: (v) => setState(() => _classId = v),
                decoration: const InputDecoration(labelText: 'For which class?'),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _topic,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'What do you need?',
                hintText: 'e.g. A 10-question quiz on fractions with word problems',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _generating || _topic.text.trim().isEmpty ? null : _generate,
              icon: _generating
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_awesome_rounded),
              label: Text(_generating ? 'Drafting…' : 'Create $_kind'),
            ),
            if (_result != null) ...[
              const SizedBox(height: 18),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(_result!.title, style: Theme.of(context).textTheme.titleMedium)),
                          IconButton(
                            tooltip: 'Copy',
                            onPressed: () => _copy('${_result!.title}\n\n${_result!.content}'),
                            icon: Icon(Icons.copy_rounded, color: cs.primary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SelectableText(_result!.content, style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45)),
                    ],
                  ),
                ),
              ),
            ],
            if (_history.isNotEmpty) ...[
              const SizedBox(height: 22),
              Text('Recent plans', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    for (var i = 0; i < _history.length; i++)
                      ListTile(
                        dense: true,
                        leading: Icon(Icons.event_note_rounded, color: cs.primary, size: 20),
                        title: Text(_history[i].title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium),
                        trailing: IconButton(
                          icon: Icon(Icons.delete_outline_rounded, color: AiMarkerColors.neutral, size: 20),
                          onPressed: () => _deleteSaved(i),
                        ),
                        onTap: () => _openSaved(_history[i]),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
