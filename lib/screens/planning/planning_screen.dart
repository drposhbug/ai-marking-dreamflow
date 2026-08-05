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

/// Unicode subscript glyphs for tidying v_i / t_0 style notation.
const _subscriptMap = {
  '0': '₀', '1': '₁', '2': '₂', '3': '₃', '4': '₄', '5': '₅', '6': '₆', '7': '₇', '8': '₈', '9': '₉',
  'a': 'ₐ', 'e': 'ₑ', 'h': 'ₕ', 'i': 'ᵢ', 'j': 'ⱼ', 'k': 'ₖ', 'l': 'ₗ', 'm': 'ₘ', 'n': 'ₙ',
  'o': 'ₒ', 'p': 'ₚ', 'r': 'ᵣ', 's': 'ₛ', 't': 'ₜ', 'u': 'ᵤ', 'v': 'ᵥ', 'x': 'ₓ',
};

/// v_i → vᵢ, t_0 → t₀; when a letter has no Unicode subscript (like f) the
/// underscore is simply dropped: v_f → vf. Handles v_{max} braces too.
String tidyPlanText(String s) {
  return s.replaceAllMapped(RegExp(r'([A-Za-zΔθω])_\{?([A-Za-z0-9]{1,4})\}?'), (m) {
    final sub = m.group(2)!;
    final mapped = sub.split('').map((c) => _subscriptMap[c.toLowerCase()]).toList();
    if (mapped.every((c) => c != null)) return m.group(1)! + mapped.join();
    return m.group(1)! + sub;
  });
}

bool _isDividerLine(String l) {
  final t = l.trim();
  return t.length >= 3 && RegExp(r'^[-=_*·—–\s]+$').hasMatch(t);
}

/// Plain text for the clipboard: subscripts tidied, markdown markers and
/// divider lines stripped.
String planCopyText(String s) {
  final lines = tidyPlanText(s).split('\n').where((l) => !_isDividerLine(l));
  return lines.join('\n').replaceAll('**', '').replaceAll(RegExp(r'^#+\s*', multiLine: true), '');
}

/// Renders a plan neatly: bold section headings, clean bullets, tidied
/// subscripts — markdown clutter (**, ##, ---) is converted or dropped
/// instead of shown raw.
class _PlanContent extends StatelessWidget {
  final String content;
  const _PlanContent({required this.content});

  List<InlineSpan> _inline(String text, TextStyle base) {
    final spans = <InlineSpan>[];
    var idx = 0;
    for (final m in RegExp(r'\*\*(.+?)\*\*').allMatches(text)) {
      if (m.start > idx) spans.add(TextSpan(text: text.substring(idx, m.start)));
      spans.add(TextSpan(text: m.group(1), style: base.copyWith(fontWeight: FontWeight.w800)));
      idx = m.end;
    }
    if (idx < text.length) spans.add(TextSpan(text: text.substring(idx)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyMedium!.copyWith(height: 1.45);
    final heading = theme.textTheme.titleSmall!.copyWith(fontWeight: FontWeight.w800);

    final children = <Widget>[];
    for (final rawLine in tidyPlanText(content).split('\n')) {
      final line = rawLine.trimRight();
      final t = line.trim();
      if (t.isEmpty) {
        children.add(const SizedBox(height: 8));
        continue;
      }
      if (_isDividerLine(t)) continue;

      // Headings: "## Title", "**Title**" alone, or short "Title:" lines.
      var h = t.replaceFirst(RegExp(r'^#+\s*'), '');
      final wrappedBold = RegExp(r'^\*\*(.+)\*\*:?$').firstMatch(h);
      if (wrappedBold != null) h = '${wrappedBold.group(1)!}${h.endsWith(':') ? ':' : ''}';
      final looksLikeHeading = h != t || (h.endsWith(':') && h.length <= 60 && !RegExp(r'^\d').hasMatch(h));
      if (looksLikeHeading && !h.startsWith('•') && !h.startsWith('-')) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 2),
          child: Text(h.replaceAll('**', ''), style: heading),
        ));
        continue;
      }

      // Bullets: •, -, or * markers.
      final bullet = RegExp(r'^[•\-\*]\s+(.*)$').firstMatch(t);
      if (bullet != null) {
        children.add(Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('•  ', style: body.copyWith(fontWeight: FontWeight.w700)),
              Expanded(child: Text.rich(TextSpan(style: body, children: _inline(bullet.group(1)!, body)))),
            ],
          ),
        ));
        continue;
      }

      children.add(Text.rich(TextSpan(style: body, children: _inline(t, body))));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}

class _PlanningScreenState extends State<PlanningScreen> with SingleTickerProviderStateMixin {
  static const _kinds = ['Lesson plan', 'Test', 'Quiz', 'Assignment', 'Worksheet'];

  final _topic = TextEditingController();
  String _kind = _kinds.first;
  String? _classId;
  bool _generating = false;
  GeneratedPlan? _result;
  List<_SavedPlan> _history = const [];

  /// Drives the "generating… N%" display. Progress isn't knowable for a
  /// single API call, so it eases toward ~92% over the typical duration
  /// and snaps to done when the draft arrives.
  late final AnimationController _progress = AnimationController(vsync: this, duration: const Duration(seconds: 28));

  /// Planning is a thank-you feature: unlocked by referring one teacher.
  /// null = still checking; fail-open so a network hiccup never locks it.
  bool? _planningUnlocked;
  String _refCode = '';
  final _redeemCtrl = TextEditingController();
  bool _redeeming = false;

