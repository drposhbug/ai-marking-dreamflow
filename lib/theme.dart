import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppSpacing {
  // Spacing values
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;

  // Edge insets shortcuts
  static const EdgeInsets paddingXs = EdgeInsets.all(xs);
  static const EdgeInsets paddingSm = EdgeInsets.all(sm);
  static const EdgeInsets paddingMd = EdgeInsets.all(md);
  static const EdgeInsets paddingLg = EdgeInsets.all(lg);
  static const EdgeInsets paddingXl = EdgeInsets.all(xl);

  // Horizontal padding
  static const EdgeInsets horizontalXs = EdgeInsets.symmetric(horizontal: xs);
  static const EdgeInsets horizontalSm = EdgeInsets.symmetric(horizontal: sm);
  static const EdgeInsets horizontalMd = EdgeInsets.symmetric(horizontal: md);
  static const EdgeInsets horizontalLg = EdgeInsets.symmetric(horizontal: lg);
  static const EdgeInsets horizontalXl = EdgeInsets.symmetric(horizontal: xl);

  // Vertical padding
  static const EdgeInsets verticalXs = EdgeInsets.symmetric(vertical: xs);
  static const EdgeInsets verticalSm = EdgeInsets.symmetric(vertical: sm);
  static const EdgeInsets verticalMd = EdgeInsets.symmetric(vertical: md);
  static const EdgeInsets verticalLg = EdgeInsets.symmetric(vertical: lg);
  static const EdgeInsets verticalXl = EdgeInsets.symmetric(vertical: xl);
}

/// Border radius constants for consistent rounded corners
class AppRadius {
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0; // cards
  static const double xl = 24.0; // primary buttons
}

// =============================================================================
// TEXT STYLE EXTENSIONS
// =============================================================================

/// Extension to add text style utilities to BuildContext
/// Access via context.textStyles
extension TextStyleContext on BuildContext {
  TextTheme get textStyles => Theme.of(this).textTheme;
}

/// Helper methods for common text style modifications
extension TextStyleExtensions on TextStyle {
  /// Make text bold
  TextStyle get bold => copyWith(fontWeight: FontWeight.bold);

  /// Make text semi-bold
  TextStyle get semiBold => copyWith(fontWeight: FontWeight.w600);

  /// Make text medium weight
  TextStyle get medium => copyWith(fontWeight: FontWeight.w500);

  /// Make text normal weight
  TextStyle get normal => copyWith(fontWeight: FontWeight.w400);

  /// Make text light
  TextStyle get light => copyWith(fontWeight: FontWeight.w300);

  /// Add custom color
  TextStyle withColor(Color color) => copyWith(color: color);

  /// Add custom size
  TextStyle withSize(double size) => copyWith(fontSize: size);
}

// =============================================================================
// COLORS
// =============================================================================

/// AI Marker design system colors
class AiMarkerColors {
  // ---------------------------------------------------------------------
  // Chrome
  //
  // In a marking tool colour is information: red is a deduction, green is a
  // mark earned. So the furniture around the work is deliberately almost
  // colourless — chalkboard, paper, warm ink — and the only saturated
  // things on a screen are the marks themselves.
  //
  // This replaced a blue/violet scheme that was louder than the marking it
  // framed: a gradient banner meaning nothing outranked the red pen beside
  // it. These tones are the marketing site's, which was already built from
  // the same idea.
  // ---------------------------------------------------------------------

  /// Chalkboard. Near-black with a green cast — a surface, never a "correct"
  /// signal, so it cannot be mistaken for [tickInk] at a glance.
  static const primary = Color(0xFF143528);

  /// The deep end of the board, for the one or two places that carry a
  /// gradient.
  static const boardDeep = Color(0xFF0E271E);

  /// A mark earned. Same green as the ticks on the page, so "good" means one
  /// colour across the whole product.
  static const secondary = Color(0xFF1D6A44);

  /// Pencil. The quiet accent that separates one group of tools from
  /// another without introducing a hue that competes with a mark. There is
  /// no free colour left: red is the pen, green is the tick, amber is
  /// [warning] — so this stays a warm ink rather than inventing one.
  static const tertiary = Color(0xFF4C4636);

