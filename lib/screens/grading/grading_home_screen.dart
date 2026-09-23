import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:marking_prokect_v2/app/app_routes.dart';
import 'package:marking_prokect_v2/app/app_state.dart';
import 'package:marking_prokect_v2/models/teacher_class.dart';
import 'package:marking_prokect_v2/screens/grading/live_scan_screen.dart';
import 'package:marking_prokect_v2/screens/grading/web_image_picker.dart';
import 'package:marking_prokect_v2/services/anonymizer.dart';
import 'package:marking_prokect_v2/services/browser_intake.dart';
import 'package:marking_prokect_v2/services/bulk_page_processor.dart';
import 'package:marking_prokect_v2/services/document_processor.dart';
import 'package:marking_prokect_v2/services/drive_picker.dart';
import 'package:marking_prokect_v2/services/dropped_intake.dart';
import 'package:marking_prokect_v2/services/auth_service.dart';
import 'package:marking_prokect_v2/services/batch_marking.dart';
import 'package:marking_prokect_v2/services/classes_service.dart';
import 'package:marking_prokect_v2/services/grading_queue_service.dart';
import 'package:marking_prokect_v2/services/overnight_service.dart';
import 'package:marking_prokect_v2/services/students_service.dart';
import 'package:marking_prokect_v2/services/submissions_service.dart';
import 'package:marking_prokect_v2/theme.dart';
import 'package:marking_prokect_v2/widgets/drop_target_overlay.dart';
import 'package:marking_prokect_v2/widgets/pill.dart';
import 'package:marking_prokect_v2/widgets/responsive.dart';
import 'package:marking_prokect_v2/widgets/teacher_topbar.dart';
import 'package:marking_prokect_v2/widgets/web_upload_gate.dart';
import 'package:provider/provider.dart';

class GradingHomeScreen extends StatefulWidget {
  const GradingHomeScreen({super.key});

  @override
  State<GradingHomeScreen> createState() => _GradingHomeScreenState();
}

