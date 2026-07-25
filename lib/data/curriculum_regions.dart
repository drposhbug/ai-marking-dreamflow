/// Curriculum regions the teacher can pick from. The AI anchors its
/// grade-level expectations to the selected region's curriculum.
///
/// KEEP IN SYNC with the CURRICULA table in
/// supabase/functions/MARKING-PROCESS/index.ts — the `id` values must match;
/// the edge function holds the per-region expectation text.
class CurriculumRegion {
  final String id;
  final String label;
  final String country;

  const CurriculumRegion(this.id, this.label, this.country);
}

const List<CurriculumRegion> curriculumRegions = [
  // Canada
  CurriculumRegion('ca-on', 'Ontario', 'Canada'),
  CurriculumRegion('ca-qc', 'Quebec', 'Canada'),
  CurriculumRegion('ca-bc', 'British Columbia', 'Canada'),
  CurriculumRegion('ca-ab', 'Alberta', 'Canada'),
  CurriculumRegion('ca-sk', 'Saskatchewan', 'Canada'),
  CurriculumRegion('ca-mb', 'Manitoba', 'Canada'),
  CurriculumRegion('ca-ns', 'Nova Scotia', 'Canada'),
  CurriculumRegion('ca-nb', 'New Brunswick', 'Canada'),
  CurriculumRegion('ca-nl', 'Newfoundland and Labrador', 'Canada'),
  CurriculumRegion('ca-pe', 'Prince Edward Island', 'Canada'),
  CurriculumRegion('ca-other', 'Canada — other', 'Canada'),
  // United States
  CurriculumRegion('us-ca', 'California', 'United States'),
  CurriculumRegion('us-tx', 'Texas', 'United States'),
  CurriculumRegion('us-fl', 'Florida', 'United States'),
  CurriculumRegion('us-ny', 'New York', 'United States'),
  CurriculumRegion('us-il', 'Illinois', 'United States'),
  CurriculumRegion('us-pa', 'Pennsylvania', 'United States'),
  CurriculumRegion('us-oh', 'Ohio', 'United States'),
  CurriculumRegion('us-ga', 'Georgia', 'United States'),
  CurriculumRegion('us-mi', 'Michigan', 'United States'),
  CurriculumRegion('us-nc', 'North Carolina', 'United States'),
  CurriculumRegion('us-nj', 'New Jersey', 'United States'),
  CurriculumRegion('us-va', 'Virginia', 'United States'),
  CurriculumRegion('us-wa', 'Washington', 'United States'),
  CurriculumRegion('us-ma', 'Massachusetts', 'United States'),
  CurriculumRegion('us-az', 'Arizona', 'United States'),
  CurriculumRegion('us-co', 'Colorado', 'United States'),
  CurriculumRegion('us-tn', 'Tennessee', 'United States'),
  CurriculumRegion('us-in', 'Indiana', 'United States'),
  CurriculumRegion('us-mo', 'Missouri', 'United States'),
  CurriculumRegion('us-md', 'Maryland', 'United States'),
  CurriculumRegion('us-mn', 'Minnesota', 'United States'),
  CurriculumRegion('us-wi', 'Wisconsin', 'United States'),
  CurriculumRegion('us-cc', 'United States — other (Common Core)', 'United States'),
  // Mexico
  CurriculumRegion('mx', 'Mexico', 'Mexico'),
  // Fallback
  CurriculumRegion('other', 'Other / International', 'Other'),
];

CurriculumRegion? regionById(String id) {
  for (final r in curriculumRegions) {
    if (r.id == id) return r;
  }
  return null;
}
