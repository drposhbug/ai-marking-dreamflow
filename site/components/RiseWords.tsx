'use client';

import type { CSSProperties } from 'react';
import { useWriteOn } from './useWriteOn';

/**
 * A heading that rises in word by word as it scrolls into view. The words
 * stay real text in one element, so it reads and copies exactly as written;
 * the spaces sit between the word spans, not inside them, because a space
 * at the end of an inline-block is dropped.
 */
export function RiseWords({ children }: { children: string }) {
  const ref = useWriteOn<HTMLSpanElement>(0.6);
  const words = children.split(' ');
  return (
    <span ref={ref} className="rise">
      {words.map((w, i) => (
        <span key={i}>
          <span className="rise-w" style={{ '--i': i } as CSSProperties}>
            {w}
          </span>
          {i < words.length - 1 ? ' ' : null}
        </span>
      ))}
    </span>
  );
}
