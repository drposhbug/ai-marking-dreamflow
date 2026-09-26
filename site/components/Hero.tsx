import { LAUNCH_MAILTO, ROUTES } from '../lib/content';
import { HeroRender } from './HeroRender';

/**
 * The cover page of the exam booklet: warm paper edge to edge, a faint red
 * margin rule down the left, the title centred in the schoolbook serif, and
 * under it what the product leaves behind: a marked class set being flipped
 * through, page by page, onto a done pile.
 *
 * That visual is a render, not a screenshot, and is captioned as one — it is
 * a `figure.illo`, so the build's honesty check holds it to that. It replaced
 * a real screenshot of the app that had gone stale: it showed the old blue
 * palette and the old name, which made the page advertise a product that no
 * longer existed. Screenshots and illustrations are never allowed to be
 * mistaken for each other, in either direction.
 *
 * Under it, the only numbers UMarkless actually has - how long each route takes
 * for a class of thirty - in a strip whose rules run the full width of the
 * screen. There are no adoption rates, no hours-saved claims and no user
 * counts here, because none has ever been measured.
 */
export function Hero() {
  return (
    <section className="s s--paper s--hero" aria-labelledby="h-hero">
      <div className="wrap">
        <div className="hero-intro">
          <p className="eyebrow">
            Marking assistant for teachers · <b>not on any app store yet</b>
          </p>
          <h1 id="h-hero">Marking eats your evenings. UMarkless takes the first pass.</h1>

          <p className="lede">
            Import a Google Form, scan a stack from the photocopier, or photograph papers one at a
            time. Back come question-by-question marks, a written reason for every deduction, and
            feedback a fourteen-year-old will actually read — all of which you can override.
          </p>

          <div className="cta-row">
            <a className="btn btn-primary" href="#signin">
              Sign in and start marking
            </a>
            {/* TODO: replace this mailto with the Google Play listing URL once the app is live. */}
            <a className="btn btn-ghost" href={LAUNCH_MAILTO}>
              Ask to be told when it launches
            </a>
          </div>
          <p className="note-small">
            There is no app store listing yet — signing in opens the browser version.
          </p>
        </div>

        <figure className="illo hero-shot hero-render">
          <HeroRender />
          <figcaption>An illustration, rendered in Blender — not a screenshot of the app.</figcaption>
        </figure>
      </div>

      <div className="hero-times-strip">
        <ul className="hero-times">
          {ROUTES.map((r) => (
            <li key={r.id}>
              <b>
                {r.minutes}
                <em>min</em>
              </b>
              <span>{r.tab}</span>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}
