'use client';

import { useEffect, useState } from 'react';

/**
 * A media query as React state. It reports `false` during the server render and
 * the first paint, then the truth.
 *
 * That is safe here because the stylesheet already neutralises every scroll
 * effect inside `@media (prefers-reduced-motion: reduce)` and below 62rem, with
 * `!important` so it beats the inline styles the animation writes. This hook
 * only stops the JavaScript from doing work the CSS has already overruled - it
 * is never the only thing standing between a reader and a moving page.
 */
export function useMedia(query: string) {
  const [matches, setMatches] = useState(false);

  useEffect(() => {
    const mq = window.matchMedia(query);
    const update = () => setMatches(mq.matches);
    update();
    mq.addEventListener('change', update);
    return () => mq.removeEventListener('change', update);
  }, [query]);

  return matches;
}

export const useReducedMotionSafe = () => useMedia('(prefers-reduced-motion: reduce)');

/** Pinning a section is wrong on a phone and on a touch tablet: the CSS drops
 *  it below 62rem, and so does the JavaScript. */
export const useNarrow = () => useMedia('(max-width: 61.99rem)');
