import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:marking_prokect_v2/app/app_routes.dart';
import 'package:marking_prokect_v2/services/ai_grading_service.dart';
import 'package:marking_prokect_v2/services/auth_service.dart';
import 'package:marking_prokect_v2/services/batch_marking.dart';
import 'package:marking_prokect_v2/services/document_processor.dart';
import 'package:marking_prokect_v2/services/drive_picker.dart';
import 'package:marking_prokect_v2/services/page_fingerprint.dart';
import 'package:marking_prokect_v2/services/pdf_splitter.dart';
import 'package:marking_prokect_v2/theme.dart';
import 'package:provider/provider.dart';

/// How many pages a single copier stack may bring in — 40 students × 3 pages
/// with room to spare. Far above the 15-page cap for a single test, because
/// here a long PDF is the whole point.
const int kMaxStackPages = 150;

enum _Stage { pick, working, review }

/// One student's paper inside the stack.
class _Group {
  List<int> pages;
  String? name;
  _Group(this.pages, this.name);
}

/// Feed a class set through the photocopier once, then split the PDF back
/// into one paper per student here.
class SplitStackScreen extends StatefulWidget {
  const SplitStackScreen({super.key});

  @override
  State<SplitStackScreen> createState() => _SplitStackScreenState();
}

class _SplitStackScreenState extends State<SplitStackScreen> {
  _Stage _stage = _Stage.pick;
  String _fileName = '';
  String _progress = '';
  bool _truncated = false;

  List<Uint8List> _pages = const [];
  List<PageSignals> _signals = const [];
  List<_Group> _groups = [];

  /// null = boundaries were detected; a number = every paper is that long.
  int? _fixedPerStudent;
  bool _detectionUsable = true;
  /// One fingerprint per page, so a wrong split can be spotted before any
  /// credits are spent on marking it.
  List<PageFingerprint?> _fingerprints = const [];

  /// Which papers look wrong, recomputed whenever the boundaries change.
  StackCheck get _check => StackCheck.run(
        groups: [for (final g in _groups) g.pages],
        fingerprints: _fingerprints,
        coverPage: [for (var i = 0; i < _pages.length; i++) i < _signals.length && _signals[i].looksLikeFirstPage],
        // The name read off each page. With a name field printed on EVERY
        // page this is what catches a shuffled page whose numbering still
        // reads 1, 2, 3.
        names: [for (var i = 0; i < _pages.length; i++) i < _signals.length ? _signals[i].studentName : null],
      );


  /// How many students the teacher expects. Optional, but it is the only
  /// way to catch a double-feed: the copier silently pulls two sheets
  /// through as one, a page vanishes, and every split after it shifts.
  int? _expectedStudents;

