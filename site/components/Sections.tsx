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
        <a className="btn btn-ghost" href={APP_URL}>
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

/* --------------------------------------------------------------- limits */

/**
 * The known gaps, near the foot of the page: stated in full for anyone
 * deciding whether to trust it, and out of the way of everyone else.
 */
export function Limits() {
  return (
    <section className="s s--paper s--limits" id="limits" aria-label="Where the promise stops">
      <div className="wrap">
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
            It reduces exposure; it does not make a page anonymous. Every gap is in{' '}
            <a href={COMPLIANCE_URL}>Security and compliance</a>.
          </p>
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
            <h2 id="h-close">Take back your evenings.</h2>
            <p>
              Submitted to the RevenueCat Shipaton 2026 and not on an app store yet. Ask to hear
              when it launches — or, if you are a school, read the compliance write-up first.
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
