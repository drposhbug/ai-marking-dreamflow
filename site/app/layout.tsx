import type { Metadata, Viewport } from 'next';
import { Besley, Caveat, Courier_Prime, Public_Sans } from 'next/font/google';
import './globals.css';

/* next/font fetches and self-hosts these at build time, so the static export
   carries the files and a visitor's browser never asks Google for a font.

   The three faces are the three instruments a mark actually passes through:
     Besley        - a Clarendon, the letterform of school primers and report
                     cards. Display headings, and the pen-written marks.
     Public Sans   - the plain civic sans of official documents. Body text.
     Courier Prime - the school-office typewriter. Labels, codes, the CSV,
                     the counters. */
const display = Besley({
  subsets: ['latin'],
  display: 'swap',
  style: ['normal', 'italic'],
  variable: '--font-display',
});
const sans = Public_Sans({
  subsets: ['latin'],
  display: 'swap',
  style: ['normal', 'italic'],
  variable: '--font-sans',
});
const mono = Courier_Prime({
  subsets: ['latin'],
  display: 'swap',
  weight: ['400', '700'],
  variable: '--font-mono',
});
/* The fourth instrument: the student's own hand. The illustrations used to
   fake handwriting with wobbly SVG strokes; they write real working now, and
   real words need a real handwriting face. */
const hand = Caveat({
  subsets: ['latin'],
  display: 'swap',
  weight: ['500', '600'],
  variable: '--font-hand',
});

// Where this build will actually be served from. Absolute, because canonical
// URLs and link-preview images cannot be relative — a share card that points
// at a host the site is not on is a 404 in someone else's timeline.
//
// Defaults to app.umarkless.com, the production home; set MARKLESS_SITE_URL to
// build for any other host. Trailing slash enforced here so callers do not
// have to remember it.
const SITE = (() => {
  const raw = (process.env.MARKLESS_SITE_URL ?? '').trim();
  const url = raw === '' ? 'https://app.umarkless.com/' : raw;
  return url.endsWith('/') ? url : `${url}/`;
})();
const BP = process.env.NEXT_PUBLIC_BASE_PATH ?? '';

const TITLE = 'UMarkless — mark a class set in minutes, with real feedback';
const DESCRIPTION =
  'UMarkless takes the first pass at marking. Import a Google Form or scan a stack of paper and get question-by-question marks, a justification for every deduction, and feedback students will read. Student names are blacked out on your own device before anything is uploaded.';

export const metadata: Metadata = {
  metadataBase: new URL(SITE),
  title: TITLE,
  description: DESCRIPTION,
  alternates: { canonical: SITE },
  icons: {
    icon: [{ url: `${BP}/icon.png`, type: 'image/png' }],
    apple: [{ url: `${BP}/icon.png` }],
  },
  openGraph: {
    type: 'website',
    siteName: 'UMarkless',
    url: SITE,
    title: TITLE,
    description:
      'Marking eats your evenings. UMarkless takes the first pass: question-by-question marks, a justification for every deduction, and feedback students will read. The teacher decides the grade.',
    images: [{ url: `${SITE}icon.png`, alt: 'The UMarkless app icon.' }],
  },
  twitter: {
    card: 'summary',
    title: TITLE,
    description:
      'Marking eats your evenings. UMarkless takes the first pass: question-by-question marks, a justification for every deduction, and feedback students will read. The teacher decides the grade.',
    images: [{ url: `${SITE}icon.png`, alt: 'The UMarkless app icon.' }],
  },
};

export const viewport: Viewport = {
  themeColor: '#143528',
  width: 'device-width',
  initialScale: 1,
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${display.variable} ${sans.variable} ${mono.variable} ${hand.variable}`}>
      <body>{children}</body>
    </html>
  );
}
