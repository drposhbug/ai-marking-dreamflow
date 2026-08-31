import 'package:flutter/material.dart';

/// The shape the app takes for the window it is in.
///
/// Only two, on purpose. A teacher is either on a phone (or a browser window
/// no wider than a phone) or at a desk on a laptop or monitor. Everything in
/// between reads as one of those two, and two layouts is two things to keep
/// working rather than five.
enum AppLayout { compact, expanded }

/// The single place the app decides what "a wide window" means.
///
/// Every one of these is a pure number so it can be tested, and so a new
/// screen never has to guess its own breakpoint.
class Breakpoints {
  Breakpoints._();

  /// Below this the teacher gets the phone layout, bottom tab bar and all.
  ///
  /// 840 is Material's "expanded" window class, and it is also the first
  /// width where a navigation rail (80) plus a comfortable column of content
  /// plus real margins all fit without squeezing anything. A phone held
  /// sideways lands above it, which is what we want: a bottom bar eats the
  /// little height a landscape phone has, a rail costs none of it.
  static const double expanded = 840;

  /// How wide a screen's content is ever allowed to get.
  ///
  /// The app's screens are a single column of cards and form fields. Let that
  /// column run the full width of a 27" monitor and a teacher reads headings
  /// at one end of the desk and their value at the other, and every text field
  /// becomes a 1200px slot for a six-character class name. 960 keeps a line of
  /// body text near 90 characters, which is a normal document measure, and
  /// leaves room for two cards side by side if a screen ever wants that.
  static const double maxContentWidth = 960;

  /// Above this the rail has room to show its labels beside the icons instead
  /// of underneath them, which is what a teacher expects of a desktop app on
  /// a big monitor.
  static const double railExtended = 1240;

  /// The desk a teacher marks at, not the laptop she carries to school.
  ///
  /// 1600 is where a 27" monitor with a maximised browser lands. Below it a
  /// window is a laptop and one column of cards fills it honestly. At and
  /// above it a 960px column leaves two hands' width of empty desk on either
  /// side, which reads as a screen nobody sized rather than a calm one.
  static const double largeDesktop = 1600;

  /// How wide a screen made of cards rather than sentences may get.
  ///
  /// [maxContentWidth] is a measure for prose and prose should keep it. A run
  /// of cards is not prose: at 1440 two of them sit side by side at about 700
  /// each, which is a comfortable card with short lines inside it. Past 1440
  /// the extra room goes to the desk, not to the cards.
  static const double maxWideContentWidth = 1440;

  /// How wide the sign-in sheet may get.
  ///
  /// Login is one illustration beside one short form, so it has none of the
  /// reasons the rest of the app has to stay narrow, and it is the first
  /// thing a teacher ever sees. 1560 fills about three fifths of a 2560
  /// monitor: a sheet laid on a desk rather than a card adrift on one.
  static const double maxSplashWidth = 1560;

  /// The narrowest a card may be once a screen splits into two columns.
  ///
  /// Under this a card's title and its one line of explanation stop being a
  /// title and a line and become a paragraph, and a taller page is better
  /// than that.
  static const double minCardColumn = 470;

  static AppLayout layoutFor(double width) => width >= expanded ? AppLayout.expanded : AppLayout.compact;

  /// True when the window earns the desktop presentation: side rail, centred
  /// content.
  static bool isExpanded(double width) => layoutFor(width) == AppLayout.expanded;

  /// True when the side rail should show text labels beside its icons.
  static bool railIsExtendedAt(double width) => width >= railExtended;

  /// True when the window is a desk monitor rather than a laptop screen.
  static bool isLargeDesktopAt(double width) => width >= largeDesktop;

  /// The width content should actually take given the room it has.
  static double contentWidthFor(double available, {double maxWidth = maxContentWidth}) {
    if (!available.isFinite) return maxWidth;
    return available < maxWidth ? available : maxWidth;
  }

  /// The width a screen made of cards should take.
  ///
  /// It holds the reading measure until the window has clearly outgrown it,
  /// then grows *with* the window rather than jumping, so dragging a browser
  /// wider never snaps the page to a new size in front of the teacher.
  static double wideContentWidthFor(double available, {double maxWidth = maxWideContentWidth}) {
    if (!available.isFinite) return maxWidth;
    if (available <= maxContentWidth) return available;
    final grown = available * 0.62;
    if (grown <= maxContentWidth) return maxContentWidth;
    return grown >= maxWidth ? maxWidth : grown;
  }

  /// The width the sign-in sheet should take: the same fluid growth with a
  /// higher ceiling, because nothing on that screen is a long line of text.
  static double splashWidthFor(double available, {double maxWidth = maxSplashWidth}) {
    if (!available.isFinite) return maxWidth;
    if (available <= maxContentWidth) return available;
    final grown = available * 0.74;
    if (grown <= maxContentWidth) return maxContentWidth;
    return grown >= maxWidth ? maxWidth : grown;
  }

