import { Underline } from './Ink';
import { MarkedPaper } from './MarkedPaper';
import { LAUNCH_MAILTO, ROUTES } from '../lib/content';

export function Hero() {
  return (
    <section className="band band--hero row" aria-labelledby="h-hero">
      <div className="hero-grid">
        <div>
          <p className="eyebrow">
            Marking assistant for teachers · <b>not on any app store yet</b>
          </p>
          <h1 id="h-hero">
            Marking eats your evenings. Markless takes <Underline>the first pass.</Underline>
          </h1>
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

        <figure className="illo hero-illo">
          <MarkedPaper />
          <figcaption>An illustration of what comes back, not a screenshot.</figcaption>
        </figure>
      </div>
    </section>
  );
}
