'use client';

import { useRef, useState } from 'react';
import { motion, useMotionValueEvent, useScroll, useSpring, useTransform, type MotionValue } from 'framer-motion';
import { STAGES } from '../lib/content';
import { FreeBody, PenLoop, Tick } from './Ink';
import { QUESTIONS, SheetQuestion } from './MarkedPaper';
import { useNarrow, useReducedMotionSafe } from './useMedia';
import { RiseWords } from './RiseWords';

/* ==========================================================================
   The scroll-locked sequence: one class set, from the copier to the gradebook,
   as a split screen. While pinned, the left half of the viewport is an
   exam-paper panel holding the stage's illustration and the red-pen note; the
   right half is the board, with one enormous chalk word, the stage title, and
   the body. The two surfaces are painted on `.seq-sticky` itself, so stages
   cross-fade over stable backgrounds.

   HOW THE PIN WORKS
   -----------------
   A tall `.seq-track` holds a `position: sticky` child that is exactly one
   viewport minus the header. The track is `stages x 82svh` tall on top of that,
   so while the track is passing the viewport the child stays put and the page
   keeps scrolling "through" it. `useScroll({ offset: ['start start','end end'] })`
   turns that stretch of scrolling into 0 -> 1, which is divided into five equal
   stretches, one per stage. Because the sticky child is exactly the height that
   remains after the header, progress reaches 1 at the precise scroll position
   where the child unsticks - so the section releases cleanly instead of
   sticking a frame too long or letting go early.

   Stages cross-fade over a narrow window either side of each boundary, and the
   incoming stage rises 22px as it arrives. Nothing is unmounted: all five
   stages are always in the DOM and readable by a screen reader in order, and
   none of them contains anything focusable, so there is no focus trap in the
   pinned region.

   HOW IT DEGRADES
   ---------------
   The split and the pin exist only inside
   `(min-width: 62rem) and (prefers-reduced-motion: no-preference)`. Under
   `prefers-reduced-motion: reduce`, and on any viewport under 62rem (because
   pinning is wrong on a phone), the base CSS applies instead: the track is
   `height: auto`, the sticky child is `position: static`, and the five stages
   read as five ordinary blocks down the page, in order, with a rule between
   them and the rail hidden. A reduced-motion block at the end of globals.css
   additionally forces every stage to opacity 1 with no transform, with
   `!important`, so it beats any inline style this file had already written.
   The JavaScript also stands down (`staticMode` below), so no scroll listener
   runs and no inline style is written at all. Trapping a reader who cannot
   process motion inside a 500vh pin would be a serious accessibility failure;
   the CSS rule is the guarantee and the JavaScript is the optimisation.
   ========================================================================== */

const N = STAGES.length;

/**
 * A stage is IN or it is OUT, and the fade between the two runs on time,
 * not on scroll distance.
 *
 * It used to scrub: opacity followed the scroll through a long crossfade
 * window, which meant stopping mid-window parked the screen at half a
 * stage — two ghosts, neither readable, "stuck on a fade". Now the scroll
 * only decides WHICH stage is on, and a quick spring plays the fade out to
 * completion by itself. The spans are exclusive — half-open, so a boundary
 * belongs to exactly one stage — because an overlap would let a parked
 * scroll rest with two stages both fully lit on top of each other, which
 * is the same bug wearing more opacity. Whatever the scroll position,
 * the screen settles to one whole stage.
 */
function useStageMotion(scrollYProgress: MotionValue<number>, i: number) {
  const a = i / N;
  const b = (i + 1) / N;
  const first = i === 0;
  const last = i === N - 1;

  const on = useTransform(scrollYProgress, (v): number => {
    if (first && v < b) return 1;
    if (last && v >= a) return 1;
    return v >= a && v < b ? 1 : 0;
  });
  const opacity = useSpring(on, { stiffness: 190, damping: 26, restDelta: 0.004 });
  const y = useTransform(opacity, [0, 1], [22, 0]);
  /** 0 -> 1 across this stage alone, for animation inside a visual. */
  const local = useTransform(scrollYProgress, [a, b], [0, 1]);

  return { opacity, y, local };
}

