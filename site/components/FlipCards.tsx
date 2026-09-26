'use client';

import { useRef } from 'react';
import { motion, useMotionValue, useMotionValueEvent, useScroll, useSpring, useTransform } from 'framer-motion';
import { FLIP_CARDS, type FlipCard } from '../lib/content';
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
        <figure className="illo marking-paper">
          <MarkedPaper />
          <figcaption>
            An illustration of one whole marked paper — the name blacked out, half and quarter
            marks down the page, the slip on Q2 underlined. Not a screenshot.
          </figcaption>
        </figure>

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
  const rotateY = useSpring(latched, { stiffness: 48, damping: 38, mass: 1, restDelta: 0.01 });

  return (
    <div className="flip" ref={ref}>
      <motion.div className="flip-inner" style={{ rotateY: reduced ? 0 : rotateY }}>
        <div className="flip-face flip-face--front">
          <div className="page">
            <span className="flip-sub">{card.subject} · the answer</span>
            <p className="flip-q">{card.question}</p>
            <div className="flip-answer">
              {card.answer.map((line) => (
                <span key={line}>{line}</span>
              ))}
            </div>
            <p className="flip-hint">Keep scrolling →</p>
          </div>
        </div>

        <div className="flip-face flip-face--back">
          <div className="page">
            <span className="flip-sub">{card.subject} · what came back</span>
            <div className="flip-mark" style={{ marginTop: '.7rem' }}>
              <b className={card.tone}>{card.mark}</b>
              {card.outOf && <i>{card.outOf}</i>}
            </div>
            <p className="flip-reason">{card.reason}</p>
            <p className="flip-feedback">{card.feedback}</p>
          </div>
        </div>
      </motion.div>
    </div>
  );
}
