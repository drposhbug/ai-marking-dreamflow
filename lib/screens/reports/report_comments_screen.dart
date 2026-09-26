import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:marking_prokect_v2/models/teacher_class.dart';
import 'package:marking_prokect_v2/services/ai_grading_service.dart';
import 'package:marking_prokect_v2/services/auth_service.dart';
import 'package:marking_prokect_v2/services/classes_service.dart';
import 'package:marking_prokect_v2/services/file_saver.dart';
import 'package:marking_prokect_v2/services/gradebook_export.dart';
import 'package:marking_prokect_v2/services/presets_service.dart';
import 'package:marking_prokect_v2/services/report_comments.dart';
import 'package:marking_prokect_v2/services/students_service.dart';
import 'package:marking_prokect_v2/services/submissions_service.dart';
import 'package:marking_prokect_v2/theme.dart';
import 'package:provider/provider.dart';

/// Drafts a report card comment for every student in a class, out of the
/// work they actually had marked.
///
/// A teacher writes about thirty of these per class, three times a year, at
/// three to five minutes each — five to ten hours a term, and the part of
/// the job most of them dread more than the marking. UMarkless can do it
/// honestly because it already holds the evidence, so the drafts cite real
/// marks instead of reading like the same paragraph thirty times.
///
/// Two things this screen must never let slip:
///
///  * No name leaves the device. The evidence is summarised here, sent as
///    an anonymous array, and the names are put back on arrival.
///  * These are DRAFTS. Every button, every label, says so. A teacher who
///    believes a comment is finished will not check it, and an unchecked
///    claim about a child is the worst thing this feature can produce.
class ReportCommentsScreen extends StatefulWidget {
  const ReportCommentsScreen({super.key});

  @override
  State<ReportCommentsScreen> createState() => _ReportCommentsScreenState();
}

class _ReportCommentsScreenState extends State<ReportCommentsScreen> {
  String? _classId;
  int _days = 90; // roughly a term
  DateTimeRange? _customRange;
  String _tone = 'warm';
  int _words = 70;
  bool _nextStep = true;
  bool _busy = false;
  String? _error;

  /// The edited comment per student. The controller IS the draft — a
  /// teacher's edit must survive a rebuild, a scroll, and re-drafting
  /// somebody else, so it is never rebuilt from the model's text again
  /// once it exists.
  final _drafts = <String, TextEditingController>{};
  final _grounds = <String, List<String>>{};
  final _pronouns = <String, String>{};

  /// The text this screen last drafted, per student, exactly as it was handed
  /// over. If the controller no longer matches, the teacher has typed in it,
  /// and a bulk re-draft must leave it alone: a teacher who has spent an hour
  /// editing thirty comments and taps Draft to fill two blanks must not lose
  /// the hour.
  final _asDrafted = <String, String>{};

  /// The pronoun to draft with: what the teacher picked this session, else
  /// what they picked on this student before, else they/them. Never guessed
  /// from the name — a wrong guess misgenders a child in a document that
  /// goes home to their parents.
  String _pronounFor(String studentId) =>
      _pronouns[studentId] ??
      context.read<StudentsService>().getById(studentId)?.pronoun ??
      'they';

  bool _edited(String studentId) {
    final c = _drafts[studentId];
    if (c == null || c.text.trim().isEmpty) return false;
    return c.text != _asDrafted[studentId];
  }

  @override
  void dispose() {
    for (final c in _drafts.values) {
      c.dispose();
    }
    super.dispose();
  }

  TermWindow get _window => _customRange != null
      ? TermWindow.between(_customRange!.start, _customRange!.end, label: 'the reporting period')
      : TermWindow.lastDays(_days, label: 'the last $_days days');

