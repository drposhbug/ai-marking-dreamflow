import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:marking_prokect_v2/services/auth_service.dart';
import 'package:marking_prokect_v2/services/billing_service.dart';
import 'package:marking_prokect_v2/widgets/bottom_nav_shell.dart';
import 'package:provider/provider.dart';

/// The desktop sidebar has to reach a screen reader.
///
/// Every page route carries a modal barrier, and a barrier blocks the
/// semantics of everything painted before it up to the nearest semantics
/// boundary. The sidebar is painted before the page, so until the page area
/// got its own boundary a screen reader heard the page and no navigation.
void main() {
  testWidgets('the sidebar and the page are both in the semantics tree', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final handle = tester.ensureSemantics();

    Widget page(String path) => Scaffold(body: Center(child: Text('Page $path')));
    final router = GoRouter(
      initialLocation: '/grading',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => BottomNavShell(shell: shell),
          branches: [
            for (final p in ['/grading', '/dashboard', '/classes', '/library', '/settings'])
              StatefulShellBranch(routes: [GoRoute(path: p, builder: (c, s) => page(p))]),
          ],
        ),
      ],
    );
    // The same app-wide services main.dart provides; a signed-out teacher,
    // so the sidebar's upgrade promo stays hidden.
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => BillingService(onWeb: false)),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Dashboard'), findsOneWidget);
    expect(find.bySemanticsLabel('Export marks'), findsOneWidget);
    expect(find.bySemanticsLabel('Plans & credits'), findsOneWidget);
    expect(find.bySemanticsLabel('Page /grading'), findsOneWidget);
    handle.dispose();
  });
}
