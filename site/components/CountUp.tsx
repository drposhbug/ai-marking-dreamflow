'use client';

import { useEffect, useRef, useState } from 'react';

/**
 * A number that counts up to itself the first time it is seen - "~15"
 * runs ~0, ~1 ... ~15 over about a second, easing out as it lands.
 *
 * The server renders the final value, so without JavaScript, or under
 * reduced motion, the number is simply there. [value] may carry a prefix
 * such as "~"; only the digits count.
 */
export function CountUp({ value, duration = 1100 }: { value: string; duration?: number }) {
  const match = /^(\D*)(\d+)(.*)$/.exec(value);
  const prefix = match?.[1] ?? '';
  const target = match ? Number(match[2]) : 0;
  const suffix = match?.[3] ?? '';
  const [shown, setShown] = useState(target);
  const ref = useRef<HTMLSpanElement>(null);

  useEffect(() => {
    const el = ref.current;
    if (!match || !el || typeof IntersectionObserver === 'undefined') return;
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    let raf = 0;
    setShown(0);
    const run = () => {
      const start = performance.now();
      const tick = (now: number) => {
        const t = Math.min(1, (now - start) / duration);
        setShown(Math.round(target * (1 - Math.pow(1 - t, 3))));
        if (t < 1) raf = requestAnimationFrame(tick);
      };
      raf = requestAnimationFrame(tick);
    };
    const io = new IntersectionObserver(
      ([entry]) => {
        if (entry?.isIntersecting) {
          io.disconnect();
          run();
        }
      },
      { threshold: 0.6 },
    );
    io.observe(el);
    return () => {
      io.disconnect();
      cancelAnimationFrame(raf);
    };
    // Re-runs when the value changes, so a new tab counts up to its own number.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [value, duration]);

  return (
    <span ref={ref} className="count-up">
      {/* Screen readers get the real value once, not every frame of the count. */}
      <span aria-hidden="true">
        {prefix}
        {shown}
        {suffix}
      </span>
      <span className="sr-only">{value}</span>
    </span>
  );
}
