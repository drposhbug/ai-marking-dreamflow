import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:marking_prokect_v2/services/anonymizer.dart';

/// The result of showing a teacher what is about to be sent.
class ReviewedPages {
  /// The pages to hand to the queue. These are the ORIGINALS, with any box
  /// the teacher painted burned in — the queue redacts at marking time and
  /// relies on the original still being there for her to look at afterwards.
  final List<Uint8List> pages;

  /// True when every page ends up with its name covered — either by the
  /// reader or by hand. The queue needs this because a page covered by hand
  /// has its `Name:` label under the black box, so the automatic pass finds
  /// nothing and would otherwise report that the name went out in the open.
  final bool allCovered;

  const ReviewedPages({required this.pages, required this.allCovered});
}

/// Shows every page as it will be sent, and lets the teacher cover anything
/// the reader missed — before a single one leaves the machine.
///
/// This is the browser being *better* than a phone rather than catching up
/// to it. The app has always been able to say "no name was found on page 14".
/// On a phone that is where it ends: thumbing through thirty scans on a
/// handset to find page 14, and then covering it in some other app, is not
/// something a teacher holding a stack of papers is going to do. On a screen
/// this size all thirty are visible at once, the ones worth a look have an
/// amber edge, and covering a missed name is a drag with a mouse.
///
/// Returns null if the teacher backed out, in which case nothing is sent.
Future<ReviewedPages?> reviewBeforeUpload(
  BuildContext context, {
  required List<Uint8List> pages,
  bool onWeb = kIsWeb,
  String title = 'Check these before they go',
}) async {
  if (pages.isEmpty) return const ReviewedPages(pages: [], allCovered: true);

  // A phone redacts at marking time and has no screen to do this on, so it
  // is left exactly as it was.
  if (!onWeb || !Anonymizer.available) {
    return ReviewedPages(pages: pages, allCovered: false);
  }

  final previews = await Anonymizer.review(pages);
  if (!context.mounted) return null;

  return showDialog<ReviewedPages>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _RedactionReview(previews: previews, originals: pages, title: title),
  );
}

class _RedactionReview extends StatefulWidget {
  final List<AnonymizedPage> previews;
  final List<Uint8List> originals;
  final String title;
  const _RedactionReview({required this.previews, required this.originals, required this.title});

  @override
  State<_RedactionReview> createState() => _RedactionReviewState();
}

