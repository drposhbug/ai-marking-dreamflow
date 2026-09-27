import { APP_URL } from '../lib/content';

/**
 * The cover page of the exam booklet: warm paper edge to edge, a faint red
 * margin rule down the left, the title centred in the schoolbook serif.
 *
 * No product visual here, on purpose, after two attempts at one. A real
 * screenshot went stale the moment the app was redesigned and quietly
 * advertised a product that no longer existed; a rendered animation drew the
 * eye away from the one sentence this section exists to say. The headline
 * and the four real timings under it ARE the hero. The marked-paper
 * illustrations live further down, where they explain rather than decorate.
 *
 */
export function Hero() {
  return (
    <section className="s s--paper s--hero" aria-labelledby="h-hero">
      <div className="wrap">
        <div className="hero-intro">
          <p className="eyebrow">The marking assistant for teachers</p>
          <h1 id="h-hero">
            Take your evenings back. UMarkless marks the whole stack.
          </h1>

          <p className="lede">
            A class set of thirty, marked in the time it takes to pour a coffee: a mark for every
            question, a written reason for every deduction, and feedback your students will
            actually read. Every mark stays yours to change.
          </p>

          <div className="cta-row">
            <a className="btn btn-primary" href={APP_URL}>
              Start marking free
            </a>
            <a className="btn btn-ghost" href="#how">
              See how it works
            </a>
          </div>
          <p className="note-small">Free to start, right in your browser. No card, no setup.</p>
        </div>

      </div>

      {/* The hero fills the first screen, so say there is more below it. */}
      <a className="scroll-cue" href="#evenings" aria-label="Scroll down to the next section">
        <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
          <path d="M12 4v15M5.5 12.5 12 19l6.5-6.5" />
        </svg>
      </a>
    </section>
  );
}