  static const error = Color(0xFFDC2626);
  static const neutral = Color(0xFF7C7460);
  /// Amber: something needs a look but nothing is broken — a stack whose
  /// page count does not add up, a result flagged for teacher review.
  static const warning = Color(0xFFD97706);

  /// The desk. Warm, so a sheet laid on it reads as paper rather than as a
  /// panel in an application.
  static const bg = Color(0xFFF6F1E3);

  /// A sheet on the desk. Warm white, not clinical white.
  static const card = Color(0xFFFFFDF7);
  static const outline = Color(0x1A211E15); // 10%

  // Dark mode: the same desk at night. Warm blacks rather than the navy
  // that came with the blue scheme — a cool dark under a red pen mark makes
  // the mark look purple.
  static const darkBg = Color(0xFF14120E);
  static const darkCard = Color(0xFF211E15);
  static const darkOutline = Color(0xFF3A3529);

  // ---------------------------------------------------------------------
  // Marked paper
  //
  // The marketing site is a sheet of marked paper on a desk. A teacher who
  // arrives from it should feel she is still on the same sheet, so the app
  // keeps the same tones. Read these through [PaperTones] rather than
  // reaching for the light or dark one directly.
  // ---------------------------------------------------------------------

  /// The sheet itself: warm, a shade off white, so it reads as paper next
  /// to the plain white of a text field.
  static const paper = Color(0xFFFDFAF1);

  /// A second, duller sheet — what sits *on* the page, like a scanned
  /// answer or a field the teacher types into.
  static const paperShade = Color(0xFFF2ECDC);

  /// The faint printed rules between questions on a page.
  static const paperRule = Color(0xFFDCD3BB);

  /// Biro red. This is annotation — a margin rule, a teacher's note, a mark
  /// she took off. It never means "something broke"; that is [error].
  static const pen = Color(0xFFC1272D);

  /// The pencil grey of a student's handwriting in an illustration.
  static const graphite = Color(0xFFC4BCA8);

  /// A full mark written in green — darker than [secondary] so a small
  /// number stays readable on paper.
  static const tickInk = Color(0xFF10703A);

  static const darkPaper = Color(0xFF211E15);
  static const darkPaperShade = Color(0xFF191710);
  static const darkPaperRule = Color(0xFF3A3529);
  static const darkPen = Color(0xFFFF8078);
  static const darkGraphite = Color(0xFF4A4436);
  static const darkTickInk = Color(0xFF6EE79A);
}

/// The paper tones for whichever theme is in play.
///
/// A screen asks once and gets the right sheet, so marking at 11pm in dark
/// mode does not glare like a photocopy.
class PaperTones {
  /// The sheet.
  final Color paper;

  /// What sits on the sheet: fields, panels, an illustration.
  final Color shade;

  /// Hairlines printed on the sheet.
  final Color rule;

  /// Biro red, for the margin rule and the teacher's notes.
  final Color pen;

  /// Stylised handwriting.
  final Color graphite;

  /// A mark that lost nothing.
  final Color tick;

  const PaperTones({
    required this.paper,
    required this.shade,
    required this.rule,
    required this.pen,
    required this.graphite,
    required this.tick,
  });

  static const light = PaperTones(
    paper: AiMarkerColors.paper,
    shade: AiMarkerColors.paperShade,
    rule: AiMarkerColors.paperRule,
    pen: AiMarkerColors.pen,
    graphite: AiMarkerColors.graphite,
    tick: AiMarkerColors.tickInk,
  );

  static const dark = PaperTones(
    paper: AiMarkerColors.darkPaper,
    shade: AiMarkerColors.darkPaperShade,
    rule: AiMarkerColors.darkPaperRule,
    pen: AiMarkerColors.darkPen,
    graphite: AiMarkerColors.darkGraphite,
    tick: AiMarkerColors.darkTickInk,
  );

