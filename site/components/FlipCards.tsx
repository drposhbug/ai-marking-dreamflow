'use client';

import { useRef } from 'react';
import { motion, useScroll, useTransform } from 'framer-motion';
import { FLIP_CARDS, type FlipCard } from '../lib/content';
import { useReducedMotionSafe } from './useMedia';

/* ==========================================================================
   Flip cards.

   One face is what the student wrote. The other is what came back: the mark,
   the quarter mark, the reason for the deduction and the feedback. The flip is
   scroll-linked rather than timed - the card turns over as it crosses the
   viewport, and turns back if you scroll up - and each card in a row is offset
   slightly so a row cascades instead of snapping in unison.

   Under `prefers-reduced-motion` the two faces cannot occupy the same box, so
   the CSS stacks them: the answer, then what came back, both fully readable
   with no rotation at all. The inline rotation this file writes is overruled
   there by `!important`, and the hook additionally pins the rotation to a
   literal 0 - a literal rather than an absent style prop, because dropping the
   prop would leave whatever the animation had last written on the element.
   ========================================================================== */

export function FlipCards() {
  return (
    <section className="band row" id="marking" aria-labelledby="h-flip">
      <p className="note-margin">Turn one over.</p>

      <div className="head head--wide">
        <h2 id="h-flip">Real marking, not a vibe check</h2>
        <p className="sub">
          Every card is one question. The front is what the student wrote; the back is what came
          back — the mark, the quarter mark, the reason for the deduction, and something to do
          differently. You can change any of it.
        </p>
      </div>

      <figure className="illo">
        <div className="flip-grid">
          {FLIP_CARDS.map((card, i) => (
            <Card key={card.id} card={card} index={i} />
          ))}
        </div>
        <figcaption>
          Illustrations of marked answers, not screenshots. Half and quarter marks, a written reason
          for every deduction, and a question handed back rather than guessed at.
        </figcaption>
      </figure>

      <p className="more">
        <strong>Also in the app:</strong> answer keys, scanned once or learned from the first paper
        of a stack · Ontario KTCA categories and curriculum expectations for your region · gradebook
        CSV and Google Drive export · drafted quizzes, worksheets and lesson plans.
      </p>
    </section>
  );
}

function Card({ card, index }: { card: FlipCard; index: number }) {
  const ref = useRef<HTMLDivElement>(null);
  const reduced = useReducedMotionSafe();

  const { scrollYProgress } = useScroll({
    target: ref,
    offset: ['start 0.92', 'start 0.3'],
  });

  // The card holds its answer face until it is well inside the viewport, then
  // turns; each card in a row starts a little after the one before it.
  const lead = Math.min(index, 3) * 0.045;
  const rotateY = useTransform(scrollYProgress, [0.3 + lead, 0.86 + lead], [0, 180]);

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
