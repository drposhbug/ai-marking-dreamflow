import {
  APP_URL,
  COMPLIANCE_URL,
  CONTACT,
  LAUNCH_MAILTO,
  LIMITS,
  PLANS,
  PRIVACY_CLAIMS,
  README_URL,
  REPO_URL,
} from '../lib/content';

/* --------------------------------------------------------------- header */

export function SiteHeader() {
  return (
    <header className="site-header s--paper">
      <div className="wrap">
        <a className="brand" href="./">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="icon.png" width={24} height={24} alt="The UMarkless app icon" />
          UMarkless
        </a>
        <nav className="site-nav" aria-label="Primary">
          <a href="#how">How it works</a>
          <a href="#sequence">A class set</a>
          <a href="#marking">What comes back</a>
          <a href="#beliefs">What we won&rsquo;t do</a>
          <a href="#privacy">Privacy</a>
          <a href="#pricing">Plans</a>
        </nav>
        <a className="btn btn-ghost" href="#signin">
          Sign in
        </a>
      </div>
    </header>
  );
}

/* -------------------------------------------------------------- privacy */

export function Privacy() {
  return (
    <section className="s s--paper" id="privacy" aria-labelledby="h-priv">
      <div className="wrap">
        <p className="kicker">Including the parts that are not perfect</p>

        <div className="privacy-split">
          <div>
            <div className="head">
              <h2 id="h-priv">What leaves the phone, stated plainly</h2>
              <p className="sub">
                You would be handing us other people&rsquo;s children&rsquo;s work. Here is exactly
                what happens to it.
              </p>
            </div>

            <ul className="claims">
              {PRIVACY_CLAIMS.map((c) => (
                <li key={c.title}>
                  <h3>{c.title}</h3>
                  <p>{c.body}</p>
                </li>
              ))}
            </ul>
          </div>

          <figure className="illo">
            <div
              className="leaves"
              role="img"
              aria-label="Diagram of what stays on the device, what is uploaded, and what is never sent. Staying: the unaltered page, the student name, multiple-choice marking, the split of a scanned stack, and the printed stamping of test copies. Uploaded: the redacted page image, typed answers keyed by row number, marking settings, and the teacher account id used for metering. Never sent: contacts, location, the photo library beyond the pages picked, advertising identifiers, and any analytics profile."
            >
              <div className="stays">
                <h4>Stays on the device</h4>
                <ul>
                  <li>The unaltered page</li>
                  <li>The student&rsquo;s name</li>
                  <li>Multiple-choice marking</li>
                  <li>Splitting a scanned stack</li>
                  <li>Stamping printed copies</li>
                </ul>
              </div>
              <div className="goes">
                <h4>Goes up for marking</h4>
                <ul>
                  <li>The redacted page image</li>
                  <li>Typed answers, by row number</li>
                  <li>Grading mode and criteria</li>
                  <li>Grade level and region</li>
                  <li>Your account id, to meter usage</li>
                </ul>
              </div>
              <div className="never">
                <h4>Never transmitted at all</h4>
                <ul>
                  <li>Contacts</li>
                  <li>Location</li>
                  <li>Your photo library, beyond the pages you pick</li>
                  <li>Advertising identifiers</li>
                  <li>Any analytics profile — there is no analytics SDK</li>
                </ul>
              </div>
            </div>
            <figcaption>
              An illustration of the split between device and server on iOS and Android — not a
              screenshot, and read the limits below.
            </figcaption>
          </figure>
        </div>

        <div className="limits">
          <h3>Where the promise stops</h3>
          <ul>
            {LIMITS.map((l) => (
              <li key={l.before.slice(0, 40)}>
                {l.before}
                {l.em && <em>{l.em}</em>}
                {l.after}
              </li>
            ))}
          </ul>
          <p className="after">
            UMarkless reduces exposure substantially. It does not make a scanned page anonymous, and
            no vendor should claim otherwise. Subprocessors, legal footing, retention and every
            known gap are in <a href={COMPLIANCE_URL}>Security and compliance</a>.
          </p>
        </div>
      </div>
    </section>
  );
}