  static PaperTones of(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// Font size constants
class FontSizes {
  static const double displayLarge = 57.0;
  static const double displayMedium = 45.0;
  static const double displaySmall = 36.0;
  static const double headlineLarge = 32.0;
  static const double headlineMedium = 28.0;
  static const double headlineSmall = 24.0;
  static const double titleLarge = 22.0;
  static const double titleMedium = 16.0;
  static const double titleSmall = 14.0;
  static const double labelLarge = 14.0;
  static const double labelMedium = 12.0;
  static const double labelSmall = 11.0;
  static const double bodyLarge = 16.0;
  static const double bodyMedium = 14.0;
  static const double bodySmall = 12.0;
}

// =============================================================================
// THEMES
// =============================================================================

/// Light theme with modern, neutral aesthetic
ThemeData get lightTheme => ThemeData(
  useMaterial3: true,
  splashFactory: NoSplash.splashFactory,
  colorScheme: const ColorScheme.light(
    primary: AiMarkerColors.primary,
    onPrimary: Colors.white,
    secondary: AiMarkerColors.secondary,
    onSecondary: Colors.white,
    tertiary: AiMarkerColors.tertiary,
    onTertiary: Colors.white,
    error: AiMarkerColors.error,
    onError: Colors.white,
    surface: AiMarkerColors.card,
    onSurface: Color(0xFF211E15),
    surfaceContainerHighest: AiMarkerColors.bg,
    onSurfaceVariant: AiMarkerColors.neutral,
    outline: Color(0x33211E15),
  ),
  brightness: Brightness.light,
  // Material 3 draws a progress bar's track in secondaryContainer, which
  // ColorScheme.light/.dark fill with [secondary] — the same green as the
  // bar. Every track read as full: the Plans screen said "0% used" over a
  // solid green bar.
  progressIndicatorTheme: ProgressIndicatorThemeData(color: AiMarkerColors.primary, linearTrackColor: const Color(0x1F211E15)),
  // Transparent so [DeskBackground] shows through on every route.
  scaffoldBackgroundColor: Colors.transparent,
  appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0, centerTitle: true),
  // A sheet spanning a 1440px monitor is a phone habit. The cap is wider than
  // any phone, so phones see no change.
  bottomSheetTheme: const BottomSheetThemeData(constraints: BoxConstraints(maxWidth: 640)),
  // A sheet lying on a desk, not a panel flush with it. At elevation 0 with a
  // 10% hairline these were three per cent lighter than the background and
  // read as one flat field — the whole screen at a single value, which is
  // what makes a layout look bland however good the colours are. The lift is
  // small and the shadow is warm: a cool shadow on cream looks like dirt.
  cardTheme: CardThemeData(
    color: AiMarkerColors.card,
    elevation: 3,
    shadowColor: const Color(0x14211E15),
    // Material 3 tints a raised surface toward the primary colour. Here that
    // would wash every card green with height.
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg), side: const BorderSide(color: AiMarkerColors.outline, width: 1)),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: const BorderSide(color: AiMarkerColors.outline)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: const BorderSide(color: AiMarkerColors.outline)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: const BorderSide(color: AiMarkerColors.primary, width: 1.5)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      side: const BorderSide(color: AiMarkerColors.outline),
      textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
    ),
  ),
  textTheme: _buildTextTheme(),
);

/// Dark theme with good contrast and readability
ThemeData get darkTheme => ThemeData(
  useMaterial3: true,
  splashFactory: NoSplash.splashFactory,
  colorScheme: const ColorScheme.dark(
    primary: AiMarkerColors.primary,
    onPrimary: Colors.white,
    secondary: AiMarkerColors.secondary,
    onSecondary: Colors.white,
    tertiary: AiMarkerColors.tertiary,
    onTertiary: Colors.white,
    error: AiMarkerColors.error,
    onError: Colors.white,
    surface: AiMarkerColors.darkCard,
    onSurface: Colors.white,
    surfaceContainerHighest: AiMarkerColors.darkBg,
    onSurfaceVariant: Color(0xFFC7D2FE),
    outline: AiMarkerColors.darkOutline,
  ),
  brightness: Brightness.dark,
  // Material 3 draws a progress bar's track in secondaryContainer, which
  // ColorScheme.light/.dark fill with [secondary] — the same green as the
  // bar. Every track read as full: the Plans screen said "0% used" over a
  // solid green bar.
  progressIndicatorTheme: ProgressIndicatorThemeData(color: AiMarkerColors.primary, linearTrackColor: Colors.white.withValues(alpha: 0.14)),
  scaffoldBackgroundColor: Colors.transparent,
  appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0, centerTitle: true),
  // A sheet spanning a 1440px monitor is a phone habit. The cap is wider than
  // any phone, so phones see no change.
  bottomSheetTheme: const BottomSheetThemeData(constraints: BoxConstraints(maxWidth: 640)),
  cardTheme: CardThemeData(
    color: AiMarkerColors.darkCard,
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg), side: const BorderSide(color: AiMarkerColors.darkOutline, width: 1)),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AiMarkerColors.darkCard,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: const BorderSide(color: AiMarkerColors.darkOutline)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: const BorderSide(color: AiMarkerColors.darkOutline)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: const BorderSide(color: AiMarkerColors.primary, width: 1.5)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      side: const BorderSide(color: AiMarkerColors.darkOutline),
      textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
    ),
  ),
  textTheme: _buildTextTheme(),
);