  /// How much bigger a sign-in sheet is than the one that fitted the old
  /// 960px column: 0 at that column, 1 on the owner's 27" monitor.
  ///
  /// The splash screen writes every measurement it has -- the display face,
  /// the drawn page, the air around the form -- in terms of this one number,
  /// the way the marketing site runs its whole type ramp off one clamped root
  /// size. Without it a wider sheet is only a bigger empty sheet.
  static double sheetGrowthFor(double sheetWidth) {
    const from = 912.0; // the sheet inside the old 960px column
    const to = 1512.0; // the sheet on a 2557px monitor
    if (!sheetWidth.isFinite) return 1;
    if (sheetWidth <= from) return 0;
    if (sheetWidth >= to) return 1;
    return (sheetWidth - from) / (to - from);
  }

  /// A measurement partway between what it is on a laptop and what it becomes
  /// on a monitor, given [grow] from [sheetGrowthFor].
  static double grown(double small, double large, double grow) => small + (large - small) * grow;

  /// How many columns a run of cards should sit in, given the room it has.
  static int cardColumnsFor(double available, {double spacing = 12, double minColumn = minCardColumn}) {
    if (!available.isFinite) return 1;
    return available >= minColumn * 2 + spacing ? 2 : 1;
  }
}

/// Holds [child] to a readable width and centres it.
///
/// Use this inside a screen when only part of it should be constrained. Whole
/// routed screens already get it for free from [AppPageFrame].
class MaxContentWidth extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const MaxContentWidth({super.key, required this.child, this.maxWidth = Breakpoints.maxContentWidth});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
    );
  }
}

/// The frame every routed screen goes through.
///
/// On a phone it is nothing at all — the screen is handed straight back, so
/// the phone layout is byte-for-byte what it always was. On a wide browser
/// window it centres the screen in a column of at most [maxWidth] and paints
/// the page colour out to the edges, so the app stops looking like a phone
/// that has been stretched.
///
/// It also tells the screen inside it that the window is [maxWidth] wide.
/// Screens that size something off `MediaQuery.size.width` are then sizing
/// against the column they are actually in, not the monitor.
/// [widthFor] is for the screens that should not stop at a fixed measure —
/// login grows with the monitor rather than sitting at 960 in the middle of
/// it. Leave it out and the frame behaves exactly as it always has.
class AppPageFrame extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final double Function(double available)? widthFor;

  const AppPageFrame({super.key, required this.child, this.maxWidth = Breakpoints.maxContentWidth, this.widthFor});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final width = (widthFor == null || !available.isFinite) ? maxWidth : widthFor!(available);
        if (!available.isFinite || available <= width) return child;
        final mq = MediaQuery.of(context);
        return ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: MediaQuery(
            data: mq.copyWith(size: Size(width, mq.size.height)),
            child: MaxContentWidth(maxWidth: width, child: child),
          ),
        );
      },
    );
  }
}

/// A run of cards that stands in one column on a phone or a laptop and steps
/// into two once the desk is wide enough that one column would leave half of
/// it empty.
///
/// The cards keep their order left to right, top to bottom, so a teacher who
/// learned the order on her phone finds the same order on the monitor.
class CardColumns extends StatelessWidget {
  final List<Widget> children;
  final double spacing;
  final double minColumn;

  const CardColumns({
    super.key,
    required this.children,
    this.spacing = 12,
    this.minColumn = Breakpoints.minCardColumn,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = Breakpoints.cardColumnsFor(constraints.maxWidth, spacing: spacing, minColumn: minColumn);
        if (columns < 2) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: spacing),
                children[i],
              ],
            ],
          );
        }
        final width = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [for (final child in children) SizedBox(width: width, child: child)],
        );
      },
    );
  }
}

/// Two named columns on a wide desk, one stacked column everywhere else.
///
/// [start] and [rest] are what goes on the left and the right of a monitor.
/// [stacked] is the order a phone shows, given separately because a phone's
/// running order is not simply one column after the other — the thing a
/// teacher scrolls to last on a phone is often the thing that sits beside
/// the first thing on a desk.
class DeskColumns extends StatelessWidget {
  final List<Widget> start;
  final List<Widget> rest;
  final List<Widget> stacked;
  final double spacing;
  final double minColumn;

  const DeskColumns({
    super.key,
    required this.start,
    required this.rest,
    required this.stacked,
    this.spacing = 16,
    this.minColumn = Breakpoints.minCardColumn,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = Breakpoints.cardColumnsFor(constraints.maxWidth, spacing: spacing, minColumn: minColumn);
        if (columns < 2) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: stacked);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: start)),
            SizedBox(width: spacing),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rest)),
          ],
        );
      },
    );
  }
}
