import type { Metadata } from 'next';
import LegalDocumentView from '@/components/LegalDocumentView';
import { CANCELLATION_REFUND_POLICY } from '@/lib/legal';

export const metadata: Metadata = {
  title: 'Cancellation & Refund Policy',
  description: CANCELLATION_REFUND_POLICY.summary,
};

export default function CancellationRefundPage() {
  return <LegalDocumentView doc={CANCELLATION_REFUND_POLICY} />;
}
