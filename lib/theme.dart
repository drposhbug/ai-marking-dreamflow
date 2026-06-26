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
  static const primary = Color(0xFF2563EB);
  static const secondary = Color(0xFF16A34A);
  static const tertiary = Color(0xFF7C3AED);
  static const error = Color(0xFFDC2626);
  static const neutral = Color(0xFF6B7280);

  static const bg = Color(0xFFF4F7FB);
  static const card = Color(0xFFFFFFFF);
  static const outline = Color(0x1A6B7280); // 10%

  // Dark mode palette (per spec)
  static const darkBg = Color(0xFF0F172A);
  static const darkCard = Color(0xFF1E293B);
  static const darkOutline = Color(0xFF334155);
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
    onSurface: Color(0xFF0F172A),
    surfaceContainerHighest: AiMarkerColors.bg,
    onSurfaceVariant: AiMarkerColors.neutral,
    outline: Color(0x336B7280),
  ),
  brightness: Brightness.light,
  scaffoldBackgroundColor: AiMarkerColors.bg,
  appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0, centerTitle: true),
  cardTheme: CardThemeData(
    color: AiMarkerColors.card,
    elevation: 0,
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
  scaffoldBackgroundColor: AiMarkerColors.darkBg,
  appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0, centerTitle: true),
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
