import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:marking_prokect_v2/app/app_routes.dart';
import 'package:marking_prokect_v2/app/app_state.dart';
import 'package:marking_prokect_v2/data/curriculum_regions.dart';
import 'package:marking_prokect_v2/models/grading_preset.dart';
import 'package:marking_prokect_v2/services/billing_service.dart';
import 'package:marking_prokect_v2/services/ai_grading_service.dart';
import 'package:marking_prokect_v2/services/anonymizer.dart';
import 'package:marking_prokect_v2/services/auth_service.dart';
import 'package:marking_prokect_v2/services/classes_service.dart';
import 'package:marking_prokect_v2/services/drive_service.dart';
import 'package:marking_prokect_v2/services/local_store.dart';
import 'package:marking_prokect_v2/services/push_service.dart';
import 'package:marking_prokect_v2/services/supabase_hook.dart';
import 'package:marking_prokect_v2/theme.dart';
import 'package:marking_prokect_v2/widgets/region_picker.dart';
import 'package:provider/provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _driveAutoSave = false;

  UsageSummary? _usage;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      if (!mounted) return;
      final auth = context.read<AuthService>().currentUser;
      if (auth == null) return;
      final v = await DriveService().autoSaveEnabled(auth.id);
      if (mounted) setState(() => _driveAutoSave = v);
      try {
        final u = await AiGradingService().getUsage(teacherId: auth.id);
        if (mounted) setState(() => _usage = u);
      } catch (e) {
        debugPrint('SettingsScreen usage load failed: $e');
      }
    });
  }

  /// Saved against the account, not the phone, so a teacher who switches
  /// devices keeps the answer they already gave.
  Future<void> _setPushPrefs(PushPrefs prefs) async {
    final auth = context.read<AuthService>().currentUser;
    if (auth == null) return;
    await context.read<PushService>().setPrefs(auth.id, prefs);
  }

  bool _deleting = false;

  /// Erases the account everywhere — required by both app stores, and the
  /// one action in the app that can't be undone, so it asks twice: once for
  /// the consequences, once with the word DELETE typed out.
  Future<void> _deleteAccount() async {
    final auth = context.read<AuthService>().currentUser;
    if (auth == null) return;
    // Held now, before the confirmations: a deleted account must stop being
    // a notification target too, and by then the context is long gone.
    final push = context.read<PushService>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete your account?'),
        content: Text(
          'This erases ${auth.email} for good: every marked test, class, student, '
          'answer key and setting, on this phone and on our servers. Nobody can '
          'bring it back — not even us.\n\n'
          'Cancelling a subscription is separate: do that in the Play Store or App Store.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep my account')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AiMarkerColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final typed = TextEditingController();
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Type DELETE to confirm'),
        content: TextField(
          controller: typed,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'DELETE'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AiMarkerColors.error),
            onPressed: () => Navigator.pop(context, typed.text.trim().toUpperCase() == 'DELETE'),
            child: const Text('Delete for good'),
          ),
        ],
      ),
    );
    typed.dispose();
    if (sure != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      // Server first: if it fails the teacher still has their account, which
      // is the recoverable side of the mistake.
      await AiGradingService().deleteAccountCloud(teacherId: auth.id);
      await const LocalStore().clear();
      await push.logOut();
      if (!mounted) return;
      await context.read<BillingService>().logOut();
      if (!mounted) return;
      await context.read<AuthService>().signOut();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your account and everything in it has been deleted.')),
      );
      context.go(AppRoutes.login);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Couldn\'t delete the account: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  /// Opt-in consent for automatic Drive export — requires a Google session
  /// so the export can actually happen.
  Future<void> _setDriveAutoSave(bool v) async {
    final auth = context.read<AuthService>().currentUser;
    if (auth == null) return;
    if (v && !DriveService().isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connect Google Drive first — use the button below.')),
      );
      return;
    }
    setState(() => _driveAutoSave = v);
    await DriveService().setAutoSave(auth.id, v);
    if (!mounted || !v) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Every marked test will now also be saved to your Drive\'s UMarkless folder — you\'ll see a note each time.')),
    );
  }

  bool _linkingDrive = false;

  /// Email-account teachers link Google onto their existing account (same
  /// account, no re-registering) to unlock Drive export.
  Future<void> _connectDrive() async {
    setState(() => _linkingDrive = true);
    try {
      await context.read<AuthService>().connectGoogleDrive();
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Google Drive connected ✓ — you can now export and auto-save marked tests.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _linkingDrive = false);
    }
  }
  String _modeLabel(GradingMode m) => switch (m) {
    GradingMode.homework => 'Homework',
    GradingMode.testQuiz => 'Test / Quiz',
    GradingMode.labReport => 'Lab Report',
    GradingMode.englishEssay => 'English / Essay',
  };

  String _harshnessLabel(int v) => v <= 3 ? 'Lenient' : (v <= 6 ? 'Balanced' : 'Strict');

  String _regionLabel(String id) => id.isEmpty ? 'Not set' : (regionById(id)?.label ?? 'Not set');

  Future<void> _pickRegion() async {
    final auth = context.read<AuthService>().currentUser;
    if (auth == null) return;
    final appState = context.read<AppState>();
    final picked = await showRegionPicker(context, selectedId: appState.region);
    if (picked == null || !mounted) return;
    await appState.setRegion(teacherId: auth.id, regionId: picked.id);
  }

  Future<void> _manageMarkingFeedback() async {
    final auth = context.read<AuthService>().currentUser;
    if (auth == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) => _MarkingFeedbackSheet(teacherId: auth.id),
    );
  }

  Future<void> _pickDefaultMode() async {
    final auth = context.read<AuthService>().currentUser;
    if (auth == null) return;
    final appState = context.read<AppState>();
    final selected = await showModalBottomSheet<GradingMode>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        final current = appState.defaultMode;
        final items = const [GradingMode.homework, GradingMode.testQuiz, GradingMode.labReport, GradingMode.englishEssay];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Default Mode', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                Card(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final m in items)
                        ListTile(
                          title: Text(_modeLabel(m), style: Theme.of(context).textTheme.titleSmall),
                          trailing: m == current ? Icon(Icons.check_rounded, color: cs.primary) : null,
                          onTap: () => Navigator.of(context).pop(m),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected == null || !mounted) return;

    final hook = context.read<SupabaseHook>();
    await context.read<AppState>().setDefaultMode(teacherId: auth.id, mode: selected);
    await hook.updateUserPreferences(userId: auth.id, defaultMode: selected);
  }

  Future<void> _pickDefaultHarshness() async {
    final auth = context.read<AuthService>().currentUser;
    if (auth == null) return;
    final appState = context.read<AppState>();

    final selected = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        double v = appState.defaultHarshness.toDouble();
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(14, 6, 14, 16 + MediaQuery.of(context).viewInsets.bottom),
            child: StatefulBuilder(
              builder: (context, setModalState) {
                final intValue = v.round().clamp(1, 10);
                final label = _harshnessLabel(intValue);
                final Color accent = intValue >= 7 ? AiMarkerColors.error : (intValue <= 3 ? AiMarkerColors.secondary : Colors.orange);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Default Harshness', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 6),
                    Text('Controls how strict marking is by default.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text('Lenient (1–3)', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                                const Spacer(),
                                Text('Strict (7–10)', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                              ],
                            ),
                            Slider(
                              value: v,
                              min: 1,
                              max: 10,
                              divisions: 9,
                              label: '$label ($intValue/10)',
                              onChanged: (nv) => setModalState(() => v = nv),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$label ($intValue/10)',
                              style: Theme.of(context).textTheme.labelLarge?.copyWith(color: accent, fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              label == 'Lenient'
                                  ? 'Gives benefit of the doubt; rewards effort and partial credit.'
                                  : (label == 'Balanced'
                                      ? 'Most teachers prefer this: fair, consistent, and moderate.'
                                      : 'Holds students to the rubric strictly; fewer points for unclear work.'),
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: OutlinedButton.styleFrom(foregroundColor: cs.onSurface),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.of(context).pop(intValue),
                            style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: Colors.white),
                            child: const Text('Save'),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );

    if (selected == null || !mounted) return;
    final hook = context.read<SupabaseHook>();
    await context.read<AppState>().setDefaultHarshness(teacherId: auth.id, harshness: selected);
    await hook.updateUserPreferences(userId: auth.id, defaultHarshness: selected);
  }

  Future<void> _editProfile() async {
    final auth = context.read<AuthService>().currentUser;
    if (auth == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please sign in to edit your profile.')));
      return;
    }

    final cs = Theme.of(context).colorScheme;
    // The field holds the bare name; the dropdown owns the honorific — so
    // switching Ms. → Mr. actually switches instead of sticking.
    final nameCtrl = TextEditingController(text: AuthService.stripHonorific(auth.name));
    final schoolCtrl = TextEditingController(text: auth.school);
    String title = auth.title;

    // "Ms." + "Lee" → "Ms. Lee". Never doubles a title the teacher already
    // typed; "Teacher" acts as a plain role with no prefix.
    String composeName(String t, String raw) {
      final r = raw.trim();
      if (r.isEmpty || t.isEmpty || t == 'Teacher') return r;
      const honorifics = ['Mr.', 'Ms.', 'Mrs.', 'Mx.', 'Dr.', 'Teacher'];
      final lower = r.toLowerCase();
      for (final h in honorifics) {
        final base = h.toLowerCase();
        if (lower.startsWith(base) || lower.startsWith(base.replaceAll('.', ' ')) || lower.startsWith('${base.replaceAll('.', '')} ')) return r;
      }
      return '$t $r';
    }

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: cs.surface,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 6, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
            child: StatefulBuilder(
              builder: (context, setModalState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Edit Profile', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 10),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                        child: Column(
                          children: [
                            DropdownButtonFormField<String>(
                              value: (title.isEmpty) ? 'Teacher' : title,
                              decoration: const InputDecoration(labelText: 'Role / Title'),
                              items: const [
                                DropdownMenuItem(value: 'Teacher', child: Text('Teacher')),
                                DropdownMenuItem(value: 'Ms.', child: Text('Ms.')),
                                DropdownMenuItem(value: 'Mr.', child: Text('Mr.')),
                                DropdownMenuItem(value: 'Mrs.', child: Text('Mrs.')),
                                DropdownMenuItem(value: 'Mx.', child: Text('Mx.')),
                                DropdownMenuItem(value: 'Dr.', child: Text('Dr.')),
                              ],
                              onChanged: (v) => setModalState(() => title = (v ?? 'Teacher')),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: nameCtrl,
                              textInputAction: TextInputAction.next,
                              onChanged: (_) => setModalState(() {}),
                              decoration: InputDecoration(
                                labelText: 'Display name',
                                hintText: 'e.g. Lee',
                                helperText: composeName(title, nameCtrl.text).isEmpty ? null : 'Shown as: ${composeName(title, nameCtrl.text)}',
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: schoolCtrl,
                              textInputAction: TextInputAction.done,
                              decoration: const InputDecoration(labelText: 'School'),
                            ),
                            const SizedBox(height: 6),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => context.pop(false),
                            style: OutlinedButton.styleFrom(foregroundColor: cs.onSurface),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              final name = nameCtrl.text.trim();
                              if (name.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name can\'t be empty.')));
                                return;
                              }
                              context.pop(true);
                            },
                            style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: Colors.white),
                            child: const Text('Save'),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );

    if (saved != true || !mounted) return;

    final nextName = composeName(title, nameCtrl.text);
    final nextSchool = schoolCtrl.text.trim();
    await context.read<AuthService>().updateProfile(name: nextName, school: nextSchool, title: title);

    // Best-effort Supabase sync (safe when not configured).
    try {
      await AiGradingService().saveProfile(teacherId: auth.id, name: nextName, school: nextSchool);
    } catch (e) {
      debugPrint('SettingsScreen._editProfile Supabase sync failed: $e');
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated.')));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = context.watch<AuthService>().currentUser;
    final appState = context.watch<AppState>();
    final classCount = context.watch<ClassesService>().classes.length;
    final push = context.watch<PushService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Grading Assistant')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
          children: [
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: cs.primary.withValues(alpha: 0.12),
                    // Skip the honorific so "Mr. Lee" shows "L", not "M".
                    child: Text(
                      AuthService.stripHonorific(user?.name ?? '').isEmpty ? 'T' : AuthService.stripHonorific(user!.name).substring(0, 1).toUpperCase(),
                      style: TextStyle(color: cs.primary, fontWeight: FontWeight.w800, fontSize: 22),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(color: cs.surface, shape: BoxShape.circle, border: Border.all(color: cs.outline.withValues(alpha: 0.25))),
                      child: Icon(Icons.photo_camera_rounded, size: 16, color: cs.primary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(user?.name ?? 'Teacher', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('${user?.email ?? ''}\n${user?.school ?? ''}', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _editProfile,
              style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: Colors.white),
              child: const Text('Edit Profile'),
            ),
            const SizedBox(height: 18),
            // Big, obvious feedback entry — the most important control here.
            Card(
              color: cs.primary.withValues(alpha: 0.08),
              child: InkWell(
                splashFactory: NoSplash.splashFactory,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                onTap: _manageMarkingFeedback,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
                            child: Icon(Icons.school_rounded, color: cs.primary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Teach Mark — Marking Feedback', style: Theme.of(context).textTheme.titleMedium),
                                const SizedBox(height: 2),
                                Text(
                                  appState.markingFeedback.isEmpty
                                      ? 'Disagree with how it marks? Tell Mark — it follows your feedback on every grade.'
                                      : '${appState.markingFeedback.length} correction${appState.markingFeedback.length == 1 ? '' : 's'} active.',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.35),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _manageMarkingFeedback,
                          style: FilledButton.styleFrom(
                            backgroundColor: cs.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          icon: const Icon(Icons.rate_review_rounded, size: 20),
                          label: Text(
                            appState.markingFeedback.isEmpty ? 'Give feedback' : 'Give more feedback',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text('MY PREFERENCES', style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.2, color: AiMarkerColors.neutral)),
            const SizedBox(height: 10),
            Card(
              child: Column(
                children: [
                  _RowItem(icon: Icons.tune_rounded, title: 'Default Mode', trailing: _modeLabel(appState.defaultMode), onTap: _pickDefaultMode),
                  _RowItem(icon: Icons.speed_rounded, title: 'Default Harshness', trailing: _harshnessLabel(appState.defaultHarshness), onTap: _pickDefaultHarshness),
                  _RowItem(icon: Icons.place_rounded, title: 'Curriculum Region', trailing: _regionLabel(appState.region), onTap: _pickRegion),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text('ORGANIZATION', style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.2, color: AiMarkerColors.neutral)),
            const SizedBox(height: 10),
            Card(
              child: Column(
                children: [
                  _RowItem(icon: Icons.groups_2_rounded, title: 'My Classes', subtitle: null, badge: '$classCount', onTap: () => context.go(AppRoutes.classes)),
                  // Marking schemes were removed from the UI — Mark detects
                  // the assignment style itself. Answers (keys) live in the
                  // bottom tab, so no stale scheme count is shown here.
                  _RowItem(
                    icon: Icons.key_rounded,
                    title: 'Answer Keys',
                    subtitle: 'Scan or manage saved answer keys',
                    onTap: () => context.go(AppRoutes.library),
                  ),
                  _RowItem(
                    icon: Icons.upload_rounded,
                    title: 'Export marks',
                    subtitle: 'Send them to your gradebook instead of typing them in',
                    onTap: () => context.push(AppRoutes.exportMarks),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text('PLAN & USAGE', style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.2, color: AiMarkerColors.neutral)),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(_usage == null ? 'Marking credits' : 'Marking credits · ${_usage!.planLabel}', style: Theme.of(context).textTheme.titleSmall)),
                        Text(
                          _usage == null ? '—' : '${_usage!.monthPct}% used',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(value: (_usage?.monthPct ?? 0) / 100, minHeight: 8),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _usage == null
                          ? 'Credits scale with marking complexity — a quick multiple-choice quiz uses far less than a long problem set. Repeats are always free.'
                          : 'This month: ${_usage!.monthPct}% · this week: ${_usage!.weekPct}% · today: ${_usage!.dayPct}%. Credits scale with marking complexity — a quick multiple-choice quiz uses far less than a long problem set. Repeats are always free.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.4),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => context.push(AppRoutes.plans),
                      icon: const Icon(Icons.workspace_premium_rounded, size: 18),
                      label: Text(context.watch<BillingService>().isPro ? 'Manage plan' : 'See plans & upgrade'),
                    ),
                    const Divider(height: 26),
                    _GivingRow(giving: context.watch<BillingService>().giving),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text('PRIVACY', style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.2, color: AiMarkerColors.neutral)),
            const SizedBox(height: 10),
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // A browser can do this now, with a weaker reader that
                  // works off the printed label. Where a platform has no
                  // reader at all the switch is greyed out and labelled
                  // rather than left sitting on, which would tell a teacher
                  // a lie they act on with a child's work.
                  _ToggleRow(
                    title: Anonymizer.available
                        ? 'Hide student names before marking'
                        : 'Hide student names before marking — not available here',
                    value: Anonymizer.available && appState.anonymizeUploads,
                    onChanged: !Anonymizer.available
                        ? null
                        : (v) async {
                            final auth = context.read<AuthService>().currentUser;
                            if (auth == null) return;
                            await context.read<AppState>().setAnonymizeUploads(teacherId: auth.id, on: v);
                          },
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: Text(
                      Anonymizer.available
                          ? Anonymizer.hidingExplainer
                          : 'Blacking names out needs text recognition running on this device, and this one has none. Pages you upload here go for marking exactly as you picked them, name and all. Cover names before uploading, or mark from a Google Form or CSV — that route sends answers keyed by row number and never sends the name column.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.4),
                    ),
                  ),
                  if (!Anonymizer.available)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      child: OutlinedButton.icon(
                        onPressed: () => context.push(AppRoutes.importResponses),
                        icon: const Icon(Icons.table_chart_rounded, size: 18),
                        label: const Text('Mark from a Google Form or CSV'),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text('GOOGLE DRIVE', style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.2, color: AiMarkerColors.neutral)),
            const SizedBox(height: 10),
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ToggleRow(title: 'Auto-save marked tests to Drive', value: _driveAutoSave, onChanged: _setDriveAutoSave),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                      'With your consent, every marked test is saved as a Google Doc in your Drive\'s "UMarkless" folder the moment marking finishes — and you get a notification each time.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.4),
                    ),
                  ),
                  if (!DriveService().isConnected)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      child: OutlinedButton.icon(
                        onPressed: _linkingDrive ? null : _connectDrive,
                        icon: _linkingDrive
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.add_to_drive_rounded, size: 18),
                        label: const Text('Connect Google Drive'),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text('NOTIFICATIONS', style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.2, color: AiMarkerColors.neutral)),
            const SizedBox(height: 10),
            Card(
              child: Column(
                children: [
                  _ToggleRow(
                    title: 'Marked class sets',
                    value: push.prefs.batchDone,
                    onChanged: (v) => _setPushPrefs(push.prefs.copyWith(batchDone: v)),
                  ),
                  _ToggleRow(
                    title: 'Trial and credit reminders',
                    value: push.prefs.planNudges,
                    onChanged: (v) => _setPushPrefs(push.prefs.copyWith(planNudges: v)),
                  ),
                  _ToggleRow(
                    title: 'Weekly summary',
                    value: push.prefs.weeklySummary,
                    onChanged: (v) => _setPushPrefs(push.prefs.copyWith(weeklySummary: v)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: Text(
                      push.unavailableReason.isNotEmpty
                          ? push.unavailableReason
                          : 'Nothing is sent until you\'ve queued a class set overnight — that\'s the only thing worth waking you for.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text('APP THEME', style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.2, color: AiMarkerColors.neutral)),
            const SizedBox(height: 10),
            _ThemeToggle(
              mode: appState.themeMode,
              onSelect: (m) => context.read<AppState>().setThemeMode(m),
            ),
            const SizedBox(height: 28),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AiMarkerColors.error, splashFactory: NoSplash.splashFactory),
              onPressed: () async {
                // Signing out has to hand the device back to nobody, or the
                // next teacher on this phone gets the last one's nudges.
                final push = context.read<PushService>();
                await context.read<AuthService>().signOut();
                await push.logOut();
                if (!context.mounted) return;
                context.go(AppRoutes.login);
              },
              child: const Text('→ Sign Out'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AiMarkerColors.neutral, splashFactory: NoSplash.splashFactory),
              onPressed: _deleting ? null : _deleteAccount,
              child: _deleting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Delete my account'),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _RowItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailing;
  final String? badge;
  final VoidCallback onTap;

  const _RowItem({required this.icon, required this.title, required this.onTap, this.subtitle, this.trailing, this.badge});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      splashFactory: NoSplash.splashFactory,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: cs.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                  ],
                ],
              ),
            ),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999), border: Border.all(color: cs.primary.withValues(alpha: 0.18))),
                child: Text(badge!, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w800)),
              )
            else
              Text(trailing ?? '', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, color: AiMarkerColors.neutral.withValues(alpha: 0.85)),
          ],
        ),
      ),
    );
  }
}

