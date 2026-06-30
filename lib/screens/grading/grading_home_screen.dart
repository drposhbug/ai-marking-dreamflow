import 'dart:typed_data';
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:marking_prokect_v2/app/app_routes.dart';
import 'package:marking_prokect_v2/app/app_state.dart';
import 'package:marking_prokect_v2/models/grading_preset.dart';
import 'package:marking_prokect_v2/screens/grading/live_scan_screen.dart';
import 'package:marking_prokect_v2/screens/grading/web_image_picker.dart';
import 'package:marking_prokect_v2/services/auth_service.dart';
import 'package:marking_prokect_v2/services/presets_service.dart';
import 'package:marking_prokect_v2/services/students_service.dart';
import 'package:marking_prokect_v2/services/submissions_service.dart';
import 'package:marking_prokect_v2/theme.dart';
import 'package:marking_prokect_v2/widgets/mode_card.dart';
import 'package:marking_prokect_v2/widgets/pill.dart';
import 'package:marking_prokect_v2/widgets/teacher_topbar.dart';
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

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _handlePickedFile(XFile? image) async {
    if (image == null) return;
    try {
      final Uint8List bytes = await image.readAsBytes();
      context.read<AppState>().setImageBytes(bytes: bytes, fileName: image.name);
      if (!mounted) return;
      context.push(AppRoutes.gradingContext, extra: {'imageBytes': bytes, 'fileName': image.name});
    } catch (e) {
      debugPrint('Failed to read picked image bytes: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not read image.')));
    }
  }

  Future<void> _pickFromCamera() async {
    try {
      // Live auto-scan camera: holds the preview open and auto-captures
      // each page once it's held steady, so the teacher can keep sliding
      // assignments through without tapping a shutter button.
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LiveScanScreen(
            onCapture: (bytes, fileName) async {
              if (!mounted) return false;
              context.read<AppState>().setImageBytes(bytes: bytes, fileName: fileName);
              context.push(AppRoutes.gradingContext, extra: {'imageBytes': bytes, 'fileName': fileName});
              // Return true to keep the scanner open for the next page,
              // or false to close the scanner after this one capture.
              return true;
            },
          ),
        ),
      );
    } catch (e) {
      debugPrint('Pick from camera failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open camera.')));
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      if (kIsWeb) {
        final picked = await pickWebImage(captureEnvironmentCamera: false);
        if (picked == null) return;
        if (!mounted) return;
        context.read<AppState>().setImageBytes(bytes: picked.bytes, fileName: picked.name);
        context.push(AppRoutes.gradingContext, extra: {'imageBytes': picked.bytes, 'fileName': picked.name});
        return;
      }

      final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      await _handlePickedFile(image);
    } catch (e) {
      debugPrint('Pick from gallery failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open gallery.')));
    }
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

  static String _builtInIdForMode(GradingMode mode) => switch (mode) {
    GradingMode.homework => GradingPreset.builtInHomeworkId,
    GradingMode.testQuiz => GradingPreset.builtInTestId,
    GradingMode.labReport => GradingPreset.builtInLabId,
    GradingMode.englishEssay => GradingPreset.builtInEnglishId,
  };

  void _selectMode(GradingMode mode) {
    final state = context.read<AppState>();
    final draft = state.draft;
    state.setMode(mode);
    if (!draft.autoDetectScheme) {
      state.setStudentClassPreset(presetId: _builtInIdForMode(mode));
    } else {
      state.setStudentClassPreset(presetId: null);
    }
  }

  Future<void> _selectSchemeManually() async {
    final auth = context.read<AuthService>().currentUser;
    final draft = context.read<AppState>().draft;
    if (draft.autoDetectScheme) return;
    final presets = context.read<PresetsService>();

    final all = <GradingPreset>[
      ...presets.builtInSchemes,
      if (auth != null) ...presets.customGlobalSchemes(teacherId: auth.id),
      if (auth != null && draft.classId != null) ...presets.byClass(draft.classId!),
    ];

    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SchemePickerSheet(
        currentId: draft.presetId,
        presets: all,
      ),
    );
    if (!mounted || picked == null) return;
    context.read<AppState>().setStudentClassPreset(presetId: picked);
  }

  void _selectStudent(_StudentSuggestion s) {
    final app = context.read<AppState>();
    final draft = app.draft;
    final subs = context.read<SubmissionsService>();

    final classId = s.classId.trim().isEmpty ? draft.classId : s.classId;
    String? lastPresetId;
    if (classId != null && classId.trim().isNotEmpty) {
      final recents = subs.byStudent(s.studentId).where((sub) => sub.classId == classId).toList();
      lastPresetId = recents.isEmpty ? null : recents.first.presetId;
    }

    final pickedPreset = draft.autoDetectScheme ? null : (lastPresetId ?? _builtInIdForMode(draft.mode));
    app.setStudentClassPreset(studentId: s.studentId, classId: classId, presetId: pickedPreset);
    setState(() => _studentHits = const []);
    _search.text = s.name;
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = context.watch<AuthService>().currentUser;
    final state = context.watch<AppState>();
    final preset = state.draft.presetId == null ? null : context.watch<PresetsService>().getById(state.draft.presetId!);
    final builtInForMode = context.watch<PresetsService>().getById(_builtInIdForMode(state.draft.mode));
    final schemeName = state.draft.autoDetectScheme
        ? (preset?.name ?? 'Auto-detecting...')
        : (preset?.name ?? builtInForMode?.name ?? 'Select marking scheme');

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
          children: [
            TeacherTopbar(title: 'AI Marker', onBell: () {}),
            const SizedBox(height: 14),
            Text('Good morning,', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AiMarkerColors.neutral)),
            const SizedBox(height: 2),
            Text('${user?.name.isNotEmpty == true ? user!.name : 'Teacher'} 👋', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: _pickFromCamera,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  gradient: const LinearGradient(colors: [AiMarkerColors.primary, AiMarkerColors.tertiary], begin: Alignment.topLeft, end: Alignment.bottomRight),
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
                    Align(
                      alignment: Alignment.center,
                      child: PillButton(
                        label: 'From Gallery',
                        icon: Icons.photo_library_rounded,
                        background: Colors.white.withValues(alpha: 0.16),
                        foreground: Colors.white,
                        onTap: _pickFromGallery,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text('Grading Mode', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.45,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                ModeCard(mode: GradingMode.homework, title: 'Homework', subtitle: 'Completion %', color: AiMarkerColors.primary, icon: Icons.menu_book_rounded, selected: state.draft.mode == GradingMode.homework, onTap: () => _selectMode(GradingMode.homework)),
                ModeCard(mode: GradingMode.testQuiz, title: 'Test / Quiz', subtitle: 'x / total', color: AiMarkerColors.error, icon: Icons.quiz_rounded, selected: state.draft.mode == GradingMode.testQuiz, onTap: () => _selectMode(GradingMode.testQuiz)),
                ModeCard(mode: GradingMode.labReport, title: 'Lab Report', subtitle: 'Rubric score', color: AiMarkerColors.secondary, icon: Icons.science_rounded, selected: state.draft.mode == GradingMode.labReport, onTap: () => _selectMode(GradingMode.labReport)),
                ModeCard(mode: GradingMode.englishEssay, title: 'English / Essay', subtitle: 'Grade band', color: AiMarkerColors.tertiary, icon: Icons.auto_stories_rounded, selected: state.draft.mode == GradingMode.englishEssay, onTap: () => _selectMode(GradingMode.englishEssay)),
              ],
            ),
            const SizedBox(height: 18),
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
                    _CombinedSchemeRow(
                      schemeName: schemeName,
                      autoDetectEnabled: state.draft.autoDetectScheme,
                      onTapScheme: _selectSchemeManually,
                      onToggleAutoDetect: (v) {
                        context.read<AppState>().setAutoDetectScheme(v);
                        if (v) {
                          context.read<AppState>().setStudentClassPreset(presetId: null);
                        } else {
                          context.read<AppState>().setStudentClassPreset(presetId: _builtInIdForMode(state.draft.mode));
                        }
                      },
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
}

class _StudentSearchResults extends StatelessWidget {
  final List<_StudentSuggestion> items;
  final ValueChanged<_StudentSuggestion> onSelect;

  const _StudentSearchResults({required this.items, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.22))),
      child: Column(
        children: [
          for (final s in items.take(6))
            ListTile(
              leading: CircleAvatar(backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12), child: Text(s.name.isEmpty ? '?' : s.name.substring(0, 1), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700))),
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

class _CombinedSchemeRow extends StatelessWidget {
  final String schemeName;
  final bool autoDetectEnabled;
  final VoidCallback onTapScheme;
  final ValueChanged<bool> onToggleAutoDetect;

  const _CombinedSchemeRow({required this.schemeName, required this.autoDetectEnabled, required this.onTapScheme, required this.onToggleAutoDetect});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pillBorder = cs.outline.withValues(alpha: 0.22);
    return Row(
      children: [
        Expanded(
          child: InkWell(
            splashFactory: NoSplash.splashFactory,
            borderRadius: BorderRadius.circular(999),
            onTap: autoDetectEnabled ? null : onTapScheme,
            child: Container(
              constraints: const BoxConstraints(minHeight: 46, minWidth: 160),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: pillBorder),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(Icons.tune_rounded, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      schemeName,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 12),
                    ),
                  ),
                  Icon(Icons.keyboard_arrow_down_rounded, color: AiMarkerColors.neutral.withValues(alpha: 0.9)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        InkWell(
          splashFactory: NoSplash.splashFactory,
          borderRadius: BorderRadius.circular(999),
          onTap: () => onToggleAutoDetect(!autoDetectEnabled),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: autoDetectEnabled ? cs.secondary.withValues(alpha: 0.16) : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: autoDetectEnabled ? cs.secondary.withValues(alpha: 0.35) : pillBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome_rounded, size: 18, color: autoDetectEnabled ? cs.secondary : AiMarkerColors.neutral),
                const SizedBox(width: 8),
                Text('Auto-detect', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: autoDetectEnabled ? cs.secondary : AiMarkerColors.neutral, fontWeight: FontWeight.w800)),
                const SizedBox(width: 8),
                Switch(
                  value: autoDetectEnabled,
                  onChanged: onToggleAutoDetect,
                  activeColor: cs.secondary,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SchemePickerSheet extends StatelessWidget {
  final String? currentId;
  final List<GradingPreset> presets;
  const _SchemePickerSheet({required this.currentId, required this.presets});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final grouped = <GradingMode, List<GradingPreset>>{};
    for (final p in presets) {
      (grouped[p.gradingMode] ??= <GradingPreset>[]).add(p);
    }
    for (final entry in grouped.entries) {
      entry.value.sort((a, b) => a.name.compareTo(b.name));
    }

    String modeLabel(GradingMode m) => switch (m) {
      GradingMode.homework => 'Homework',
      GradingMode.testQuiz => 'Test / Quiz',
      GradingMode.labReport => 'Lab Report',
      GradingMode.englishEssay => 'English / Essay',
    };

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
                Expanded(child: Text('Select Marking Scheme', style: Theme.of(context).textTheme.titleLarge)),
                IconButton(onPressed: () => context.pop(), icon: Icon(Icons.close_rounded, color: AiMarkerColors.neutral)),
              ],
            ),
            const SizedBox(height: 6),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final mode in GradingMode.values)
                    if ((grouped[mode] ?? const []).isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 12, 6, 6),
                        child: Text(modeLabel(mode), style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.1, color: AiMarkerColors.neutral)),
                      ),
                      for (final p in grouped[mode]!)
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                          title: Text(p.name, style: Theme.of(context).textTheme.titleSmall),
                          subtitle: Text('${p.criteria.length} criteria · ${p.harshness}/10', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                          trailing: p.id == currentId ? Icon(Icons.check_circle_rounded, color: cs.primary) : Icon(Icons.chevron_right_rounded, color: AiMarkerColors.neutral.withValues(alpha: 0.8)),
                          onTap: () => context.pop(p.id),
                        ),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
