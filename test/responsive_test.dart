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

  group('Breakpoints.isLargeDesktopAt', () {
    test('a laptop is not a desk monitor', () {
      expect(Breakpoints.isLargeDesktopAt(1024), isFalse);
      expect(Breakpoints.isLargeDesktopAt(1440), isFalse);
      expect(Breakpoints.isLargeDesktopAt(1599), isFalse);
    });

    test('a 27 inch monitor is', () {
      expect(Breakpoints.isLargeDesktopAt(1600), isTrue);
      expect(Breakpoints.isLargeDesktopAt(2557), isTrue);
    });
  });

  group('Breakpoints.wideContentWidthFor', () {
    test('a phone still uses every pixel it has', () {
      expect(Breakpoints.wideContentWidthFor(390), 390);
      expect(Breakpoints.wideContentWidthFor(844), 844);
    });

    test('a laptop keeps the reading measure it has today', () {
      expect(Breakpoints.wideContentWidthFor(1280), Breakpoints.maxContentWidth);
      expect(Breakpoints.wideContentWidthFor(1440), Breakpoints.maxContentWidth);
    });

    test('a desk monitor grows past it rather than sitting in the middle', () {
      expect(Breakpoints.wideContentWidthFor(1700), greaterThan(Breakpoints.maxContentWidth));
      expect(Breakpoints.wideContentWidthFor(1920), closeTo(1190.4, 0.1));
    });

    test('it grows smoothly, never in a jump', () {
      final a = Breakpoints.wideContentWidthFor(1800);
      final b = Breakpoints.wideContentWidthFor(1810);
      expect(b - a, lessThan(12));
      expect(b, greaterThan(a));
    });

    test('and stops before a card gets silly', () {
      expect(Breakpoints.wideContentWidthFor(2557), Breakpoints.maxWideContentWidth);
      expect(Breakpoints.wideContentWidthFor(3840), Breakpoints.maxWideContentWidth);
      expect(Breakpoints.wideContentWidthFor(double.infinity), Breakpoints.maxWideContentWidth);
    });
  });

  group('Breakpoints.splashWidthFor', () {
    test('a phone is untouched', () {
      expect(Breakpoints.splashWidthFor(390), 390);
    });

    test('a small laptop window looks exactly as it does today', () {
      expect(Breakpoints.splashWidthFor(1024), Breakpoints.maxContentWidth);
      expect(Breakpoints.splashWidthFor(1280), Breakpoints.maxContentWidth);
    });

    test('sign-in fills more of a big window than the rest of the app does', () {
      expect(Breakpoints.splashWidthFor(1920), greaterThan(Breakpoints.wideContentWidthFor(1920)));
      expect(Breakpoints.splashWidthFor(1920), closeTo(1420.8, 0.1));
    });

    test("the owner's own monitor gets the full sheet", () {
      expect(Breakpoints.splashWidthFor(2557), Breakpoints.maxSplashWidth);
      expect(Breakpoints.splashWidthFor(2560), Breakpoints.maxSplashWidth);
      // Over half the monitor, which is the whole point of the change.
      expect(Breakpoints.splashWidthFor(2557) / 2557, greaterThan(0.55));
    });
  });

  group('Breakpoints.cardColumnsFor', () {
    test('a phone never splits a run of cards in two', () {
      expect(Breakpoints.cardColumnsFor(390), 1);
      expect(Breakpoints.cardColumnsFor(844), 1);
    });

    test('nor does the 960 reading measure', () {
      expect(Breakpoints.cardColumnsFor(928), 1);
    });

    test('a desk monitor does', () {
      expect(Breakpoints.cardColumnsFor(1408), 2);
      expect(Breakpoints.cardColumnsFor(Breakpoints.maxWideContentWidth), 2);
    });

    test('a caller asking for wider cards gets fewer columns', () {
      expect(Breakpoints.cardColumnsFor(1100, minColumn: 700), 1);
    });
  });

  group('Breakpoints.sheetGrowthFor', () {
    test('a sheet the size of the old 960px column has grown by nothing', () {
      expect(Breakpoints.sheetGrowthFor(390), 0);
      expect(Breakpoints.sheetGrowthFor(912), 0);
    });

    test('a sheet on a 27 inch monitor has grown all the way', () {
      expect(Breakpoints.sheetGrowthFor(1512), 1);
      expect(Breakpoints.sheetGrowthFor(2000), 1);
      expect(Breakpoints.sheetGrowthFor(double.infinity), 1);
    });

    test('and everything between grows smoothly, never in a step', () {
      expect(Breakpoints.sheetGrowthFor(1212), closeTo(0.5, 0.001));
      final a = Breakpoints.sheetGrowthFor(1200);
      final b = Breakpoints.sheetGrowthFor(1210);
      expect(b, greaterThan(a));
      expect(b - a, lessThan(0.02));
    });

    test('the display face runs from what it is today to a hero size', () {
      final laptop = Breakpoints.grown(27, 46, Breakpoints.sheetGrowthFor(912));
      final monitor = Breakpoints.grown(27, 46, Breakpoints.sheetGrowthFor(1512));
      // A phone and a small laptop window are left exactly as they were.
      expect(laptop, 27);
      expect(monitor, 46);
      expect(Breakpoints.grown(27, 46, Breakpoints.sheetGrowthFor(1212)), closeTo(36.5, 0.1));
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

    testWidgets('a splash screen grows with the monitor instead of stopping at 960', (tester) async {
      tester.view.physicalSize = const Size(2560, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: Size(2560, 1400)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: AppPageFrame(
            widthFor: Breakpoints.splashWidthFor,
            child: const SizedBox.expand(key: ValueKey('screen')),
          ),
        ),
      ));

      final rect = tester.getRect(find.byKey(const ValueKey('screen')));
      expect(rect.width, Breakpoints.maxSplashWidth);
      expect(rect.center.dx, 1280);
    });

    testWidgets('a splash screen on a phone is still handed straight back', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MediaQuery(
        data: MediaQueryData(size: Size(390, 844)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: AppPageFrame(
            widthFor: Breakpoints.splashWidthFor,
            child: SizedBox.expand(key: ValueKey('screen')),
          ),
        ),
      ));

      expect(tester.getSize(find.byKey(const ValueKey('screen'))).width, 390);
      expect(find.byType(MaxContentWidth), findsNothing);
    });
  });

  group('CardColumns', () {
    Widget harness(double width) => Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: CardColumns(
            children: [
              for (var i = 0; i < 4; i++) SizedBox(height: 60, key: ValueKey('card$i')),
            ],
          ),
        ),
      ),
    );

    testWidgets('a phone keeps one card per row, full width', (tester) async {
      await tester.pumpWidget(harness(358));
      expect(tester.getSize(find.byKey(const ValueKey('card0'))).width, 358);
      expect(tester.getRect(find.byKey(const ValueKey('card1'))).left, 0);
    });

    testWidgets('a desk monitor puts two side by side, in order', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(harness(1408));
      final first = tester.getRect(find.byKey(const ValueKey('card0')));
      final second = tester.getRect(find.byKey(const ValueKey('card1')));
      final third = tester.getRect(find.byKey(const ValueKey('card2')));
      expect(first.width, 698);
      expect(second.left, greaterThan(first.right));
      expect(second.top, first.top);
      expect(third.left, first.left);
      expect(third.top, greaterThan(first.bottom));
    });
  });

  group('DeskColumns', () {
    Widget harness(double width) => Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: DeskColumns(
            start: const [SizedBox(height: 60, key: ValueKey('a'))],
            rest: const [SizedBox(height: 60, key: ValueKey('b'))],
            stacked: const [
              SizedBox(height: 60, key: ValueKey('b')),
              SizedBox(height: 60, key: ValueKey('a')),
            ],
          ),
        ),
      ),
    );

    testWidgets("a phone gets the phone's own running order", (tester) async {
      await tester.pumpWidget(harness(358));
      expect(tester.getRect(find.byKey(const ValueKey('b'))).top, 0);
      expect(tester.getRect(find.byKey(const ValueKey('a'))).top, 60);
    });

    testWidgets('a desk monitor puts the two columns beside each other', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(harness(1408));
      final a = tester.getRect(find.byKey(const ValueKey('a')));
      final b = tester.getRect(find.byKey(const ValueKey('b')));
      expect(a.left, 0);
      expect(b.left, greaterThan(a.right));
      expect(a.top, b.top);
    });
  });
}