class _GradingHomeScreenState extends State<GradingHomeScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<_StudentSuggestion> _studentHits = const [];

  final ImagePicker _picker = ImagePicker();

  /// Dragging a folder onto the window and pasting a screenshot, on a
  /// desktop browser. Null everywhere else — the gesture does not exist on a
  /// phone, so nothing about it is shown there either.
  BrowserIntake? _browserIntake;
  bool _dragOver = false;

  /// A second drop while the class picker is still open would stack two
  /// intakes on top of each other and mark the same papers twice.
  bool _intakeBusy = false;

  @override
  void initState() {
    super.initState();
    _browserIntake = startBrowserIntake(
      onHover: (hovering) {
        if (!mounted || hovering == _dragOver) return;
        setState(() => _dragOver = hovering && _isVisibleTab);
      },
      onDropped: (files) => _intakeDroppedFiles(files, pasted: false),
      onPasted: (files) => _intakeDroppedFiles(files, pasted: true),
    );
  }

  @override
  void dispose() {
    _browserIntake?.dispose();
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// The drop listeners live on the whole document, but the grading tab is
  /// kept alive behind the others. A drop while the teacher is looking at
  /// her dashboard must not silently push her onto a marking screen.
  bool get _isVisibleTab => TickerMode.valuesOf(context).enabled;

  Future<void> _handlePickedFile(XFile? image) async {
    if (image == null) return;
    try {
      await _handleSinglePhoto(PickedPhoto(bytes: await image.readAsBytes(), fileName: image.name));
    } catch (e) {
      debugPrint('Failed to read picked image bytes: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not read image.')));
    }
  }

  /// One page, however it arrived — picked, dropped or pasted. Everything
  /// after this point is the single-photo route the gallery has always used.
  Future<void> _handleSinglePhoto(PickedPhoto photo) async {
    try {
      // Photos get the same scanner treatment as live scans: EXIF/sideways
      // rotation, straightening, contrast, and sharpening.
      final processed = await DocumentProcessor.processPage(photo.bytes);
      if (!mounted) return;
      context.read<AppState>().setImageBytes(bytes: processed, fileName: photo.fileName);
      context.push(AppRoutes.gradingContext, extra: {'imageBytes': processed, 'fileName': photo.fileName});
    } catch (e) {
      debugPrint('Failed to prepare picked image: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not read image.')));
    }
  }

  /// Shared with every other browser upload route — see
  /// [ensureWebUploadAcknowledged]. A gate on this screen but not on the
  /// stack splitter would be the same as no gate at all.
  Future<bool> _webUploadAcknowledged() => ensureWebUploadAcknowledged(
        context,
        teacherId: context.read<AuthService>().currentUser?.id,
        onUseForm: () => context.push(AppRoutes.importResponses),
      );

  /// Asks which class the scan is for so grading automatically uses that
  /// class's grade level. Returns false when the teacher dismisses the sheet
  /// (cancels the scan). Skipped silently when no classes exist yet.
  Future<bool> _askWhichClass() async {
    final classes = context.read<ClassesService>().classes;
    if (classes.isEmpty) return true;
    final draft = context.read<AppState>().draft;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ClassPickerSheet(classes: classes, currentId: draft.classId),
    );
    if (picked == null || !mounted) return false;
    final app = context.read<AppState>();
    app.setStudentClassPreset(classId: picked); // '' = no class
    if (picked.isNotEmpty) {
      final k = classes.cast<TeacherClass?>().firstWhere((c) => c?.id == picked, orElse: () => null);
      if (k?.gradeLevel != null) app.setGradeLevel(k!.gradeLevel!);
    }
    return true;
  }

  Future<void> _pickFromCamera() async {
    if (!await _webUploadAcknowledged() || !mounted) return;
    final ok = await _askWhichClass();
    if (!ok || !mounted) return;
    try {
      // Live auto-scan camera: holds the preview open and auto-captures
      // each page once it's held steady, so the teacher can keep sliding
      // assignments through. Returns every captured page when the teacher
      // taps Done; an empty list means the scan was cancelled.
      if (!mounted) return;
      final pages = await Navigator.of(context).push<List<ScannedPage>>(
        MaterialPageRoute(builder: (_) => const LiveScanScreen()),
      );
      if (pages == null || pages.isEmpty) return;
      if (!mounted) return;
      context.read<AppState>().setPages(pages);
      context.push(AppRoutes.gradingContext);
    } catch (e) {
      debugPrint('Pick from camera failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open camera.')));
    }
  }

  /// Multi-select images or PDFs via the system document picker; images get
  /// the full scanner treatment, PDFs are rendered to pages on-device.
  Future<List<ScannedPage>> _pickPagesFromFiles() async {
    // FileType.any, not a custom extension list: Drive-backed files often
    // arrive without an extension and get greyed out by the filter, which
    // looks like "I can't select my JPG". The bytes are sniffed after.
    final res = await FilePicker.pickFiles(
      type: FileType.any,
      allowMultiple: true,
      withData: true,
    );
    if (res == null || res.files.isEmpty) return const [];
    final pages = <ScannedPage>[];
    for (final f in res.files) {
      final bytes = f.bytes;
      if (bytes == null) continue;
      pages.addAll(await pagesFromPickedFile(name: f.name, mime: '', bytes: bytes));
    }
    return pages;
  }

  Future<void> _pickFromGallery() async {
    if (!await _webUploadAcknowledged() || !mounted) return;
    final ok = await _askWhichClass();
    if (!ok || !mounted) return;
    try {
      if (kIsWeb) {
        final picked = await pickWebImage(captureEnvironmentCamera: false);
        if (picked == null) return;
        final processed = await DocumentProcessor.processPage(picked.bytes);
        if (!mounted) return;
        context.read<AppState>().setImageBytes(bytes: processed, fileName: picked.name);
        context.push(AppRoutes.gradingContext, extra: {'imageBytes': processed, 'fileName': picked.name});
        return;
      }

      final images = await _picker.pickMultiImage(imageQuality: 85);
      if (images.isEmpty || !mounted) return;
      if (images.length == 1) {
        await _handlePickedFile(images.first);
        return;
      }

      final choice = await _askOneTestOrOnePerStudent(images.length);
      if (!mounted || choice == null) return;

      final picked = <PickedPhoto>[];
      for (final img in images) {
        picked.add(PickedPhoto(bytes: await img.readAsBytes(), fileName: img.name));
      }
      await _prepareAndFilePhotos(picked, choice);
    } catch (e) {
      debugPrint('Pick from gallery failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open gallery.')));
    }
  }

  void _snackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Work dragged onto the window, or a screenshot pasted with Ctrl-V.
  ///
  /// This is a pick like any other, so it goes through the same three gates
  /// in the same order — the browser upload acknowledgement, the class, then
  /// the page ceiling — and then joins the gallery route. A teacher who
  /// dropped a folder gets exactly what she would have got had she picked
  /// the same files, including the batching question and the counted
  /// progress she can stop.
  Future<void> _intakeDroppedFiles(List<DroppedFile> files, {required bool pasted}) async {
    if (!mounted || _intakeBusy || !_isVisibleTab) return;
    _intakeBusy = true;
    try {
      final usable = markableDrops(files);
      final skipped = files.length - usable.length;
      if (usable.isEmpty) {
        _snackBar(pasted ? 'There was no image on the clipboard. Copy a screenshot first, then paste.' : 'Nothing there Markless can mark. Drop photos of the work, or PDFs.');
        return;
      }

      if (!await _webUploadAcknowledged() || !mounted) return;
      final ok = await _askWhichClass();
      if (!ok || !mounted) return;

      final photos = await _photosFromDroppedFiles(usable);
      if (!mounted || photos == null) return;
      if (photos.isEmpty) {
        _snackBar('Those files couldn\'t be read. Drop photos of the work, or PDFs.');
        return;
      }
      if (skipped > 0) {
        _snackBar('$skipped file${skipped == 1 ? '' : 's'} skipped — only photos and PDFs can be marked.');
      }

      if (photos.length == 1) {
        await _handleSinglePhoto(photos.first);
        return;
      }
      final choice = await _askOneTestOrOnePerStudent(photos.length);
      if (!mounted || choice == null) return;
      await _prepareAndFilePhotos(photos, choice);
    } catch (e) {
      debugPrint('Drop intake failed: $e');
      _snackBar('Could not read what was dropped.');
    } finally {
      _intakeBusy = false;
    }
  }

  /// A drop, flattened into the pile of photos the gallery route expects.
  ///
  /// A dropped PDF is a stack of pages, so its pages are rendered first and
  /// keep the file's name — that is what lets one student's three pages be
  /// marked as one paper further down. When nothing is a PDF this is free
  /// and the drop goes straight through.
  Future<List<PickedPhoto>?> _photosFromDroppedFiles(List<DroppedFile> files) async {
    if (!files.any((f) => f.isPdf)) return photosFromDrop(files);

    // A drop of PDFs can be a whole class set, and rendering is real work:
    // the teacher gets the same count and the same way out she gets for a
    // Drive import rather than a spinner she can only force-quit.
    final capped = await _confirmBulkCap(photosFromDrop(files));
    if (capped == null || !mounted) return null;
    // The cap keeps the first N in order, so the files it kept are the same
    // first N — cheaper and safer than matching them back up by name.
    final todo = files.sublist(0, capped.length);

    return _withCountedProgress<List<PickedPhoto>>(
      total: todo.length,
      label: (done, total) => 'Reading file ${done + (done < total ? 1 : 0)} of $total',
      note: 'Each page inside a PDF is rendered before marking. You can stop and keep what is ready.',
      work: (run) async {
        final out = <PickedPhoto>[];
        for (var i = 0; i < todo.length; i++) {
          if (run.stopped) break;
          final file = todo[i];
          if (file.isPdf) {
            try {
              final images = await renderPdfPages(file.bytes);
              for (var p = 0; p < images.length; p++) {
                out.add(PickedPhoto(bytes: images[p], fileName: '${file.name} (page ${p + 1})'));
              }
            } catch (e) {
              // One unreadable PDF must not cost her the rest of the stack.
              debugPrint('Could not render dropped PDF "${file.name}": $e');
            }
          } else {
            out.add(PickedPhoto(bytes: file.bytes, fileName: file.name));
          }
          run.report(i + 1, todo.length);
        }
        return out;
      },
    );
  }

  /// Several pages at once: are they the pages of ONE test, or one test per
  /// page? Asked the same way whether they were picked, dropped or pasted,
  /// because the answer decides whether this is one mark or thirty.
  Future<String?> _askOneTestOrOnePerStudent(int count) => showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('$count photos picked'),
          content: const Text('Are these the pages of one test, or a separate student\'s test per photo?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'combine'), child: const Text('One test (pages)')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'batch'), child: const Text('One per student')),
          ],
        ),
      );

  /// Prepares a pile of pages and files them the way the teacher asked —
  /// one submission, or one background job per student.
  ///
  /// Every multi-page route ends here, so a drop and a gallery pick cannot
  /// drift apart in what they do with what they collected.
  Future<void> _prepareAndFilePhotos(List<PickedPhoto> photos, String choice) async {
    final result = await _preparePickedPhotos(photos);
    if (!mounted || result == null) return;
    if (result.failed.isNotEmpty) {
      _snackBar('Couldn\'t read ${result.failed.length} of the photos — the rest are ready. '
          'Re-shoot ${result.failed.take(3).join(', ')}${result.failed.length > 3 ? '…' : ''}');
    }
    if (result.pages.isEmpty) return;

    if (choice == 'batch') {
      // Pages of one dropped PDF belong to one student — marking them as
      // three students would hand back three part-marks and three names.
      _enqueueBatch(groupPagesBySourceFile(result.pages));
      return;
    }
    context.read<AppState>().setPages(result.pages);
    context.push(AppRoutes.gradingContext);
  }

  /// The 60-page ceiling, and the plain-English warning that goes with it.
  ///
  /// Returns what will actually be prepared, or null when the teacher backs
  /// out. Dropping a folder of 300 scans has to land here exactly as picking
  /// 300 photos does, or it is an out-of-memory crash instead of a choice.
  Future<List<PickedPhoto>?> _confirmBulkCap(List<PickedPhoto> picked) async {
    final warning = bulkPickWarning(picked.length);
    if (warning == null) return picked;
    if (!mounted) return null;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('That is a lot of photos'),
        content: Text(warning),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Prepare $kMaxGalleryPhotos'),
          ),
        ],
      ),
    );
    if (go != true) return null;
    return capPicked(picked);
  }

  /// Straightens and cleans a pile of picked photos, showing how far along it
  /// is and letting the teacher stop.
  ///
  /// A class set is thirty photos and each one is decoded at full camera
  /// resolution, so this is minutes of work, not seconds. A spinner with no
  /// count and no way out is how a teacher ends up force-quitting halfway
  /// and losing the lot. Returns null if they backed out with nothing done.
  Future<BulkPageResult?> _preparePickedPhotos(List<PickedPhoto> picked) async {
    final todo = await _confirmBulkCap(picked);
    if (todo == null || !mounted) return null;

    return _withCountedProgress<BulkPageResult>(
      total: todo.length,
      label: (done, total) => 'Preparing photo ${done + (done < total ? 1 : 0)} of $total',
      note: 'Straightening and sharpening each page. You can stop and keep what is ready.',
      work: (run) => processPickedPages(
        todo,
        process: DocumentProcessor.processPage,
        isCancelled: () => run.stopped,
        onProgress: (d, t) => run.report(d, t),
      ),
    );
  }

  /// Runs [work] behind a dialog that shows a real count and a Stop button.
  ///
  /// A pile of photos or a class set of PDFs is minutes of work, and a bare
  /// spinner through all of it is how a teacher ends up force-quitting halfway
  /// and losing the lot. So she gets three things: a count that moves, a way
  /// out that keeps whatever is already done, and a close that can only ever
  /// take this dialog. Back is deliberately blocked while it runs, which makes
  /// closing in a finally essential — a failure part-way must never leave her
  /// trapped behind a dialog nothing can dismiss.
  Future<T> _withCountedProgress<T>({
    required String Function(int done, int total) label,
    required String note,
    required Future<T> Function(_CountedRun run) work,
    int total = 0,
  }) async {
    final run = _CountedRun()..total = total;
    final navigator = Navigator.of(context, rootNavigator: true);

    // Held as a route rather than closed through the builder's context: work
    // that finishes before the dialog has built would otherwise leave it up,
    // and popping "whatever is on top" is what threw teachers off screens.
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        // Back must not dismiss the dialog out from under a run that is still
        // going — Stop is the way out, so the loop stops with it.
        canPop: false,
        child: AlertDialog(
          content: StatefulBuilder(builder: (ctx, setInner) {
            run._redraw = () => setInner(() {});
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label(run.done, run.total)),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  // A bar that fills is only honest once the total is known;
                  // until then it sweeps rather than claiming a fraction.
                  child: LinearProgressIndicator(value: run.total == 0 ? null : run.done / run.total),
                ),
                const SizedBox(height: 10),
                Text(
                  note,
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral),
                ),
              ],
            );
          }),
          actions: [
            TextButton(onPressed: () => run.stopped = true, child: const Text('Stop')),
          ],
        ),
      ),
    );
    unawaited(navigator.push(route));

    try {
      return await work(run);
    } finally {
      run._redraw = null;
      // removeRoute rather than pop: it works whether or not the dialog has
      // finished animating in, and can only ever remove this route.
      if (route.isActive) navigator.removeRoute(route);
    }
  }

  /// Assignment pages straight from the Google Drive app's own picker;
  /// falls back to the system file picker when Drive isn't installed.
  /// Multi-select supported; every page gets the scanner treatment.
  Future<void> _pickFromDrive() async {
    if (!await _webUploadAcknowledged() || !mounted) return;
    final ok = await _askWhichClass();
    if (!ok || !mounted) return;
    try {
      // The Drive app's picker is often single-select, so let the teacher
      // stack up the whole class set across several picks before marking.
      final groups = <List<ScannedPage>>[];
      var unreadable = 0;
      var pdfTruncated = false;
      while (true) {
        // A whole class set of PDFs is every page of every file rendered and
        // straightened, so the count matters: "file 4 of 12" tells her it is
        // working and roughly how long is left, where a spinner tells her
        // nothing and invites a force-quit. The total is only knowable once
        // Drive hands the files back, so it starts as an honest "loading".
        final import = await _withCountedProgress<DriveImport>(
          label: (done, total) => total == 0 ? 'Loading from Google Drive…' : 'Reading file ${done + (done < total ? 1 : 0)} of $total',
          note: 'Each page is rendered and straightened before marking. You can stop and keep what is ready.',
          work: (run) => DrivePicker.importScannedPages(
            onProgress: run.report,
            isCancelled: () => run.stopped,
          ),
        );
        if (!mounted) return;
        if (import.cancelled) {
          if (groups.isEmpty) return; // cancelled the first pick — nothing to do
          break; // cancelled an "add more" round — mark what we have
        }
        // Stopped before the first file finished: nothing failed, so telling
        // her a file "couldn't be read" would be a lie about her own choice.
        if (import.pages.isEmpty && import.unreadable == 0) {
          if (groups.isEmpty) return;
          break;
        }
        if (import.pages.isEmpty) {
          final who = import.unreadableNames.isEmpty ? 'That file' : '"${import.unreadableNames.first}"';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            duration: const Duration(seconds: 7),
            content: Text('$who couldn\'t be read — pick a photo or a PDF. For a Google Doc, open it in Drive and use Share → Save as PDF first.'),
          ));
          if (groups.isEmpty) return;
        } else {
          groups.addAll(import.fileGroups);
          unreadable += import.unreadable;
          pdfTruncated = pdfTruncated || import.pdfTruncated;
        }

        final more = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('${groups.length} test file${groups.length == 1 ? '' : 's'} ready'),
            content: const Text('Add more tests from Google Drive, or start marking what you have?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, 'more'), child: const Text('Add more')),
              FilledButton(onPressed: () => Navigator.pop(ctx, 'go'), child: const Text('Start marking')),
            ],
          ),
        );
        if (!mounted) return;
        if (more != 'more') break;
      }
      if (groups.isEmpty) return;

      if (unreadable > 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$unreadable file${unreadable == 1 ? '' : 's'} couldn\'t be read and ${unreadable == 1 ? 'was' : 'were'} skipped.'),
        ));
      }
      if (pdfTruncated) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Long PDF — only the first 15 pages were imported.'),
        ));
      }

      // Several files usually means several STUDENTS (one PDF per test) —
      // offer to mark each file as its own submission in the background.
      if (groups.length > 1) {
        final choice = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('${groups.length} files picked'),
            content: const Text('Mark each file as a separate student\'s test, or combine all pages into one submission?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, 'combine'), child: const Text('One submission')),
              FilledButton(onPressed: () => Navigator.pop(ctx, 'batch'), child: const Text('One per student')),
            ],
          ),
        );
        if (!mounted || choice == null) return;
        if (choice == 'batch') {
          _enqueueBatch(groups);
          return;
        }
      }

      context.read<AppState>().setPages([for (final g in groups) ...g]);
      context.push(AppRoutes.gradingContext);
    } on DrivePickerUnavailable {
      final pages = await _pickPagesFromFiles();
      if (pages.isEmpty || !mounted) return;
      context.read<AppState>().setPages(pages);
      context.push(AppRoutes.gradingContext);
    } catch (e) {
      debugPrint('Pick from Drive failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open Google Drive.')));
    }
  }

  /// One background marking job per file — a whole class set of PDFs gets
  /// marked while the teacher does something else. Students auto-link from
  /// the name on each paper; class/key/grade come from the current draft.
  void _enqueueBatch(List<List<ScannedPage>> groups) {
    final n = enqueueStudentGroups(
      context: context,
      groups: [for (final g in groups) g.map((p) => p.bytes).toList(growable: false)],
      labels: [for (final g in groups) g.first.fileName.replaceAll(RegExp(r'\s*\(page \d+\)$'), '')],
    );
    if (n == 0) return;
    final draft = context.read<AppState>().draft;
    // A class set skips the setup screen, so this is the point at which the
    // teacher finds out whether the names on those papers are going up with
    // them. Said once for the set, not once per paper.
    final hiding = Anonymizer.intent(settingOn: context.read<AppState>().anonymizeUploads);
    final nameNote = hiding.hidesTheName ? '' : ' ${hiding.headline}: these pages go up as they are.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: hiding.hidesTheName ? const Duration(seconds: 4) : const Duration(seconds: 7),
      content: Text((draft.answerKeyId.isEmpty
              ? 'Marking $n students — the first paper goes ahead to learn the answer key, then the rest follow.'
              : 'Marking $n students in the background — results land in the tray as they finish.') +
          nameNote),
    ));
  }

  /// The Google Form / CSV route. In a browser it is also the surest route
  /// for keeping student names off the wire — answers go up keyed by row
  /// number and the name column is never sent, with no recognition step that
  /// could fail to find a name field — so it is recommended there and placed
  /// first.
  Widget _importFormCard(BuildContext context) {
    return Card(
      child: InkWell(
        splashFactory: NoSplash.splashFactory,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => context.push(AppRoutes.importResponses),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: AiMarkerColors.secondary.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.table_chart_rounded, color: AiMarkerColors.secondary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text('Import a Google Form', style: Theme.of(context).textTheme.titleMedium, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(color: AiMarkerColors.secondary.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(999)),
                          child: Text(kIsWeb ? 'BEST HERE' : 'FASTEST',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AiMarkerColors.secondary, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    // The real pitch: setting the quiz as a Form skips
                    // scanning altogether, so nothing is faster.
                    Text('The quickest way to mark — no scanning at all. Multiple choice marks itself; written answers are AI-marked.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                    if (kIsWeb) ...[
                      const SizedBox(height: 4),
                      Text(
                        'In a browser, use this one: answers go up keyed by row number and the name column is never sent. Photos here have the "Name:" line blacked out first, but a browser reads a page less well than a phone — this route has nothing to read.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.secondary, height: 1.35),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AiMarkerColors.neutral.withValues(alpha: 0.9)),
            ],
          ),
        ),
      ),
    );
  }

  void _onSearchChanged(String value) {
    final auth = context.read<AuthService>();
    final teacherId = auth.currentUser?.id;
    if (teacherId == null) return;

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 160), () async {
      final students = context.read<StudentsService>();
      final res = await students.searchRemote(value, teacherId: teacherId);
      if (!mounted) return;
      setState(() {
        _studentHits = res.map((s) => _StudentSuggestion(studentId: s.id, name: s.name, studentCode: s.studentId, classId: s.classId)).toList(growable: false);
      });
    });
  }

  void _selectStudent(_StudentSuggestion s) {
    final app = context.read<AppState>();
    final classId = s.classId.trim().isEmpty ? app.draft.classId : s.classId;
    app.setStudentClassPreset(studentId: s.studentId, classId: classId);
    // The student's class carries the grade level the AI marks at.
    if (classId != null && classId.trim().isNotEmpty) {
      final k = context.read<ClassesService>().getById(classId);
      if (k?.gradeLevel != null) app.setGradeLevel(k!.gradeLevel!);
    }
    setState(() => _studentHits = const []);
    _search.text = s.name;
    FocusScope.of(context).unfocus();
  }
  /// What is happening right now: papers marking overnight, the queue, and
  /// the student the next scan belongs to.
  ///
  /// On a monitor the running work sits on the left and the student box on
  /// the right, because a search field stretched across 1400px is a slot for
  /// a name that looks like a mistake.
  Widget _workInProgress(BuildContext context, GradingQueueService queue, TeacherClass? selectedClass) {
    final running = <Widget>[
      if (context.watch<OvernightService>().batches.isNotEmpty) ...[
        const SizedBox(height: 14),
        Card(
          color: AiMarkerColors.tertiary.withValues(alpha: 0.10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.bedtime_rounded, color: AiMarkerColors.tertiary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('${context.watch<OvernightService>().pendingPapers} papers marking overnight',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                for (final b in context.watch<OvernightService>().batches)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('• ${b.label} — ${b.papers.length} papers', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                  ),
                const SizedBox(height: 6),
                Text(
                  // Not "we'll let you know": nothing tells the phone a
                  // batch has finished, so the marks are filed when she
                  // next opens Markless. Promising a notification she
                  // never gets is worse than promising nothing.
                  'Marking carries on with the app closed. Open Markless in the morning and the marks are waiting on your dashboard.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.4),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: context.watch<OvernightService>().checking
                      ? null
                      : () async {
                          final filed = await checkOvernight(context);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(filed > 0 ? '$filed papers came back — they\'re on your dashboard.' : 'Still marking. Nothing to file yet.'),
                          ));
                        },
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Check now'),
                ),
              ],
            ),
          ),
        ),
      ],
      const SizedBox(height: 18),
      if (queue.jobs.isNotEmpty) ...[
        Row(
          children: [
            Expanded(child: Text('Marking', style: Theme.of(context).textTheme.titleMedium)),
            if (queue.markingCount > 0) Text('${queue.markingCount} in progress', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
          ],
        ),
        if (queue.heldJobs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Card(
              color: AiMarkerColors.warning.withValues(alpha: 0.10),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${queue.heldJobs.length} papers waiting on you', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                      'Open the first marked paper. If it marked the way you would, release the rest — if not, fix the answer key or mode first and nothing has been wasted.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.4),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: () {
                            final n = queue.heldJobs.length;
                            queue.releaseHeld(
                              students: context.read<StudentsService>(),
                              submissions: context.read<SubmissionsService>(),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Marking the remaining $n papers.')),
                            );
                          },
                          icon: const Icon(Icons.play_arrow_rounded, size: 18),
                          label: Text('Mark all ${queue.heldJobs.length}'),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: queue.discardHeld,
                          child: const Text('Discard'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 10),
        Card(
          child: Column(
            children: [
              for (final job in queue.jobs.take(8))
                ListTile(
                  leading: switch (job.status) {
                    GradingJobStatus.marking => const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)),
                    GradingJobStatus.held => const Icon(Icons.pause_circle_rounded, color: AiMarkerColors.warning),
                    GradingJobStatus.done => const Icon(Icons.check_circle_rounded, color: AiMarkerColors.secondary),
                    GradingJobStatus.error => const Icon(Icons.error_rounded, color: AiMarkerColors.error),
                  },
                  title: Text(job.label, style: Theme.of(context).textTheme.titleSmall),
                  subtitle: Text(
                    switch (job.status) {
                      GradingJobStatus.marking => "Marking…",
                      GradingJobStatus.held => "Waiting for your OK — check the first result",
                      GradingJobStatus.done => "${job.result?.primaryDisplay ?? "Done"} — tap to view",
                      GradingJobStatus.error => "Failed — tap to retry",
                    },
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral),
                  ),
                  trailing: job.status == GradingJobStatus.marking
                      ? null
                      : IconButton(
                          icon: Icon(Icons.close_rounded, color: AiMarkerColors.neutral, size: 20),
                          onPressed: () => queue.remove(job.id),
                          tooltip: 'Dismiss',
                        ),
                  onTap: job.status == GradingJobStatus.done
                      ? () => context.push(
                            '${AppRoutes.result}?submissionId=${job.submissionId}',
                            extra: {
                              'gradeResult': job.result,
                              'imageBytes': job.pages.isEmpty ? null : job.pages.first,
                              'pageImages': job.pages,
                            },
                          )
                      : job.status == GradingJobStatus.error
                          ? () => queue.retry(job.id, students: context.read<StudentsService>(), submissions: context.read<SubmissionsService>())
                          : null,
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
      ],
    ];
    final student = <Widget>[
      Text('STUDENT INFO', style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.2, color: AiMarkerColors.neutral)),
      const SizedBox(height: 10),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              TextField(
                controller: _search,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Enter student name or scan...',
                  prefixIcon: Icon(Icons.search_rounded, color: AiMarkerColors.neutral.withValues(alpha: 0.8)),
                  suffixIcon: IconButton(onPressed: () => _search.clear(), icon: Icon(Icons.close_rounded, color: AiMarkerColors.neutral.withValues(alpha: 0.8))),
                ),
              ),
              if (_studentHits.isNotEmpty) ...[
                const SizedBox(height: 10),
                _StudentSearchResults(items: _studentHits, onSelect: _selectStudent),
              ],
              const SizedBox(height: 12),
              _ClassRow(
                label: selectedClass == null
                    ? 'Which class? Tap to choose'
                    : '${selectedClass.name} · ${selectedClass.period}${selectedClass.gradeLevel != null ? ' · Grade ${selectedClass.gradeLevel}' : ''}',
                hasClass: selectedClass != null,
                onTap: () => _askWhichClass(),
              ),
            ],
          ),
        ),
      ),
    ];
    return DeskColumns(
      start: running,
      rest: [const SizedBox(height: 14), ...student],
      stacked: [...running, ...student],
    );
  }


  /// The two ways to start marking right now, and the routes into the other
  /// jobs a teacher opens Markless for.
  ///
  /// A phone reads them as one list, in the order it always has. A desk
  /// monitor puts the camera and the paste box down the left and the routes
  /// down the right, so the scan card stays a card rather than a gradient
  /// banner stretched across a 27" screen with a small stack of writing lost
  /// in the middle of it.
  Widget _routes(BuildContext context) {
    final Widget scan = GestureDetector(
      onTap: _pickFromCamera,
      // The one loud thing on the screen, and the only place boldness is
      // spent: a slate, not a dark rectangle. The light comes from the same
      // top-left corner as the desk behind it, it throws a shadow so it sits
      // *on* the desk rather than being a hole cut in it, and a hairline of
      // chalk dust catches the top edge.
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          gradient: const LinearGradient(
            colors: [Color(0xFF1E4A38), AiMarkerColors.primary, AiMarkerColors.boardDeep],
            stops: [0.0, 0.45, 1.0],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          boxShadow: [
            BoxShadow(
              color: AiMarkerColors.boardDeep.withValues(alpha: 0.30),
              blurRadius: 26,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.18), border: Border.all(color: Colors.white.withValues(alpha: 0.22))),
              child: const Icon(Icons.photo_camera_rounded, color: Colors.white),
            ),
            const SizedBox(height: 10),
            Text('Scan Assignment', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white)),
            const SizedBox(height: 4),
            Text('Take a photo to start grading', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.9))),
            const SizedBox(height: 12),
            // Answer keys live in the Answers tab — the card keeps
            // one clean row of import sources.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                PillButton(
                  label: 'From Gallery',
                  icon: Icons.photo_library_rounded,
                  background: Colors.white.withValues(alpha: 0.16),
                  foreground: Colors.white,
                  onTap: _pickFromGallery,
                ),
                const SizedBox(width: 10),
                PillButton(
                  label: 'From Drive',
                  icon: Icons.add_to_drive_rounded,
                  background: Colors.white.withValues(alpha: 0.16),
                  foreground: Colors.white,
                  onTap: _pickFromDrive,
                ),
              ],
            ),
          ],
        ),
      ),
    );
    // Discoverable, not a hidden trick: on a laptop the fastest way in is
    // the one nothing on screen mentions.
    final Widget? hint = _browserIntake == null ? null : const DropAndPasteHint();
    final Widget prepareTest = Card(
      child: InkWell(
        splashFactory: NoSplash.splashFactory,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => context.push(AppRoutes.prepareTest),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: AiMarkerColors.secondary.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.qr_code_2_rounded, color: AiMarkerColors.secondary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Prepare a test to print', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text('Each copy gets a tiny code, so scanning it back never mixes students up.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AiMarkerColors.neutral.withValues(alpha: 0.9)),
            ],
          ),
        ),
      ),
    );
    final Widget splitStack = Card(
      child: InkWell(
        splashFactory: NoSplash.splashFactory,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => context.push(AppRoutes.splitStack),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: AiMarkerColors.tertiary.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.print_rounded, color: AiMarkerColors.tertiary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Split a scanned stack', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text('Feed the class set through the photocopier once — one PDF in, one paper per student out.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AiMarkerColors.neutral.withValues(alpha: 0.9)),
            ],
          ),
        ),
      ),
    );
    final Widget planWithMark = Card(
      child: InkWell(
        splashFactory: NoSplash.splashFactory,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => context.push(AppRoutes.planning),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: AiMarkerColors.tertiary.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.event_note_rounded, color: AiMarkerColors.tertiary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Plan with Mark', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text('Draft a lesson plan, quiz, assignment, or worksheet in seconds.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AiMarkerColors.neutral.withValues(alpha: 0.9)),
            ],
          ),
        ),
      ),
    );
    // Report writing is the other job that eats a teacher's evenings, and
    // the only app that can do it honestly is the one already holding the
    // marks. Put where the marking lives, because that is where the
    // evidence comes from.
    final Widget reportComments = Card(
      child: InkWell(
        splashFactory: NoSplash.splashFactory,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => context.push(AppRoutes.reportComments),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: AiMarkerColors.secondary.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.rate_review_rounded, color: AiMarkerColors.secondary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Report card comments', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text('A draft for every student, written from their own marks this term.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AiMarkerColors.neutral.withValues(alpha: 0.9)),
            ],
          ),
        ),
      ),
    );
    // Replaces a passive "the assistant is clever" line with the one thing
    // that actually changes how long an evening takes. Left to guess, most
    // teachers reach for the camera — the slowest of the four routes — and
    // conclude the app is slow.
    final Widget waysToMark = Card(
      child: InkWell(
        splashFactory: NoSplash.splashFactory,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => context.push(AppRoutes.waysToMark),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.speed_rounded, color: Theme.of(context).colorScheme.secondary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Four ways to mark a class set', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text('A form takes 2 minutes, the copier 6, photos 15. Tap for the steps.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.35)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AiMarkerColors.neutral.withValues(alpha: 0.9)),
            ],
          ),
        ),
      ),
    );
    // On the phone this sits with the other routes. In a browser it is the
    // one route that stays private, so there it goes directly under the
    // scan card instead.
    final Widget importForm = _importFormCard(context);

    const gap = SizedBox(height: 12);
    return DeskColumns(
      start: [
        scan,
        if (hint != null) ...[const SizedBox(height: 10), hint],
        if (kIsWeb) ...[gap, importForm],
      ],
      rest: [
        prepareTest,
        gap,
        splitStack,
        if (!kIsWeb) ...[gap, importForm],
        gap,
        planWithMark,
        gap,
        reportComments,
        gap,
        waysToMark,
      ],
      stacked: [
        scan,
        if (hint != null) ...[const SizedBox(height: 10), hint],
        if (kIsWeb) ...[gap, importForm],
        gap,
        prepareTest,
        gap,
        splitStack,
        if (!kIsWeb) ...[gap, importForm],
        gap,
        planWithMark,
        gap,
        reportComments,
        gap,
        waysToMark,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    final state = context.watch<AppState>();
    final classes = context.watch<ClassesService>().classes;
    final queue = context.watch<GradingQueueService>();
    final selectedClass = (state.draft.classId == null || state.draft.classId!.isEmpty) ? null : classes.cast<TeacherClass?>().firstWhere((c) => c?.id == state.draft.classId, orElse: () => null);

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
              children: [
                TeacherTopbar(title: 'Markless', onBell: () {}),
                const SizedBox(height: 14),
                Text('Good morning,', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AiMarkerColors.neutral)),
                const SizedBox(height: 2),
                Text('${user?.name.isNotEmpty == true ? user!.name : 'Teacher'} 👋', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 14),
                _routes(context),
                _workInProgress(context, queue, selectedClass),
              ],
            ),
          ),
          // Only while a drag is actually over the window. A teacher holding
          // a folder over the page has to be able to see that letting go
          // will do something.
          if (_dragOver) const Positioned.fill(child: DropTargetOverlay()),
        ],
      ),
    );
  }
}

