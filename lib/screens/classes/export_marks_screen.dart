import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:marking_prokect_v2/models/teacher_class.dart';
import 'package:marking_prokect_v2/services/classes_service.dart';
import 'package:marking_prokect_v2/services/csv_import.dart';
import 'package:marking_prokect_v2/services/drive_service.dart';
import 'package:marking_prokect_v2/services/gradebook_export.dart';
import 'package:marking_prokect_v2/services/students_service.dart';
import 'package:marking_prokect_v2/services/submissions_service.dart';
import 'package:marking_prokect_v2/theme.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

/// Gets the marks out of Markless and into the school's gradebook.
///
/// This exists because marking thirty papers and then typing thirty numbers
/// into PowerSchool by hand leaves the teacher doing the boring half of the
/// job. Two ways out, because every board runs a different gradebook:
/// a plain CSV, or filling in a file the teacher exported from their own
/// system — which works everywhere without this app knowing the format.
class ExportMarksScreen extends StatefulWidget {
  const ExportMarksScreen({super.key});

  @override
  State<ExportMarksScreen> createState() => _ExportMarksScreenState();
}

class _ExportMarksScreenState extends State<ExportMarksScreen> {
  String? _classId;
  int _days = 30;
  bool _asPercent = false;
  bool _busy = false;

  List<MarkRow> get _rows {
    final id = _classId;
    if (id == null) return const [];
    return GradebookExport.rowsForClass(
      students: context.read<StudentsService>().students,
      submissions: context.read<SubmissionsService>().submissions,
      classId: id,
      since: _days > 0 ? DateTime.now().subtract(Duration(days: _days)) : null,
    );
  }