export function PinnedSequence() {
  const trackRef = useRef<HTMLDivElement>(null);
  const [active, setActive] = useState(0);

  const reduced = useReducedMotionSafe();
  const narrow = useNarrow();
  const staticMode = reduced || narrow;

  const { scrollYProgress } = useScroll({
    target: trackRef,
    offset: ['start start', 'end end'],
  });

  useMotionValueEvent(scrollYProgress, 'change', (v) => {
    const i = Math.min(N - 1, Math.max(0, Math.floor(v * N)));
    setActive((prev) => (prev === i ? prev : i));
  });

  // Hooks cannot live in a conditional, so every stage's motion values are
  // built either way; `staticMode` decides whether they are ever applied.
  // Every animated style below is passed as a literal when static rather than
  // omitted. Dropping the style prop leaves whatever the animation had already
  // written on the element, which on a phone meant an illustration stuck at
  // opacity 0 after the media query resolved.
  const stageMotion = STAGES.map((_, i) => useStageMotion(scrollYProgress, i));

  const goTo = (i: number) => {
    const el = trackRef.current;
    if (!el) return;
    const top = el.getBoundingClientRect().top + window.scrollY;
    const travel = el.offsetHeight - window.innerHeight;
    const p = (i + 0.5) / N;
    window.scrollTo({ top: top + p * travel, behavior: 'smooth' });
  };

  return (
    <section className="s s--paper s--seq" id="sequence" aria-labelledby="h-seq">
      <div className="wrap">
        <p className="kicker">One class set, start to finish</p>

        <div className="head head--wide">
          <h2 id="h-seq"><RiseWords>Scan, split, mark, review, export. Then your evening.</RiseWords></h2>
          <p className="sub">
            This is the paper route — a stack off the photocopier, thirty papers deep. Scroll and it
            moves through it one step at a time.
          </p>
        </div>
      </div>

      {/* While the track is passing, the viewport is split: the exam-paper
          panel on the left holds the stage's illustration, the board on the
          right holds one enormous chalk word and two short paragraphs. Both
          surfaces are painted once, on the sticky element, so the stages can
          cross-fade over them without the backgrounds flickering. */}
      <div
        className="seq-track"
        ref={trackRef}
        style={{ ['--seq-count' as string]: N }}
      >
        <div className="seq-sticky">
          <div className="seq-stages">
            {STAGES.map((stage, i) => (
              <motion.article
                key={stage.id}
                className="seq-stage"
                data-active={active === i}
                style={{
                  opacity: staticMode ? 1 : stageMotion[i].opacity,
                  y: staticMode ? 0 : stageMotion[i].y,
                }}
              >
                <div className="seq-half seq-half--board">
                  <div className="seq-board-in">
                    <span className="seq-n">Stage {stage.n}</span>
                    <h3 className="seq-word">{stage.label}</h3>
                    <p className="seq-lead">{stage.title}</p>
                    <p className="seq-body">{stage.body}</p>
                    <p className="seq-meta">The paper route · a class of thirty</p>
                  </div>
                </div>
                <div className="seq-half seq-half--paper">
                  <div className="seq-paper-in">
                    <StageVisual id={stage.id} local={stageMotion[i].local} staticMode={staticMode} />
                    <p className="seq-note">{stage.note}</p>
                  </div>
                </div>
              </motion.article>
            ))}
          </div>

          <div className="seq-rail">
            {STAGES.map((s, i) => (
              <button
                key={s.id}
                type="button"
                onClick={() => goTo(i)}
                aria-current={active === i}
              >
                {s.label}
              </button>
            ))}
            <span className="seq-bar" aria-hidden="true">
              <motion.i style={{ scaleX: staticMode ? 1 : scrollYProgress }} />
            </span>
            <span className="seq-count">
              {String(active + 1).padStart(2, '0')} / {String(N).padStart(2, '0')}
            </span>
          </div>
        </div>
      </div>
    </section>
  );
}

/* ----------------------------------------------------------- the visuals */

type VisProps = { local: MotionValue<number>; staticMode: boolean };

