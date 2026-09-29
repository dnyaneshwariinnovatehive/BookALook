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

// [PLACEHOLDER] No Pricing section exists yet — this nav item scrolls to the
// salon section until a dedicated pricing section is added.
const NAV_LINKS = [
  { href: '/#for-customers', label: 'Customers' },
  { href: '/#for-salons', label: 'For Salons' },
  { href: '/#for-salons', label: 'Pricing' },
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
        {/* [PLACEHOLDER] Points at the customer-badge section for now; swap to the real
            store listing URL once the Customer App listing is live. */}
        <Link className="blk-btn blk-btn--gold blk-btn--sm" href="/#for-customers">
          Get the App
        </Link>
      </div>
    </header>
  );
}
