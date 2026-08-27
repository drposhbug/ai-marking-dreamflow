import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:marking_prokect_v2/app/app_routes.dart';
import 'package:marking_prokect_v2/theme.dart';

/// The four routes a class set can take, with honest times and the actual
/// steps for each.
///
/// This is on the home screen rather than buried in help because the
/// fastest route is the one nobody guesses. Left alone, most teachers reach
/// for the camera — the slowest of the four — decide the app is slow, and
/// never find out that the same job takes two minutes through a Google
/// Form. The guide is the difference between the product being fast and
/// merely being capable of being fast.
class WaysToMarkScreen extends StatelessWidget {
  const WaysToMarkScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.pop()),
        title: const Text('Ways to mark'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Text(
            'Times are for a class of thirty. Most teachers end up using two of these — one for quizzes, one for real tests.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AiMarkerColors.neutral, height: 1.45),
          ),
          const SizedBox(height: 16),
          _Route(
            icon: Icons.assignment_turned_in_rounded,
            colour: cs.primary,
            title: 'Google Form or spreadsheet',
            time: '~2 min',
            best: 'Quizzes, and anything students type. Nothing to scan at all.',
            steps: const [
              'In your form: Responses, then the green Sheets icon.',
              'In Sheets: File → Download → Comma-separated values (.csv).',
              'Here: Import a Google Form, and pick that file.',
              'Check the columns it found, and tap the correct answer for each multiple-choice question.',
              'Mark. Multiple choice is marked on your phone for free — only the written answers use credits.',
            ],
            note: 'Every student\'s answer to one question is marked together, so the whole class is judged the same way.',
            action: ('Import a Google Form', AppRoutes.importResponses),
          ),
          _Route(
            icon: Icons.qr_code_2_rounded,
            colour: AiMarkerColors.secondary,
            title: 'Prepare, print, then scan the stack',
            time: '~6 min',
            best: 'Real tests on paper. The fastest paper route, and the only one that can\'t mix students up.',
            steps: const [
              'Here: Prepare a test to print, and pick your test file.',
              'Choose how many copies, then send the one file to the copier and print as normal.',
              'Hand out, collect back, and take the staples out.',
              'Feed the stack through the copier\'s document feeder and scan to PDF — most will email it to you or drop it in Drive.',
              'Here: Split a scanned stack, and pick that PDF.',
              'Every paper sorts itself out by the code printed on it. Check it over, then mark.',
            ],
            note: 'Each copy carries a tiny code in the footer, so pages can be shuffled, creased or scanned out of order and still land in the right paper.',
            action: ('Prepare a test to print', AppRoutes.prepareTest),
          ),
          _Route(
            icon: Icons.print_rounded,
            colour: AiMarkerColors.tertiary,
            title: 'Scan a stack you already printed',
            time: '~6 min',
            best: 'A test that\'s already been written on, printed the ordinary way.',
            steps: const [
              'Take the staples out — a feeder will jam or tear on one.',
              'Feed the stack through the copier and scan to PDF.',
              'Here: Split a scanned stack, and pick that PDF.',
              'It works out where each paper starts from the name fields and page numbers.',
              'Check the split — anything odd is flagged — then mark.',
            ],
            note: 'Tell it how many students to expect and it will catch a page the feeder swallowed, which is the failure you\'d otherwise never notice.',
            action: ('Split a scanned stack', AppRoutes.splitStack),
          ),
          _Route(
            icon: Icons.photo_camera_rounded,
            colour: AiMarkerColors.warning,
            title: 'Photograph each paper',
            time: '~15 min',
            best: 'A handful of papers, a late submission, or anywhere without a copier.',
            steps: const [
              'Prop your phone up on something, or hold it in one hand.',
              'Here: Scan Assignment.',
              'Slide each page underneath. It shoots automatically and tells you — a sound, or a buzz — when to slide the next one.',
              'Tap Done, pick the class, and mark.',
            ],
            note: 'Change the sound to a buzz, or turn it off, with the button at the top of the scan screen.',
            action: null,
          ),
          Card(
            color: cs.primary.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.verified_rounded, size: 18, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Whichever route you take, the first paper is marked on its own and shown to you before the rest '
                      'go ahead. A wrong answer key costs one paper, never thirty.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One route, collapsed to its headline until the teacher wants the steps.
class _Route extends StatefulWidget {
  final IconData icon;
  final Color colour;
  final String title;
  final String time;
  final String best;
  final List<String> steps;
  final String note;

  /// Label and route for starting this way of marking, when there is a
  /// screen for it.
  final (String, String)? action;

  const _Route({
    required this.icon,
    required this.colour,
    required this.title,
    required this.time,
    required this.best,
    required this.steps,
    required this.note,
    required this.action,
  });

  @override
  State<_Route> createState() => _RouteState();
}

class _RouteState extends State<_Route> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final act = widget.action;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: widget.colour.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(widget.icon, color: widget.colour, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(widget.title,
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                            ),
                            Text(widget.time,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(color: widget.colour, fontWeight: FontWeight.w800)),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(widget.best,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.35)),
                      ],
                    ),
                  ),
                  Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AiMarkerColors.neutral),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 12),
                  for (var i = 0; i < widget.steps.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: widget.colour.withValues(alpha: 0.14),
                              shape: BoxShape.circle,
                            ),
                            child: Text('${i + 1}',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(color: widget.colour, fontWeight: FontWeight.w800)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(widget.steps[i],
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4)),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(widget.note,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AiMarkerColors.neutral, fontStyle: FontStyle.italic, height: 1.4)),
                  if (act != null) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonal(
                        onPressed: () => context.push(act.$2),
                        child: Text(act.$1),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