class _StudentSearchResults extends StatelessWidget {
  final List<_StudentSuggestion> items;
  final ValueChanged<_StudentSuggestion> onSelect;

  const _StudentSearchResults({required this.items, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.22))),
      child: Column(
        children: [
          for (final s in items.take(6))
            ListTile(
              leading: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                  child: Text(s.name.isEmpty ? '?' : s.name.substring(0, 1), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700))),
              title: Text(s.name, style: Theme.of(context).textTheme.titleSmall),
              subtitle: Text(s.studentCode, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
              trailing: Icon(Icons.north_east_rounded, color: AiMarkerColors.neutral.withValues(alpha: 0.85)),
              onTap: () => onSelect(s),
            ),
        ],
      ),
    );
  }
}

class _StudentSuggestion {
  final String studentId;
  final String name;
  final String studentCode;
  final String classId;
  const _StudentSuggestion({required this.studentId, required this.name, required this.studentCode, required this.classId});
}

class _ClassRow extends StatelessWidget {
  final String label;
  final bool hasClass;
  final VoidCallback onTap;

  const _ClassRow({required this.label, required this.hasClass, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      splashFactory: NoSplash.splashFactory,
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 46),
        decoration: BoxDecoration(
          color: hasClass ? cs.primary.withValues(alpha: 0.10) : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: hasClass ? cs.primary.withValues(alpha: 0.3) : cs.outline.withValues(alpha: 0.22)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(Icons.groups_rounded, color: hasClass ? cs.primary : AiMarkerColors.neutral),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 12, color: hasClass ? cs.primary : null),
              ),
            ),
            Icon(Icons.keyboard_arrow_down_rounded, color: AiMarkerColors.neutral.withValues(alpha: 0.9)),
          ],
        ),
      ),
    );
  }
}

