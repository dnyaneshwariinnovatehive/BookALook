import type { Metadata } from 'next';
import LegalDocumentView from '@/components/LegalDocumentView';
import { ABOUT } from '@/lib/legal';

export const metadata: Metadata = {
  title: 'About BookALook',
  description: ABOUT.summary,
};

export default function AboutPage() {
  return <LegalDocumentView doc={ABOUT} />;
}
