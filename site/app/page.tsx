import { Hero } from '../components/Hero';
import { RouteTabs } from '../components/RouteTabs';
import { PinnedSequence } from '../components/PinnedSequence';
import { FlipCards } from '../components/FlipCards';
import { Beliefs } from '../components/Beliefs';
import { Closing, Plans, Privacy, SignIn, SiteFooter, SiteHeader } from '../components/Sections';

/**
 * One page, in the order a teacher meets the product:
 *
 *   Hero            what it is, and the four real timings
 *   RouteTabs       the four routes, compared, with the timing as the number
 *   PinnedSequence  the scroll-locked walk through one class set
 *   FlipCards       one question, both sides: the answer and the marking
 *   Beliefs         the dark band - seven rules, including the awkward ones
 *   Privacy         what leaves the phone, and where the promise stops
 *   Plans           the four tiers, at the prices the app states
 *   SignIn          the handoff into the app
 *   Closing         who built it and what state it is in
 */
export default function Page() {
  return (
    <div className="desk">
      <a className="skip" href="#main">
        Skip to content
      </a>
      <div className="sheet">
        <SiteHeader />
        <main id="main">
          <Hero />
          <RouteTabs />
          <PinnedSequence />
          <FlipCards />
          <Beliefs />
          <Privacy />
          <Plans />
          <SignIn />
          <Closing />
        </main>
      </div>
      <SiteFooter />
    </div>
  );
}