function StageVisual({ id, local, staticMode }: VisProps & { id: string }) {
  if (id === 'scan') return <ScanVisual local={local} staticMode={staticMode} />;
  if (id === 'split') return <SplitVisual local={local} staticMode={staticMode} />;
  if (id === 'mark') return <MarkVisual local={local} staticMode={staticMode} />;
  if (id === 'review') return <ReviewVisual local={local} staticMode={staticMode} />;
  return <ExportVisual local={local} staticMode={staticMode} />;
}

/* Three pupils' page ones of the same French quiz. The stack is one class,
   so the pages match; the answers are each pupil's own. */
const QUIZ_PAGES = [
  ['Je suis allé au cinéma.', 'Nous avons vu le film.', 'C’était vraiment super.'],
  ['Je suis allée au parc.', 'Avec ma sœur et Léa.', 'Il a fait très beau.'],
  ['J’ai joué au foot.', 'Avec mon équipe.', 'Nous avons gagné !'],
];
const QUIZ_PROMPTS = ['Racontez votre samedi.', 'Avec qui ?', 'C’était comment ?'];

/** Page one of the quiz as the uploaded copy has it: the name painted out,
 *  the answers in the pupil's pen, the code and page number in the footer. */
function QuizPage({
  answers,
  code,
  redact,
  ringFooter,
}: {
  answers: string[];
  code: string;
  redact?: MotionValue<number> | number;
  ringFooter?: boolean;
}) {
  return (
    <div className="sheet qpage">
      <span className="sheet-hole" />
      <span className="sheet-hole" />
      <span className="sheet-hole" />
      <p className="sheet-kicker">French 10 · Quiz 4</p>
      <p className="qpage-title">Le passé composé</p>
      <p className="qpage-name">
        Nom
        <span className="qpage-blank">
          <motion.span className="qpage-redact" style={{ scaleX: redact ?? 1, transformOrigin: '0 50%' }} />
        </span>
      </p>
      <ol className="qpage-qs">
        {QUIZ_PROMPTS.map((prompt, i) => (
          <li key={prompt}>
            <span className="qpage-prompt">{prompt}</span>
            <span className="bp qpage-line">{answers[i]}</span>
          </li>
        ))}
      </ol>
      <p className="qpage-foot">
        <span className={ringFooter ? 'qpage-ringed' : undefined}>
          {ringFooter && <PenLoop seed={5} />}
          {code} · Page 1 of 4
        </span>
      </p>
    </div>
  );
}

function ScanVisual({ local, staticMode }: VisProps) {
  // The black bar over the name paints itself in as the stage arrives.
  const bar = useTransform(local, [0.15, 0.55], [0, 1]);
  return (
    <figure className="illo">
      <div
        className="scan-stack"
        role="img"
        aria-label="Illustration of a scanned stack of French quizzes: two sheets squared up behind the top one, whose name is painted out in solid black, with a note in red pen that the name never leaves your device."
      >
        <span className="scan-under" />
        <span className="scan-under" />
        <QuizPage answers={QUIZ_PAGES[0]} code="mk-7F3A-01" redact={staticMode ? 1 : bar} />
        <p className="pen scan-note">
          <svg viewBox="0 0 90 50" aria-hidden="true" focusable="false">
            <path d="M86 4 Q46 12 14 44 M8 30 L13 45 L28 41" />
          </svg>
          the name never leaves your device
        </p>
        <p className="pen scan-count">30 papers · one feeder · one PDF</p>
      </div>
      <figcaption>An illustration of redaction — not a screenshot, and read the limits below.</figcaption>
    </figure>
  );
}

function SplitVisual({ local, staticMode }: VisProps) {
  return (
    <figure className="illo">
      <div
        className="split-row"
        role="img"
        aria-label="Illustration of the scanned stack split back into separate papers: three pupils' first pages of the same quiz, each found by the code and page number printed in its footer, circled in red pen. Thirty of thirty papers found."
      >
        {QUIZ_PAGES.map((answers, i) => {
          const appear = useTransform(local, [0.1 + i * 0.13, 0.38 + i * 0.13], [0, 1]);
          const lift = useTransform(local, [0.1 + i * 0.13, 0.38 + i * 0.13], [14, 0]);
          return (
            <motion.div
              key={answers[0]}
              className="split-page"
              style={{ opacity: staticMode ? 1 : appear, y: staticMode ? 0 : lift }}
            >
              <QuizPage answers={answers} code={`mk-7F3A-0${i + 1}`} ringFooter />
            </motion.div>
          );
        })}
        <p className="pen split-count">30 of 30 papers found</p>
      </div>
      <figcaption>
        An illustration of a stack coming apart by the codes printed on each page — not a screenshot.
      </figcaption>
    </figure>
  );
}

