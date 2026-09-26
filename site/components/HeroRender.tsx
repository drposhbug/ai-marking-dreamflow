'use client';

import { useEffect, useRef } from 'react';
import { useReducedMotionSafe } from './useMedia';

const DESCRIPTION =
  "A rendered illustration of a hand bringing a phone in over a student's algebra quiz lying on a desk. The phone's camera finds the page and captures it, and the screen comes back with the paper marked 17 out of 20 and the student's name hidden before upload.";

/**
 * A hand scanning a student's algebra quiz with a phone, rendered in Blender
 * (site/art/marking-scan.blend) and played once: the phone comes in, finds
 * the page, captures, and the screen comes back with the paper marked.
 *
 * The quiz is real type (site/art/worksheet.html), not grey bars standing in
 * for writing, and every answer and mark on it is correct algebra: 17/20 is
 * what those five answers actually earn.
 *
 * Once, not on a loop. A hero that moves forever is a distraction from the
 * words beside it; one that does a single thing and stops is a demonstration.
 * The video's last frame is the finished state, and a browser holds the last
 * frame when a video ends, so there is nothing to reset.
 *
 * Two things here are easy to get wrong:
 *
 * - `muted` is set on the element, not only as an attribute. React does not
 *   write `muted` into server-rendered HTML, and a browser will not autoplay a
 *   video it believes has sound — so the attribute alone leaves a static poster
 *   on the page and no error anywhere.
 *
 * - Reduced motion is honoured in the stylesheet, not just here. Before this
 *   component hydrates it cannot know the preference, so the CSS swaps the
 *   video for the settled still on its own; this only stops playback the CSS
 *   has already hidden.
 */
export function HeroRender() {
  const ref = useRef<HTMLVideoElement>(null);
  const reduced = useReducedMotionSafe();

  useEffect(() => {
    const v = ref.current;
    if (!v) return;
    v.muted = true;
    if (reduced) {
      v.pause();
      return;
    }
    // A refused autoplay (data saver, a strict browser) leaves the poster —
    // the untouched stack — which is a perfectly good picture on its own.
    v.play().catch(() => {});
  }, [reduced]);

  return (
    <div className="render-frame">
      <video
        ref={ref}
        className="render-motion"
        muted
        playsInline
        preload="auto"
        poster="art/marking-scan-start.webp"
        width={1400}
        height={980}
        aria-label={DESCRIPTION}
      >
        <source src="art/marking-scan.webm" type="video/webm" />
        <source src="art/marking-scan.mp4" type="video/mp4" />
      </video>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        className="render-still"
        src="art/marking-scan-end.webp"
        width={1400}
        height={980}
        alt={DESCRIPTION}
      />
    </div>
  );
}
