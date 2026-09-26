'use client';

import { useEffect, useRef } from 'react';
import { useReducedMotionSafe } from './useMedia';

const DESCRIPTION =
  'A rendered illustration of a marked class set of algebra quizzes being flipped through, page by page, onto a done pile. Each paper shows a different student’s working with the teacher’s red ticks, a comment naming any mistake, and a circled score in the Total box.';

/**
 * A marked class set being flipped through, rendered in Blender
 * (site/art/class-set.blend) and played once: six pages turn onto a done
 * pile, then it settles on the next marked paper.
 *
 * The quizzes are real type (site/art/worksheet.html), not grey bars
 * standing in for writing, and every answer and mark is correct algebra
 * across three different students' scripts — 17, 20 and 16 out of 20 are
 * what those answers actually earn.
 *
 * The frames have a transparent background, so the pile sits on the page's
 * own paper: the WebM carries the alpha, and the MP4 fallback (H.264 has no
 * alpha) bakes the same cream underneath instead.
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
        poster="art/class-set-start.webp"
        width={1400}
        height={980}
        aria-label={DESCRIPTION}
      >
        <source src="art/class-set.webm" type="video/webm" />
        <source src="art/class-set.mp4" type="video/mp4" />
      </video>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        className="render-still"
        src="art/class-set-end.webp"
        width={1400}
        height={980}
        alt={DESCRIPTION}
      />
    </div>
  );
}
