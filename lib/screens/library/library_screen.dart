import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:marking_prokect_v2/app/app_state.dart';
import 'package:marking_prokect_v2/screens/grading/live_scan_screen.dart';
import 'package:marking_prokect_v2/services/drive_picker.dart';
import 'package:marking_prokect_v2/services/ai_grading_service.dart';
import 'package:marking_prokect_v2/services/auth_service.dart';
import 'package:marking_prokect_v2/theme.dart';
import 'package:marking_prokect_v2/widgets/teacher_topbar.dart';
import 'package:provider/provider.dart';

/// Answer key library: every key the teacher has scanned, ready to reuse.
/// (The old marking-scheme library was removed from the UI — scheme data and
/// services still exist, the AI now detects the assignment type itself.)
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  bool _loading = false;
  List<AnswerKeySummary> _keys = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final auth = context.read<AuthService>().currentUser;
    if (auth == null) return;
    setState(() => _loading = true);
    try {
      final keys = await AiGradingService().listAnswerKeys(teacherId: auth.id);
      if (!mounted) return;
      setState(() => _keys = keys);
    } catch (e) {
      debugPrint('LibraryScreen._refresh failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _scanNewKey() async {
    final auth = context.read<AuthService>().currentUser;
    if (auth == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sign in first.')));
      return;
    }

    // Camera scan, or pull the key document from Files / Google Drive —
    // same choice as the home screen's Scan Answer Key button.
    final source = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('Scan with camera'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.add_to_drive_rounded),
              title: const Text('Files or Google Drive'),
              subtitle: const Text('Pick images of the key from Drive or any storage'),
              onTap: () => Navigator.pop(context, 'files'),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    List<ScannedPage>? pages;
    if (source == 'files') {
      pages = <ScannedPage>[];
      try {
        // Drive app's own picker first; system picker as the fallback.
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 18),
                Expanded(child: Text('Loading from Google Drive…')),
              ],
            ),
          ),
        );
        DriveImport import;
        try {
          import = await DrivePicker.importScannedPages();
        } finally {
          if (mounted) Navigator.of(context, rootNavigator: true).pop();
        }
        if (!mounted || import.cancelled) return;
        if (import.pages.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            duration: Duration(seconds: 6),
            content: Text('That file couldn\'t be read — pick a photo or a PDF of the key. For a Google Doc, use Share → Save as PDF in Drive first.'),
          ));
          return;
        }
        pages.addAll(import.pages);
      } on DrivePickerUnavailable {
        final res = await FilePicker.pickFiles(
          type: FileType.any,
          allowMultiple: true,
          withData: true,
        );
        if (res == null || res.files.isEmpty) return;
        for (final f in res.files) {
          final bytes = f.bytes;
          if (bytes == null) continue;
          pages.addAll(await pagesFromPickedFile(name: f.name, mime: '', bytes: bytes));
        }
      }
    } else {
      pages = await Navigator.of(context).push<List<ScannedPage>>(
        MaterialPageRoute(builder: (_) => const LiveScanScreen()),
      );
    }
    if (pages == null || pages.isEmpty || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 18),
            Expanded(child: Text('Reading the answer key…\nThis happens only once — it will be saved for reuse.')),
          ],
        ),
      ),
    );
    try {
      final key = await AiGradingService().extractAnswerKey(
        teacherId: auth.id,
        pages: pages.map((p) => p.bytes).toList(growable: false),
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      context.read<AppState>().setAnswerKey(id: key.id, name: key.name);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Answer key saved: ${key.name} — it will be used for the next grade.')),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not read the answer key: $e')));
    }
  }

  void _useKey(AnswerKeySummary key) {
    context.read<AppState>().setAnswerKey(id: key.id, name: key.name);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${key.name} will be used for the next grade.')),
    );
  }

  void _clearActiveKey() {
    context.read<AppState>().setAnswerKey(id: '', name: '');
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Answer key cleared — next grade marks without one.')));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeKeyId = context.watch<AppState>().draft.answerKeyId;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
            children: [
              TeacherTopbar(
                title: 'Markless',
                trailingIcon: Icons.add_rounded,
                onBell: _scanNewKey,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: Text('Answers', style: Theme.of(context).textTheme.titleLarge)),
                  FilledButton.icon(
                    onPressed: _scanNewKey,
                    style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: Colors.white),
                    icon: const Icon(Icons.document_scanner_rounded, color: Colors.white),
                    label: const Text('Scan Key'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Scan a test\'s answer key once — it\'s read, saved, and every student is marked strictly against it.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.4),
              ),
              const SizedBox(height: 14),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 20),
                  child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                )
              else if (_keys.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 28),
                  child: Column(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(18)),
                        child: Icon(Icons.key_rounded, color: cs.primary, size: 28),
                      ),
                      const SizedBox(height: 14),
                      Text('No answer keys yet', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 6),
                      Text(
                        'Scan your first answer key to start marking tests against it.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AiMarkerColors.neutral, height: 1.45),
                      ),
                    ],
                  ),
                )
              else
                for (final key in _keys) ...[
                  Card(
                    child: ListTile(
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: (key.id == activeKeyId ? AiMarkerColors.secondary : cs.primary).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(Icons.key_rounded, color: key.id == activeKeyId ? AiMarkerColors.secondary : cs.primary),
                      ),
                      title: Text(key.name, style: Theme.of(context).textTheme.titleSmall),
                      subtitle: Text(
                        [
                          if ((key.subject ?? '').isNotEmpty) key.subject!,
                          if (key.totalMarks != null) '${key.totalMarks!.round()} marks',
                          if (key.id == activeKeyId) 'Active for next grade',
                        ].join(' · '),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: key.id == activeKeyId ? AiMarkerColors.secondary : AiMarkerColors.neutral,
                            ),
                      ),
                      trailing: key.id == activeKeyId
                          ? IconButton(
                              tooltip: 'Stop using this key',
                              onPressed: _clearActiveKey,
                              icon: Icon(Icons.close_rounded, color: AiMarkerColors.neutral),
                            )
                          : Icon(Icons.chevron_right_rounded, color: AiMarkerColors.neutral.withValues(alpha: 0.8)),
                      onTap: () => _useKey(key),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
            ],
          ),
        ),
      ),
    );
  }
}
