import { CountUp } from './CountUp';

/* ==========================================================================
   What marking costs teachers, from published surveys.

   Every figure here is someone else's measurement, traced to its primary
   source and linked from the line beneath it, with the population it
   describes in plain words - Alberta is not Ontario and the US is not
   Canada, so neither is stretched to cover them. UMarkless's own numbers
   stay the four route timings; this band says why those matter.
   ========================================================================== */

const STATS = [
  {
    value: '5',
    unit: 'hours',
    text: 'a week a typical US teacher spends grading and giving feedback on student work.',
    who: 'EdWeek Research Center teacher survey, 2022',
    href: 'https://www.edweek.org/teaching-learning/how-teachers-spend-their-time-a-breakdown/2022/04',
  },
  {
    value: '52%',
    unit: '',
    text: 'of Alberta teachers name “too much marking” as a source of stress, the most common one.',
    who: 'OECD TALIS 2024, Alberta country note',
    href: 'https://www.oecd.org/en/publications/results-from-talis-2024-country-notes_e127f9e2-en/alberta-canada_60368aa6-en.html',
  },
  {
    value: '10',
    unit: 'hours',
    text: 'a week US teachers work beyond their contract: 49 hours against 39.',
    who: 'RAND, State of the American Teacher 2025',
    href: 'https://www.rand.org/pubs/research_reports/RRA1108-16.html',
  },
];

export function Stats() {
  return (
    <section className="s s--tint s--stats" id="evenings" aria-labelledby="h-stats">
      <div className="wrap">
        <h2 id="h-stats" className="stats-head">
          Where the evenings go
        </h2>
        <p className="stats-sub">
          UMarkless gives that time back: a class set of thirty is marked in 2 to 15 minutes,
          depending on the route, and you check and sign off instead of marking every paper.
        </p>
        <ul className="stats">
          {STATS.map((s) => (
            <li key={s.value}>
              <p className="stat-n">
                <CountUp value={s.value} />
                {s.unit && <em>{s.unit}</em>}
              </p>
              <p className="stat-text">{s.text}</p>
              <a className="stat-src" href={s.href}>
                {s.who}
              </a>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}