class _RedactionReviewState extends State<_RedactionReview> {
  /// Boxes the teacher has painted, per page, in image pixels. Held rather
  /// than burned in as they are drawn: re-encoding a full page on every drag
  /// would stutter, and nothing has to be permanent until Send.
  late List<List<Rect>> _extra;
  int? _open;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _extra = List.generate(widget.previews.length, (_) => <Rect>[]);
  }

  bool _coveredAt(int i) => widget.previews[i].redacted || _extra[i].isNotEmpty;

  int get _needLook =>
      List.generate(widget.previews.length, _coveredAt).where((c) => !c).length;

  Future<void> _send() async {
    setState(() => _sending = true);
    final out = <Uint8List>[];
    for (var i = 0; i < widget.originals.length; i++) {
      out.add(await Anonymizer.cover(widget.originals[i], _extra[i]));
    }
    if (!mounted) return;
    Navigator.pop(
      context,
      ReviewedPages(pages: out, allCovered: _needLook == 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final open = _open;
    final n = widget.previews.length;

    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180, maxHeight: 880),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title, style: theme.textTheme.titleLarge),
                        const SizedBox(height: 4),
                        Text(
                          _needLook == 0
                              ? '$n ${n == 1 ? "page" : "pages"} · a name is covered on every one'
                              : '$n ${n == 1 ? "page" : "pages"} · $_needLook with no name found',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: _needLook == 0
                                ? theme.colorScheme.outline
                                : const Color(0xFFB26A00),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (open != null)
                    TextButton.icon(
                      onPressed: () => setState(() => _open = null),
                      icon: const Icon(Icons.grid_view_rounded, size: 18),
                      label: const Text('All pages'),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: open == null ? _grid(theme) : _detail(theme, open)),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      open == null
                          ? 'Open any page to cover something the reader missed. Nothing has been sent yet.'
                          : 'Drag across the page to cover anything still showing.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ),
                  TextButton(
                    onPressed: _sending ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _sending ? null : _send,
                    child: _sending
                        ? const SizedBox(
                            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text('Send $n ${n == 1 ? "page" : "pages"}'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _grid(ThemeData theme) {
    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        childAspectRatio: 0.74,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: widget.previews.length,
      itemBuilder: (_, i) {
        final needsLook = !_coveredAt(i);
        return InkWell(
          onTap: () => setState(() => _open = i),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: needsLook ? const Color(0xFFE8A33D) : theme.colorScheme.outlineVariant,
                width: needsLook ? 2.5 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _PagePreview(
                    bytes: widget.previews[i].bytes,
                    extra: _extra[i],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  color: needsLook
                      ? const Color(0xFFFFF4E2)
                      : theme.colorScheme.surfaceContainerHighest,
                  child: Row(
                    children: [
                      Icon(
                        needsLook ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                        size: 15,
                        color: needsLook ? const Color(0xFFB26A00) : theme.colorScheme.outline,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          needsLook ? 'No name found' : 'Name covered',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: needsLook ? const Color(0xFFB26A00) : theme.colorScheme.outline,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text('${i + 1}', style: theme.textTheme.labelSmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _detail(ThemeData theme, int index) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: _PagePreview(
              key: ValueKey('page-$index'),
              bytes: widget.previews[index].bytes,
              extra: _extra[index],
              onCover: (r) => setState(() => _extra[index].add(r)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: index > 0 ? () => setState(() => _open = index - 1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Text('Page ${index + 1} of ${widget.previews.length}',
                  style: theme.textTheme.labelLarge),
              IconButton(
                onPressed: index < widget.previews.length - 1
                    ? () => setState(() => _open = index + 1)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
              if (_extra[index].isNotEmpty) ...[
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: () => setState(() => _extra[index].clear()),
                  icon: const Icon(Icons.undo, size: 16),
                  label: Text('Undo ${_extra[index].length}'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One page, with the boxes the teacher has drawn painted over it.
///
/// The boxes are drawn as widgets rather than burned into the image: the page
/// can then be re-laid-out, zoomed and scrolled without a re-encode, and
/// nothing becomes permanent until Send. [onCover] being null makes it a
/// read-only thumbnail.
class _PagePreview extends StatefulWidget {
  final Uint8List bytes;
  final List<Rect> extra;
  final ValueChanged<Rect>? onCover;
  const _PagePreview({super.key, required this.bytes, required this.extra, this.onCover});

  @override
  State<_PagePreview> createState() => _PagePreviewState();
}

class _PagePreviewState extends State<_PagePreview> {
  ui.Image? _image;
  Offset? _from;
  Offset? _to;

  @override
  void initState() {
    super.initState();
    decodeImageFromList(widget.bytes).then((i) {
      if (mounted) setState(() => _image = i);
    });
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) {
      return const Center(
        child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Where the page actually sits inside the space it was given. The
        // mapping has to come from the decoded image rather than the layout,
        // or a letterboxed page covers the wrong part of the paper.
        final scale = (constraints.maxWidth / image.width)
            .clamp(0.0, constraints.maxHeight / image.height);
        final shown = Size(image.width * scale, image.height * scale);
        final origin = Offset(
          (constraints.maxWidth - shown.width) / 2,
          (constraints.maxHeight - shown.height) / 2,
        );

        Rect toWidget(Rect r) => Rect.fromLTRB(
              origin.dx + r.left * scale,
              origin.dy + r.top * scale,
              origin.dx + r.right * scale,
              origin.dy + r.bottom * scale,
            );

        Rect? dragRect() {
          final a = _from, b = _to;
          return (a == null || b == null) ? null : Rect.fromPoints(a, b);
        }

        final painted = <Widget>[
          Positioned.fill(
            child: Image.memory(widget.bytes, fit: BoxFit.contain, gaplessPlayback: true),
          ),
          for (final r in widget.extra)
            Positioned.fromRect(rect: toWidget(r), child: const ColoredBox(color: Colors.black)),
          if (dragRect() != null)
            Positioned.fromRect(
              rect: dragRect()!,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  border: Border.all(color: Colors.white70),
                ),
              ),
            ),
        ];

        if (widget.onCover == null) return Stack(children: painted);

        return MouseRegion(
          cursor: SystemMouseCursors.precise,
          child: GestureDetector(
            onPanStart: (d) => setState(() {
              _from = d.localPosition;
              _to = d.localPosition;
            }),
            onPanUpdate: (d) => setState(() => _to = d.localPosition),
            onPanEnd: (_) {
              final r = dragRect();
              setState(() {
                _from = null;
                _to = null;
              });
              if (r == null || r.width < 6 || r.height < 6) return;
              final inImage = Rect.fromLTRB(
                ((r.left - origin.dx) / scale).clamp(0.0, image.width.toDouble()),
                ((r.top - origin.dy) / scale).clamp(0.0, image.height.toDouble()),
                ((r.right - origin.dx) / scale).clamp(0.0, image.width.toDouble()),
                ((r.bottom - origin.dy) / scale).clamp(0.0, image.height.toDouble()),
              );
              if (inImage.width < 2 || inImage.height < 2) return;
              widget.onCover!(inImage);
            },
            child: Stack(children: painted),
          ),
        );
      },
    );
  }
}
