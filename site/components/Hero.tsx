import { APP_URL, LAUNCH_MAILTO, ROUTES } from '../lib/content';
import { CountUp } from './CountUp';

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
          <h1 id="h-hero">Marking eats your evenings. UMarkless marks it first — you just check and sign off.</h1>

          <p className="lede">
            Import a Google Form, scan a stack from the photocopier, or photograph papers one at a
            time. Back come question-by-question marks, a written reason for every deduction, and
            feedback a fourteen-year-old will actually read — all of which you can override.
          </p>

          <div className="cta-row">
            <a className="btn btn-primary" href={APP_URL}>
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

      </div>

      <div className="hero-times-strip">
        <ul className="hero-times">
          {ROUTES.map((r) => (
            <li key={r.id}>
              <b>
                <CountUp value={r.minutes} />
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
