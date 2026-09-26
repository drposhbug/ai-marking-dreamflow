'use client';

import { useRef, useState } from 'react';
import { motion, useMotionValueEvent, useScroll, useSpring, useTransform, type MotionValue } from 'framer-motion';
import { STAGES } from '../lib/content';
import { Handwriting, Tick } from './Ink';
import { useNarrow, useReducedMotionSafe } from './useMedia';

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
          <h2 id="h-seq">Scan, split, mark, review, export. Then your evening.</h2>
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

function ScanVisual({ local, staticMode }: VisProps) {
  // The black bar over the name paints itself in as the stage arrives.
  const bar = useTransform(local, [0.15, 0.55], [0, 1]);
  return (
    <figure className="illo">
      <div
        className="stack-sheets"
        role="img"
        aria-label="Stylised illustration of a scanned stack: three sheets offset behind one another, the top one with its name field painted out in black and two lines of handwriting below it."
      >
        <span className="ghost" style={{ transform: 'rotate(2.2deg) translate(10px, 8px)' }} />
        <span className="ghost" style={{ transform: 'rotate(-1.4deg) translate(-6px, 5px)' }} />
        <div className="page">
          <div className="pg-top">
            <span className="field">Name</span>
            <motion.span
              className="redact"
              style={{ scaleX: staticMode ? 1 : bar, transformOrigin: '0 50%' }}
            />
            <span className="tag-ok tag-push">stays on the device</span>
          </div>
          <ul className="qlist">
            <li>
              <span className="qn">Q1</span>
              <Handwriting lines={['Je suis allé au cinéma.', 'Nous avons vu le film.']} seed={101} />
              <span className="tag-ok">uploaded</span>
            </li>
            <li>
              <span className="qn">Q2</span>
              <Handwriting lines={['C’était vraiment super.']} seed={137} />
              <span className="tag-ok">uploaded</span>
            </li>
            <li>
              <span className="qn">Q3</span>
              <Handwriting lines={['Mes amis ont aimé aussi,', 'surtout la fin du film.']} seed={173} />
              <span className="tag-ok">uploaded</span>
            </li>
            <li>
              <span className="qn">Q4</span>
              <Handwriting lines={['Nous y retournerons samedi.']} seed={199} />
              <span className="tag-ok">uploaded</span>
            </li>
          </ul>
          <p className="pg-note">30 papers · one document feeder · one PDF.</p>
        </div>
      </div>
      <figcaption>An illustration of redaction — not a screenshot, and read the limits below.</figcaption>
    </figure>
  );
}

function SplitVisual({ local, staticMode }: VisProps) {
  const codes = ['mk-7F3A-01', 'mk-7F3A-02', 'mk-7F3A-03'];
  return (
    <figure className="illo">
      <div
        className="split-grid"
        role="img"
        aria-label="Stylised illustration of a scanned stack split back into three separate papers, each labelled with its own printed code."
      >
        {codes.map((code, i) => {
          const appear = useTransform(local, [0.1 + i * 0.13, 0.38 + i * 0.13], [0, 1]);
          const lift = useTransform(local, [0.1 + i * 0.13, 0.38 + i * 0.13], [14, 0]);
          return (
            <motion.div
              key={code}
              className="page"
              style={{ opacity: staticMode ? 1 : appear, y: staticMode ? 0 : lift }}
            >
              <span className="code">{code}</span>
              {/* Three papers, three classes: a stack is where different
                  subjects genuinely sit together on one desk, so it is the
                  one illustration that should NOT be all algebra. */}
              <ul className="qlist" style={{ marginTop: '.7rem' }}>
                {[
                  ['3x = 15, so x = 5', '4(2x − 3) = 8x − 12', '2x − 2 = x + 7'],
                  ['The fog hides the truth', 'from everyone in the case,', 'and follows the lawyers.'],
                  ['Je suis allé au cinéma.', 'Nous avons vu le film,', 'c’était vraiment super.'],
                ][i % 3].map((line, li, arr) => (
                  <li key={line} style={li === arr.length - 1 ? { borderBottom: 0 } : undefined}>
                    <Handwriting lines={[line]} seed={211 + i * 53 + li} />
                  </li>
                ))}
              </ul>
              <p className="pg-note" style={{ fontSize: '.72rem' }}>page 1 of 4</p>
            </motion.div>
          );
        })}
      </div>
      <figcaption>
        An illustration of a stack reassembling by its printed codes — not a screenshot. 30 of 30
        papers found.
      </figcaption>
    </figure>
  );
}

/* One paper, so one subject — the same algebra quiz the marked-paper card
   shows, because this storyboard IS that paper being marked. The subject
   variety lives where there are several papers: the stamped stack and the
   redaction card each carry a different class's work. */
