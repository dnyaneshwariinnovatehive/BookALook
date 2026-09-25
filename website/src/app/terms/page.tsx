import Link from 'next/link';

export const metadata = {
  title: 'Terms & Conditions | BookALook',
  description: 'BookALook terms and conditions (placeholder)',
};

export default function TermsPage() {
  return (
    <main className="blk-page">
      <div className="blk-container">
        <p className="blk-section-kicker">BookALook</p>
        <h1 className="blk-section-title">Terms &amp; Conditions</h1>
        {/* [PLACEHOLDER] Placeholder Terms page — replace with the real,
            legally-reviewed terms before launch. This page exists so footer links
            never point at a 404. */}
        <div className="blk-page__body">
          <p>
            This page is a placeholder. The full BookALook terms and conditions will be published here shortly.
          </p>
          <p>
            They will cover how bookings, advance payments, cancellations, and payouts work for customers,
            salons, staff, and collaborators.
          </p>
          <p>
            In the meantime, questions about terms can be sent to{' '}
            <a href="mailto:hello@bookalook.in">hello@bookalook.in</a>.
          </p>
          <Link href="/">← Back to BookALook</Link>
        </div>
      </div>
    </main>
  );
}