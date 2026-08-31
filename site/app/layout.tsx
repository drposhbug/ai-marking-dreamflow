import type { Metadata, Viewport } from 'next';
import { IBM_Plex_Mono, Inter } from 'next/font/google';
import './globals.css';

/* next/font fetches and self-hosts these at build time, so the static export
   carries the files and a visitor's browser never asks Google for a font. */
const sans = Inter({
  subsets: ['latin'],
  display: 'swap',
  weight: ['400', '500', '600', '700'],
  variable: '--font-sans',
});
const mono = IBM_Plex_Mono({
  subsets: ['latin'],
  display: 'swap',
  weight: ['400', '500', '600', '700'],
  variable: '--font-mono',
});

const SITE = 'https://drposhbug.github.io/ai-marking-dreamflow/';
const BP = process.env.NEXT_PUBLIC_BASE_PATH ?? '';

const TITLE = 'Markless — mark a class set in minutes, with real feedback';
const DESCRIPTION =
  'Markless takes the first pass at marking. Import a Google Form or scan a stack of paper and get question-by-question marks, a justification for every deduction, and feedback students will read. Student names are blacked out on the phone before anything is uploaded.';

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
    siteName: 'Markless',
    url: SITE,
    title: TITLE,
    description:
      'Marking eats your evenings. Markless takes the first pass: question-by-question marks, a justification for every deduction, and feedback students will read. The teacher decides the grade.',
    images: [{ url: `${SITE}icon.png`, alt: 'The Markless app icon.' }],
  },
  twitter: {
    card: 'summary',
    title: TITLE,
    description:
      'Marking eats your evenings. Markless takes the first pass: question-by-question marks, a justification for every deduction, and feedback students will read. The teacher decides the grade.',
    images: [{ url: `${SITE}icon.png`, alt: 'The Markless app icon.' }],
  },
};

export const viewport: Viewport = {
  themeColor: '#2563EB',
  width: 'device-width',
  initialScale: 1,
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${sans.variable} ${mono.variable}`}>
      <body>{children}</body>
    </html>
  );
}
