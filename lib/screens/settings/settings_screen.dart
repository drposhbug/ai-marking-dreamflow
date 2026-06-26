import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:marking_prokect_v2/app/app_routes.dart';
import 'package:marking_prokect_v2/app/app_state.dart';
import 'package:marking_prokect_v2/models/grading_preset.dart';
import 'package:marking_prokect_v2/services/auth_service.dart';
import 'package:marking_prokect_v2/services/classes_service.dart';
import 'package:marking_prokect_v2/services/presets_service.dart';
import 'package:marking_prokect_v2/services/supabase_hook.dart';
import 'package:marking_prokect_v2/theme.dart';
import 'package:provider/provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _alertsNew = true;
  bool _alertsTriage = true;
  bool _weekly = false;
  bool _share = false;
  String _modeLabel(GradingMode m) => switch (m) {
    GradingMode.homework => 'Homework',
    GradingMode.testQuiz => 'Test / Quiz',
    GradingMode.labReport => 'Lab Report',
    GradingMode.englishEssay => 'English / Essay',
  };

  String _harshnessLabel(int v) => v <= 3 ? 'Lenient' : (v <= 6 ? 'Balanced' : 'Strict');

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
    if (selected == null) return;

    await context.read<AppState>().setDefaultMode(teacherId: auth.id, mode: selected);
    await context.read<SupabaseHook>().updateUserPreferences(userId: auth.id, defaultMode: selected);
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
                    Text('Controls how strict the AI is by default.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
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
                              label: '$label (${intValue}/10)',
                              onChanged: (nv) => setModalState(() => v = nv),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$label (${intValue}/10)',
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

    if (selected == null) return;
    await context.read<AppState>().setDefaultHarshness(teacherId: auth.id, harshness: selected);
    await context.read<SupabaseHook>().updateUserPreferences(userId: auth.id, defaultHarshness: selected);
  }

  Future<void> _editProfile() async {
    final auth = context.read<AuthService>().currentUser;
    if (auth == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please sign in to edit your profile.')));
      return;
    }

    final cs = Theme.of(context).colorScheme;
    final nameCtrl = TextEditingController(text: auth.name);
    final schoolCtrl = TextEditingController(text: auth.school);
    String title = auth.title;

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
                                DropdownMenuItem(value: 'Dr.', child: Text('Dr.')),
                              ],
                              onChanged: (v) => setModalState(() => title = (v ?? 'Teacher')),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: nameCtrl,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(labelText: 'Display name'),
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

    if (saved != true) return;

    final nextName = nameCtrl.text.trim();
    final nextSchool = schoolCtrl.text.trim();
    await context.read<AuthService>().updateProfile(name: nextName, school: nextSchool, title: title);

    // Best-effort Supabase sync (safe when not configured).
    try {
      await context.read<SupabaseHook>().updateUserProfileByEmail(email: auth.email, displayName: nextName, school: nextSchool, title: title);
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
    final presetCount = context.watch<PresetsService>().presets.length;

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
                    child: Text((user?.name ?? 'T').substring(0, 1), style: TextStyle(color: cs.primary, fontWeight: FontWeight.w800, fontSize: 22)),
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
            Text('MY PREFERENCES', style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.2, color: AiMarkerColors.neutral)),
            const SizedBox(height: 10),
            Card(
              child: Column(
                children: [
                  _RowItem(icon: Icons.tune_rounded, title: 'Default Mode', trailing: _modeLabel(appState.defaultMode), onTap: _pickDefaultMode),
                  _RowItem(icon: Icons.speed_rounded, title: 'Default Harshness', trailing: _harshnessLabel(appState.defaultHarshness), onTap: _pickDefaultHarshness),
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
                  _RowItem(
                    icon: Icons.library_books_rounded,
                    title: 'My Marking Schemes',
                    subtitle: 'Your saved marking schemes',
                    badge: '$presetCount',
                    onTap: () => context.go(AppRoutes.library),
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
                  _ToggleRow(title: 'New submission alerts', value: _alertsNew, onChanged: (v) => setState(() => _alertsNew = v)),
                  _ToggleRow(title: 'Triage flag alerts', value: _alertsTriage, onChanged: (v) => setState(() => _alertsTriage = v)),
                  _ToggleRow(title: 'Weekly summary', value: _weekly, onChanged: (v) => setState(() => _weekly = v)),
                  _ToggleRow(title: 'Share results with students', value: _share, onChanged: (v) => setState(() => _share = v)),
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
                await context.read<AuthService>().signOut();
                if (!mounted) return;
                context.go(AppRoutes.login);
              },
              child: const Text('→ Sign Out'),
            ),
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

class _ToggleRow extends StatelessWidget {
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({required this.title, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleSmall)),
          Switch(value: value, onChanged: onChanged, activeColor: cs.primary),
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