class _ClassPickerSheet extends StatelessWidget {
  final List<TeacherClass> classes;
  final String? currentId;
  const _ClassPickerSheet({required this.classes, required this.currentId});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(color: cs.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('Which class is this for?', style: Theme.of(context).textTheme.titleLarge)),
                IconButton(onPressed: () => context.pop(), icon: Icon(Icons.close_rounded, color: AiMarkerColors.neutral)),
              ],
            ),
            Text(
              'Marking follows the class\'s grade level automatically.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral),
            ),
            const SizedBox(height: 6),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final c in classes)
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                        child: Icon(Icons.bookmark_rounded, color: cs.primary, size: 20),
                      ),
                      title: Text(c.name, style: Theme.of(context).textTheme.titleSmall),
                      subtitle: Text(
                        '${c.period}${c.gradeLevel != null ? ' · Grade ${c.gradeLevel}' : ''}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral),
                      ),
                      trailing: c.id == currentId ? Icon(Icons.check_circle_rounded, color: cs.primary) : Icon(Icons.chevron_right_rounded, color: AiMarkerColors.neutral.withValues(alpha: 0.8)),
                      onTap: () => context.pop(c.id),
                    ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                      child: Icon(Icons.block_rounded, color: AiMarkerColors.neutral, size: 20),
                    ),
                    title: Text('No class — just grade it', style: Theme.of(context).textTheme.titleSmall),
                    onTap: () => context.pop(''),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How far along a long job is, and the teacher's way out of it.
///
/// [total] is zero until the work knows how much there is to do — the Drive
/// picker only says how many files she chose once she has finished choosing —
/// so the dialog can say "loading" honestly instead of inventing a count.
class _CountedRun {
  int done = 0;
  int total = 0;
  bool stopped = false;

  /// Null before the dialog has built and again once it is gone, so a late
  /// progress report can never call setState on a dead widget.
  VoidCallback? _redraw;

  void report(int done, int total) {
    this.done = done;
    this.total = total;
    _redraw?.call();
  }
}
