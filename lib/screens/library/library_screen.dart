import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:marking_prokect_v2/app/app_routes.dart';
import 'package:marking_prokect_v2/models/grading_preset.dart';
import 'package:marking_prokect_v2/services/auth_service.dart';
import 'package:marking_prokect_v2/services/presets_service.dart';
import 'package:marking_prokect_v2/theme.dart';
import 'package:marking_prokect_v2/widgets/teacher_topbar.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  bool _loadingCustom = false;

  @override
  void initState() {
    super.initState();
    // Optionally fetch additional custom schemes after first paint.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCustomSchemesIfSignedIn());
  }

  Future<void> _loadCustomSchemesIfSignedIn() async {
    final auth = context.read<AuthService>().currentUser;
    // If they aren't signed into the app, there's nothing extra to load.
    if (auth == null) return;

    // If Supabase isn't authenticated, also skip (defaults still show).
    final supabaseSignedIn = _hasSupabaseSession();
    if (!supabaseSignedIn) return;

    try {
      if (mounted) setState(() => _loadingCustom = true);
      await context.read<PresetsService>().refreshCustomSchemesFromSupabase(teacherId: auth.id);
    } catch (e) {
      // Never show an error state on this screen; just log.
      debugPrint('LibraryScreen custom scheme fetch failed: $e');
    } finally {
      if (mounted) setState(() => _loadingCustom = false);
    }
  }

  bool _hasSupabaseSession() {
    try {
      return Supabase.instance.client.auth.currentSession != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final auth = context.watch<AuthService>().currentUser;
    final presetsService = context.watch<PresetsService>();

    final defaults = presetsService.builtInSchemes;
    final custom = auth == null ? const <GradingPreset>[] : presetsService.customGlobalSchemes(teacherId: auth.id);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadCustomSchemesIfSignedIn,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
            children: [
              TeacherTopbar(
                title: 'AI Marker',
                trailingIcon: Icons.add_rounded,
                onBell: () {
                  if (auth == null) {
                    _showSignInSheet(context);
                    return;
                  }
                  context.push('${AppRoutes.presetFlow}?classId=');
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: Text('Marking Schemes', style: Theme.of(context).textTheme.titleLarge)),
                  FilledButton.icon(
                    onPressed: () {
                      if (auth == null) {
                        _showSignInSheet(context);
                        return;
                      }
                      context.push('${AppRoutes.presetFlow}?classId=');
                    },
                    style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: Colors.white),
                    icon: const Icon(Icons.add_rounded, color: Colors.white),
                    label: const Text('+ New Scheme'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (auth == null) ...[
                _SignInBanner(onSignIn: () => context.go(AppRoutes.login)),
                const SizedBox(height: 12),
              ],
              _SectionLabel(text: 'Defaults'),
              const SizedBox(height: 10),
              for (final scheme in defaults) ...[
                SchemeCard(scheme: scheme),
                const SizedBox(height: 12),
              ],
              if (auth != null) ...[
                const SizedBox(height: 4),
                _SectionLabel(text: 'Your custom schemes'),
                const SizedBox(height: 10),
                if (_loadingCustom)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                  ),
                if (custom.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text('Create your own custom schemes to save time across classes.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AiMarkerColors.neutral)),
                  ),
                for (final scheme in custom) ...[
                  SchemeCard(scheme: scheme),
                  const SizedBox(height: 12),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showSignInSheet(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Sign in required', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text('Sign in to create and save your own custom marking schemes.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AiMarkerColors.neutral, height: 1.45)),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () {
                  ctx.pop();
                  context.go(AppRoutes.login);
                },
                style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(52)),
                child: const Text('Go to Sign In'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => ctx.pop(),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), side: BorderSide(color: cs.outline.withValues(alpha: 0.45))),
                child: Text('Not now', style: TextStyle(color: cs.primary)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(999), border: Border.all(color: cs.outline.withValues(alpha: 0.14))),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AiMarkerColors.neutral, fontWeight: FontWeight.w900)),
    );
  }
}

