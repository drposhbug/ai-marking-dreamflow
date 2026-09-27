'use client';

import { useEffect, useRef, useState } from 'react';
import { FLIP_CARDS, type FlipCard } from '../lib/content';
import { FreeBody, PenLoop, Tick } from './Ink';
import { MarkedPaper } from './MarkedPaper';
import { useWriteOn } from './useWriteOn';

/* ==========================================================================
   Flip cards.

   One face is what the student wrote. The other is what came back: the mark,
   the quarter mark, the reason for the deduction and the feedback. Once a
   card is well inside the viewport it turns over by itself, slowly and
   once, each a little after the one before it. After that it turns only
   when clicked, tapped or pressed (Enter or Space).

   Under `prefers-reduced-motion` the two faces cannot occupy the same box, so
   the CSS stacks them: the answer, then what came back, both fully readable
   with no rotation at all.
   ========================================================================== */

/**
 * The class summary for the quiz drawn above, as the app lays it out: worst
 * question first, how many of the thirty got it fully right, and the slip
 * that came up most on the papers that lost marks there. The class average
 * (15.7 / 20) is the sum of the per-question averages 2.9, 3.8, 4.2, 4.8.
 */
const CLASS_BARS = [
  { q: 'Q2', full: 12, error: '11 wrote 4 × −3 as −3, not −12', flag: true },
  { q: 'Q3', full: 18, error: '6 swapped the signs in a bracket' },
  { q: 'Q4', full: 22, error: '4 stopped at 2x − 2 = x + 7' },
  { q: 'Q1', full: 28, error: 'Marks came off with no single repeated slip.' },
];

export function FlipCards() {
  // One trigger for the paper and its key, so each line of the key lights up
  // as the pen reaches the mark it explains.
  const leadRef = useWriteOn<HTMLDivElement>(0.2);
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
        <div className="marking-lead" ref={leadRef}>
          <figure className="illo marking-paper">
            <MarkedPaper />
            <figcaption>
              An illustration of one whole marked paper — half and quarter marks down the page, the
              slip on Q2 underlined and corrected. Not a screenshot.
            </figcaption>
          </figure>

          <div className="marking-side">
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

          {/* What the same marks say about the whole set - the class analysis
              the app builds from a class set, drawn for this quiz. */}
          <section className="class-bars" aria-labelledby="h-class">
            <h3 id="h-class">Then, across all thirty</h3>
            <p className="class-bars-sub">
              Mark the whole set and each question shows how many students got it fully right, and
              the slip that came up most — worst first, so you know what to go over tomorrow.
            </p>
            <p className="class-bars-avg">
              Class average <b>15.7</b>
              <small> / 20</small>
            </p>
            <ul>
              {CLASS_BARS.map((b, i) => (
                <li key={b.q} className={b.flag ? 'is-flag' : undefined} style={{ '--i': i } as React.CSSProperties}>
                  <span className="class-bars-q">{b.q}</span>
                  <span className="class-bars-track">
                    <span className="class-bars-fill" style={{ width: `${(b.full / 30) * 100}%` }} />
                  </span>
                  <span className="class-bars-n">
                    {b.full}/30
                    <small> students</small>
                  </span>
                  <span className="class-bars-err">{b.error}</span>
                </li>
              ))}
            </ul>
            <p className="pen class-bars-note">Reteach Q2 tomorrow — ten minutes.</p>
          </section>

          {/* The rest of what the app does, beside the paper rather than a
              paragraph under the cards. */}
          <section className="also" aria-labelledby="h-also">
            <h3 id="h-also">Also in the app</h3>
            <ul>
              <li><b>Answer keys</b> scanned once, or learned from the first paper of a stack.</li>
              <li><b>Ontario KTCA</b> categories and curriculum expectations for your region.</li>
              <li><b>Gradebook export</b> as a CSV, or straight to Google Drive.</li>
              <li><b>Planning</b> — drafted quizzes, worksheets and lesson plans.</li>
            </ul>
          </section>
          </div>
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

      </div>
    </section>
  );
}

function Card({ card, index }: { card: FlipCard; index: number }) {
  const [turned, setTurned] = useState(false);
  const [slow, setSlow] = useState(true);
  const ref = useRef<HTMLDivElement>(null);
  const turn = () => {
    setSlow(false);
    setTurned((t) => !t);
  };

  useEffect(() => {
    const el = ref.current;
    if (!el || typeof IntersectionObserver === 'undefined') return;
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    let timer = 0;
    const io = new IntersectionObserver(
      ([entry]) => {
        if (!entry?.isIntersecting) return;
        io.disconnect();
        timer = window.setTimeout(() => setTurned(true), 500 + index * 450);
      },
      { threshold: 0.7 },
    );
    io.observe(el);
    return () => {
      io.disconnect();
      window.clearTimeout(timer);
    };
  }, [index]);

  return (
    <div
      ref={ref}
      className={`flip${turned ? ' is-turned' : ''}${slow ? ' is-slow' : ''}`}
      role="button"
      tabIndex={0}
      aria-pressed={turned}
      onClick={turn}
      onKeyDown={(e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          turn();
        }
      }}
    >
      <div className="flip-inner">
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
            <p className="pen flip-hint" aria-hidden="true">tap to turn over →</p>
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
      </div>
    </div>
  );
}
