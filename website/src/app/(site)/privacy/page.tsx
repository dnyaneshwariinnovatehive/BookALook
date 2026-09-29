import type { Metadata } from 'next';
import LegalDocumentView from '@/components/LegalDocumentView';
import { PRIVACY_POLICY } from '@/lib/legal';

export const metadata: Metadata = {
  title: 'Privacy Policy',
  description: PRIVACY_POLICY.summary,
};

export default function PrivacyPage() {
  return <LegalDocumentView doc={PRIVACY_POLICY} />;
}
