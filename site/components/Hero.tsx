import { APP_URL, LAUNCH_MAILTO } from '../lib/content';

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
          <p className="eyebrow">
            Marking assistant for teachers · <b>not on any app store yet</b>
          </p>
          <h1 id="h-hero">
            Marking eats your evenings. UMarkless marks it first. You just check and sign off.
          </h1>

          <p className="lede">
            Import a Google Form, scan a stack from the photocopier, or photograph papers one at a
            time. Back come question-by-question marks, a written reason for every deduction, and
            feedback a fourteen-year-old will actually read. You can override all of it.
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
            There is no app store listing yet. Signing in opens the browser version.
          </p>
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
