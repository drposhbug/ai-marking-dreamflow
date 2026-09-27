'use client';

import { useEffect, useId, useRef, useState } from 'react';
import { AnimatePresence, motion } from 'framer-motion';
import { ROUTES } from '../lib/content';
import { CountUp } from './CountUp';
import { Tick } from './Ink';
import { useReducedMotionSafe } from './useMedia';

/* ==========================================================================
   The four marking routes, as a tabbed panel.

   The tab bar is its own full-bleed strip, so the rule beneath it runs the
   whole width of the screen while the tabs themselves sit on the content
   column.

   The big number is the only kind of statistic UMarkless actually has: how long
   a route takes for a class of thirty, from README.md. There are no adoption
   rates, no satisfaction scores and no hours-saved claims on this page because
   there is no measurement behind any of them.

   The tab list follows the ARIA tabs pattern: arrow keys move between tabs,
   Home and End jump to the ends, and only the selected tab is in the tab order.

   Left alone, the panel moves on to the next route once there has been time
   to read it - a thin bar fills under the tab meanwhile, so the change is
   never a surprise. It holds while the pointer is over the section or the
   section is off screen, and stops for good the moment a tab is chosen.
   ========================================================================== */

/** Roughly how long a panel takes to read: about 230 words a minute. */
function readingTime(route: (typeof ROUTES)[number]): number {
  const text = [route.title, route.bestFor, route.how, route.onDevice, ...route.steps].join(' ');
  const words = text.split(/s+/).filter(Boolean).length;
  return Math.min(18000, Math.max(10000, words * 260));
}

export function RouteTabs() {
  const [selected, setSelected] = useState(0);
  const baseId = useId();
  const tabRefs = useRef<(HTMLButtonElement | null)[]>([]);
  const reduced = useReducedMotionSafe();
  const [auto, setAuto] = useState(true);
  const [inView, setInView] = useState(false);
  const [hovering, setHovering] = useState(false);
  const sectionRef = useRef<HTMLElement>(null);

  useEffect(() => {
    const el = sectionRef.current;
    if (!el || typeof IntersectionObserver === 'undefined') return;
    const io = new IntersectionObserver(([entry]) => setInView(!!entry?.isIntersecting), { threshold: 0.35 });
    io.observe(el);
    return () => io.disconnect();
  }, []);

  const choose = (i: number) => {
    setAuto(false);
    setSelected(i);
  };
  const advance = () => setSelected((s) => (s + 1) % ROUTES.length);
  const playing = auto && inView && !hovering;

  const onKeyDown = (e: React.KeyboardEvent) => {
    const last = ROUTES.length - 1;
    let next = selected;
    if (e.key === 'ArrowRight') next = selected === last ? 0 : selected + 1;
    else if (e.key === 'ArrowLeft') next = selected === 0 ? last : selected - 1;
    else if (e.key === 'Home') next = 0;
    else if (e.key === 'End') next = last;
    else return;
    e.preventDefault();
    choose(next);
    tabRefs.current[next]?.focus();
  };

  const route = ROUTES[selected];

  return (
    <section
      className="s s--dark"
      id="how"
      aria-labelledby="h-how"
      ref={sectionRef}
      onMouseEnter={() => setHovering(true)}
      onMouseLeave={() => setHovering(false)}
    >
      <div className="wrap">
        <p className="kicker">Times are for a class of thirty</p>

        <div className="head head--wide">
          <h2 id="h-how">Four ways to mark. The fastest is the one nobody guesses.</h2>
          <p className="sub">
            Most teachers settle on two of them — one for quizzes, one for real tests on paper. Pick
            a route to see what it costs you in minutes.
          </p>
        </div>
      </div>

      <div className="tabs-strip">
        <div
          className="tabs"
          role="tablist"
          aria-label="The four marking routes"
          onKeyDown={onKeyDown}
        >
          {ROUTES.map((r, i) => (
            <button
              key={r.id}
              ref={(el) => {
                tabRefs.current[i] = el;
              }}
              type="button"
              role="tab"
              id={`${baseId}-tab-${r.id}`}
              aria-selected={selected === i}
              aria-controls={`${baseId}-panel-${r.id}`}
              tabIndex={selected === i ? 0 : -1}
              onClick={() => choose(i)}
            >
              {r.tab}
              <em>{r.minutes} min</em>
              {auto && !reduced && selected === i && (
                <span
                  key={r.id}
                  className="tab-progress"
                  aria-hidden="true"
                  style={{ animationDuration: `${readingTime(r)}ms`, animationPlayState: playing ? 'running' : 'paused' }}
                  onAnimationEnd={advance}
                />
              )}
            </button>
          ))}
        </div>
      </div>

      <div className="wrap">
        <AnimatePresence mode="wait" initial={false}>
          <motion.div
            key={route.id}
            className="tabpanel"
            role="tabpanel"
            id={`${baseId}-panel-${route.id}`}
            aria-labelledby={`${baseId}-tab-${route.id}`}
            initial={reduced ? false : { opacity: 0, y: 10 }}
            animate={reduced ? {} : { opacity: 1, y: 0 }}
            exit={reduced ? {} : { opacity: 0, y: -8 }}
            transition={{ duration: 0.22, ease: [0.4, 0, 0.2, 1] }}
          >
            <div>
              <p className="tab-time">
                <CountUp value={route.minutes} duration={900} />
                <em>min</em>
              </p>
              <p className="tab-of">for a class of thirty, start to finish</p>
            </div>

            <div>
              <h3 className="tab-title">{route.title}</h3>
              <p className="tab-best">{route.bestFor}</p>
              <p className="tab-how">{route.how}</p>
            </div>

            <div>
              <ol className="tab-steps">
                {route.steps.map((step, i) => (
                  <li key={step}>
                    <b>{String(i + 1).padStart(2, '0')}</b>
                    {step}
                  </li>
                ))}
              </ol>
              <p className="tab-device">
                <Tick />
                <span>{route.onDevice}</span>
              </p>
            </div>
          </motion.div>
        </AnimatePresence>

        <div className="first-paper">
          <Tick />
          <p>
            <strong>The first paper of a set is always marked on its own</strong> and shown to you
            before the other twenty-nine go ahead. A wrong answer key costs one paper, never thirty
            — on every plan, including free.
          </p>
        </div>
      </div>
    </section>
  );
}