const MARK_ROWS = [
  { q: 'Q1', lines: ['3x + 5 = 20', '3x = 15, so x = 5'], mark: '5', tone: 'good' as const, seed: 311 },
  { q: 'Q2', lines: ['4(2x − 3)', '= 8x − 3'], mark: '3¾', tone: 'cut' as const, seed: 337, slip: 1 },
  { q: 'Q3', lines: ['x² + 5x + 6', '= (x + 2)(x + 3)'], mark: '4¾', tone: 'cut' as const, seed: 373 },
  { q: 'Q4', lines: ['2(x − 1) = x + 7', 'x = 9'], mark: '4', tone: 'cut' as const, seed: 397 },
];

function MarkVisual({ local, staticMode }: VisProps) {
  const total = useTransform(local, [0.72, 0.92], [0, 1]);
  const totalRotate = useTransform(local, [0.72, 0.92], [-14, -3.5]);
  return (
    <figure className="illo">
      <div
        className="page"
        role="img"
        aria-label="Stylised illustration of a paper being marked question by question, ending with a total of seventeen and a half out of twenty written in red."
      >
        <div className="pg-top">
          <span className="field">Paper 01</span>
          <span className="redact" />
          <motion.span
            className="total"
            style={{ opacity: staticMode ? 1 : total, rotate: staticMode ? -3.5 : totalRotate }}
          >
            17½<i>/20</i>
          </motion.span>
        </div>
        <ul className="qlist">
          {MARK_ROWS.map((row, i) => {
            const at = 0.12 + i * 0.15;
            const show = useTransform(local, [at, at + 0.12], [0, 1]);
            const slide = useTransform(local, [at, at + 0.12], [10, 0]);
            return (
              <li key={row.q}>
                <span className="qn">{row.q}</span>
                <Handwriting lines={row.lines} seed={row.seed} slip={row.slip} />
                <motion.span
                  className={`mk ${row.tone}`}
                  style={{ opacity: staticMode ? 1 : show, x: staticMode ? 0 : slide }}
                >
                  {row.tone === 'good' && <Tick />}
                  {row.mark}
                </motion.span>
              </li>
            );
          })}
        </ul>
        <p className="pg-note">Q2 — right method, arithmetic slip in the last line.</p>
      </div>
      <figcaption>An illustration of what comes back, not a screenshot.</figcaption>
    </figure>
  );
}

function ReviewVisual({ local, staticMode }: VisProps) {
  const override = useTransform(local, [0.25, 0.55], [0, 1]);
  return (
    <figure className="illo">
      <div
        className="page"
        role="img"
        aria-label="Stylised illustration of a review screen: a mark of three and three quarters struck through and replaced with four by the teacher, and a hand-drawn diagram flagged as requiring teacher marking."
      >
        <div className="pg-top">
          <span className="field">Review</span>
          <span className="tag-ok tag-push">override recorded</span>
        </div>
        <ul className="qlist">
          <li>
            <span className="qn">Q2</span>
            <Handwriting lines={['4(2x − 3)', '= 8x − 3']} seed={521} slip={1} />
            <span className="mk cut">
              <span className="strike">3¾</span>
              <motion.span style={{ opacity: staticMode ? 1 : override }}>4</motion.span>
            </span>
          </li>
          <li>
            <span className="qn">Q3</span>
            <Handwriting lines={['x² + 5x + 6', '= (x + 2)(x + 3)']} seed={541} />
            <span className="mk cut">4¾</span>
          </li>
          <li>
            <span className="qn">Q7</span>
            <Handwriting lines={['— hand-drawn diagram —']} seed={563} />
            <span className="chip-ask">Asks you</span>
          </li>
        </ul>
        <p className="pg-note">Hand-drawn diagram — flagged for the teacher, not scored on a hunch.</p>
        <div className="ktca">
          <span>K 8/10</span>
          <span>T 6½/8</span>
          <span>C 5/6</span>
          <span>A 4/5</span>
        </div>
      </div>
      <figcaption>
        An illustration of an override and an Ontario KTCA breakdown. Not a screenshot.
      </figcaption>
    </figure>
  );
}

const CSV_ROWS = [
  ['01', '17½', '88%'],
  ['02', '15¾', '79%'],
  ['03', '19', '95%'],
  ['04', '12½', '63%'],
  ['05', '16¼', '81%'],
  ['06', '18½', '93%'],
];

function ExportVisual({ local, staticMode }: VisProps) {
  return (
    <figure className="illo">
      <div
        className="page"
        role="img"
        aria-label="Stylised illustration of a gradebook CSV: four rows of paper numbers, marks including halves and quarters, and percentages."
      >
        <div className="pg-top">
          <span className="field field--file">class-set.csv</span>
          <span className="tag-ok tag-push">or a Doc in Drive</span>
        </div>
        <table className="csv">
          <thead>
            <tr>
              <th scope="col">Paper</th>
              <th scope="col">Mark</th>
              <th scope="col" style={{ textAlign: 'right' }}>%</th>
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
                  <td className="num">{row[2]}</td>
                </motion.tr>
              );
            })}
          </tbody>
        </table>
        <p className="pg-note">Nothing is sent to a gradebook, a student or a parent.</p>
      </div>
      <figcaption>An illustration of a gradebook export, not a screenshot.</figcaption>
    </figure>
  );
}