/// Puts a number behind the give-back the Plans screen promises.
///
/// Only ever shows what the teacher's own subscription accounts for. When
/// the store hasn't given the app a price there is no total to show, so it
/// says what one payment generates instead of inventing a running figure —
/// a made-up number on a claim about giving money away is worse than none.
class _GivingRow extends StatelessWidget {
  final GivingSummary giving;

  const _GivingRow({required this.giving});

  String _money(double amount, String currencyCode) {
    final code = currencyCode.isEmpty ? '' : ' $currencyCode';
    return '\$${amount.toStringAsFixed(2)}$code';
  }

  String _line() {
    if (giving.inTrial) {
      return 'Your trial hasn\'t been charged yet — the give-back starts with your first payment.';
    }
    if (giving.paymentsMade == 0) {
      return 'Paid plans give 10% to ${GivingSummary.charityPlaceholder}. Yours starts the day you upgrade.';
    }
    final total = giving.generatedToDate;
    if (total == null) {
      // Entitled, but the store hasn't told the app what the plan costs, so
      // there is no honest total to print.
      return '10% of every payment you\'ve made goes to ${GivingSummary.charityPlaceholder}. That\'s ${giving.paymentsMade} payments so far.';
    }
    final each = _money(giving.perPayment ?? 0, giving.currencyCode);
    return 'About ${_money(total, giving.currencyCode)} so far — 10% of each of your ${giving.paymentsMade} payments, $each a ${giving.period}.';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.volunteer_activism_rounded, size: 18, color: cs.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Giving', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                _line(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String title;
  final bool value;
  /// Null greys the switch out — for a setting that cannot do anything on
  /// this platform. A switch that looks live and changes nothing is worse
  /// than no switch at all.
  final ValueChanged<bool>? onChanged;

  const _ToggleRow({required this.title, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: onChanged == null ? AiMarkerColors.neutral : null,
                  ),
            ),
          ),
          Switch(value: value, onChanged: onChanged, activeThumbColor: cs.primary),
        ],
      ),
    );
  }
}