  String _plansKey(String teacherId) => 'ai_marker.plans.v1.$teacherId';
  String _unlockKey(String teacherId) => 'ai_marker.planning_unlocked.v1.$teacherId';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadHistory();
      _loadReferral();
    });
  }

  Future<void> _loadReferral() async {
    final user = context.read<AuthService>().currentUser;
    if (user == null) {
      setState(() => _planningUnlocked = true);
      return;
    }
    // Once unlocked, stay unlocked — no network round-trip on later opens.
    final cached = await const LocalStore().getString(_unlockKey(user.id));
    if (cached == '1') {
      if (mounted) setState(() => _planningUnlocked = true);
      return;
    }
    try {
      final status = await AiGradingService().getReferral(teacherId: user.id);
      if (!mounted) return;
      setState(() {
        _planningUnlocked = status.planningUnlocked;
        _refCode = status.code;
      });
      if (status.planningUnlocked) {
        await const LocalStore().setString(_unlockKey(user.id), '1');
      }
    } catch (e) {
      debugPrint('PlanningScreen._loadReferral failed: $e');
      if (mounted) setState(() => _planningUnlocked = true); // fail open
    }
  }

  Future<void> _redeem() async {
    final code = _redeemCtrl.text.trim();
    final user = context.read<AuthService>().currentUser;
    if (code.isEmpty || user == null || _redeeming) return;
    setState(() => _redeeming = true);
    try {
      await AiGradingService().redeemReferral(teacherId: user.id, code: code);
      if (!mounted) return;
      _redeemCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Code redeemed 🎉 — Planning is now unlocked for your colleague.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _redeeming = false);
    }
  }

  void _showUpgradeSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Markless plans', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('Start with a 7-day free trial', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              const Text('•  Starter — \$6.99/mo · 120 marks a month'),
              const Text('•  Pro ⭐ — \$14.99/mo · 400 marks (best value)'),
              const Text('•  Pro Annual — \$119.99/yr (≈ \$10/mo) · 400 marks'),
              const Text('•  School — \$24.99/mo · 900 marks'),
              const SizedBox(height: 10),
              const Text('Every paid plan sends 15% to a classroom — you pick whose.'),
              const SizedBox(height: 12),
              Text(
                'Plans launch with the app-store release. During the preview you\'re on the Pro allowance.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _progress.dispose();
    _redeemCtrl.dispose();
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
    _progress
      ..reset()
      ..forward();
    try {
      final app = context.read<AppState>();
      final klass = _classId == null ? null : context.read<ClassesService>().getById(_classId!);
      final plan = await AiGradingService().generatePlan(
        topic: topic,
        kind: _kind.toLowerCase(),
        teacherId: context.read<AuthService>().currentUser?.id,
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
    } on UsageLimitException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), duration: const Duration(seconds: 6)));
      _showUpgradeSheet();
    } catch (e) {
      debugPrint('PlanningScreen._generate failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not create that — try again in a moment.')));
    } finally {
      _progress.stop();
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _copy(String content) async {
    await Clipboard.setData(ClipboardData(text: planCopyText(content)));
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

    if (_planningUnlocked == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(onPressed: () => context.pop(), icon: Icon(Icons.arrow_back_rounded, color: cs.primary)),
          title: const Text('Planning'),
        ),
        body: const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    if (_planningUnlocked == false) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(onPressed: () => context.pop(), icon: Icon(Icons.arrow_back_rounded, color: cs.primary)),
          title: const Text('Planning'),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.card_giftcard_rounded, color: cs.primary),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Unlock Plan with Mark — free', style: Theme.of(context).textTheme.titleMedium)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Planning is a thank-you feature: invite one teacher and it\'s yours for good. Share your code below — the moment a colleague enters it in their app, Planning unlocks for you. '
                        'And it keeps paying: every colleague who subscribes adds +25 marks to your month, for as long as they stay.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          _refCode.isEmpty ? '——————' : _refCode,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w900, letterSpacing: 4),
                        ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: _refCode.isEmpty
                            ? null
                            : () => _copy('Try Markless — the marking assistant that gives teachers their evenings back. '
                                'Create an account, then enter my referral code $_refCode under Planning.'),
                        icon: const Icon(Icons.share_rounded, size: 18),
                        label: const Text('Copy invite message'),
                      ),
                      const SizedBox(height: 6),
                      OutlinedButton.icon(
                        onPressed: _loadReferral,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('A colleague joined — check again'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Have a code from a colleague?', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        'Entering it unlocks Planning for them.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _redeemCtrl,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(labelText: 'Referral code', hintText: 'e.g. 4A7C2F'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          FilledButton(
                            onPressed: _redeeming ? null : _redeem,
                            child: _redeeming
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('Redeem'),
                          ),
                        ],
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
            if (_generating) ...[
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: AnimatedBuilder(
                    animation: _progress,
                    builder: (context, _) {
                      final pct = (Curves.easeOutCubic.transform(_progress.value) * 92).clamp(3.0, 92.0).round();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text('Mark is drafting your ${_kind.toLowerCase()}…', style: Theme.of(context).textTheme.titleSmall)),
                              Text('$pct%', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w800)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(value: pct / 100, minHeight: 8),
                          ),
                          const SizedBox(height: 8),
                          Text('Usually 15–30 seconds. Popular topics come back instantly.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
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
                      SelectionArea(child: _PlanContent(content: _result!.content)),
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
