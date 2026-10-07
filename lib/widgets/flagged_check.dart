import 'package:flutter/material.dart';
import 'package:marking_prokect_v2/app/app_state.dart';
import 'package:marking_prokect_v2/services/ai_grading_service.dart';
import 'package:provider/provider.dart';

/// Questions the teacher should look at before moving on: drawings the AI
/// marked as a best guess, and anything it couldn't mark ("?").
int flaggedCount(Iterable<QuestionAnnotation> annotations) =>
    annotations.where((a) => a.teacherCheck || a.earnedMark.trim() == '?').length;

/// "Are you sure you want to continue?" before leaving a result with flagged
/// drawings. Returns true to go on. "Skip for this batch" goes on and stops
/// asking for the rest of this class's papers.
Future<bool> confirmFlagged(BuildContext context, Iterable<QuestionAnnotation> annotations) async {
  final n = flaggedCount(annotations);
  final app = context.read<AppState>();
  if (n == 0 || app.skipFlaggedCheck) return true;
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.flag_rounded, color: Color(0xFFB45309)),
      title: Text(n == 1 ? '1 flagged question' : '$n flagged questions'),
      content: const Text(
        'The AI gave its best-guess mark on drawings it can\'t be sure of (shown in amber). '
        'Are you sure you want to continue without checking them?',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, 'review'), child: const Text('Check them')),
        TextButton(onPressed: () => Navigator.pop(ctx, 'skip'), child: const Text('Skip for this batch')),
        FilledButton(onPressed: () => Navigator.pop(ctx, 'go'), child: const Text('Continue')),
      ],
    ),
  );
  if (choice == 'skip') app.skipFlaggedCheckForBatch();
  return choice == 'go' || choice == 'skip';
}
