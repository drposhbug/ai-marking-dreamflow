/// A mark the way a teacher writes it: whole numbers plain, halves and
/// quarters as ½ ¼ ¾, anything else to two places at most.
///
/// Rounding to whole numbers is what made the dashboard show a 5.5 as "6/8"
/// and a 1.5 as "2/8" — the half and quarter marks the app promises, thrown
/// away at the last step, and a class average that no longer looked like
/// the marks listed above it.
String formatMark(double v) {
  if (v.isNaN || v.isInfinite) return '—';
  final negative = v < 0;
  final a = v.abs();
  final whole = a.truncate();
  final frac = ((a - whole) * 100).round();
  String out;
  if (frac == 0) {
    out = '$whole';
  } else if (frac == 100) {
    out = '${whole + 1}';
  } else {
    const glyph = {25: '¼', 50: '½', 75: '¾'};
    final g = glyph[frac];
    if (g != null) {
      out = whole == 0 ? g : '$whole$g';
    } else {
      out = a.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }
  }
  return negative ? '-$out' : out;
}