  List<StudentEvidence> get _evidence {
    final id = _classId;
    if (id == null) return const [];
    final presets = context.read<PresetsService>().presets;
    return ReportComments.forClass(
      students: context.read<StudentsService>().students,
      submissions: context.read<SubmissionsService>().submissions,
      classId: id,
      window: _window,
      presetNames: {for (final p in presets) p.id: p.name},
    );
  }

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _customRange,
      helpText: 'Reporting period',
    );
    if (picked != null) setState(() => _customRange = picked);
  }

  /// [only] limits the run to a single student — their own Redraft button,
  /// which is the one place an edited comment may be replaced, because the
  /// teacher asked for that student by name.
  Future<void> _draft({String? only}) async {
    final auth = context.read<AuthService>().currentUser;
    if (auth == null) return;
    final klass = context.read<ClassesService>().getById(_classId ?? '');
    final all = _evidence;
    // Only students with something marked are sent. A student with an empty
    // term gets no draft at all — inventing one is exactly the failure this
    // feature cannot afford, and the teacher can see the gap on screen.
    var withWork = all.where((e) => e.pieces > 0).toList(growable: false);
    if (withWork.isEmpty) return;

    // Protect typed-in work. A bulk draft fills the blanks and rewrites the
    // drafts nobody has touched; anything the teacher has edited is left
    // exactly as they left it, and they are told how many were kept.
    final kept = only == null ? withWork.where((e) => _edited(e.studentId)).length : 0;
    withWork = withWork
        .where((e) => ReportComments.shouldDraft(
              studentId: e.studentId,
              edited: _edited(e.studentId),
              only: only,
            ))
        .toList(growable: false);
    if (withWork.isEmpty) {
      setState(() => _error = kept == 0
          ? null
          : 'Nothing to draft — all $kept ${kept == 1 ? 'comment has' : 'comments have'} your edits in them. '
              'Use Redraft on a student to replace one.');
      return;
    }

    // The roster goes along only to be scrubbed OUT of the free text: a
    // student who signed their essay can be quoted back in their own
    // marking feedback.
    final roster = all.map((e) => e.studentName).where((n) => n.isNotEmpty).toList(growable: false);

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final payload = <Map<String, dynamic>>[
        for (var i = 0; i < withWork.length; i++)
          ReportComments.anonymousPayload(
            withWork[i],
            index: i,
            scrub: roster,
            pronoun: _pronounFor(withWork[i].studentId),
          ),
      ];
      final drafts = await AiGradingService().reportComments(
        teacherId: auth.id,
        students: payload,
        options: ReportOptions(tone: _tone, words: _words, includeNextStep: _nextStep),
        subject: klass?.subject,
        gradeLevel: klass?.gradeLevel,
        term: _window.label,
      );
      if (!mounted) return;
      var missing = 0;
      for (var i = 0; i < withWork.length; i++) {
        final d = drafts[i];
        final e = withWork[i];
        if (d == null) {
          missing++;
          continue;
        }
        final text = ReportComments.personalise(d.comment, e.studentName);
        // Replace rather than reuse: a re-draft is the teacher asking for a
        // different comment, not for their edits to be preserved.
        (_drafts[e.studentId] ??= TextEditingController()).text = text;
        _asDrafted[e.studentId] = text;
        _grounds[e.studentId] = d.grounds;
      }
      setState(() {
        _busy = false;
        final notes = <String>[
          if (missing > 0)
            '$missing of ${withWork.length} came back blank. Tap Draft again — it only redoes the blank ones.',
          if (kept > 0) 'Left your $kept edited ${kept == 1 ? 'comment' : 'comments'} untouched.',
        ];
        _error = notes.isEmpty ? null : notes.join(' ');
      });
    } on UsageLimitException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Drafting failed: ${e.toString().replaceFirst('Exception: ', '')}';
      });
    }
  }

  Future<void> _exportCsv() async {
    final rows = _evidence.where((e) => (_drafts[e.studentId]?.text ?? '').trim().isNotEmpty).toList();
    if (rows.isEmpty) return;
    final klass = context.read<ClassesService>().getById(_classId ?? '');
    final b = StringBuffer('Student,Student ID,Comment\n');
    final students = context.read<StudentsService>().students;
    for (final e in rows) {
      final match = students.where((s) => s.id == e.studentId);
      final code = match.isEmpty ? '' : match.first.studentId;
      b.writeln([
        GradebookExport.csvField(e.studentName),
        GradebookExport.csvField(code),
        GradebookExport.csvField(_drafts[e.studentId]!.text.trim()),
      ].join(','));
    }
    try {
      final name = 'markless-report-comments-${(klass?.name ?? 'class').replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')}.csv';
      await saveFile(Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(b.toString())]), name, mimeType: 'text/csv');
    } catch (e) {
      if (mounted) _snack('Couldn\'t build the file: $e');
    }
  }

  void _copyAll() {
    final parts = <String>[];
    for (final e in _evidence) {
      final t = _drafts[e.studentId]?.text.trim() ?? '';
      if (t.isNotEmpty) parts.add('${e.studentName}\n$t');
    }
    if (parts.isEmpty) return;
    Clipboard.setData(ClipboardData(text: parts.join('\n\n')));
    _snack('${parts.length} comments copied.');
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final classes = context.watch<ClassesService>().classes;
    // Watched so a mark that lands while this screen is open shows up in
    // the evidence counts instead of going unnoticed.
    context.watch<SubmissionsService>();
    final evidence = _evidence;
    final withWork = evidence.where((e) => e.pieces > 0).length;
    final drafted = evidence.where((e) => (_drafts[e.studentId]?.text ?? '').trim().isNotEmpty).length;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.pop()),
        title: const Text('Report comments'),
        actions: [
          if (drafted > 0)
            IconButton(
              tooltip: 'Copy all',
              icon: const Icon(Icons.copy_all_rounded),
              onPressed: _copyAll,
            ),
          if (drafted > 0)
            IconButton(
              tooltip: 'Export as a spreadsheet',
              icon: const Icon(Icons.ios_share_rounded),
              onPressed: _exportCsv,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _draftBanner(context),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _classId,
            decoration: const InputDecoration(labelText: 'Class', border: OutlineInputBorder()),
            items: [
              for (final TeacherClass c in classes)
                DropdownMenuItem(value: c.id, child: Text(c.label)),
            ],
            onChanged: (v) => setState(() => _classId = v),
          ),
          const SizedBox(height: 12),
          _periodCard(context),
          const SizedBox(height: 12),
          _optionsCard(context),
          const SizedBox(height: 14),
          if (_error != null) ...[
            Card(
              color: AiMarkerColors.warning.withValues(alpha: 0.12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(_error!, style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4)),
              ),
            ),
            const SizedBox(height: 12),
          ],
          FilledButton.icon(
            onPressed: (_busy || withWork == 0) ? null : _draft,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome_rounded),
            label: Text(_busy
                ? 'Drafting…'
                : drafted > 0
                    ? 'Draft again ($withWork ${withWork == 1 ? 'student' : 'students'})'
                    : 'Draft $withWork ${withWork == 1 ? 'comment' : 'comments'}'),
          ),
          const SizedBox(height: 6),
          Text(
            _classId == null
                ? 'Pick a class to see whose work there is to write about.'
                : withWork == 0
                    ? 'Nothing marked for that class in this period. Try a longer one.'
                    : 'Only the marks, rubric lines and feedback go up — never names, never the scanned pages. '
                        'Names are put back on this phone.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.4),
          ),
          const SizedBox(height: 18),
          for (final e in evidence) _StudentCard(
            evidence: e,
            controller: _drafts[e.studentId],
            grounds: _grounds[e.studentId] ?? const [],
            pronoun: _pronounFor(e.studentId),
            onPronoun: (p) {
              setState(() => _pronouns[e.studentId] = p);
              context.read<StudentsService>().updatePronoun(studentId: e.studentId, pronoun: p);
            },
            onRedraft: (_busy || e.pieces == 0) ? null : () => _draft(only: e.studentId),
            onCopy: () {
              final t = _drafts[e.studentId]?.text.trim() ?? '';
              if (t.isEmpty) return;
              Clipboard.setData(ClipboardData(text: t));
              _snack('Copied ${ReportComments.firstName(e.studentName)}\'s comment.');
            },
          ),
        ],
      ),
    );
  }

  Widget _draftBanner(BuildContext context) => Card(
        color: AiMarkerColors.warning.withValues(alpha: 0.10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.edit_note_rounded, size: 18, color: AiMarkerColors.warning),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'These are drafts, and only you can finish them. Each one is written from that student\'s own marks '
                  'and nothing else — read it against the evidence shown before it goes anywhere.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.45),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _periodCard(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Reporting period',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final d in const [30, 60, 90, 180])
                    ChoiceChip(
                      label: Text('$d days'),
                      selected: _customRange == null && _days == d,
                      onSelected: (_) => setState(() {
                        _customRange = null;
                        _days = d;
                      }),
                    ),
                  ChoiceChip(
                    label: Text(_customRange == null
                        ? 'Exact dates'
                        : '${_d(_customRange!.start)} – ${_d(_customRange!.end)}'),
                    selected: _customRange != null,
                    onSelected: (_) => _pickDates(),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  static String _d(DateTime t) => '${t.day}/${t.month}';

  Widget _optionsCard(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tone', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final t in ReportOptions.tones)
                    ChoiceChip(
                      label: Text('${t[0].toUpperCase()}${t.substring(1)}'),
                      selected: _tone == t,
                      onSelected: (_) => setState(() => _tone = t),
                    ),
                ],
              ),
              const Divider(height: 22),
              Text('Length',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final w in ReportOptions.lengths)
                    ChoiceChip(
                      label: Text('$w words'),
                      selected: _words == w,
                      onSelected: (_) => setState(() => _words = w),
                    ),
                ],
              ),
              const Divider(height: 22),
              Row(
                children: [
                  Expanded(
                    child: Text('End with a next step', style: Theme.of(context).textTheme.bodyMedium),
                  ),
                  Switch(value: _nextStep, onChanged: (v) => setState(() => _nextStep = v)),
                ],
              ),
            ],
          ),
        ),
      );
}

