'use client';

import { motion } from 'framer-motion';
import { PenLoop, Tick } from './Ink';
import { useReducedMotionSafe } from './useMedia';

/**
 * One whole marked paper, seen from above: a photocopied, three-hole-punched
 * algebra quiz. The student's working is in green pen on the printed
 * answer lines; everything the teacher did is in red pen - a tick, a wavy
 * line under the slip with the wrong digit struck out and the right one
 * written beside it, each mark ringed in the margin, the total ringed in the
 * corner, and a note at the foot of the page.
 *
 * Mirrors the approved design in Figma ("UMarkless — realistic paper & flip
 * cards"). It is an illustration, and its caption says so.
 */

export type Line = { text: string; tick?: boolean; slip?: { wrong: string; right: string } };

/* 5 + 3¾ + 4¾ + 4 = 17½, the total ringed in the corner. Any change here has
   to keep that arithmetic true. The working is real algebra; Q2's last line
   is the slip the note at the foot calls out: 4 × −3 is −12, not −3. */
export type Question = { prompt: string; lines: Line[]; mark: string };

export const QUESTIONS: Question[] = [
  { prompt: 'Solve 3x + 5 = 20', lines: [{ text: '3x + 5 = 20' }, { text: '3x = 15  so  x = 5', tick: true }], mark: '5' },
  { prompt: 'Expand 4(2x − 3)', lines: [{ text: '4(2x − 3)' }, { text: '= 8x − ', slip: { wrong: '3', right: '12' } }], mark: '3¾' },
  { prompt: 'Factor x² + 5x + 6', lines: [{ text: 'x² + 5x + 6' }, { text: '= (x + 2)(x + 3)' }], mark: '4¾' },
  { prompt: 'Solve 2(x − 1) = x + 7', lines: [{ text: '2x − 2 = x + 7' }, { text: 'x = 9' }], mark: '4' },
];

export function MarkedPaper() {
  const reduced = useReducedMotionSafe();
  // Under reduced motion the parts still get an end state to go to, with no
  // tween: the server has already drawn them at their starting frame (faded
  // out), and a motion element with nothing to animate would stay there.
  const rise = (delay: number) => ({
    initial: { opacity: 0, y: 12 },
    animate: { opacity: 1, y: 0 },
    transition: reduced ? { duration: 0 } : { duration: 0.4, delay, ease: [0.4, 0, 0.2, 1] as const },
  });

  return (
    <div
      className="sheet"
      role="img"
      aria-label="Illustration of a marked algebra quiz. Four questions of handwritten working in green pen are marked in red down the page: a tick on question one, and on question two the last line, eight x minus three, is underlined, the three crossed out and twelve written beside it. Each mark is circled in the margin, five, three and three quarters, four and three quarters, and four, out of five. Seventeen and a half out of twenty is circled in the corner, with a note: right method, show the substitution next time."
    >
      <span className="sheet-hole" />
      <span className="sheet-hole" />
      <span className="sheet-hole" />

      <div className="sheet-head">
        <p className="sheet-kicker">Unit 3 quiz</p>
        <p className="sheet-title">Linear equations &amp; factoring</p>
        <p className="sheet-fields">
          <span>
            Name <span className="sheet-blank"><span className="bp">Alex M.</span></span>
          </span>
          <span>
            Date <span className="sheet-blank sheet-blank--short"><span className="bp">Oct 14</span></span>
          </span>
        </p>
        <p className="sheet-inst">Show all work.</p>
      </div>

      <motion.div
        className="sheet-total"
        initial={{ opacity: 0, scale: 0.92 }}
        animate={{ opacity: 1, scale: 1 }}
        transition={reduced ? { duration: 0 } : { duration: 0.45, delay: 0.7, ease: [0.34, 1.3, 0.64, 1] }}
      >
        <PenLoop seed={7} />
        <span className="sheet-total-n">17½</span>
        <span className="sheet-total-d">20</span>
      </motion.div>

      <ol className="sheet-qs">
        {QUESTIONS.map((q, i) => (
          <motion.li key={q.prompt} {...rise(0.15 + i * 0.09)}>
            <SheetQuestion n={i + 1} q={q} />
            <div className="sheet-mark">
              <span className="sheet-mark-n">
                <PenLoop seed={i + 1} />
                {q.mark}
              </span>
              <span className="sheet-mark-of">/5</span>
            </div>
          </motion.li>
        ))}
      </ol>

      <motion.p className="pen sheet-note" {...rise(0.85)}>
        Q2 — right method! 4 × −3 = −12, not −3.
        <br />
        Show the substitution next time.
      </motion.p>
    </div>
  );
}

/** One printed question and the student's working under it, on the printed
 *  answer lines - with the red pen's tick, underline and correction. */
export function SheetQuestion({ n, q }: { n: number; q: Question }) {
  return (
    <div className="sheet-q">
      <p className="sheet-prompt">
        <span>
          {n}.&nbsp;&nbsp;{q.prompt}
        </span>
        <span className="sheet-pts">(5 marks)</span>
      </p>
      {q.lines.map((line) => (
        <p key={line.text} className="sheet-line">
          {line.slip ? (
            <>
              <span className="bp slip">
                {line.text}
                <span className="xout">{line.slip.wrong}</span>
              </span>
              <span className="pen sheet-fix">{line.slip.right}</span>
            </>
          ) : (
            <span className="bp">{line.text}</span>
          )}
          {line.tick && <Tick className="pen-tick" />}
        </p>
      ))}
    </div>
  );
}
