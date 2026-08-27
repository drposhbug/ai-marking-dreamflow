import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:marking_prokect_v2/services/drive_picker.dart';
import 'package:marking_prokect_v2/services/test_stamper.dart';
import 'package:marking_prokect_v2/theme.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Prints the identity onto the paper so the student never has to.
///
/// A teacher picks their test, says how many copies, and gets one PDF back
/// with every copy stamped in the footer of every page. Print it exactly as
/// they print anything else. Scanned in afterwards, pages sharing a code
/// are one paper — no name to write thirty times, no handwriting to read,
/// no guessing at boundaries.
///
/// Generation is entirely on the device: it costs nothing, and it removes
/// the credits a mis-split stack would otherwise burn.
class PrepareTestScreen extends StatefulWidget {
  const PrepareTestScreen({super.key});

  @override
  State<PrepareTestScreen> createState() => _PrepareTestScreenState();
}

class _PrepareTestScreenState extends State<PrepareTestScreen> {
  List<Uint8List> _pages = const [];
  String _fileName = '';
  String _code = TestStamper.newTestCode();
  int _copies = 30;
  bool _busy = false;
  String _progress = '';

  Future<void> _pickTest() async {
    try {
      final res = await FilePicker.pickFiles(type: FileType.any, withData: true);
      final f = res?.files.firstOrNull;
      final bytes = f?.bytes;
      if (f == null || bytes == null) return;
      if (!mounted) return;
      setState(() {
        _busy = true;
        _progress = 'Reading your test…';
      });
      final images = await renderPdfPages(bytes, maxPages: 20);
      if (!mounted) return;
      if (images.isEmpty) {
        setState(() => _busy = false);
        _snack('Couldn\'t read that as a test. A PDF works best.');
        return;
      }
      setState(() {
        _pages = images;
        _fileName = f.name;
        _busy = false;
      });
    } catch (e) {
      debugPrint('Prepare test pick failed: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('Couldn\'t read that file.');
    }
  }

  Future<void> _generate() async {
    if (_pages.isEmpty) return;
    setState(() {
      _busy = true;
      _progress = 'Making $_copies copies…';
    });
    try {
      final bytes = await TestStamper.build(
        pageImages: _pages,
        testCode: _code,
        copies: _copies,
        onProgress: (done, total) {
          if (mounted) setState(() => _progress = 'Making copies… $done of $total');
        },
      );
      final dir = await getTemporaryDirectory();
      final out = File('${dir.path}/markless-$_code-$_copies-copies.pdf');
      await out.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      setState(() => _busy = false);
      // Hand it straight to whatever the teacher prints with — the copier
      // app, Drive, or email to themselves.
      await Share.shareXFiles(
        [XFile(out.path)],
        subject: 'Markless test $_code — $_copies copies',
        text: 'Print this one file. Every copy carries its own code.',
      );
    } catch (e) {
      debugPrint('Prepare test generate failed: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('Couldn\'t build the copies: ${e.toString().replaceFirst('Exception: ', '')}');
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.pop()),
        title: const Text('Prepare a test'),
      ),
      body: _busy
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(_progress),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: AiMarkerColors.secondary.withValues(alpha: 0.10),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Let the paper carry the name',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        Text(
                          'Every copy gets its own tiny code printed in the footer of every page. When you scan the '
                          'stack back in, pages sharing a code are one student\'s paper — so nothing depends on '
                          'students writing their name more than once, or on the pile staying in order.\n\n'
                          'You print it exactly as you print anything else.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.45),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (_pages.isEmpty)
                  FilledButton.icon(
                    onPressed: _pickTest,
                    icon: const Icon(Icons.upload_file_rounded),
                    label: const Text('Choose your test'),
                  )
                else ...[
                  Card(
                    child: ListTile(
                      leading: Icon(Icons.description_rounded, color: cs.primary),
                      title: Text(_fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${_pages.length} pages'),
                      trailing: TextButton(onPressed: _pickTest, child: const Text('Change')),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text('Copies to print', style: Theme.of(context).textTheme.titleSmall),
                              ),
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
                                onPressed: _copies <= 1 ? null : () => setState(() => _copies--),
                              ),
                              Text('$_copies', style: Theme.of(context).textTheme.titleMedium),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                                onPressed: _copies >= 60 ? null : () => setState(() => _copies++),
                              ),
                            ],
                          ),
                          const Divider(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Test code', style: Theme.of(context).textTheme.titleSmall),
                                    Text('Printed as  mk·$_code·01 · p1/${_pages.length}',
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                                  ],
                                ),
                              ),
                              TextButton(
                                onPressed: () => setState(() => _code = TestStamper.newTestCode()),
                                child: const Text('New code'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'It prints small and grey at the bottom of the page — students won\'t give it a second look.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _generate,
                    icon: const Icon(Icons.picture_as_pdf_rounded),
                    label: Text('Make $_copies copies to print'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_copies * _pages.length} pages in one file. Send it to the staffroom copier the way you would any '
                    'other document — printing one long file and printing $_copies copies are the same job.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.4),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
    );
  }
}