/// One student: what the term actually shows, then the draft written from
/// it. The evidence sits ABOVE the comment on purpose — a teacher who reads
/// the draft first is checking it against nothing.
class _StudentCard extends StatelessWidget {
  final StudentEvidence evidence;
  final TextEditingController? controller;
  final List<String> grounds;
  final String pronoun;
  final ValueChanged<String> onPronoun;
  final VoidCallback onCopy;
  final VoidCallback? onRedraft;

  const _StudentCard({
    required this.evidence,
    required this.controller,
    required this.grounds,
    required this.pronoun,
    required this.onPronoun,
    required this.onCopy,
    required this.onRedraft,
  });

  @override
  Widget build(BuildContext context) {
    final e = evidence;
    final avg = e.averagePercent;
    final trend = e.trendPoints;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(e.studentName,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Pronoun used in the draft',
                  initialValue: pronoun,
                  onSelected: onPronoun,
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'they', child: Text('they / them')),
                    PopupMenuItem(value: 'she', child: Text('she / her')),
                    PopupMenuItem(value: 'he', child: Text('he / him')),
                  ],
                  child: Chip(
                    label: Text(pronoun),
                    visualDensity: VisualDensity.compact,
                    labelStyle: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (e.pieces == 0)
              Text('Nothing marked in this period — no comment can be drafted from evidence that isn\'t there.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AiMarkerColors.neutral, height: 1.4, fontStyle: FontStyle.italic))
            else ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _pill(context, '${e.pieces} ${e.pieces == 1 ? 'piece' : 'pieces'}', AiMarkerColors.neutral),
                  if (avg != null) _pill(context, 'avg $avg%', AiMarkerColors.primary),
                  if (trend != null && trend.abs() >= 3)
                    _pill(context, '${trend > 0 ? '+' : ''}$trend pts across the term',
                        trend > 0 ? AiMarkerColors.secondary : AiMarkerColors.warning),
                  if (e.isThin) _pill(context, 'thin evidence', AiMarkerColors.warning),
                ],
              ),
              if (e.criteriaTrends.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  e.criteriaTrends
                      .map((c) => '${c.name} ${c.averagePercent}%${c.seen > 1 ? ' ×${c.seen}' : ''}')
                      .take(6)
                      .join('  ·  '),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.4),
                ),
              ],
              if (controller != null) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLines: null,
                  minLines: 3,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    labelText: 'Draft — edit freely',
                  ),
                ),
                if (grounds.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Written from: ${grounds.join('; ')}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AiMarkerColors.neutral, height: 1.4)),
                ],
                // Rechecked as the teacher types: an edit is where a figure
                // is most likely to drift off the evidence, and a warning
                // that only reflects the original draft would be silent
                // exactly when it matters.
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller!,
                  builder: (context, value, _) {
                    final suspects = ReportComments.suspectFigures(value.text, e);
                    if (suspects.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline_rounded, size: 15, color: AiMarkerColors.warning),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Check ${suspects.join(', ')} — ${suspects.length == 1 ? 'that figure is' : 'those figures are'} not in this student\'s marks.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AiMarkerColors.warning, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // The only way an edited comment gets replaced. Bulk
                    // Draft skips edited ones, so this is deliberate and
                    // per-student.
                    TextButton.icon(
                      onPressed: onRedraft,
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Redraft'),
                    ),
                    TextButton.icon(
                      onPressed: onCopy,
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Copy'),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _pill(BuildContext context, String text, Color colour) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colour, fontWeight: FontWeight.w700)),
      );
}
