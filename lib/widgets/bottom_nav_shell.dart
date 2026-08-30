import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:marking_prokect_v2/theme.dart';
import 'package:marking_prokect_v2/widgets/responsive.dart';

/// One destination in the app's main navigation, written down once so the
/// phone's bottom bar and the desktop's side rail can never drift apart.
class _Dest {
  final IconData icon;
  final String label;
  const _Dest(this.icon, this.label);
}

const List<_Dest> _destinations = [
  _Dest(Icons.edit_document, 'Grading'),
  _Dest(Icons.grid_view_rounded, 'Dashboard'),
  _Dest(Icons.groups_2_rounded, 'Classes'),
  _Dest(Icons.fact_check_rounded, 'Answers'),
  _Dest(Icons.settings_rounded, 'Settings'),
];

/// The app's main shell.
///
/// Same five destinations, same routes, same branch state — the only thing
/// that changes with the window is where the teacher's thumb or mouse finds
/// them. On a phone that is a bottom tab bar. On a laptop or a desktop
/// browser a bottom bar pinned to the foot of a 900px-tall window is a long
/// way from anything, so those get a rail down the left instead, which is
/// where a teacher already looks for navigation on the web.
class BottomNavShell extends StatelessWidget {
  final StatefulNavigationShell shell;
  const BottomNavShell({super.key, required this.shell});

  void _go(int i) => shell.goBranch(i, initialLocation: i == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Breakpoints.isExpanded(width) ? _wide(context, extended: Breakpoints.railIsExtendedAt(width)) : _compact(context);
  }

  /// The phone layout, unchanged.
  Widget _compact(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: shell,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(color: Theme.of(context).cardColor, border: Border(top: BorderSide(color: cs.outline.withValues(alpha: 0.35), width: 1))),
        padding: const EdgeInsets.only(top: 6),
        child: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: _go,
          destinations: [
            for (final d in _destinations)
              NavigationDestination(icon: Icon(d.icon, color: AiMarkerColors.neutral), selectedIcon: Icon(d.icon), label: d.label),
          ],
        ),
      ),
    );
  }

  /// The desktop layout: a rail that stays put while the teacher works, and
  /// the screen itself centred in the space that is left.
  Widget _wide(BuildContext context, {required bool extended}) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Row(
        children: [
          Container(
            decoration: BoxDecoration(color: Theme.of(context).cardColor, border: Border(right: BorderSide(color: cs.outline.withValues(alpha: 0.35), width: 1))),
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: MediaQuery.sizeOf(context).height),
                child: IntrinsicHeight(
                  child: NavigationRail(
                    backgroundColor: Colors.transparent,
                    extended: extended,
                    labelType: extended ? null : NavigationRailLabelType.all,
                    // Sit the destinations near the top rather than floating
                    // them in the middle of a tall monitor.
                    groupAlignment: -0.9,
                    selectedIndex: shell.currentIndex,
                    onDestinationSelected: _go,
                    destinations: [
                      for (final d in _destinations)
                        NavigationRailDestination(
                          icon: Icon(d.icon, color: AiMarkerColors.neutral),
                          selectedIcon: Icon(d.icon),
                          label: Text(d.label),
                          padding: const EdgeInsets.symmetric(vertical: 4),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: shell),
        ],
      ),
    );
  }
}
