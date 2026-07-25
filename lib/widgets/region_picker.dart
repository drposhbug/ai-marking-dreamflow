import 'package:flutter/material.dart';
import 'package:marking_prokect_v2/data/curriculum_regions.dart';
import 'package:marking_prokect_v2/theme.dart';

/// Searchable bottom-sheet picker for the teacher's curriculum region.
Future<CurriculumRegion?> showRegionPicker(BuildContext context, {String? selectedId}) {
  return showModalBottomSheet<CurriculumRegion>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (context) => _RegionPickerSheet(selectedId: selectedId),
  );
}

class _RegionPickerSheet extends StatefulWidget {
  final String? selectedId;
  const _RegionPickerSheet({this.selectedId});

  @override
  State<_RegionPickerSheet> createState() => _RegionPickerSheetState();
}

class _RegionPickerSheetState extends State<_RegionPickerSheet> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final q = _search.text.trim().toLowerCase();
    final filtered = q.isEmpty
        ? curriculumRegions
        : curriculumRegions.where((r) => r.label.toLowerCase().contains(q) || r.country.toLowerCase().contains(q)).toList();

    // Group by country, preserving list order.
    final countries = <String>[];
    for (final r in filtered) {
      if (!countries.contains(r.country)) countries.add(r.country);
    }

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Where do you teach?', style: Theme.of(context).textTheme.titleLarge)),
                  IconButton(onPressed: () => Navigator.pop(context), icon: Icon(Icons.close_rounded, color: AiMarkerColors.neutral)),
                ],
              ),
              Text(
                'Marking follows your province or state\'s curriculum expectations.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _search,
                autofocus: false,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search province or state...',
                  prefixIcon: Icon(Icons.search_rounded, color: AiMarkerColors.neutral.withValues(alpha: 0.85)),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: [
                    for (final country in countries) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                        child: Text(country, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AiMarkerColors.neutral)),
                      ),
                      for (final r in filtered.where((r) => r.country == country))
                        ListTile(
                          dense: true,
                          leading: Icon(
                            r.id == widget.selectedId ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                            color: r.id == widget.selectedId ? cs.primary : AiMarkerColors.neutral,
                          ),
                          title: Text(r.label, style: Theme.of(context).textTheme.bodyMedium),
                          onTap: () => Navigator.pop(context, r),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
