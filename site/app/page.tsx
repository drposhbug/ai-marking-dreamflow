import { Hero } from '../components/Hero';
import { RouteTabs } from '../components/RouteTabs';
import { PinnedSequence } from '../components/PinnedSequence';
import { FlipCards } from '../components/FlipCards';
import { Beliefs } from '../components/Beliefs';
import { Closing, Plans, Privacy, SignIn, SiteFooter, SiteHeader } from '../components/Sections';

/**
 * One page, in the order a teacher meets the product, and one band per step.
 *
 * Every band is full-bleed: it paints its own background across the whole
 * screen and holds its words on a centred column inside itself. Nothing here
 * wraps the page in a frame, and nothing should.
 *
 * The bands alternate paper and board all the way down:
 *
 *   Hero            paper   the exam-booklet cover, and the four real timings
 *   RouteTabs       board   the four routes chalked up, timing as the number
 *   PinnedSequence  split   paper panel left, one chalk word right
 *   FlipCards       manila  one question, both sides: the answer and the marking
 *   Beliefs         board   seven rules, including the awkward ones
 *   Privacy         paper   what leaves the phone, and where the promise stops
 *   Plans           board   the four tiers, at the prices the app states
 *   SignIn          paper   the handoff into the app
 *   Closing         board   who built it and what state it is in
 */
export default function Page() {
  return (
    <>
      <a className="skip" href="#main">
        Skip to content
      </a>
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
      <SiteFooter />
    </>
  );
}
