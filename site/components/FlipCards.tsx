'use client';

import { useRef } from 'react';
import { motion, useMotionValue, useMotionValueEvent, useScroll, useSpring, useTransform } from 'framer-motion';
import { FLIP_CARDS, type FlipCard } from '../lib/content';
import { FreeBody, PenLoop, Tick } from './Ink';
import { MarkedPaper } from './MarkedPaper';
import { useReducedMotionSafe } from './useMedia';

/* ==========================================================================
   Flip cards.

   One face is what the student wrote. The other is what came back: the mark,
   the quarter mark, the reason for the deduction and the feedback. The flip
   is scroll-earned rather than timed - the card turns over, once, as it
   crosses the viewport, at a spring's pace, and a turned card stays turned -
   and each card in a row is offset slightly so a row cascades instead of
   snapping in unison.

   Under `prefers-reduced-motion` the two faces cannot occupy the same box, so
   the CSS stacks them: the answer, then what came back, both fully readable
   with no rotation at all. The inline rotation this file writes is overruled
   there by `!important`, and the hook additionally pins the rotation to a
   literal 0 - a literal rather than an absent style prop, because dropping the
   prop would leave whatever the animation had last written on the element.
   ========================================================================== */

export function FlipCards() {
  return (
    <section className="s s--tint" id="marking" aria-labelledby="h-flip">
      <div className="wrap">
        <p className="kicker">Turn one over</p>

        <div className="head head--wide">
          <h2 id="h-flip">Real marking, not a vibe check</h2>
          <p className="sub">
            Every card is one question. The front is what the student wrote; the back is what came
            back — the mark, the quarter mark, the reason for the deduction, and something to do
            differently. You can change any of it.
          </p>
        </div>

        {/* One whole paper first, then one question of it turned over. */}
        {/* The paper, and beside it a key to what the red pen on it means. */}
        <div className="marking-lead">
          <figure className="illo marking-paper">
            <MarkedPaper />
            <figcaption>
              An illustration of one whole marked paper — half and quarter marks down the page, the
              slip on Q2 underlined and corrected. Not a screenshot.
            </figcaption>
          </figure>

          <aside className="pen-key" aria-labelledby="h-pen-key">
            <h3 id="h-pen-key">Reading the red pen</h3>
            <ul>
              <li>
                <span className="pen-key-mark" aria-hidden="true">
                  <span className="pen pen-key-ring">
                    <PenLoop seed={2} />
                    3¾
                  </span>
                </span>
                <p>
                  <b>A mark for every question.</b> Half and quarter marks, the way you would give
                  them, not a single score at the end.
                </p>
              </li>
              <li>
                <span className="pen-key-mark" aria-hidden="true">
                  <span className="bp slip">8x − 3</span>
                </span>
                <p>
                  <b>The line where it went wrong.</b> Underlined, so the student sees exactly where
                  the working slipped.
                </p>
              </li>
              <li>
                <span className="pen-key-mark" aria-hidden="true">
                  <span className="bp">
                    <span className="xout">3</span>
                  </span>
                  <span className="pen sheet-fix">12</span>
                </span>
                <p>
                  <b>The fix, written in.</b> The wrong value struck out and the right one beside it.
                </p>
              </li>
              <li>
                <span className="pen-key-mark" aria-hidden="true">
                  <span className="pen pen-key-note">Show the substitution.</span>
                </span>
                <p>
                  <b>One thing to do next time.</b> Feedback a student can act on, not just a grade.
                </p>
              </li>
            </ul>
            <p className="pen-key-foot">
              Green is the student’s pen. Red is what comes back — and you can change any of it.
            </p>
          </aside>
        </div>

        <figure className="illo">
          <div className="flip-grid">
            {FLIP_CARDS.map((card, i) => (
              <Card key={card.id} card={card} index={i} />
            ))}
          </div>
          <figcaption>
            Illustrations of marked answers, not screenshots. Half and quarter marks, a written
            reason for every deduction, and a question handed back rather than guessed at.
          </figcaption>
        </figure>

        <p className="more">
          <strong>Also in the app:</strong> answer keys, scanned once or learned from the first
          paper of a stack · Ontario KTCA categories and curriculum expectations for your region ·
          gradebook CSV and Google Drive export · drafted quizzes, worksheets and lesson plans.
        </p>
      </div>
    </section>
  );
}