class _SignInBanner extends StatelessWidget {
  final VoidCallback onSignIn;
  const _SignInBanner({required this.onSignIn});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: cs.primary.withValues(alpha: 0.14))),
      child: Row(
        children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)), child: Icon(Icons.lock_open_rounded, color: cs.primary)),
          const SizedBox(width: 12),
          Expanded(child: Text('Sign in to save your own custom schemes', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AiMarkerColors.neutral, height: 1.35))),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: onSignIn,
            style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
            child: const Text('Sign in'),
          ),
        ],
      ),
    );
  }
}

class SchemeCard extends StatefulWidget {
  final GradingPreset scheme;

  const SchemeCard({super.key, required this.scheme});

  @override
  State<SchemeCard> createState() => _SchemeCardState();
}

class _SchemeCardState extends State<SchemeCard> {
  Timer? _debounce;
  late double _harshness;

  @override
  void initState() {
    super.initState();
    _harshness = widget.scheme.harshness.toDouble();
  }

  @override
  void didUpdateWidget(covariant SchemeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scheme.harshness != widget.scheme.harshness) {
      _harshness = widget.scheme.harshness.toDouble();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = _accentFor(widget.scheme.gradingMode);
    final enabledCount = widget.scheme.criteria.entries.where((e) => e.value == true).length;

    return Container(
      decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: cs.outline.withValues(alpha: 0.22))),
      child: InkWell(
        splashFactory: NoSplash.splashFactory,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => context.push('${AppRoutes.presetDetail}?presetId=${widget.scheme.id}'),
        child: Stack(
          children: [
            Positioned.fill(
              child: Row(
                children: [
                  Container(width: 4, decoration: BoxDecoration(color: accent, borderRadius: const BorderRadius.only(topLeft: Radius.circular(AppRadius.lg), bottomLeft: Radius.circular(AppRadius.lg)))),
                  const SizedBox(width: 0),
                  const Expanded(child: SizedBox()),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(widget.scheme.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
                      if (widget.scheme.isDefault)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(999), border: Border.all(color: cs.outline.withValues(alpha: 0.18))),
                          child: Text('Default', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AiMarkerColors.neutral, fontWeight: FontWeight.w900)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Pill(text: _modeLabel(widget.scheme.gradingMode), color: accent.withValues(alpha: 0.12), textColor: accent),
                      _Pill(text: '$enabledCount criteria', color: cs.surfaceContainerHighest, textColor: AiMarkerColors.neutral),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                    decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: cs.outline.withValues(alpha: 0.14))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Text('Strictness', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                            const SizedBox(width: 8),
                            Text(_harshnessWord(_harshness.round()), style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w900, color: _harshnessColor(_harshness.round()))),
                            const Spacer(),
                            Text('${_harshness.round()}/10', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
                          ],
                        ),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(trackHeight: 3.2, overlayShape: SliderComponentShape.noOverlay),
                          child: Slider(
                            value: _harshness,
                            min: 0,
                            max: 10,
                            divisions: 10,
                            onChanged: (v) {
                              setState(() => _harshness = v);
                              _debounce?.cancel();
                              _debounce = Timer(const Duration(milliseconds: 450), () => _commitHarshness());
                            },
                            onChangeEnd: (_) => _commitHarshness(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Edit',
                        onPressed: () => context.push(AppRoutes.presetEdit, extra: widget.scheme),
                        icon: Icon(Icons.edit_rounded, color: AiMarkerColors.neutral),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        onPressed: () => _confirmDelete(context, scheme: widget.scheme),
                        icon: Icon(Icons.delete_outline_rounded, color: AiMarkerColors.neutral),
                      ),
                      const Spacer(),
                      PopupMenuButton<String>(
                        tooltip: 'More',
                        splashRadius: 18,
                        onSelected: (v) async {
                          if (v == 'duplicate') {
                            final auth = context.read<AuthService>().currentUser;
                            if (auth == null) {
                              final host = context.findAncestorStateOfType<_LibraryScreenState>();
                              host?._showSignInSheet(context);
                              return;
                            }
                            await context.read<PresetsService>().duplicate(presetId: widget.scheme.id, teacherIdOverride: auth.id, classIdOverride: '');
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'duplicate',
                            child: Row(
                              children: [
                                Icon(Icons.copy_rounded, color: cs.primary),
                                const SizedBox(width: 10),
                                const Text('Duplicate'),
                              ],
                            ),
                          ),
                        ],
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                          child: Icon(Icons.more_horiz_rounded, color: AiMarkerColors.neutral.withValues(alpha: 0.9)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _commitHarshness() async {
    final next = _harshness.round();
    if (next == widget.scheme.harshness) return;
    try {
      await context.read<PresetsService>().updateHarshness(presetId: widget.scheme.id, harshness: next);
    } catch (e) {
      debugPrint('SchemeCard updateHarshness failed: $e');
    }
  }

  Future<void> _confirmDelete(BuildContext context, {required GradingPreset scheme}) async {
    final cs = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(scheme.isBuiltInDefault ? 'Reset scheme?' : 'Delete scheme?'),
        content: Text(scheme.isBuiltInDefault ? 'Your changes to “${scheme.name}” will be reverted back to the built-in default.' : '“${scheme.name}” will be removed.'),
        actions: [
          TextButton(onPressed: () => ctx.pop(false), child: Text('Cancel', style: TextStyle(color: cs.primary))),
          FilledButton(
            onPressed: () => ctx.pop(true),
            style: FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: Colors.white),
            child: Text(scheme.isBuiltInDefault ? 'Reset' : 'Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    try {
      await context.read<PresetsService>().delete(scheme.id);
    } catch (e) {
      debugPrint('SchemeCard delete failed: $e');
    }
  }

  Color _accentFor(GradingMode mode) => switch (mode) {
    GradingMode.homework => AiMarkerColors.primary,
    GradingMode.testQuiz => AiMarkerColors.error,
    GradingMode.labReport => AiMarkerColors.secondary,
    GradingMode.englishEssay => AiMarkerColors.tertiary,
  };

  String _modeLabel(GradingMode m) => switch (m) {
    GradingMode.homework => 'Homework',
    GradingMode.testQuiz => 'Test / Quiz',
    GradingMode.labReport => 'Lab Report',
    GradingMode.englishEssay => 'English / Essay',
  };

  String _harshnessWord(int h) => h <= 3 ? 'Lenient' : (h <= 6 ? 'Balanced' : 'Strict');

  Color _harshnessColor(int h) => h <= 3 ? AiMarkerColors.secondary : (h <= 6 ? Colors.orange : AiMarkerColors.error);
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  final Color textColor;

  const _Pill({required this.text, required this.color, required this.textColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999), border: Border.all(color: textColor.withValues(alpha: 0.18))),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: textColor, fontWeight: FontWeight.w800)),
    );
  }
}

class _EmptySchemesState extends StatelessWidget {
  final VoidCallback onCreate;
  final bool showRestore;
  final Future<void> Function() onRestore;

  const _EmptySchemesState({required this.onCreate, required this.showRestore, required this.onRestore});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(18)),
              child: Icon(Icons.library_books_rounded, color: cs.primary, size: 28),
            ),
          ),
          const SizedBox(height: 14),
          Center(child: Text('No marking schemes yet', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
          const SizedBox(height: 6),
          if (showRestore)
            Center(
              child: Text(
                'Your 4 default schemes were removed. Create a new one or restore defaults.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AiMarkerColors.neutral, height: 1.45),
              ),
            )
          else
            Center(
              child: Text(
                'Create your first marking scheme to get started.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AiMarkerColors.neutral, height: 1.45),
              ),
            ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: onCreate,
            style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(52)),
            child: const Text('Create New Scheme'),
          ),
          if (showRestore) ...[
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () async => onRestore(),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), side: BorderSide(color: cs.outline.withValues(alpha: 0.45))),
              child: Text('Restore Defaults', style: TextStyle(color: cs.primary)),
            ),
          ],
        ],
      ),
    );
  }
}

class _InlineErrorCard extends StatelessWidget {
  final String text;
  final Future<void> Function() onRetry;

  const _InlineErrorCard({required this.text, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [Icon(Icons.error_outline_rounded, color: cs.error), const SizedBox(width: 10), Expanded(child: Text('Could not load schemes', style: Theme.of(context).textTheme.titleMedium))]),
            const SizedBox(height: 8),
            Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async => onRetry(),
              style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: Colors.white),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
