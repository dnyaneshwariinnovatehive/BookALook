import type { Metadata } from 'next';
import LegalDocumentView from '@/components/LegalDocumentView';
import { PARTNER_TERMS } from '@/lib/legal';

export const metadata: Metadata = {
  title: 'Partner Terms & Conditions',
  description: PARTNER_TERMS.summary,
};

export default function PartnerTermsPage() {
  return <LegalDocumentView doc={PARTNER_TERMS} />;
}