function Card({ card, index }: { card: FlipCard; index: number }) {
  const ref = useRef<HTMLDivElement>(null);
  const reduced = useReducedMotionSafe();

  const { scrollYProgress } = useScroll({
    target: ref,
    // The whole lower two-thirds of the viewport, so the turn spends real
    // scroll distance turning. The old window was a third as deep, which on
    // one wheel-flick meant the card had already snapped over.
    offset: ['start 0.98', 'start 0.22'],
  });

  // The card holds its answer face until it is well inside the viewport, then
  // turns; each card in a row starts a little after the one before it. The
  // spring is what stops a fast scroll reading as an instant snap: however
  // hard the wheel is flicked, the card itself turns at a paper pace and
  // settles, instead of teleporting to its end state.
  //
  // And it turns ONCE. The rotation used to track the scroll in both
  // directions, so reading up and down the page spun the cards over and
  // over like a lark — the latch keeps the largest angle the scroll has
  // earned, and a turned card stays turned.
  const lead = Math.min(index, 3) * 0.045;
  const raw = useTransform(scrollYProgress, [0.12 + lead, 0.92 + lead], [0, 180]);
  const latched = useMotionValue(0);
  useMotionValueEvent(raw, 'change', (v) => {
    if (v > latched.get()) latched.set(v);
  });
  const rotateY = useSpring(latched, { stiffness: 60, damping: 26, mass: 1, restDelta: 0.01 });

  return (
    <div className="flip" ref={ref}>
      <motion.div className="flip-inner" style={{ rotateY: reduced ? 0 : rotateY }}>
        {/* The front is a piece cut from the subject's printed test: its
            running header, the numbered question with its marks, and the
            student's answer written on the printed answer lines. */}
        <div className="flip-face flip-face--front">
          <div className="icard tpiece">
            <p className="tpiece-test">{card.test}</p>
            <div className="tpiece-q">
              <span className="tpiece-n">{card.number}</span>
              <p className="tpiece-prompt">
                {card.prompt}
                {card.given && <span className="tpiece-given">{card.given}</span>}
              </p>
              <span className="tpiece-marks">{card.marks}</span>
            </div>
            {card.diagram === 'free-body' ? (
              <div className="tpiece-box">
                <FreeBody />
                <span className="sr-only">{card.answer.join(' ')}</span>
                <span className="tpiece-hint">Label every force.</span>
              </div>
            ) : (
              <div className="tpiece-lines">
                {card.answer.map((line, i) => (
                  <span key={line} className={`bp${card.slip === i ? ' slip' : ''}`}>
                    {line}
                    {card.tone === 'good' && i === card.answer.length - 1 && <Tick className="pen-tick" />}
                  </span>
                ))}
              </div>
            )}
            <p className="pen flip-hint" aria-hidden="true">turn over →</p>
          </div>
        </div>

        {/* The back is the other side of the same piece: the mark ringed in red pen, the
            reason in the same pen, and the feedback on a sticky note. A
            question the model will not guess at gets the teacher's stamp. */}
        <div className="flip-face flip-face--back">
          <div className="icard">
            <span className="flip-sub">{card.subject} · what came back</span>
            {card.tone === 'ask' ? (
              <p className="stamp">
                Teacher
                <br />
                to mark
              </p>
            ) : (
              <p className="icard-mark">
                <span className="icard-mark-n">
                  <PenLoop seed={index + 2} />
                  {card.mark}
                </span>
                {card.outOf && <span className="icard-mark-of">{card.outOf}</span>}
              </p>
            )}
            <p className="pen flip-reason">{card.reason}</p>
            {card.tone === 'ask' ? (
              <p className="sr-only">{card.feedback}</p>
            ) : (
              <p className={`sticky${index % 2 ? ' sticky--left' : ''}`}>{card.feedback}</p>
            )}
          </div>
        </div>
      </motion.div>
    </div>
  );
}
