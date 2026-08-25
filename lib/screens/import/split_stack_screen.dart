import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:marking_prokect_v2/app/app_routes.dart';
import 'package:marking_prokect_v2/services/batch_marking.dart';
import 'package:marking_prokect_v2/services/document_processor.dart';
import 'package:marking_prokect_v2/services/drive_picker.dart';
import 'package:marking_prokect_v2/services/pdf_splitter.dart';
import 'package:marking_prokect_v2/theme.dart';

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

      final usable = !PdfSplitter.detectionUnusable(signals);
      final suggested = PdfSplitter.suggestPagesPerStudent(signals);
      setState(() {
        _pages = processed;
        _signals = signals;
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

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  void _startMarking() {
    final groups = <List<Uint8List>>[];
    final names = <String?>[];
    for (final g in _groups) {
      if (g.pages.isEmpty) continue;
      groups.add([for (final p in g.pages) _pages[p]]);
      names.add(g.name);
    }
    if (groups.isEmpty) return;
    final n = enqueueStudentGroups(context: context, groups: groups, studentNames: names);
    if (n == 0) {
      _snack('Couldn\'t start marking — try signing in again.');
      return;
    }
    _snack('Marking $n papers in the background — results land in the tray as they finish.');
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
        _splitModeCard(),
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