TextTheme _buildTextTheme() => TextTheme(
  headlineLarge: GoogleFonts.poppins(fontSize: FontSizes.headlineLarge, fontWeight: FontWeight.w700, height: 1.15),
  headlineMedium: GoogleFonts.poppins(fontSize: FontSizes.headlineMedium, fontWeight: FontWeight.w700, height: 1.15),
  headlineSmall: GoogleFonts.poppins(fontSize: FontSizes.headlineSmall, fontWeight: FontWeight.w700, height: 1.15),
  titleLarge: GoogleFonts.poppins(fontSize: FontSizes.titleLarge, fontWeight: FontWeight.w700, height: 1.2),
  titleMedium: GoogleFonts.inter(fontSize: FontSizes.titleMedium, fontWeight: FontWeight.w600, height: 1.3),
  titleSmall: GoogleFonts.inter(fontSize: FontSizes.titleSmall, fontWeight: FontWeight.w600, height: 1.3),
  bodyLarge: GoogleFonts.inter(fontSize: FontSizes.bodyLarge, fontWeight: FontWeight.w400, height: 1.5),
  bodyMedium: GoogleFonts.inter(fontSize: FontSizes.bodyMedium, fontWeight: FontWeight.w400, height: 1.5),
  bodySmall: GoogleFonts.inter(fontSize: FontSizes.bodySmall, fontWeight: FontWeight.w400, height: 1.5),
  labelLarge: GoogleFonts.inter(fontSize: FontSizes.labelLarge, fontWeight: FontWeight.w600, height: 1.2),
  labelMedium: GoogleFonts.inter(fontSize: FontSizes.labelMedium, fontWeight: FontWeight.w600, height: 1.2),
  labelSmall: GoogleFonts.inter(fontSize: FontSizes.labelSmall, fontWeight: FontWeight.w600, height: 1.2),
);

// =============================================================================
// THE DESK
// =============================================================================

/// The surface every screen sits on.
///
/// A single flat fill behind everything is the other half of what makes a
/// layout look bland: with the cards at one value and the ground at another,
/// there are exactly two depths on screen and nothing suggests a room. This
/// is light falling across a desk from the top left — a few per cent of
/// warmth, closer to a photograph's falloff than to a gradient anyone would
/// name as one.
///
/// Applied once in [MaterialApp.builder] so it is behind every route
/// including dialogs, with the scaffolds left transparent on top of it.
class DeskBackground extends StatelessWidget {
  final Widget child;

  const DeskBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          // Off the top-left corner, so the brightest point sits outside the
          // frame and the falloff across the page is even rather than a
          // visible blob in a corner.
          center: const Alignment(-0.8, -1.1),
          radius: 1.9,
          // Three stops, not two. A two-stop wash across a 27" screen is so
          // gradual that it reads as a flat fill; the middle stop puts the
          // falloff where the eye actually is rather than spending it all in
          // the far corner.
          stops: const [0.0, 0.55, 1.0],
          colors: dark
              ? const [Color(0xFF221E17), Color(0xFF17140F), Color(0xFF100E09)]
              : const [Color(0xFFFFFDF5), Color(0xFFF7F1DF), Color(0xFFEDE5CE)],
        ),
      ),
      child: child,
    );
  }
}