/* ---------------------------------------------------------------- plans */

export function Plans() {
  return (
    <section className="s s--dark" id="pricing" aria-labelledby="h-plans">
      <div className="wrap">
        {/* TODO: name the charity before launch. */}
        <p className="kicker">10% goes to charity, off the top</p>

        <div className="head head--wide">
          <h2 id="h-plans">Plans</h2>
          <p className="sub">
            <strong>Every paid plan gives 10% to charities that help kids learn</strong> — not a
            marketing line, it comes off the top. Start on a free trial. Paid plans are
            credit-based: credits scale with how much work a paper actually takes, so a short
            multiple-choice quiz costs a fraction of a six-page problem set, and re-marking the same
            paper is free.
          </p>
        </div>
      </div>

      {/* Full width: the hairlines between the tiers run to both edges. */}
      <div className="plans-strip">
        <div className="plans">
          {PLANS.map((plan) => (
            <article key={plan.id} className={`plan${plan.highlight ? ' pick' : ''}`}>
              <h3 className="pname">
                {plan.name}
                {plan.highlight && <span className="pick-mark">best value</span>}
              </h3>
              <p className="price">
                {plan.price} <span>{plan.period}</span>
              </p>
              <p className="credits">{plan.credits}</p>
              <ul>
                {plan.perks.map((perk) => (
                  <li key={perk}>{perk}</li>
                ))}
              </ul>
            </article>
          ))}
        </div>
      </div>

      <div className="wrap">
        <p className="fine">
          Prices are in US dollars; the store shows your own currency. Marking overnight costs about
          a fifth of marking on the spot, which is why every plan goes so much further that way.
          Subscriptions renew until cancelled and can be cancelled any time in the store.
        </p>
      </div>
    </section>
  );
}

/* -------------------------------------------------------------- sign in */

