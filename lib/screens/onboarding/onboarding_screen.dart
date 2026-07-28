import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:marking_prokect_v2/app/app_routes.dart';
import 'package:marking_prokect_v2/app/app_state.dart';
import 'package:marking_prokect_v2/services/ai_grading_service.dart';
import 'package:marking_prokect_v2/services/auth_service.dart';
import 'package:marking_prokect_v2/services/classes_service.dart';
import 'package:marking_prokect_v2/services/local_store.dart';
import 'package:marking_prokect_v2/services/students_service.dart';
import 'package:marking_prokect_v2/theme.dart';
import 'package:provider/provider.dart';

/// First-run walkthrough: a short intro, then an optional "create your first
/// class" step where the roster can be filled by photographing an attendance
/// sheet (AI extracts the names) or by typing students in one by one.
/// Every step can be skipped.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  /// LocalStore flag — set once the teacher finishes or skips onboarding.
  static String doneKey(String teacherId) => 'ai_marker.onboarding_done.v1.$teacherId';

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0; // 0 = welcome, 1 = name + school (required), 2 = classes

  final _subject = TextEditingController();
  final _period = TextEditingController();
  final _studentName = TextEditingController();
  final _school = TextEditingController();
  final _name = TextEditingController();

  /// Grade level of the class currently being set up (1–12).
  int? _classGrade;

  final List<RosterEntry> _students = [];
  final ImagePicker _picker = ImagePicker();
  bool _scanning = false;
  bool _creating = false;

  // Curriculum region inferred from the school name — the teacher is only
  // asked when the school name matches multiple regions.
  List<RegionCandidate> _regionCandidates = const [];
  String _regionLabel = '';
  bool _inferringRegion = false;

  /// Names of classes already created this session — teachers usually have
  /// about 3, so the setup step loops: save a class, form clears, add the next.
  final List<String> _createdClasses = [];

  @override
  void initState() {
    super.initState();
    _school.text = context.read<AppState>().school;
    final currentName = context.read<AuthService>().currentUser?.name ?? '';
    // 'Ms. Johnson' is the placeholder profile name — don't prefill with it.
    if (currentName.isNotEmpty && currentName != 'Ms. Johnson') _name.text = currentName;
  }

  Future<void> _inferRegionFromSchool() async {
    final school = _school.text.trim();
    if (school.isEmpty || _inferringRegion) return;
    setState(() {
      _inferringRegion = true;
      _regionCandidates = const [];
    });
    try {
      final found = await AiGradingService().inferRegion(school: school);
      if (!mounted) return;
      if (found.length == 1) {
        await _applyRegion(found.first);
      } else if (found.length > 1) {
        setState(() => _regionCandidates = found);
      }
    } catch (e) {
      debugPrint('OnboardingScreen._inferRegionFromSchool failed: $e');
    } finally {
      if (mounted) setState(() => _inferringRegion = false);
    }
  }

  Future<void> _applyRegion(RegionCandidate c) async {
    setState(() {
      _regionLabel = c.label;
      _regionCandidates = const [];
    });
    final user = context.read<AuthService>().currentUser;
    if (user != null) {
      await context.read<AppState>().setRegion(teacherId: user.id, regionId: c.regionId);
    }
  }

  @override
  void dispose() {
    _subject.dispose();
    _period.dispose();
    _studentName.dispose();
    _school.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final user = context.read<AuthService>().currentUser;
    if (user != null) {
      final app = context.read<AppState>();
      if (_school.text.trim().isNotEmpty) {
        await app.setSchool(teacherId: user.id, school: _school.text);
        // Teacher typed a school but never triggered inference (or never
        // picked from the ambiguous list) — silently take the best guess;
        // Settings → Curriculum Region can always override it.
        if (app.region.isEmpty) {
          try {
            final found = _regionCandidates.isNotEmpty
                ? _regionCandidates
                : await AiGradingService().inferRegion(school: _school.text.trim());
            if (found.isNotEmpty) {
              await app.setRegion(teacherId: user.id, regionId: found.first.regionId);
            }
          } catch (e) {
            debugPrint('OnboardingScreen._finish region inference failed: $e');
          }
        }
      }
      await const LocalStore().setString(OnboardingScreen.doneKey(user.id), '1');
    }
    if (!mounted) return;
    context.go(AppRoutes.grading);
  }

  Future<void> _scanAttendance() async {
    ImageSource? source = ImageSource.gallery;
    if (!kIsWeb) {
      source = await showModalBottomSheet<ImageSource>(
        context: context,
        backgroundColor: Theme.of(context).colorScheme.surface,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_rounded),
                title: const Text('Take a photo'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );
      if (source == null) return;
    }

    try {
      final XFile? image = await _picker.pickImage(source: source, imageQuality: 85);
      if (image == null || !mounted) return;
      setState(() => _scanning = true);
      final bytes = await image.readAsBytes();
      final found = await AiGradingService().extractRoster(pages: [bytes]);
      if (!mounted) return;
      final existing = _students.map((s) => s.name.toLowerCase()).toSet();
      final fresh = found.where((s) => !existing.contains(s.name.toLowerCase())).toList();
      setState(() => _students.addAll(fresh));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(fresh.isEmpty
              ? 'No new names found on that photo.'
              : 'Added ${fresh.length} student${fresh.length == 1 ? '' : 's'} from the attendance sheet.'),
        ),
      );
    } catch (e) {
      debugPrint('OnboardingScreen._scanAttendance failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read the attendance sheet. Try a clearer photo, or add students below.')),
      );
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _addStudentManually() {
    final name = _studentName.text.trim();
    if (name.isEmpty) return;
    final exists = _students.any((s) => s.name.toLowerCase() == name.toLowerCase());
    if (!exists) {
      setState(() => _students.add(RosterEntry(name: name)));
    }
    _studentName.clear();
  }

  Future<void> _saveClass({required bool addAnother}) async {
    final user = context.read<AuthService>().currentUser;
    if (user == null) return _finish();
    final subject = _subject.text.trim().isEmpty ? 'General' : _subject.text.trim();
    final period = _period.text.trim().isEmpty ? 'P1' : _period.text.trim();
    // Classes name themselves: "Physics P2" — no typing needed.
    final name = '$subject $period';
    if (_subject.text.trim().isEmpty) return;

    setState(() => _creating = true);
    try {
      final created = await context.read<ClassesService>().create(
        teacherId: user.id,
        name: name,
        subject: subject,
        period: period,
        gradeLevel: _classGrade,
      );
      if (!mounted) return;

      final students = context.read<StudentsService>();
      final studentCount = _students.length;
      for (final s in _students) {
        // Same auto-code rule as the class hub's Add Student sheet.
        final code = s.studentId ??
            '${s.name.trim().split(RegExp(r'\s+')).map((w) => w[0].toUpperCase()).join()}${DateTime.now().millisecondsSinceEpoch % 1000}';
        await students.create(teacherId: user.id, classId: created.id, name: s.name, studentId: code);
      }
      if (!mounted) return;

      _createdClasses.add(name);
      if (addAnother) {
        // Clear the form and stay for the next class.
        _subject.clear();
        _period.clear();
        _studentName.clear();
        setState(() {
          _students.clear();
          _classGrade = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$name created with $studentCount student${studentCount == 1 ? '' : 's'} — add your next class.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$name created with $studentCount student${studentCount == 1 ? '' : 's'}.')),
        );
        await _finish();
      }
    } catch (e) {
      debugPrint('OnboardingScreen._saveClass failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not create the class. Please try again.')));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  /// Saves the required name + school, kicks off curriculum matching, and
  /// moves on to class setup.
  Future<void> _continueProfile() async {
    final name = _name.text.trim();
    final school = _school.text.trim();
    if (name.isEmpty || school.isEmpty) return;
    final user = context.read<AuthService>().currentUser;
    if (user != null) {
      await context.read<AuthService>().updateProfile(name: name, school: school);
      await context.read<AppState>().setSchool(teacherId: user.id, school: school);
    }
    if (!mounted) return;
    if (_regionLabel.isEmpty && _regionCandidates.isEmpty) _inferRegionFromSchool();
    setState(() => _step = 2);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(switch (_step) { 0 => 'Welcome', 1 => 'About you', _ => 'Set up your classes' }),
        actions: [
          // Only the welcome step gets a top-right skip; the other steps
          // have their own buttons at the bottom.
          if (_step == 0)
            TextButton(onPressed: _creating ? null : _finish, child: const Text('Skip')),
        ],
      ),
      body: SafeArea(
        child: switch (_step) {
          0 => _buildWelcome(context),
          1 => _buildProfile(context),
          _ => _buildClassSetup(context),
        },
      ),
    );
  }

  Widget _buildProfile(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canContinue = _name.text.trim().isNotEmpty && _school.text.trim().isNotEmpty;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Tell us about you', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                'Your name goes on feedback, and your school matches marking to the right curriculum.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.4),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Your name', hintText: 'e.g. Ms. Rivera'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _school,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _inferRegionFromSchool(),
                onEditingComplete: () {
                  FocusScope.of(context).unfocus();
                  _inferRegionFromSchool();
                },
                decoration: const InputDecoration(labelText: 'Which school do you teach at?', hintText: 'e.g. Riverdale High School'),
              ),
              if (_inferringRegion) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 8),
                    Text('Matching your curriculum…', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                  ],
                ),
              ] else if (_regionCandidates.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'That school name exists in a few places — which one is yours?',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in _regionCandidates)
                      ActionChip(
                        avatar: Icon(Icons.place_rounded, size: 16, color: cs.primary),
                        label: Text('(${c.place})'),
                        onPressed: () => _applyRegion(c),
                      ),
                  ],
                ),
              ] else if (_regionLabel.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.check_circle_rounded, size: 16, color: AiMarkerColors.secondary),
                    const SizedBox(width: 6),
                    Text('Curriculum: $_regionLabel', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.secondary, fontWeight: FontWeight.w700)),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: canContinue ? _continueProfile : null,
                child: const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcome(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Align(
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.primary.withValues(alpha: 0.10),
                    border: Border.all(color: cs.primary.withValues(alpha: 0.20)),
                  ),
                  child: Icon(Icons.school_rounded, color: cs.primary, size: 40),
                ),
              ),
              const SizedBox(height: 18),
              Text('Welcome to MarkMate', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: cs.primary)),
              const SizedBox(height: 8),
              Text(
                'Your marking assistant — scan student work, get it marked in seconds, and keep every class organized.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AiMarkerColors.neutral),
              ),
              const SizedBox(height: 24),
              _FeatureRow(icon: Icons.document_scanner_rounded, title: 'Scan & mark', body: 'Photograph a test or homework page and it\'s marked against your answer key.'),
              _FeatureRow(icon: Icons.groups_rounded, title: 'Classes made easy', body: 'Build a class roster from one photo of your attendance sheet.'),
              _FeatureRow(icon: Icons.insights_rounded, title: 'Track progress', body: 'See per-student strengths, improvements, and trends over time.'),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => setState(() => _step = 1),
                child: const Text('Get started'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(onPressed: _finish, child: const Text('Skip for now')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClassSetup(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Recommended: snap a photo of each class\'s attendance sheet and the roster fills itself in. You can also resume later from the Classes tab.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.4),
              ),
              const SizedBox(height: 16),
              if (_createdClasses.isNotEmpty) ...[
                Text('Created so far', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Column(
                      children: [
                        for (final n in _createdClasses)
                          ListTile(
                            dense: true,
                            leading: Icon(Icons.check_circle_rounded, color: AiMarkerColors.secondary),
                            title: Text(n, style: Theme.of(context).textTheme.bodyMedium),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
              Text(_createdClasses.isEmpty ? 'Your first class' : 'Class ${_createdClasses.length + 1}', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                'Most teachers have about 3 classes — save one, then add the next. The class names itself, like "Physics P2".',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _subject,
                      textCapitalization: TextCapitalization.words,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(labelText: 'Subject', hintText: 'Physics'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _period,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(labelText: 'Period', hintText: 'P2'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                value: _classGrade,
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('Not set')),
                  for (var g = 1; g <= 12; g++) DropdownMenuItem<int?>(value: g, child: Text('Grade $g')),
                ],
                onChanged: (v) => setState(() => _classGrade = v),
                decoration: const InputDecoration(
                  labelText: 'Grade level',
                  helperText: 'This class is marked at its grade\'s expectations automatically.',
                ),
              ),
              const SizedBox(height: 20),
              Text('Students', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                'Snap a photo of your attendance sheet and the roster fills itself in — or add students one by one.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral),
              ),
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                onPressed: _scanning ? null : _scanAttendance,
                icon: _scanning
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.photo_camera_rounded),
                label: Text(_scanning ? 'Reading names…' : 'Scan attendance sheet'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _studentName,
                      textCapitalization: TextCapitalization.words,
                      onSubmitted: (_) => _addStudentManually(),
                      decoration: const InputDecoration(labelText: 'Student name', hintText: 'e.g. Amelia Chen'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filled(
                    onPressed: _addStudentManually,
                    icon: const Icon(Icons.add_rounded),
                    tooltip: 'Add student',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_students.isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Column(
                      children: [
                        for (var i = 0; i < _students.length; i++)
                          ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: cs.primary.withValues(alpha: 0.12),
                              child: Text(
                                _students[i].name.isEmpty ? '?' : _students[i].name[0].toUpperCase(),
                                style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700),
                              ),
                            ),
                            title: Text(_students[i].name, style: Theme.of(context).textTheme.bodyMedium),
                            subtitle: _students[i].studentId == null
                                ? null
                                : Text('ID: ${_students[i].studentId}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                            trailing: IconButton(
                              icon: Icon(Icons.close_rounded, color: AiMarkerColors.neutral),
                              onPressed: () => setState(() => _students.removeAt(i)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _creating || _subject.text.trim().isEmpty ? null : () => _saveClass(addAnother: true),
                icon: _creating
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.add_rounded),
                label: Text(_students.isEmpty
                    ? 'Save class & add another'
                    : 'Save class (${_students.length} student${_students.length == 1 ? '' : 's'}) & add another'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _creating || _subject.text.trim().isEmpty ? null : () => _saveClass(addAnother: false),
                child: const Text('Save class & finish'),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: _creating ? null : _finish,
                child: Text(_createdClasses.isEmpty ? 'Resume later — take me to the app' : 'Done — take me to the app'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _FeatureRow({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: cs.primary.withValues(alpha: 0.10),
            ),
            child: Icon(icon, color: cs.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(body, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
