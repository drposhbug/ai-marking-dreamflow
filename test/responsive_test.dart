import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marking_prokect_v2/widgets/responsive.dart';

void main() {
  group('Breakpoints.layoutFor', () {
    test('a phone stays on the phone layout', () {
      expect(Breakpoints.layoutFor(320), AppLayout.compact);
      expect(Breakpoints.layoutFor(390), AppLayout.compact);
      expect(Breakpoints.layoutFor(430), AppLayout.compact);
    });

    test('a tablet in portrait stays on the phone layout', () {
      expect(Breakpoints.layoutFor(768), AppLayout.compact);
      expect(Breakpoints.layoutFor(839.9), AppLayout.compact);
    });

    test('a laptop or desktop browser gets the wide layout', () {
      expect(Breakpoints.layoutFor(840), AppLayout.expanded);
      expect(Breakpoints.layoutFor(1024), AppLayout.expanded);
      expect(Breakpoints.layoutFor(1440), AppLayout.expanded);
    });

    test('isExpanded agrees with layoutFor', () {
      expect(Breakpoints.isExpanded(389), isFalse);
      expect(Breakpoints.isExpanded(1440), isTrue);
    });
  });

  group('Breakpoints.railIsExtendedAt', () {
    test('a small laptop keeps the icon-only rail', () {
      expect(Breakpoints.railIsExtendedAt(1024), isFalse);
      expect(Breakpoints.railIsExtendedAt(1239), isFalse);
    });

    test('a big monitor shows the labels', () {
      expect(Breakpoints.railIsExtendedAt(1240), isTrue);
      expect(Breakpoints.railIsExtendedAt(1920), isTrue);
    });
  });

  group('Breakpoints.contentWidthFor', () {
    test('narrow windows use every pixel they have', () {
      expect(Breakpoints.contentWidthFor(390), 390);
      expect(Breakpoints.contentWidthFor(800), 800);
    });

    test('wide windows stop at the readable measure', () {
      expect(Breakpoints.contentWidthFor(1440), Breakpoints.maxContentWidth);
      expect(Breakpoints.contentWidthFor(3840), Breakpoints.maxContentWidth);
    });

    test('an unbounded parent falls back to the measure instead of infinity', () {
      expect(Breakpoints.contentWidthFor(double.infinity), Breakpoints.maxContentWidth);
    });

    test('a caller can ask for a narrower measure', () {
      expect(Breakpoints.contentWidthFor(1440, maxWidth: 600), 600);
    });
  });

  group('AppPageFrame', () {
    Widget harness(Size size) => MediaQuery(
      data: MediaQueryData(size: size),
      child: const Directionality(
        textDirection: TextDirection.ltr,
        child: AppPageFrame(child: SizedBox.expand(key: ValueKey('screen'))),
      ),
    );

    testWidgets('leaves a phone screen exactly as it was', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(harness(const Size(390, 844)));

      expect(tester.getSize(find.byKey(const ValueKey('screen'))).width, 390);
      // No wrapper at all on a phone, so nothing can shift.
      expect(find.byType(MaxContentWidth), findsNothing);
    });

    testWidgets('centres and caps the screen on a desktop window', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(harness(const Size(1440, 900)));

      final rect = tester.getRect(find.byKey(const ValueKey('screen')));
      expect(rect.width, Breakpoints.maxContentWidth);
      expect(rect.center.dx, 720);
    });

    testWidgets('tells the screen the column width, not the monitor width', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      double? seenWidth;
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: Size(1440, 900)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: AppPageFrame(
            child: Builder(builder: (context) {
              seenWidth = MediaQuery.of(context).size.width;
              return const SizedBox.expand();
            }),
          ),
        ),
      ));

      expect(seenWidth, Breakpoints.maxContentWidth);
    });
  });
}
