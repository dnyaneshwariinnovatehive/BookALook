import Image from 'next/image';
import Link from 'next/link';

/**
 * The public site header.
 *
 * This used to live inline in the landing page, which meant the legal pages
 * had no navigation at all. It now sits in the `(site)` route group layout so
 * every public page gets it.
 *
 * The nav targets are absolute (`/#for-salons`, not `#for-salons`) because these
 * anchors live on the landing page. As bare fragments they resolved against
 * whatever page you were on, so "For Salons" from the Terms page would have
 * scrolled to nothing.
 */

// Written for salon owners first; customers still have their own section.
const NAV_LINKS = [
  { href: '/#features', label: 'Features' },
  { href: '/#pricing', label: 'Pricing' },
  { href: '/#get-started', label: 'Get started' },
  { href: '/#for-customers', label: 'Customers' },
  { href: '/#faq', label: 'FAQ' },
];

export default function SiteHeader() {
  return (
    <header className="blk-header">
      <div className="blk-header__inner">
        <Link href="/" className="blk-header__logo" aria-label="BookALook home">
          <Image src="/logo.png" alt="BookALook" width={150} height={42} style={{ objectFit: 'contain' }} priority />
        </Link>
        <nav className="blk-header__nav" aria-label="Primary">
          {NAV_LINKS.map((link) => (
            <Link key={link.label} className="blk-header__link" href={link.href}>
              {link.label}
            </Link>
          ))}
        </nav>
        <Link className="blk-btn blk-btn--gold blk-btn--sm" href="/#enquiry-section">
          Register your salon
        </Link>
      </div>
    </header>
  );
}
