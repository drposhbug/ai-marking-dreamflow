import { LAUNCH_MAILTO, ROUTES } from '../lib/content';

/**
 * The cover page of the exam booklet: warm paper edge to edge, a faint red
 * margin rule down the left, the title centred in the schoolbook serif, and
 * the real product underneath it.
 *
 * The visual is a real screenshot of the Flutter web app, captured from the
 * running build. It is captioned as a screenshot because that is what it is.
 * Every drawn visual elsewhere on this page is captioned as an illustration
 * for the same reason: the two are never allowed to be mistaken for each other.
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

        <figure className="shot hero-shot">
          <div className="shot-frame">
            <div className="shot-bar" aria-hidden="true">
              <span>UMarkless · grading</span>
              <span>running in a browser</span>
            </div>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src="shots/app-grading-home.png"
              width={2880}
              height={1800}
              alt="A screenshot of the UMarkless web app on its grading screen. A navigation rail lists Grading, Dashboard, Classes, Answers and Settings. A Scan Assignment card offers From Gallery and From Drive, and below it sit the routes: import a Google Form, prepare a test to print, split a scanned stack, plan with Mark, and report card comments."
            />
          </div>
          <figcaption>
            A screenshot of the UMarkless web app, running in a browser. The teacher name on it is
            sample data typed into a demo account.
          </figcaption>
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
