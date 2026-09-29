import Image from 'next/image';
import Link from 'next/link';
import StoreBadge from './StoreBadge';
import { CONTACT_ADDRESS, CONTACT_COMPANY, CONTACT_EMAIL, CUSTOMER_APP_STORE_URL, CUSTOMER_PLAY_STORE_URL, SOCIAL_URLS } from '@/lib/site-links';

/**
 * The public site footer.
 *
 * Extracted from the landing page, where it was inline and therefore invisible
 * to every other public route.
 *
 * The "Company" column is the site's only legal index, so all five approved
 * documents are linked from here. If a sixth is ever added, it belongs in that
 * list and in the `related` array of each document in `src/lib/legal.ts`.
 *
 * The year is read at render time. On a statically generated page that is build
 * time, which is why the site needs a redeploy each January — the alternative
 * was making the whole footer a client component to move a string.
 */
export default function SiteFooter() {
  return (
    <footer className="blk-footer">
      <div className="blk-container blk-footer__grid">
        <div className="blk-footer__brand">
          <Image src="/logo.png" alt="BookALook" width={150} height={42} style={{ objectFit: 'contain' }} />
          <p className="blk-footer__tag">No waiting. Just booking.</p>
        </div>
        <div className="blk-footer__col">
          <p className="blk-footer__head">Download</p>
          {/* [PLACEHOLDER] Store badge URLs — replace with the real Customer App listings. */}
          <div className="blk-footer__badges">
            <StoreBadge store="apple" url={CUSTOMER_APP_STORE_URL} label="App Store" />
            <StoreBadge store="google" url={CUSTOMER_PLAY_STORE_URL} label="Google Play" />
          </div>
        </div>
        <div className="blk-footer__col">
          <p className="blk-footer__head">Company</p>
          <Link className="blk-footer__link" href="/about">
            About BooKalook
          </Link>
          <Link className="blk-footer__link" href="/terms">
            Terms &amp; Conditions
          </Link>
          <Link className="blk-footer__link" href="/privacy">
            Privacy Policy
          </Link>
          <Link className="blk-footer__link" href="/cancellation-refund">
            Cancellation &amp; Refund
          </Link>
          <Link className="blk-footer__link" href="/partner-terms">
            Partner Terms &amp; Conditions
          </Link>
        </div>
        <div className="blk-footer__col">
          <p className="blk-footer__head">Contact</p>
          <span className="blk-footer__link">{CONTACT_COMPANY}</span>
          <span className="blk-footer__link">{CONTACT_ADDRESS}</span>
          <a className="blk-footer__link" href={`mailto:${CONTACT_EMAIL}`}>
            {CONTACT_EMAIL}
          </a>
          <div className="blk-footer__social">
            <a href={SOCIAL_URLS.instagram} target="_blank" rel="noopener noreferrer">
              Instagram
            </a>
            <a href={SOCIAL_URLS.facebook} target="_blank" rel="noopener noreferrer">
              Facebook
            </a>
            <a href={SOCIAL_URLS.x} target="_blank" rel="noopener noreferrer">
              X
            </a>
          </div>
        </div>
      </div>
      <div className="blk-footer__bottom">© {new Date().getFullYear()} BookALook. All rights reserved.</div>
    </footer>
  );
}