/* Paper 01 coming back: the same quiz sheet the marked-paper illustration
   shows, because this storyboard IS that paper being marked. The marks land
   one question at a time as the stage plays, then the total. */
function MarkVisual({ local, staticMode }: VisProps) {
  const total = useTransform(local, [0.72, 0.92], [0, 1]);
  return (
    <figure className="illo">
      <div
        className="sheet sheet--flat"
        role="img"
        aria-label="Illustration of a quiz being marked question by question in red pen: five, three and three quarters, four and three quarters and four, each circled, ending with seventeen and a half out of twenty circled at the top."
      >
        <span className="sheet-hole" />
        <span className="sheet-hole" />
        <span className="sheet-hole" />
        <div className="sheet-head">
          <p className="sheet-kicker">Unit 3 quiz</p>
          <p className="sheet-title">Linear equations &amp; factoring</p>
        </div>
        <motion.div className="sheet-total" style={{ opacity: staticMode ? 1 : total }}>
          <PenLoop seed={7} />
          <span className="sheet-total-n">17½</span>
          <span className="sheet-total-d">20</span>
        </motion.div>
        <ol className="sheet-qs">
          {QUESTIONS.map((q, i) => {
            const at = 0.12 + i * 0.15;
            const show = useTransform(local, [at, at + 0.12], [0, 1]);
            const slide = useTransform(local, [at, at + 0.12], [10, 0]);
            return (
              <li key={q.prompt}>
                <SheetQuestion n={i + 1} q={q} />
                <motion.div
                  className="sheet-mark"
                  style={{ opacity: staticMode ? 1 : show, x: staticMode ? 0 : slide }}
                >
                  <span className="sheet-mark-n">
                    <PenLoop seed={i + 1} />
                    {q.mark}
                  </span>
                  <span className="sheet-mark-of">/5</span>
                </motion.div>
              </li>
            );
          })}
        </ol>
        <p className="pen sheet-note">Q2 — right method, arithmetic slip in the last line.</p>
      </div>
      <figcaption>An illustration of what comes back, not a screenshot.</figcaption>
    </figure>
  );
}

/* The teacher's pass over the same paper: the suggested 3¾ struck through
   and 4 written beside it, initialled, with the change noted on a sticky
   note; a drawn answer stamped for the teacher; the achievement chart at the
   foot filled in by hand. */
const KTCA = [
  ['Knowledge', '8', '10'],
  ['Thinking', '6½', '8'],
  ['Communication', '5', '6'],
  ['Application', '4', '5'],
];

