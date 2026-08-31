import 'package:flutter/material.dart';
import 'package:marking_prokect_v2/theme.dart';

/// The marked-paper language from the marketing site, in Flutter.
///
/// The site is one sheet of exercise-book paper: a red margin rule running
/// the height of the page, the teacher's notes hanging in that margin, and
/// marks written on the page rather than typed into it. A teacher who
/// clicks through from the site should land on the same sheet, so these are
/// the pieces of it the app can reuse. Everything here is drawn — nothing
/// needs downloading.

/// A sheet of paper.
///
/// [ruleAt] puts the red margin rule that many pixels in from the sheet's
/// left edge, running the full height of the sheet the way it does in an
/// exercise book — through the margins, not just beside the writing. Pass
/// null for a sheet with no rule.
///
/// [raised] is the sheet lying on a desk: a hairline, a hint of a corner,
/// and the shadow of a page. On a phone the sheet *is* the screen, so it
/// wants none of that.
class PaperSheet extends StatelessWidget {
  final Widget child;
  final double? ruleAt;
  final bool raised;
  final EdgeInsetsGeometry padding;

  const PaperSheet({
    super.key,
    required this.child,
    this.ruleAt,
    this.raised = false,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final tones = PaperTones.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tones.paper,
        borderRadius: raised ? BorderRadius.circular(3) : null,
        border: raised ? Border.all(color: tones.rule) : null,
        boxShadow: raised
            ? [
                BoxShadow(
                  color: dark ? Colors.black.withValues(alpha: 0.55) : const Color(0xFF101622).withValues(alpha: 0.18),
                  blurRadius: 48,
                  spreadRadius: -26,
                  offset: const Offset(0, 22),
                ),
              ]
            : null,
      ),
      child: Stack(
        children: [
          if (ruleAt != null)
            Positioned(
              left: ruleAt,
              top: 0,
              bottom: 0,
              width: 1,
              child: ColoredBox(color: tones.pen.withValues(alpha: 0.45)),
            ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

/// A note in the teacher's own hand: red, italic, serif.
///
/// On the site these hang in the margin beside the rule. [hangingInMargin]
/// right-aligns the note and hangs a short red dash under it, which is what
/// makes it read as written beside the page rather than printed on it.
class MarginNote extends StatelessWidget {
  final String text;
  final bool hangingInMargin;
  final double fontSize;

  const MarginNote(this.text, {super.key, this.hangingInMargin = false, this.fontSize = 13});

  @override
  Widget build(BuildContext context) {
    final tones = PaperTones.of(context);
    final note = Text(
      text,
      textAlign: hangingInMargin ? TextAlign.right : TextAlign.start,
      style: TextStyle(
        // Georgia where it exists, any serif where it does not. A note
        // written in the same face as the form would just look like more
        // form.
        fontFamily: 'Georgia',
        fontFamilyFallback: const ['Iowan Old Style', 'Times New Roman', 'serif'],
        fontStyle: FontStyle.italic,
        fontSize: fontSize,
        height: 1.4,
        color: tones.pen,
      ),
    );
    if (!hangingInMargin) return note;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        note,
        // The dash is written under the note, so it grows with it rather
        // than staying a 13px-note's dash under a 20px note.
        SizedBox(height: fontSize * 0.54),
        Container(width: fontSize * 1.38, height: 1, color: tones.pen.withValues(alpha: 0.5)),
      ],
    );
  }
}

/// The mark itself.
///
/// Marks are the numbers a teacher argues with, so they are set apart from
/// the prose around them: even-width figures, tight, sitting on the page
/// the way a mark is written rather than typed into a sentence.
TextStyle markStyle(BuildContext context, {required double size, required Color color, FontWeight weight = FontWeight.w700}) {
  final base = Theme.of(context).textTheme.titleMedium ?? const TextStyle();
  return base.copyWith(
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: 1.0,
    letterSpacing: -0.4,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

/// The app's mark: a sheet with a margin rule and a tick on it.
class MarklessMark extends StatelessWidget {
  final double size;

  const MarklessMark({super.key, this.size = 34});

  @override
  Widget build(BuildContext context) {
    final tones = PaperTones.of(context);
    return Container(
      width: size * 0.84,
      height: size,
      decoration: BoxDecoration(
        color: tones.shade,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: tones.rule),
      ),
      child: Stack(
        children: [
          Positioned(
            left: size * 0.2,
            top: 0,
            bottom: 0,
            width: 1,
            child: ColoredBox(color: tones.pen.withValues(alpha: 0.55)),
          ),
          Padding(
            padding: EdgeInsets.only(left: size * 0.2),
            child: Center(child: Icon(Icons.check_rounded, size: size * 0.46, color: tones.tick)),
          ),
        ],
      ),
    );
  }
}

/// What comes back, drawn rather than described: a name blacked out before
/// anything is uploaded, a mark on every question with the half and quarter
/// marks a real rubric needs, and a written reason for the one that lost
/// something.
///
/// It is an illustration and says so — the app never shows a teacher a
/// screenshot of marking that did not happen.
/// [scale] grows every measurement on the drawn page together — the padding,
/// the handwriting, the marks, the note. A big monitor gets a bigger page,
/// not the same small page with more blank paper around it.
class MarkedPaperPreview extends StatelessWidget {
  final double scale;

  const MarkedPaperPreview({super.key, this.scale = 1.0});

  @override
  Widget build(BuildContext context) {
    final tones = PaperTones.of(context);
    final s = scale;
    final label = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AiMarkerColors.neutral,
          letterSpacing: 1.0 * s,
          fontSize: 10 * s,
        );

    return Container(
      decoration: BoxDecoration(
        color: tones.shade,
        borderRadius: BorderRadius.circular(4 * s),
        border: Border.all(color: tones.rule),
      ),
      padding: EdgeInsets.fromLTRB(16 * s, 14 * s, 16 * s, 15 * s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('NAME', style: label),
              SizedBox(width: 9 * s),
              // The name is painted out before the page leaves the phone.
              // Blacked out in either theme -- a pale bar in dark mode would
              // read as a highlighter, which is the opposite of the point.
              Container(
                width: 84 * s,
                height: 11 * s,
                decoration: BoxDecoration(color: const Color(0xFF080C13), border: Border.all(color: tones.rule)),
              ),
              const Spacer(),
              Transform.rotate(
                angle: -0.06,
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: '17½', style: markStyle(context, size: 21 * s, color: tones.pen)),
                      TextSpan(text: '/20', style: markStyle(context, size: 12 * s, color: tones.pen.withValues(alpha: 0.8), weight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 11 * s),
          _rule(tones),
          _QuestionRow(q: 'Q1', strokes: const [0.88, 0.61], mark: '5', full: true, scale: s),
          _rule(tones),
          _QuestionRow(q: 'Q2', strokes: const [0.94, 0.47], slip: 1, mark: '3¾', scale: s),
          _rule(tones),
          _QuestionRow(q: 'Q3', strokes: const [0.79, 0.88, 0.34], mark: '4¾', scale: s),
          _rule(tones),
          SizedBox(height: 11 * s),
          MarginNote('Q2 — right method, arithmetic slip in the last line.', fontSize: 12.5 * s),
        ],
      ),
    );
  }

  Widget _rule(PaperTones tones) => Container(height: 1, color: tones.rule);
}

/// One question: its number, the handwriting, and what it scored.
class _QuestionRow extends StatelessWidget {
  final String q;
  final List<double> strokes;

  /// Which line of handwriting the marker underlined in red.
  final int? slip;
  final String mark;
  final bool full;
  final double scale;

  const _QuestionRow({required this.q, required this.strokes, required this.mark, this.slip, this.full = false, this.scale = 1.0});

  @override
  Widget build(BuildContext context) {
    final tones = PaperTones.of(context);
    final colour = full ? tones.tick : tones.pen;
    final s = scale;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 9 * s),
      child: Row(
        children: [
          SizedBox(
            width: 20 * s,
            child: Text(
              q,
              style: markStyle(context, size: 11 * s, color: AiMarkerColors.neutral, weight: FontWeight.w600),
            ),
          ),
          SizedBox(width: 10 * s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < strokes.length; i++) ...[
                  if (i > 0) SizedBox(height: 5 * s),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: strokes[i],
                    child: Column(
                      children: [
                        Container(
                          height: 4 * s,
                          decoration: BoxDecoration(color: tones.graphite, borderRadius: BorderRadius.circular(2 * s)),
                        ),
                        if (i == slip) ...[
                          SizedBox(height: 3 * s),
                          Container(height: 1.5 * s, color: tones.pen),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(width: 12 * s),
          if (full) ...[
            Icon(Icons.check_rounded, size: 14 * s, color: tones.tick),
            SizedBox(width: 3 * s),
          ],
          Text(mark, style: markStyle(context, size: 14 * s, color: colour)),
        ],
      ),
    );
  }
}
