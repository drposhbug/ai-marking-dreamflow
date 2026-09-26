'use client';

import { useRef } from 'react';
import { motion, useMotionValue, useMotionValueEvent, useScroll, useSpring, useTransform } from 'framer-motion';
import { FLIP_CARDS, type FlipCard } from '../lib/content';
import { PenLoop, Tick } from './Ink';
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
            An illustration of one whole marked paper — half and quarter marks down the page, the
            slip on Q2 underlined and corrected. Not a screenshot.
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
  const rotateY = useSpring(latched, { stiffness: 60, damping: 26, mass: 1, restDelta: 0.01 });

  return (
    <div className="flip" ref={ref}>
      <motion.div className="flip-inner" style={{ rotateY: reduced ? 0 : rotateY }}>
        {/* The front is a ruled index card: the question printed above the red
            line, the answer in the student's ballpoint on the rules below it. */}
        <div className="flip-face flip-face--front">
          <div className="icard icard--ruled">
            <div className="icard-head">
              <span className="flip-sub">{card.subject}</span>
              <p className="flip-q">{card.question}</p>
            </div>
            <div className="icard-lines">
              {card.diagram === 'free-body' ? (
                <>
                  <FreeBody />
                  <span className="sr-only">{card.answer.join(' ')}</span>
                </>
              ) : (
                card.answer.map((line, i) => (
                  <span key={line} className={`bp${card.slip === i ? ' slip' : ''}`}>
                    {line}
                    {card.tone === 'good' && i === card.answer.length - 1 && <Tick className="pen-tick" />}
                  </span>
                ))
              )}
            </div>
            <p className="pen flip-hint" aria-hidden="true">turn over →</p>
          </div>
        </div>

        {/* The back is the card's blank side: the mark ringed in red pen, the
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

/** The physics answer, drawn the way a student draws it in ballpoint: a block
 *  on the floor and four forces leaving its edges - normal up, weight down,
 *  the push to the right, friction to the left. */
function FreeBody() {
  return (
    <svg className="fbd" viewBox="0 0 270 220" aria-hidden="true" focusable="false">
      <g fill="none" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <path d="M90 80 L180 81 L179 142 L91 141 Z" />
        <path d="M24 143 L250 145" strokeWidth="1.6" />
        <path d="M135 78 L136 18 M128 28 L136 17 L144 29" />
        <path d="M135 144 L134 204 M127 194 L134 205 L141 195" />
        <path d="M181 111 L251 110 M241 103 L252 110 L242 118" />
        <path d="M89 113 L31 114 M41 106 L30 114 L40 121" />
      </g>
      <g className="fbd-label">
        <text x="146" y="30">N</text>
        <text x="143" y="210">mg</text>
        <text x="236" y="98">F</text>
        <text x="34" y="100">f</text>
      </g>
    </svg>
  );
}