  /// The teacher's allowance, so the cost of piecing a stack back together
  /// can be shown before they agree to it.
  UsageSummary? _usage;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final auth = context.read<AuthService>().currentUser;
      if (auth == null) return;
      try {
        final u = await AiGradingService().getUsage(teacherId: auth.id);
        if (mounted) setState(() => _usage = u);
      } catch (e) {
        debugPrint('SplitStack usage load failed: $e');
      }
    });
  }

  Future<void> _pickPdf() async {
    try {
      final res = await FilePicker.pickFiles(type: FileType.any, withData: true);
      final f = res?.files.firstOrNull;
      final bytes = f?.bytes;
      if (f == null || bytes == null) return;
      if (!mounted) return;
      setState(() {
        _stage = _Stage.working;
        _fileName = f.name;
        _progress = 'Reading the PDF…';
      });

      final images = await renderPdfPages(bytes, maxPages: kMaxStackPages);
      if (!mounted) return;
      if (images.isEmpty) {
        setState(() => _stage = _Stage.pick);
        _snack('That file isn\'t a PDF this can read. Scan the stack to PDF and try again.');
        return;
      }
      _truncated = await pdfExceedsPageCap(f.name, '', bytes) && images.length >= kMaxStackPages;

      // Clean each page the same way a photographed page is cleaned.
      final processed = <Uint8List>[];
      for (var i = 0; i < images.length; i++) {
        processed.add(await DocumentProcessor.processPage(images[i]));
        if (!mounted) return;
        setState(() => _progress = 'Preparing pages… ${i + 1} of ${images.length}');
      }

      // Boundary detection, entirely on this phone.
      setState(() => _progress = 'Looking for where each student\'s paper starts…');
      final signals = await PdfSplitter.scan(
        processed,
        onProgress: (done, total) {
          if (mounted) setState(() => _progress = 'Looking for name fields… $done of $total pages');
        },
      );
      if (!mounted) return;
      PdfSplitter.debugSummary(signals);

      // Fingerprint every page: this is what catches a double-feed, a
      // missed boundary, or the same paper scanned twice.
      setState(() => _progress = 'Checking the split…');
      final prints = await PageFingerprint.ofAll(processed);
      if (!mounted) return;

      final usable = !PdfSplitter.detectionUnusable(signals);
      final suggested = PdfSplitter.suggestPagesPerStudent(signals);
      setState(() {
        _pages = processed;
        _signals = signals;
        _fingerprints = prints;
        _detectionUsable = usable;
        // Detection when it found something; otherwise fall back to a page
        // count rather than proposing a split we don't believe in.
        _fixedPerStudent = usable ? null : (suggested ?? 1);
        _rebuildGroups();
        _stage = _Stage.review;
      });
    } catch (e) {
      debugPrint('Stack split failed: $e');
      if (!mounted) return;
      setState(() => _stage = _Stage.pick);
      _snack('Couldn\'t read that PDF.');
    }
  }

  void _rebuildGroups() {
    final indexGroups = _fixedPerStudent == null
        ? PdfSplitter.groupBySignals(_signals)
        : PdfSplitter.groupByFixed(_pages.length, _fixedPerStudent!);
    _groups = [
      for (final g in indexGroups) _Group(g, _signals.isEmpty ? null : _signals[g.first].studentName),
    ];
  }

  /// Start a new student at [pageIndex] — the page becomes the first of its
  /// own paper, and everything after it up to the next boundary follows.
  void _splitAt(int groupIndex, int pageIndex) {
    final g = _groups[groupIndex];
    final at = g.pages.indexOf(pageIndex);
    if (at <= 0) return;
    final tail = g.pages.sublist(at);
    setState(() {
      g.pages = g.pages.sublist(0, at);
      _groups.insert(groupIndex + 1, _Group(tail, _signals.isEmpty ? null : _signals[tail.first].studentName));
      // Hand-edited boundaries are no longer "every N pages".
      _fixedPerStudent = null;
    });
  }

  /// This paper is really a continuation of the one above it.
  void _mergeUp(int groupIndex) {
    if (groupIndex == 0) return;
    setState(() {
      _groups[groupIndex - 1].pages.addAll(_groups[groupIndex].pages);
      _groups.removeAt(groupIndex);
      _fixedPerStudent = null;
    });
  }

  Future<void> _editName(int groupIndex) async {
    final ctrl = TextEditingController(text: _groups[groupIndex].name ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Whose paper is this?'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Student name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || !mounted) return;
    setState(() => _groups[groupIndex].name = name.isEmpty ? null : name);
  }

  /// Delegates to the splitter so the arithmetic can be tested on its own.
  String? get _stackWarning => PdfSplitter.stackWarning(
        groupLengths: [for (final g in _groups) g.pages.length],
        expectedStudents: _expectedStudents,
      );
  /// Plain-English description of what looks wrong with one paper.
  String _faultsFor(int groupIndex) {
    final faults = _check.papers.length > groupIndex ? _check.papers[groupIndex].faults : const <PaperFault>{};
    if (faults.isEmpty) return '';
    final bits = <String>[
      if (faults.contains(PaperFault.duplicatePage)) 'the same page appears twice',
      if (faults.contains(PaperFault.twoCoverPages)) 'two papers look stuck together',
      if (faults.contains(PaperFault.duplicateOfAnotherPaper)) 'this paper also appears elsewhere in the stack',
      if (faults.contains(PaperFault.mixedNames)) 'pages here name different students',
    ];
    return '${bits.join('; ')} — check before marking.';
  }


  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  /// Shown when the on-device checks say the split is wrong. Marking it as
  /// it stands buys a class of wrong marks, so the teacher chooses: fix the
  /// order themselves, have the pages pieced together from the handwriting,
  /// or go ahead anyway because they know something the checks don't.
  Future<String?> _askAboutBadSplit() {
    final suspects = _check.suspects.length;
    final pageCount = _check.suspects.fold<int>(0, (n, s) => n + _groups[s.paperIndex].pages.length);
    final pct = _usage?.pctFor(pageCount, overnight: false) ?? 0;
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('This stack looks out of order'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$suspects ${suspects == 1 ? 'paper has' : 'papers have'} repeated or doubled-up pages. '
              'Marking them as they are would put one student\'s work under another\'s name.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
            const SizedBox(height: 12),
            Text(
              'Markless can read the handwriting and page numbers on those $pageCount pages and work out '
              'who wrote what${pct > 0 ? ' — about $pct% of this month\'s credits' : ''}. Anything it isn\'t '
              'sure about is left flagged for you rather than guessed.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.45),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, 'fix'), child: const Text('I\'ll fix the order')),
          TextButton(onPressed: () => Navigator.pop(context, 'anyway'), child: const Text('Mark anyway')),
          FilledButton(onPressed: () => Navigator.pop(context, 'match'), child: const Text('Match by handwriting')),
        ],
      ),
    );
  }

  /// Sends the flagged papers' pages off to be regrouped, then rebuilds the
  /// split from what comes back. Pages it couldn't place stay where they
  /// were and stay flagged.
  Future<void> _matchByHandwriting() async {
    final auth = context.read<AuthService>().currentUser;
    if (auth == null) return;
    // Only the suspect papers go up — the ones that split cleanly are fine
    // and there is no reason to pay to re-examine them.
    final pageIndexes = <int>[];
    for (final s in _check.suspects) {
      pageIndexes.addAll(_groups[s.paperIndex].pages);
    }
    if (pageIndexes.length < 2) return;

    setState(() {
      _stage = _Stage.working;
      _progress = 'Reading the handwriting on ${pageIndexes.length} pages…';
    });
    try {
      final outcome = await AiGradingService().groupPages(
        teacherId: auth.id,
        pages: [for (final i in pageIndexes) _pages[i]],
      );
      if (!mounted) return;

      // Rebuild: keep the papers that were fine, replace the suspect ones
      // with whatever came back.
      final suspectSet = {for (final s in _check.suspects) s.paperIndex};
      final kept = <_Group>[
        for (var i = 0; i < _groups.length; i++)
          if (!suspectSet.contains(i)) _groups[i],
      ];
      final rebuilt = <_Group>[];
      for (final g in outcome.groups) {
        // Indexes came back relative to what we sent — map them home.
        final pages = [for (final n in g.pageIndexes) if (n >= 0 && n < pageIndexes.length) pageIndexes[n]];
        if (pages.isEmpty) continue;
        rebuilt.add(_Group(pages, g.studentName.trim().isEmpty ? null : g.studentName.trim()));
      }
      // Unplaced pages become single-page papers so nothing is lost; the
      // teacher sees them flagged and decides.
      final stranded = [for (final n in outcome.unresolved) if (n >= 0 && n < pageIndexes.length) pageIndexes[n]];
      for (final p in stranded) {
        rebuilt.add(_Group([p], null));
      }

      setState(() {
        _groups = [...kept, ...rebuilt]..sort((a, b) => a.pages.first.compareTo(b.pages.first));
        _fixedPerStudent = null;
        _stage = _Stage.review;
      });
      _snack(stranded.isEmpty
          ? 'Pieced back together into ${outcome.groups.length} papers — check the names and mark when you\'re happy.'
          : 'Sorted ${outcome.groups.length} papers. ${stranded.length} pages couldn\'t be placed and are flagged — put those right yourself.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _stage = _Stage.review);
      _snack('Couldn\'t piece the stack together: ${e.toString().replaceFirst('Exception: ', '')}');
    }
  }


  Future<void> _startMarking() async {
    final groups = <List<Uint8List>>[];
    final names = <String?>[];
    for (final g in _groups) {
      if (g.pages.isEmpty) continue;
      groups.add([for (final p in g.pages) _pages[p]]);
      names.add(g.name);
    }
    if (groups.isEmpty) return;
    // Never mark a stack the checks say is out of order without asking.
    if (_check.anySuspect) {
      final choice = await _askAboutBadSplit();
      if (!mounted || choice == null || choice == 'fix') return;
      if (choice == 'match') {
        await _matchByHandwriting();
        return;
      }
    }


    // A teacher who fixed a bad split and rescanned the whole stack should
    // not pay again for the papers that came out fine the first time.
    final fresh = await dropAlreadyMarked(context: context, groups: groups);
    if (!mounted) return;
    final skipped = groups.length - fresh.length;
    if (fresh.isEmpty) {
      _snack('Every paper in this stack has already been marked — nothing to do.');
      return;
    }
    final keptGroups = [for (final i in fresh) groups[i]];
    final keptNames = [for (final i in fresh) names[i]];
    final n = enqueueStudentGroups(context: context, groups: keptGroups, studentNames: keptNames);
    if (n == 0) {
      _snack('Couldn\'t start marking — try signing in again.');
      return;
    }
    _snack(skipped > 0
        ? 'Marking $n papers — $skipped had already been marked, so they were skipped.'
        : 'Marking $n papers in the background — results land in the tray as they finish.');
    context.go(AppRoutes.grading);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.pop()),
        title: const Text('Split a scanned stack'),
      ),
      body: switch (_stage) {
        _Stage.pick => _pickBody(),
        _Stage.working => _workingBody(),
        _Stage.review => _reviewBody(),
      },
      bottomNavigationBar: _stage != _Stage.review
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: _groups.isEmpty ? null : _startMarking,
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: Text('Mark ${_groups.length} paper${_groups.length == 1 ? '' : 's'}'),
                ),
              ),
            ),
    );
  }

  Widget _pickBody() => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: AiMarkerColors.secondary.withValues(alpha: 0.10),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.print_rounded, color: AiMarkerColors.secondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('One trip to the photocopier', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(
                          'Put the whole class set in the copier\'s feeder and scan it to one PDF — most staffroom copiers will email it to you or drop it in your Drive. Pick that PDF here and it gets split back into one paper per student.\n\nThirty papers in about two minutes, instead of thirty photographs.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.45),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _pickPdf,
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('Choose the scanned PDF'),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Getting a clean scan', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Text(
                    '• Put a name line on EVERY page, not just the front: "Name: ______   p1/3". One footer, one print run — and it is what catches a shuffled page, because page numbers alone still read 1, 2, 3 when somebody else\'s page is in the middle.\n'
                    '• Take the staples out first. A feeder will jam or tear on one, and that is the only part that really costs you time.\n'
                    '• Flatten badly crumpled corners. Ordinary creases, pencil smudge and eraser dust all scan fine.\n'
                    '• Check the page count when it finishes. If 30 three-page tests came out as 89 pages, the feeder pulled two sheets through together and a page is missing — tell it how many students you expect below and it will flag that for you.\n'
                    '• Big stack? Scan in batches of about ten students, so one jam does not spoil the whole run.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Your phone finds where each paper starts by reading the name fields itself — nothing is uploaded to work out the split, and you get to check it before any marking happens.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.4),
            textAlign: TextAlign.center,
          ),
        ],
      );

  Widget _workingBody() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 18),
              Text(_progress, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              Text(
                'Reading happens on this phone, so a big stack takes a moment.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral),
              ),
            ],
          ),
        ),
      );

  Widget _reviewBody() {
    final cs = Theme.of(context).colorScheme;
    final named = _groups.where((g) => (g.name ?? '').isNotEmpty).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        Card(
          child: ListTile(
            leading: Icon(Icons.picture_as_pdf_rounded, color: cs.primary),
            title: Text(_fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${_pages.length} pages → ${_groups.length} papers'
                '${named > 0 ? ' · $named name${named == 1 ? '' : 's'} read off the page' : ''}'),
            trailing: TextButton(onPressed: _pickPdf, child: const Text('Change')),
          ),
        ),
        if (_truncated)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Only the first $kMaxStackPages pages were imported — split the stack into two scans if you have more.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.error),
            ),
          ),
        const SizedBox(height: 12),
        if (_check.wholeStackLooksWrong) ...[
          const SizedBox(height: 10),
          Card(
            color: AiMarkerColors.error.withValues(alpha: 0.10),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.error_rounded, size: 18, color: AiMarkerColors.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('The order looks wrong',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${_check.suspects.length} of ${_groups.length} papers have repeated or doubled-up pages. That usually means the whole stack is split in the wrong places, not that individual papers are odd.\n\n'
                    'Fix the split below, or rescan the stack — marking it like this would produce a class of wrong marks and cost you the credits to find out.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.45),
                  ),
                ],
              ),
            ),
          ),
        ],
        _splitModeCard(),
        if (_stackWarning != null) ...[
          const SizedBox(height: 10),
          Card(
            color: AiMarkerColors.warning.withValues(alpha: 0.12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.report_problem_rounded, size: 18, color: AiMarkerColors.warning),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_stackWarning!, style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4)),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text('Students expected (optional)',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
            ),
            SizedBox(
              width: 78,
              child: TextField(
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), hintText: '—'),
                onChanged: (v) => setState(() => _expectedStudents = int.tryParse(v.trim())),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('CHECK THE SPLIT', style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.2, color: AiMarkerColors.neutral)),
        const SizedBox(height: 4),
        Text(
          'Tap a page to start a new student there. Every paper marked is one submission.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < _groups.length; i++) _groupCard(i),
      ],
    );
  }

  Widget _splitModeCard() {
    final detecting = _fixedPerStudent == null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('How the stack is split', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                ChoiceChip(
                  label: const Text('Detected'),
                  selected: detecting,
                  onSelected: _detectionUsable
                      ? (_) => setState(() {
                            _fixedPerStudent = null;
                            _rebuildGroups();
                          })
                      : null,
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Same length each'),
                  selected: !detecting,
                  onSelected: (_) => setState(() {
                    _fixedPerStudent = PdfSplitter.suggestPagesPerStudent(_signals) ?? _fixedPerStudent ?? 1;
                    _rebuildGroups();
                  }),
                ),
              ],
            ),
            if (!_detectionUsable)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'No name fields or page numbers were readable in this scan, so tell it how many pages each paper is.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.4),
                ),
              ),
            if (!detecting) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('Pages per paper:', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
                    onPressed: (_fixedPerStudent ?? 1) <= 1
                        ? null
                        : () => setState(() {
                              _fixedPerStudent = _fixedPerStudent! - 1;
                              _rebuildGroups();
                            }),
                  ),
                  Text('${_fixedPerStudent ?? 1}', style: Theme.of(context).textTheme.titleMedium),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                    onPressed: (_fixedPerStudent ?? 1) >= _pages.length
                        ? null
                        : () => setState(() {
                              _fixedPerStudent = _fixedPerStudent! + 1;
                              _rebuildGroups();
                            }),
                  ),
                  const Spacer(),
                  if (_pages.length % (_fixedPerStudent ?? 1) != 0)
                    Flexible(
                      child: Text(
                        'Doesn\'t divide evenly',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.error),
                        textAlign: TextAlign.end,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _groupCard(int i) {
    final g = _groups[i];
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: cs.primary.withValues(alpha: 0.14),
                  child: Text('${i + 1}', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: cs.primary, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: () => _editName(i),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            g.name ?? 'Unnamed paper',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  color: g.name == null ? AiMarkerColors.neutral : null,
                                  fontStyle: g.name == null ? FontStyle.italic : null,
                                ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(Icons.edit_rounded, size: 14, color: AiMarkerColors.neutral),
                      ],
                    ),
                  ),
                ),
                Text('${g.pages.length} pg', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                if (i > 0)
                  IconButton(
                    tooltip: 'Join to the paper above',
                    icon: const Icon(Icons.merge_rounded, size: 20),
                    onPressed: () => _mergeUp(i),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_faultsFor(i).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.flag_rounded, size: 15, color: AiMarkerColors.warning),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(_faultsFor(i),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.warning, height: 1.35)),
                    ),
                  ],
                ),
              ),
            SizedBox(
              height: 104,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: g.pages.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, n) {
                  final pageIndex = g.pages[n];
                  return InkWell(
                    onTap: n == 0 ? null : () => _splitAt(i, pageIndex),
                    borderRadius: BorderRadius.circular(8),
                    child: Column(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: cs.outlineVariant),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Image.memory(_pages[pageIndex], height: 78, fit: BoxFit.cover),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          n == 0 ? 'p${pageIndex + 1}' : 'p${pageIndex + 1} · split',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: n == 0 ? AiMarkerColors.neutral : cs.primary,
                              ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