class _ThemeToggle extends StatelessWidget {
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onSelect;

  const _ThemeToggle({required this.mode, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bool isDark = mode == ThemeMode.dark;
    return Row(
      children: [
        Expanded(
          child: _ThemePill(
            selected: !isDark,
            label: 'Light',
            icon: Icons.light_mode_rounded,
            fillColor: cs.primary,
            onTap: () => onSelect(ThemeMode.light),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ThemePill(
            selected: isDark,
            label: 'Dark',
            icon: Icons.dark_mode_rounded,
            fillColor: cs.secondary,
            onTap: () => onSelect(ThemeMode.dark),
          ),
        ),
      ],
    );
  }
}

class _ThemePill extends StatelessWidget {
  final bool selected;
  final String label;
  final IconData icon;
  final Color fillColor;
  final VoidCallback onTap;

  const _ThemePill({required this.selected, required this.label, required this.icon, required this.fillColor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Color outline = cs.outline.withValues(alpha: 0.35);
    final Color bg = selected ? fillColor : Colors.transparent;
    final Color fg = selected ? Colors.white : cs.onSurface;
    return InkWell(
      splashFactory: NoSplash.splashFactory,
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? Colors.transparent : outline),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 8),
            Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: fg, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _MarkingFeedbackSheet extends StatefulWidget {
  final String teacherId;
  const _MarkingFeedbackSheet({required this.teacherId});

  @override
  State<_MarkingFeedbackSheet> createState() => _MarkingFeedbackSheetState();
}

class _MarkingFeedbackSheetState extends State<_MarkingFeedbackSheet> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    await context.read<AppState>().addMarkingFeedback(teacherId: widget.teacherId, feedback: text);
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final feedback = context.watch<AppState>().markingFeedback;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, 8, 14, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Teach Mark', style: Theme.of(context).textTheme.titleLarge)),
                IconButton(onPressed: () => Navigator.pop(context), icon: Icon(Icons.close_rounded, color: AiMarkerColors.neutral)),
              ],
            ),
            Text(
              'Is Mark always doing something you disagree with when marking? Tell it here — every submitted correction is followed on every future grade. For example: "Don\'t deduct for spelling in science" or "Always require units in physics answers".',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _input,
              minLines: 4,
              maxLines: 7,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                labelText: 'What should Mark do differently?',
                hintText: "e.g. Don't deduct for spelling in science answers",
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text('Submit feedback'),
            ),
            const SizedBox(height: 10),
            if (feedback.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('Nothing saved yet. You can also add feedback from any result screen with "Teach Mark".', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (var i = 0; i < feedback.length; i++)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.rule_rounded, color: Theme.of(context).colorScheme.primary, size: 20),
                        title: Text(feedback[i], style: Theme.of(context).textTheme.bodyMedium),
                        trailing: IconButton(
                          icon: Icon(Icons.delete_outline_rounded, color: AiMarkerColors.error, size: 20),
                          onPressed: () => context.read<AppState>().removeMarkingFeedbackAt(teacherId: widget.teacherId, index: i),
                        ),
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
