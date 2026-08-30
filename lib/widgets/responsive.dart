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

  static AppLayout layoutFor(double width) => width >= expanded ? AppLayout.expanded : AppLayout.compact;

  /// True when the window earns the desktop presentation: side rail, centred
  /// content.
  static bool isExpanded(double width) => layoutFor(width) == AppLayout.expanded;

  /// True when the side rail should show text labels beside its icons.
  static bool railIsExtendedAt(double width) => width >= railExtended;

  /// The width content should actually take given the room it has.
  static double contentWidthFor(double available, {double maxWidth = maxContentWidth}) {
    if (!available.isFinite) return maxWidth;
    return available < maxWidth ? available : maxWidth;
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
class AppPageFrame extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const AppPageFrame({super.key, required this.child, this.maxWidth = Breakpoints.maxContentWidth});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        if (!available.isFinite || available <= maxWidth) return child;
        final mq = MediaQuery.of(context);
        return ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: MediaQuery(
            data: mq.copyWith(size: Size(maxWidth, mq.size.height)),
            child: MaxContentWidth(maxWidth: maxWidth, child: child),
          ),
        );
      },
    );
  }
}
