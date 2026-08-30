import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:marking_prokect_v2/services/roster_paste.dart';
import 'package:marking_prokect_v2/theme.dart';

/// Builds a class list from a pasted block of names.
///
/// Typing thirty names one at a time is where teachers give up on setting
/// the app up, and it is the very first thing the app asks of them. A list
/// they already have — from Classroom, a register, a spreadsheet, an email
/// — pasted in whole turns that into about ten seconds.
///
/// The preview is the point. It shows exactly what will be created, what
/// was already in the class, and what was ignored, before anything is
/// saved. A teacher who can see the result does not have to trust the
/// parser.
class PasteRosterSheet extends StatefulWidget {
  /// Names already in the class, so a second paste tops it up rather than
  /// doubling it.
  final List<String> existingNames;

  const PasteRosterSheet({super.key, required this.existingNames});

  @override
  State<PasteRosterSheet> createState() => _PasteRosterSheetState();
}

class _PasteRosterSheetState extends State<PasteRosterSheet> {
  final _controller = TextEditingController();
  List<String> _parsed = const [];
  List<String> _duplicates = const [];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_reparse);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _reparse() {
    final parsed = RosterPaste.parse(_controller.text);
    setState(() {
      _duplicates = RosterPaste.alreadyPresent(parsed, widget.existingNames);
      _parsed = parsed;
    });
  }

  /// The names that will actually be created — the pasted ones minus any
  /// the class already has.
  List<String> get _toAdd {
    final dup = _duplicates.map((e) => e.toLowerCase()).toSet();
    return _parsed.where((n) => !dup.contains(n.toLowerCase())).toList(growable: false);
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.trim().isEmpty) return;
    _controller.text = _controller.text.trim().isEmpty ? text : '${_controller.text}\n$text';
    _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final add = _toAdd;
    final typed = _controller.text.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 14),
              Text('Paste your class list', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                'One name per line. Copy it from anywhere — Classroom, your register, a spreadsheet, an email. '
                '“Ruiz, Ana” and “Ana Ruiz” both work.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.4),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _controller,
                minLines: 6,
                maxLines: 12,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: 'Ana Ruiz\nBen Cole\nCara Diaz',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _pasteFromClipboard,
                  icon: const Icon(Icons.content_paste_rounded, size: 18),
                  label: const Text('Paste from clipboard'),
                ),
              ),
              if (typed) ...[
                const SizedBox(height: 6),
                _Summary(add: add.length, already: _duplicates.length),
                if (add.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  // The whole list, not a sample. A teacher scanning for the
                  // one name the parser mangled needs to see all of them.
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 200),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < add.length; i++)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Text('${i + 1}.  ${add[i]}',
                                  style: Theme.of(context).textTheme.bodyMedium),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (_duplicates.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Already in this class, so they will be skipped: ${_duplicates.join(', ')}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.4),
                  ),
                ],
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: add.isEmpty ? null : () => Navigator.of(context).pop(add),
                      child: Text(add.isEmpty
                          ? 'Add students'
                          : 'Add ${add.length} student${add.length == 1 ? '' : 's'}'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  final int add;
  final int already;

  const _Summary({required this.add, required this.already});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = add == 0 && already == 0
        ? 'No names found yet.'
        : [
            if (add > 0) '$add to add',
            if (already > 0) '$already already here',
          ].join(' · ');
    return Row(
      children: [
        Icon(add > 0 ? Icons.check_circle_rounded : Icons.info_outline_rounded,
            size: 18, color: add > 0 ? cs.primary : AiMarkerColors.neutral),
        const SizedBox(width: 8),
        Text(text, style: Theme.of(context).textTheme.labelLarge),
      ],
    );
  }
}