export function SignIn() {
  return (
    <section className="s s--paper" id="signin" aria-labelledby="h-signin">
      <div className="wrap">
        <p className="kicker">The password is typed in the app</p>

        <div className="signin-split">
          <div>
            <div className="head">
              <h2 id="h-signin">Sign in, and your marking is where you left it</h2>
              <p className="sub">
                Classes, answer keys and every marked test stay with the account rather than the
                device. Sign in somewhere else and they are already there.
              </p>
            </div>

            <ul className="claims">
              <li>
                <h3>This page hands you over. It does not sign you in.</h3>
                <p>
                  There is no server behind this page — it is a static file. Your email travels
                  across to UMarkless in the address bar, and the app&rsquo;s own sign-in screen
                  takes the password. Nothing here asks for one, and nothing here could receive it.
                </p>
              </li>
              <li>
                <h3>No account yet? Create one on the same screen.</h3>
                <p>
                  <strong>Create Account</strong> sits directly under the sign-in button in the app
                  and asks for an email and a password. Plans start on a free trial. Google,
                  Microsoft and Apple sign-in appear there too, when the server has them switched
                  on.
                </p>
              </li>
            </ul>
          </div>

          <div>
            {/* A handoff, not a login: this page is static and has no server,
                so it must never ask for a password. The Google button opens
                the app with ?sso=google and the app starts Google sign-in at
                once; the email form GETs the app with ?email= prefilled and
                the app's own screen takes the password. */}
            <form className="page signin-form" method="get" action={APP_URL}>
              <div className="pg-top">
                <span className="field">Sign in</span>
                <span className="tag-ok tag-push">opens the app</span>
              </div>
              <a className="btn btn-google" href={`${APP_URL}?sso=google`}>
                <svg viewBox="0 0 48 48" aria-hidden="true" focusable="false">
                  <path fill="#4285F4" d="M44.5 24.5c0-1.6-.1-2.8-.4-4.1H24v7.8h11.5c-.2 1.9-1.5 4.8-4.3 6.7l6.6 5.1c4-3.7 6.7-9.1 6.7-15.5z" />
                  <path fill="#34A853" d="M24 46c5.9 0 10.9-1.9 14.5-5.3l-6.9-5.4c-1.9 1.3-4.4 2.2-7.6 2.2-5.9 0-10.9-3.9-12.7-9.3l-7.1 5.5C7.8 40.9 15.3 46 24 46z" />
                  <path fill="#FBBC05" d="M11.3 28.2c-.5-1.3-.7-2.8-.7-4.2s.2-2.9.7-4.2l-7.1-5.5C2.7 17.1 2 20.5 2 24s.7 6.9 2.1 9.7l7.2-5.5z" />
                  <path fill="#EA4335" d="M24 9.5c3.3 0 6.3 1.1 8.6 3.3l6.4-6.3C35 2.6 30 .5 24 .5 15.3.5 7.8 5.6 4.1 13l7.1 5.5C13.1 13.4 18.1 9.5 24 9.5z" />
                </svg>
                Continue with Google
              </a>
              <div className="or-rule" aria-hidden="true">
                <span>or with email</span>
              </div>
              <label className="field" htmlFor="signin-email">
                Your email
              </label>
              <input
                id="signin-email"
                name="email"
                type="email"
                autoComplete="email"
                inputMode="email"
                spellCheck={false}
                autoCapitalize="off"
                placeholder="teacher@school.edu"
                required
              />
              <button className="btn btn-primary" type="submit">
                Continue to UMarkless
              </button>
              <a className="btn btn-ghost" href={APP_URL}>
                Create an account
              </a>
              <p className="pg-note">
                Either way, UMarkless opens on its own screen — Google&rsquo;s prompt, or the
                password field. No password is ever typed on this page.
              </p>
            </form>
            <p className="note-small">
              In a browser the name blackout runs here on your own machine, but it reads the printed
              “Name:” line rather than the handwriting, so it covers that whole line. On a page where
              it finds no printed label, nothing is covered and the app tells you.{' '}
              <a href="#privacy">Read the limits</a>.
            </p>
          </div>
        </div>
      </div>
    </section>
  );
}

/* -------------------------------------------------------------- closing */

export function Closing() {
  return (
    <section className="s s--dark" aria-labelledby="h-close">
      <div className="wrap">
        <div className="close-row">
          <div>
            <h2 id="h-close">Built by a teacher, for teachers.</h2>
            <p>
              An active project, submitted to the RevenueCat Shipaton 2026, and not on any app store
              yet. Ask to be told when it is — or, if you are a school, to read the compliance
              write-up first.
            </p>
          </div>
          <div className="cta-row">
            {/* TODO: replace this mailto with the Google Play listing URL once the app is live. */}
            <a className="btn btn-primary" href={LAUNCH_MAILTO}>
              Ask to be told when it launches
            </a>
            <a className="btn btn-ghost" href={REPO_URL}>
              Read the source
            </a>
          </div>
        </div>
      </div>
    </section>
  );
}

/* --------------------------------------------------------------- footer */

export function SiteFooter() {
  return (
    <footer className="site-footer">
      <div className="wrap">
        <nav aria-label="Footer">
          <a href="privacy.html">Privacy policy</a>
          <a href="delete-account.html">Delete your account</a>
          <a href={COMPLIANCE_URL}>Security and compliance</a>
          <a href={README_URL}>How it works, in detail</a>
          <a href={REPO_URL}>GitHub repository</a>
          <a href={`mailto:${CONTACT}`}>{CONTACT}</a>
        </nav>
        <p>
          UMarkless is a marking assistant for teachers. It proposes marks; the teacher decides them.
          It is built with Flutter for Android and iOS, and the source is public.
        </p>
        <p>Google Forms, Google Drive and Google Play are trademarks of Google LLC.</p>
      </div>
    </footer>
  );
}
