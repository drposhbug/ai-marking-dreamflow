'use client';

import { motion } from 'framer-motion';
import { Handwriting, Tick } from './Ink';
import { useReducedMotionSafe } from './useMedia';

/**
 * The hero illustration: one marked paper, seen from above.
 *
 * The name field is blacked out, four questions are scored down the page with
 * half and quarter marks, the error on Q2 is underlined in red pen, and the
 * total is written in the corner at the angle a person writes it at.
 *
 * It is an illustration. Every caption on the page says so.
 */

/* Four questions: 5 + 3¾ + 4¾ + 4 = 17½ out of 20, which is the total written
   in the corner. Any change here has to keep that arithmetic true. */
const ROWS = [
  { q: 'Q1', lines: [88, 61, 42], mark: '5', tone: 'good' as const, seed: 11 },
  { q: 'Q2', lines: [94, 47], mark: '3¾', tone: 'cut' as const, seed: 29, slip: 1 },
  { q: 'Q3', lines: [79, 88, 34], mark: '4¾', tone: 'cut' as const, seed: 47 },
  { q: 'Q4', lines: [72, 52, 39], mark: '4', tone: 'cut' as const, seed: 63 },
];

export function MarkedPaper() {
  const reduced = useReducedMotionSafe();

  const rise = reduced
    ? {}
    : {
        initial: { opacity: 0, y: 14 },
        animate: { opacity: 1, y: 0 },
      };

  return (
    <div
      className="page page-tilt"
      role="img"
      aria-label="Stylised illustration of a marked paper. The name field at the top is painted out in black. Four questions are scored down the page, including three and three quarters out of five with the error underlined in red and a written reason beneath it. A total of seventeen and a half out of twenty is written in red in the corner."
    >
      <div className="pg-top">
        <span className="field">Name</span>
        <motion.span
          className="redact"
          initial={reduced ? undefined : { scaleX: 0 }}
          animate={reduced ? undefined : { scaleX: 1 }}
          transition={{ duration: 0.42, delay: 0.15, ease: [0.4, 0, 0.2, 1] }}
          style={{ transformOrigin: '0 50%' }}
        />
        <motion.span
          className="total"
          initial={reduced ? undefined : { opacity: 0, rotate: -14, scale: 0.9 }}
          animate={reduced ? undefined : { opacity: 1, rotate: -3.5, scale: 1 }}
          transition={{ duration: 0.5, delay: 0.75, ease: [0.34, 1.3, 0.64, 1] }}
        >
          17½<i>/20</i>
        </motion.span>
      </div>

      <ul className="qlist">
        {ROWS.map((row, i) => (
          <motion.li
            key={row.q}
            {...rise}
            transition={{ duration: 0.4, delay: 0.2 + i * 0.09, ease: [0.4, 0, 0.2, 1] }}
          >
            <span className="qn">{row.q}</span>
            <Handwriting lines={row.lines} seed={row.seed} slip={row.slip} />
            <span className={`mk ${row.tone}`}>
              {row.tone === 'good' && <Tick />}
              {row.mark}
            </span>
          </motion.li>
        ))}
      </ul>

      <motion.p
        className="pg-note"
        {...rise}
        transition={{ duration: 0.45, delay: 0.85, ease: [0.4, 0, 0.2, 1] }}
      >
        Q2 — right method, arithmetic slip in the last line. Show the substitution next time.
      </motion.p>
    </div>
  );
}
