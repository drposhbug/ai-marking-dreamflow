import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:marking_prokect_v2/theme.dart';

/// What the teacher sees while she is holding a folder of scans over the
/// window.
///
/// Without it the drop works but nothing says so, and a gesture nobody can
/// see is a gesture nobody uses — she lets go over the page, watches the
/// browser open one JPEG full screen, and never tries again.
class DropTargetOverlay extends StatelessWidget {
  const DropTargetOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: Container(
        color: cs.surface.withValues(alpha: 0.92),
        padding: const EdgeInsets.all(20),
        child: Center(
          child: DottedBorderBox(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.file_download_outlined, size: 52, color: cs.primary),
                const SizedBox(height: 12),
                Text(
                  'Drop the pages here',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: cs.primary),
                ),
                const SizedBox(height: 6),
                Text(
                  'Photos or PDFs. Drop a whole class set at once and Markless\nwill ask whether it is one test or one per student.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AiMarkerColors.neutral, height: 1.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The dashed frame that makes the whole page read as one target.
class DottedBorderBox extends StatelessWidget {
  final Widget child;
  const DottedBorderBox({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CustomPaint(
      painter: _DashedRectPainter(color: cs.primary.withValues(alpha: 0.7)),
      child: Padding(padding: const EdgeInsets.all(36), child: child),
    );
  }
}

class _DashedRectPainter extends CustomPainter {
  final Color color;
  const _DashedRectPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    const dash = 9.0;
    const gap = 7.0;
    final rect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(AppRadius.lg));
    final metrics = (Path()..addRRect(rect)).computeMetrics();
    for (final metric in metrics) {
      var at = 0.0;
      while (at < metric.length) {
        canvas.drawPath(metric.extractPath(at, (at + dash).clamp(0.0, metric.length)), paint);
        at += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRectPainter old) => old.color != color;
}

/// The one line that tells a teacher on a laptop the gesture exists.
class DropAndPasteHint extends StatelessWidget {
  const DropAndPasteHint({super.key});

  @override
  Widget build(BuildContext context) {
    // A Mac teacher told to press Ctrl-V presses Ctrl-V, nothing happens,
    // and she concludes paste is not supported.
    final paste = defaultTargetPlatform == TargetPlatform.macOS ? 'Cmd-V' : 'Ctrl-V';
    return Row(
      children: [
        Icon(Icons.file_download_outlined, size: 16, color: AiMarkerColors.neutral.withValues(alpha: 0.9)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Or drag scans onto this page, or paste a screenshot with $paste.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.35),
          ),
        ),
      ],
    );
  }
}
