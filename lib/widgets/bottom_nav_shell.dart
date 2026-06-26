import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:marking_prokect_v2/theme.dart';

class BottomNavShell extends StatelessWidget {
  final StatefulNavigationShell shell;
  const BottomNavShell({super.key, required this.shell});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: shell,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(color: Theme.of(context).cardColor, border: Border(top: BorderSide(color: cs.outline.withValues(alpha: 0.35), width: 1))),
        padding: const EdgeInsets.only(top: 6),
        child: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.edit_document, color: AiMarkerColors.neutral), selectedIcon: Icon(Icons.edit_document), label: 'Grading'),
            NavigationDestination(icon: Icon(Icons.grid_view_rounded, color: AiMarkerColors.neutral), selectedIcon: Icon(Icons.grid_view_rounded), label: 'Dashboard'),
            NavigationDestination(icon: Icon(Icons.groups_2_rounded, color: AiMarkerColors.neutral), selectedIcon: Icon(Icons.groups_2_rounded), label: 'Classes'),
            NavigationDestination(icon: Icon(Icons.library_books_rounded, color: AiMarkerColors.neutral), selectedIcon: Icon(Icons.library_books_rounded), label: 'Schemes'),
            NavigationDestination(icon: Icon(Icons.settings_rounded, color: AiMarkerColors.neutral), selectedIcon: Icon(Icons.settings_rounded), label: 'Settings'),
          ],
        ),
      ),
    );
  }
}
