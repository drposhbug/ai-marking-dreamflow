import type { Metadata, Viewport } from 'next';
import './globals.css';

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
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
