import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:marking_prokect_v2/app/app_routes.dart';
import 'package:marking_prokect_v2/theme.dart';
import 'package:marking_prokect_v2/widgets/responsive.dart';

/// One of the five places the app keeps state for, written down once so the
/// phone's bottom bar and the desktop sidebar can never drift apart.
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

/// A tool that lives on a pushed route rather than a tab.
///
/// On a phone these are cards down the grading screen, which is right for a
/// thumb. On a desktop a teacher expects everything the app does to be
/// visible in the sidebar — hiding half the product one scroll down a home
/// screen is how features go unfound.
class _Tool {
  final IconData icon;
  final String label;
  final String route;
  const _Tool(this.icon, this.label, this.route);
}

class _ToolGroup {
  final String title;
  final List<_Tool> tools;
  const _ToolGroup(this.title, this.tools);
}

const List<_ToolGroup> _toolGroups = [
  _ToolGroup('Get work in', [
    _Tool(Icons.table_chart_rounded, 'Import a Google Form', AppRoutes.importResponses),
    _Tool(Icons.content_cut_rounded, 'Split a scanned stack', AppRoutes.splitStack),
    _Tool(Icons.qr_code_2_rounded, 'Prepare a test to print', AppRoutes.prepareTest),
  ]),
  _ToolGroup('Write with Mark', [
    _Tool(Icons.event_note_rounded, 'Plan with Mark', AppRoutes.planning),
    _Tool(Icons.rate_review_rounded, 'Report card comments', AppRoutes.reportComments),
  ]),
  _ToolGroup('Marks out', [
    _Tool(Icons.ios_share_rounded, 'Export marks', AppRoutes.exportMarks),
    _Tool(Icons.help_outline_rounded, 'Four ways to mark', AppRoutes.waysToMark),
  ]),
];

/// The app's main shell.
///
/// Same five destinations, same routes, same branch state — the only thing
/// that changes with the window is where the teacher's thumb or mouse finds
/// them. On a phone that is a bottom tab bar. On a laptop or a desktop
/// browser a bottom bar pinned to the foot of a 900px-tall window is a long
/// way from anything, so those get a sidebar down the left, which is where a
/// teacher already looks for navigation on the web — and it has room to show
/// every tool, not just the five tabs.
class BottomNavShell extends StatelessWidget {
  final StatefulNavigationShell shell;
  const BottomNavShell({super.key, required this.shell});

  void _go(int i) => shell.goBranch(i, initialLocation: i == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Breakpoints.isExpanded(width) ? _wide(context) : _compact(context);
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

  /// The desktop layout: a blue sidebar that stays put while the teacher
  /// works, and the screen itself in the space that is left.
  Widget _wide(BuildContext context) {
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Sidebar(currentIndex: shell.currentIndex, onDestination: _go),
          Expanded(child: shell),
        ],
      ),
    );
  }
}

/// The desktop sidebar: one blue card holding everything the app can do.
class _Sidebar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onDestination;
  const _Sidebar({required this.currentIndex, required this.onDestination});

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Inset so it reads as a panel sitting on the page rather than a wall
      // painted onto the window edge.
      padding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
      child: SizedBox(
        width: Breakpoints.sidebarWidth,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            // Deepening downwards, so the long list keeps some shape instead
            // of reading as one flat slab of blue.
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AiMarkerColors.primary, Color(0xFF1B4FD8)],
            ),
            boxShadow: [BoxShadow(color: AiMarkerColors.primary.withValues(alpha: 0.28), blurRadius: 22, offset: const Offset(0, 8))],
          ),
          child: SafeArea(
            right: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SidebarBrand(),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(10, 4, 10, 14),
                    children: [
                      for (var i = 0; i < _destinations.length; i++)
                        _SidebarItem(
                          icon: _destinations[i].icon,
                          label: _destinations[i].label,
                          selected: i == currentIndex,
                          onTap: () => onDestination(i),
                        ),
                      for (final group in _toolGroups) ...[
                        _SidebarHeading(group.title),
                        for (final t in group.tools)
                          _SidebarItem(
                            icon: t.icon,
                            label: t.label,
                            selected: false,
                            onTap: () => context.push(t.route),
                          ),
                      ],
                    ],
                  ),
                ),
                const _SidebarPlansButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarBrand extends StatelessWidget {
  const _SidebarBrand();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.sm)),
            child: const Icon(Icons.check_rounded, size: 20, color: AiMarkerColors.primary),
          ),
          const SizedBox(width: 10),
          const Text('Markless', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
        ],
      ),
    );
  }
}

class _SidebarHeading extends StatelessWidget {
  final String text;
  const _SidebarHeading(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SidebarItem({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // White pill for the tab you are on: on a blue field that reads as
    // "you are here" faster than a tint does.
    final fg = selected ? AiMarkerColors.primary : Colors.white.withValues(alpha: 0.92);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          hoverColor: Colors.white.withValues(alpha: 0.12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(icon, size: 19, color: fg),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: fg, fontSize: 14, fontWeight: selected ? FontWeight.w700 : FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pinned to the foot of the sidebar rather than buried in the list: what a
/// teacher's plan allows is the thing she looks for when marking stops.
class _SidebarPlansButton extends StatelessWidget {
  const _SidebarPlansButton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
      child: Material(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          onTap: () => context.push(AppRoutes.plans),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          hoverColor: Colors.white.withValues(alpha: 0.22),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(Icons.workspace_premium_rounded, size: 19, color: Colors.white),
                SizedBox(width: 12),
                Expanded(child: Text('Plans & credits', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
