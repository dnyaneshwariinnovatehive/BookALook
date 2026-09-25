import Link from 'next/link';

export const metadata = {
  title: 'Privacy Policy | BookALook',
  description: 'BookALook privacy policy (placeholder)',
};

export default function PrivacyPage() {
  return (
    <main className="blk-page">
      <div className="blk-container">
        <p className="blk-section-kicker">BookALook</p>
        <h1 className="blk-section-title">Privacy Policy</h1>
        {/* [PLACEHOLDER] Placeholder Privacy Policy page — replace with the real,
            legally-reviewed policy before launch. This page exists so footer links
            never point at a 404. */}
        <div className="blk-page__body">
          <p>
            This page is a placeholder. The full BookALook privacy policy will be published here shortly.
          </p>
          <p>
            It will explain how we collect, use, and protect personal data — whether you use BookALook as a
            customer, a salon owner, staff member, or collaborator.
          </p>
          <p>
            In the meantime, privacy questions can be sent to{' '}
            <a href="mailto:hello@bookalook.in">hello@bookalook.in</a>.
          </p>
          <Link href="/">← Back to BookALook</Link>
        </div>
      </div>
    </main>
  );
}