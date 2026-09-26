'use client';

import { useId, useRef, useState } from 'react';
import { AnimatePresence, motion } from 'framer-motion';
import { ROUTES } from '../lib/content';
import { Tick } from './Ink';
import { useReducedMotionSafe } from './useMedia';
import { RiseWords } from './RiseWords';

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
   ========================================================================== */

export function RouteTabs() {
  const [selected, setSelected] = useState(0);
  const baseId = useId();
  const tabRefs = useRef<(HTMLButtonElement | null)[]>([]);
  const reduced = useReducedMotionSafe();

  const onKeyDown = (e: React.KeyboardEvent) => {
    const last = ROUTES.length - 1;
    let next = selected;
    if (e.key === 'ArrowRight') next = selected === last ? 0 : selected + 1;
    else if (e.key === 'ArrowLeft') next = selected === 0 ? last : selected - 1;
    else if (e.key === 'Home') next = 0;
    else if (e.key === 'End') next = last;
    else return;
    e.preventDefault();
    setSelected(next);
    tabRefs.current[next]?.focus();
  };

  const route = ROUTES[selected];

  return (
    <section className="s s--dark" id="how" aria-labelledby="h-how">
      <div className="wrap">
        <p className="kicker">Times are for a class of thirty</p>

        <div className="head head--wide">
          <h2 id="h-how"><RiseWords>Four ways to mark. The fastest is the one nobody guesses.</RiseWords></h2>
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
              onClick={() => setSelected(i)}
            >
              {r.tab}
              <em>{r.minutes} min</em>
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
                {route.minutes}
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
