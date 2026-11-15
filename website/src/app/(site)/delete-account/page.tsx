import type { Metadata } from 'next';
import LegalDocumentView from '@/components/LegalDocumentView';
import { ACCOUNT_DELETION } from '@/lib/legal';

export const metadata: Metadata = {
  title: 'Delete Your Account',
  description: ACCOUNT_DELETION.summary,
};

export default function DeleteAccountPage() {
  return <LegalDocumentView doc={ACCOUNT_DELETION} />;
}
