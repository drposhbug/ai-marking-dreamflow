'use client';

import { motion } from 'framer-motion';
import { useReducedMotionSafe } from './useMedia';

/**
 * A block that arrives from below the first time it comes into view. It is the
 * quietest effect on the page and the only one applied to plain text, so it is
 * also the one that matters least: under `prefers-reduced-motion` the `.reveal`
 * rule in globals.css pins it to opacity 1 with no transform, and the hook
 * stops the animation being written at all.
 */

const ENTER = {
  initial: { opacity: 0, y: 16 },
  whileInView: { opacity: 1, y: 0 },
  viewport: { once: true, amount: 0.25, margin: '0px 0px -8% 0px' },
} as const;

type Props = { children: React.ReactNode; delay?: number; className?: string };

export function Reveal({ children, delay = 0, className }: Props) {
  const reduced = useReducedMotionSafe();
  if (reduced) return <div className={className}>{children}</div>;
  return (
    <motion.div
      className={`reveal ${className ?? ''}`.trim()}
      {...ENTER}
      transition={{ duration: 0.5, delay, ease: [0.4, 0, 0.2, 1] }}
    >
      {children}
    </motion.div>
  );
}

export function RevealItem({ children, delay = 0, className }: Props) {
  const reduced = useReducedMotionSafe();
  if (reduced) return <li className={className}>{children}</li>;
  return (
    <motion.li
      className={`reveal ${className ?? ''}`.trim()}
      {...ENTER}
      transition={{ duration: 0.5, delay, ease: [0.4, 0, 0.2, 1] }}
    >
      {children}
    </motion.li>
  );
}
