/**
 * The drawing primitives the illustrations are made of: a line of a
 * student's handwriting and a green tick.
 *
 * Handwriting used to be a wobbly SVG stroke standing in for words. It is
 * real words now, set in a handwriting face — a squiggle where writing
 * should be is the fastest way for a page about real marking to look fake.
 * Call sites that say what the line reads pass the string; older call sites
 * that only ever said how long the line was get real algebra from a seeded
 * bank instead, so the server and the browser always agree on the words and
 * hydration does not blink.
 */

function mulberry32(seed: number) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/* Lines of working from the same quiz the rendered class set is marked on
   (site/art/worksheet.html) — all of it true algebra, so whichever lines a
   seed happens to pick, a maths teacher finds nothing to wince at. */
const WORKING = [
  '3x + 5 = 20',
  '3x = 15, so x = 5',
  '4(2x − 3) = 8x − 12',
  'x² + 5x + 6',
  '= (x + 2)(x + 3)',
  'check: 2 × 3 = 6, 2 + 3 = 5',
  '2(x − 1) = x + 7',
  '2x − 2 = x + 7, x = 9',
  '6x² ÷ 3x = 2x',
];

type HandwritingProps = {
  /** What each line reads. A number (the old API's width) draws a line of
   *  real working from the bank instead. */
  lines: (string | number)[];
  seed: number;
  /** Index of the line the red pen is under, if any. */
  slip?: number;
};

/** Two or three lines of a student's handwriting, optionally with one
 *  underlined in red. */
export function Handwriting({ lines, seed, slip }: HandwritingProps) {
  const rand = mulberry32(seed);
  return (
    <span className="hw" aria-hidden="true">
      {lines.map((line, i) => {
        const text = typeof line === 'string' ? line : WORKING[Math.floor(rand() * WORKING.length)];
        return (
          <span key={i} className={`hw-line${slip === i ? ' hw-line--slip' : ''}`}>
            {text}
          </span>
        );
      })}
    </span>
  );
}

export function Tick({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      viewBox="0 0 16 16"
      strokeWidth="2.4"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      <path d="M2.5 8.8 6 12.5 13.5 3.5" />
    </svg>
  );
}