function ReviewVisual({ local, staticMode }: VisProps) {
  const override = useTransform(local, [0.25, 0.55], [0, 1]);
  return (
    <figure className="illo">
      <div
        className="sheet sheet--flat sheet--review"
        role="img"
        aria-label="Illustration of a teacher's review: on question two the suggested three and three quarters is crossed out and four written beside it, initialled, with a sticky note reading override recorded. A hand-drawn force diagram on question seven is stamped teacher to mark. An Ontario achievement chart at the foot reads knowledge 8 of 10, thinking 6 and a half of 8, communication 5 of 6, application 4 of 5."
      >
        <span className="sheet-hole" />
        <span className="sheet-hole" />
        <span className="sheet-hole" />
        <motion.p className="sticky review-sticky" style={{ opacity: staticMode ? 1 : override }}>
          Override recorded:
          <br />
          Q2&nbsp;&nbsp;3¾ → 4
        </motion.p>
        <p className="sheet-kicker">Unit 3 quiz</p>
        <ol className="sheet-qs">
          <li>
            <SheetQuestion n={2} q={QUESTIONS[1]} />
            <div className="sheet-mark review-mark">
              <span className="pen review-old">3¾</span>
              <motion.span className="review-new" style={{ opacity: staticMode ? 1 : override }}>
                <span className="sheet-mark-n">
                  <PenLoop seed={3} />4
                </span>
                <span className="sheet-mark-of">/5</span>
                <span className="pen review-initials">method + effort — T.M.</span>
              </motion.span>
            </div>
          </li>
          <li>
            <SheetQuestion n={3} q={QUESTIONS[2]} />
            <div className="sheet-mark">
              <span className="sheet-mark-n">
                <PenLoop seed={4} />
                {QUESTIONS[2].mark}
              </span>
              <span className="sheet-mark-of">/5</span>
            </div>
          </li>
          <li>
            <div className="sheet-q">
              <p className="sheet-prompt">
                <span>7.&nbsp;&nbsp;Sketch the forces on the block</span>
                <span className="sheet-pts">(3 marks)</span>
              </p>
              <FreeBody className="fbd--sheet" />
            </div>
            <div className="sheet-mark">
              <p className="stamp">
                Teacher
                <br />
                to mark
              </p>
            </div>
          </li>
        </ol>
        <div className="rubric">
          <p className="sheet-kicker">Achievement chart</p>
          <div className="rubric-grid">
            {KTCA.map(([k, got, of]) => (
              <p key={k} className="rubric-cell">
                <span>{k}</span>
                <span>
                  <b className="pen">{got}</b> / {of}
                </span>
              </p>
            ))}
          </div>
        </div>
      </div>
      <figcaption>
        An illustration of an override and an Ontario KTCA breakdown. Not a screenshot.
      </figcaption>
    </figure>
  );
}

/* The class set as it comes out of the printer: the CSV in the typewriter
   face, paper-clipped, each row checked off against the stack in red pen. */
const CSV_ROWS = [
  ['01', '17.5', '88'],
  ['02', '15.75', '79'],
  ['03', '19', '95'],
  ['04', '12.5', '63'],
  ['05', '16.25', '81'],
  ['06', '18.5', '93'],
];

function ExportVisual({ local, staticMode }: VisProps) {
  return (
    <figure className="illo">
      <div
        className="printout"
        role="img"
        aria-label="Illustration of a printed gradebook CSV, paper-clipped: paper numbers, marks including halves and quarters, and percentages, each row ticked in red pen, with a note that nothing is sent to a gradebook, a student or a parent."
      >
        <svg className="printout-clip" viewBox="0 0 44 92" aria-hidden="true" focusable="false">
          <path d="M10 2 L10 72 Q10 84 22 84 Q34 84 34 72 L34 14 Q34 6 26 6 Q18 6 18 14 L18 64" />
        </svg>
        <p className="printout-file">class-set.csv</p>
        <p className="printout-meta">Unit 3 quiz · printed 14 Oct · page 1 of 1</p>
        <table className="printout-table">
          <thead>
            <tr>
              <th scope="col">paper</th>
              <th scope="col">mark</th>
              <th scope="col">%</th>
              <th aria-hidden="true" />
            </tr>
          </thead>
          <tbody>
            {CSV_ROWS.map((row, i) => {
              const at = 0.12 + i * 0.16;
              const show = useTransform(local, [at, at + 0.13], [0, 1]);
              const slide = useTransform(local, [at, at + 0.13], [8, 0]);
              return (
                <motion.tr key={row[0]} style={{ opacity: staticMode ? 1 : show, x: staticMode ? 0 : slide }}>
                  <td>{row[0]}</td>
                  <td>{row[1]}</td>
                  <td>{row[2]}</td>
                  <td>
                    <Tick className="pen-tick" />
                  </td>
                </motion.tr>
              );
            })}
          </tbody>
        </table>
        <p className="printout-meta printout-foot">30 rows · columns: paper, mark, %</p>
        <p className="pen printout-note">
          Nothing is sent to a gradebook,
          <br />a student or a parent.
        </p>
      </div>
      <figcaption>An illustration of a gradebook export, not a screenshot.</figcaption>
    </figure>
  );
}