  Future<void> _shareCsv(String csv, String filename) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$filename');
    await f.writeAsString(csv, flush: true);
    await Share.shareXFiles([XFile(f.path)], subject: filename);
  }

  Future<void> _exportPlain() async {
    final rows = _rows;
    if (rows.isEmpty) return;
    final klass = context.read<ClassesService>().getById(_classId ?? '');
    setState(() => _busy = true);
    try {
      final csv = GradebookExport.plainCsv(rows, assessment: klass?.name ?? 'Assessment');
      await _shareCsv(csv, 'markless-marks-${rows.length}-students.csv');
    } catch (e) {
      if (mounted) _snack('Couldn\'t build the file: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Puts the marks in the teacher's own Google Drive as a spreadsheet.
  ///
  /// Deliberately not a Classroom sync: that needs Google's review and each
  /// district's IT admin to allow the app. A Sheet in their own Drive needs
  /// neither, and they can share it or copy it into their real gradebook.
  Future<void> _exportToDrive() async {
    final rows = _rows;
    if (rows.isEmpty) return;
    final klass = context.read<ClassesService>().getById(_classId ?? '');
    final name = klass?.name ?? 'Assessment';
    final now = DateTime.now();
    final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    setState(() => _busy = true);
    try {
      final link = await DriveService().uploadSheet(
        title: 'Marks — $name — $date',
        csv: GradebookExport.plainCsv(rows, assessment: name),
      );
      if (!mounted) return;
      _snack(link == null || link.isEmpty
          ? 'Saved to your Google Drive.'
          : 'Saved to your Google Drive, in the Markless folder.');
    } on DriveAuthException {
      if (mounted) _snack('Sign in with Google again to save to Drive.');
    } catch (e) {
      if (mounted) _snack('Couldn\'t save to Drive: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The one that works with any gradebook: the teacher hands over a file
  /// exported from their own system and gets it back with a marks column.
  Future<void> _fillTemplate() async {
    final rows = _rows;
    if (rows.isEmpty) return;
    try {
      final res = await FilePicker.pickFiles(type: FileType.any, withData: true);
      final f = res?.files.firstOrNull;
      final bytes = f?.bytes;
      if (f == null || bytes == null) return;
      if (!mounted) return;
      setState(() => _busy = true);

      final template = CsvImport.parse(utf8.decode(bytes, allowMalformed: true));

      // Classroom's export is the one shape worth recognising: it splits
      // the name over two columns, which the single-column finder can't
      // match on, so without this a Classroom file fills almost nothing.
      final classroom = ClassroomSheet.detect(template);
      final nameCol = classroom?.firstNameColumn ?? GradebookTemplate.findNameColumn(template);
      if (nameCol < 0) {
        setState(() => _busy = false);
        _snack('Couldn\'t find a column of student names in that file.');
        return;
      }
      final filled = GradebookTemplate.fill(
        template: template,
        marks: rows,
        nameColumn: nameCol,
        lastNameColumn: classroom?.lastNameColumn ?? -1,
        asPercent: _asPercent,
      );
      if (classroom != null && mounted) _snack('Recognised a Google Classroom grade sheet.');
      await _shareCsv(filled.csv, 'filled-${f.name.replaceAll('.csv', '')}.csv');
      if (!mounted) return;
      setState(() => _busy = false);
      await _reportGaps(filled);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('Couldn\'t fill that file: ${e.toString().replaceFirst('Exception: ', '')}');
    }
  }

  /// Never let a teacher upload a gradebook with silent holes in it.
  Future<void> _reportGaps(TemplateFill filled) async {
    if (filled.unmatched.isEmpty && filled.notInTemplate.isEmpty) {
      _snack('${filled.filled} marks written in.');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${filled.filled} marks written in'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (filled.unmatched.isNotEmpty) ...[
                Text('No mark for these students', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(filled.unmatched.join(', '),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4)),
                const SizedBox(height: 12),
              ],
              if (filled.notInTemplate.isNotEmpty) ...[
                Text('Marked, but not in your gradebook file', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(filled.notInTemplate.join(', '),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4)),
                const SizedBox(height: 12),
              ],
              Text(
                'Their rows were left untouched — nothing was guessed. Check the spelling on both sides, or enter those by hand.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.4),
              ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Got it'))],
      ),
    );
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final classes = context.watch<ClassesService>().classes;
    final rows = _rows;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.pop()),
        title: const Text('Export marks'),
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _classId,
                  decoration: const InputDecoration(labelText: 'Class', border: OutlineInputBorder()),
                  items: [
                    for (final TeacherClass c in classes)
                      DropdownMenuItem(value: c.id, child: Text('${c.name} · ${c.period}')),
                  ],
                  onChanged: (v) => setState(() => _classId = v),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Marked in the last', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final d in const [7, 30, 90, 0])
                              ChoiceChip(
                                label: Text(d == 0 ? 'All time' : '$d days'),
                                selected: _days == d,
                                onSelected: (_) => setState(() => _days = d),
                              ),
                          ],
                        ),
                        const Divider(height: 22),
                        Row(
                          children: [
                            Expanded(
                              child: Text('Write percentages instead of raw scores',
                                  style: Theme.of(context).textTheme.bodyMedium),
                            ),
                            Switch(value: _asPercent, onChanged: (v) => setState(() => _asPercent = v)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  color: rows.isEmpty ? null : Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      _classId == null
                          ? 'Pick a class to see what there is to export.'
                          : rows.isEmpty
                              ? 'No marked papers for that class in this window. Try a longer one.'
                              : '${rows.length} students with a mark. Where a student was marked twice, the most recent one is used.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: rows.isEmpty ? null : _fillTemplate,
                  icon: const Icon(Icons.upload_file_rounded),
                  label: const Text('Fill in my gradebook\'s file'),
                ),
                const SizedBox(height: 6),
                Text(
                  'Export a file from PowerSchool, Aspen, MyEd, Classroom or a spreadsheet, pick it here, and get it '
                  'back with the marks written in. Works with any system, because you supply the format.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.4),
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: rows.isEmpty ? null : _exportPlain,
                  icon: const Icon(Icons.table_view_rounded),
                  label: const Text('Plain spreadsheet instead'),
                ),
                const SizedBox(height: 6),
                Text(
                  'Name, score, percent and feedback. Opens in Excel or Sheets for copying a column across.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.4),
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: rows.isEmpty ? null : _exportToDrive,
                  icon: const Icon(Icons.add_to_drive_rounded),
                  label: const Text('Save to Google Drive'),
                ),
                const SizedBox(height: 6),
                Text(
                  'Puts the same marks in your own Drive as a Google Sheet, in a Markless folder. '
                  'Share it, keep it as a record, or copy the columns into Classroom yourself.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.4),
                ),
              ],
            ),
    );
  }
}
