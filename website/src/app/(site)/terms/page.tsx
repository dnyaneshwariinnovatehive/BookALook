import type { Metadata } from 'next';
import LegalDocumentView from '@/components/LegalDocumentView';
import { TERMS_OF_USE } from '@/lib/legal';

export const metadata: Metadata = {
  title: 'Terms & Conditions',
  description: TERMS_OF_USE.summary,
};

export default function TermsPage() {
  return <LegalDocumentView doc={TERMS_OF_USE} />;
}
