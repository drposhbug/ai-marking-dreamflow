'use client';

import { useEffect, useRef } from 'react';

/**
 * Starts a CSS-driven entrance the first time an element scrolls into view.
 *
 * The server renders nothing extra, so without JavaScript — or before it
 * runs — everything is simply there. Once mounted the element is marked
 * `data-write="pending"`, which holds its CSS animations at their first
 * frame; entering the viewport flips it to `"on"` and they play, once.
 * Under reduced motion the attribute is never set, so nothing moves.
 */
export function useWriteOn<T extends HTMLElement>(threshold = 0.25) {
  const ref = useRef<T>(null);
  useEffect(() => {
    const el = ref.current;
    if (!el || typeof IntersectionObserver === 'undefined') return;
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    // Pen strokes draw on by dashing their own length. The rings keep a
    // constant stroke width while they stretch (non-scaling-stroke), and
    // Chrome then dashes in on-screen pixels, not the path's own units - so
    // the length is scaled by how far the drawing is enlarged, or a big ring
    // shows part of itself before its turn.
    el.querySelectorAll<SVGPathElement>('.pen-loop path, .pen-tick path').forEach((p) => {
      const box = p.getBBox();
      const shown = p.getBoundingClientRect();
      const scale = Math.max(1, box.width ? shown.width / box.width : 1, box.height ? shown.height / box.height : 1);
      p.style.setProperty('--len', String(Math.ceil(p.getTotalLength() * scale * 1.05) + 4));
    });
    el.dataset.write = 'pending';
    const io = new IntersectionObserver(
      ([entry]) => {
        if (entry?.isIntersecting) {
          el.dataset.write = 'on';
          io.disconnect();
        }
      },
      { threshold, rootMargin: '0px 0px -8% 0px' },
    );
    io.observe(el);
    return () => io.disconnect();
  }, [threshold]);
  return ref;
}
