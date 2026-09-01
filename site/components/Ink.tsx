/**
 * The drawing primitives the illustrations are made of: a line of handwriting
 * and a green tick.
 *
 * Everything here is deterministic. The "random" wobble comes from a seeded
 * generator, so the server and the browser draw the same path and hydration
 * does not blink.
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

/**
 * A wobbly line that reads as handwriting.
 *
 * The SVG is stretched to the column with preserveAspectRatio="none", so a wave
 * count fixed in viewBox units flattens out into a long ripple on a 2557px
 * monitor. The segment count therefore scales with the line's length, which
 * keeps the stroke rhythm roughly constant however wide the page gets.
 */
export function scribblePath(seed: number, widthPct: number, segs = Math.max(12, Math.round(widthPct / 3.4))) {
  const rand = mulberry32(seed);
  const step = (widthPct - 1.2) / segs;
  let d = 'M 0.6 5.6';
  for (let i = 0; i < segs; i += 1) {
    const x0 = 0.6 + i * step;
    const x1 = 0.6 + (i + 1) * step;
    const up = i % 2 === 0;
    const cy = up ? 1.5 + rand() * 1.7 : 6.3 + rand() * 1.5;
    const my = 5.2 + (rand() - 0.5) * 1.3;
    d += ` Q ${((x0 + x1) / 2).toFixed(2)} ${cy.toFixed(2)} ${x1.toFixed(2)} ${my.toFixed(2)}`;
  }
  return d;
}

type HandwritingProps = {
  /** Line widths as percentages of the column. One path per line. */
  lines: number[];
  seed: number;
  /** Index of the line the red pen is under, if any. */
  slip?: number;
};

/** Two or three lines of stylised handwriting, optionally with one underlined. */
export function Handwriting({ lines, seed, slip }: HandwritingProps) {
  const lineH = 12;
  const height = lines.length * lineH;
  return (
    <span className="hw">
      <svg
        viewBox={`0 0 100 ${height}`}
        preserveAspectRatio="none"
        aria-hidden="true"
        focusable="false"
        style={{ height: `${lines.length * 0.7}rem` }}
      >
        {lines.map((w, i) => (
          <g key={i} transform={`translate(0 ${i * lineH})`}>
            <path d={scribblePath(seed + i * 977, w)} vectorEffect="non-scaling-stroke" />
            {slip === i && (
              <path
                className="mark-slip"
                d={`M 1 9.6 Q ${w * 0.3} 8.4 ${w * 0.55} 9.7 T ${w * 0.94} 9.2`}
                vectorEffect="non-scaling-stroke"
              />
            )}
          </g>
        ))}
      </svg>
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
