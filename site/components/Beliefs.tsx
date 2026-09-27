import { BELIEFS, COMPLIANCE_URL } from '../lib/content';
import { RevealItem } from './Reveal';

/**
 * A dark band, and the only list on the page that is full-bleed: each rule
 * between two rules runs from one edge of the screen to the other, with the
 * words held on the same column as everything else.
 *
 * Seven numbered principles, all of them implemented behaviour documented in
 * README.md and docs/security-and-compliance.md rather than aspiration -
 * including the last one, which is the list of things UMarkless does not do
 * well.
 */
export function Beliefs() {
  return (
    <section className="s s--dark" id="beliefs" aria-labelledby="h-beliefs">
      <div className="wrap">
        <p className="kicker">Rules, not preferences</p>

        <div className="head head--wide">
          <h2 id="h-beliefs">What UMarkless will not do</h2>
          <p className="sub">
            Seven rules the product is built around. Each of them costs something (speed, margin,
            or a claim we would rather be able to make), and each of them is in the code, not the
            marketing.
          </p>
        </div>
      </div>

      <ol className="beliefs">
        {BELIEFS.map((b, i) => (
          <RevealItem key={b.n} delay={Math.min(i, 4) * 0.05}>
            <div className="beliefs-in">
              <span className="bn" aria-hidden="true">
                {b.n}
              </span>
              <h3>{b.title}</h3>
              <p>{b.body}</p>
            </div>
          </RevealItem>
        ))}
      </ol>

      <div className="wrap">
        <p className="more">
          Subprocessors, legal footing, retention and every known gap are written out in{' '}
          <a href={COMPLIANCE_URL}>Security and compliance</a>.
        </p>
      </div>
    </section>
  );
}
