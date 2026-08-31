import { BELIEFS, COMPLIANCE_URL } from '../lib/content';
import { RevealItem } from './Reveal';

/**
 * The dark band. Seven numbered principles, all of them implemented behaviour
 * documented in README.md and docs/security-and-compliance.md rather than
 * aspiration - including the last one, which is the list of things Markless
 * does not do well.
 */
export function Beliefs() {
  return (
    <section className="band row slate" id="beliefs" aria-labelledby="h-beliefs">
      <p className="note-margin">Rules, not preferences.</p>

      <div className="head head--wide">
        <h2 id="h-beliefs">What Markless will not do</h2>
        <p className="sub">
          Seven rules the product is built around. Each of them costs something — speed, margin, or
          a claim we would rather be able to make — and each of them is in the code, not the
          marketing.
        </p>
      </div>

      <ol className="beliefs">
        {BELIEFS.map((b, i) => (
          <RevealItem key={b.n} delay={Math.min(i, 4) * 0.05}>
            <span className="bn" aria-hidden="true">
              {b.n}
            </span>
            <h3>{b.title}</h3>
            <p>{b.body}</p>
          </RevealItem>
        ))}
      </ol>

      <p className="more" style={{ color: 'var(--slate-ink2)', borderTopColor: 'var(--slate-rule)' }}>
        Subprocessors, legal footing, retention and every known gap are written out in{' '}
        <a href={COMPLIANCE_URL}>Security and compliance</a>.
      </p>
    </section>
  );
}
