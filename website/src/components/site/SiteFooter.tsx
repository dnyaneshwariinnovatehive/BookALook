import Image from 'next/image';
import Link from 'next/link';
import StoreBadge from './StoreBadge';
import { CONTACT_ADDRESS, CONTACT_COMPANY, CONTACT_EMAIL, CUSTOMER_APP_STORE_URL, CUSTOMER_PLAY_STORE_URL, SOCIAL_URLS } from '@/lib/site-links';
import st from '@/app/(site)/site.module.css';
import c from './chrome.module.css';

/**
 * The public site footer, with the salon-partner callout that sits half over
 * its top edge.
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
    <>
      <div className={`${st.wrap} ${c.partnerWrap}`}>
        <div className={c.partner}>
          <div>
            <p className={c.partnerKicker}>For salon partners</p>
            <h2 className={c.partnerTitle}>Grow your salon business with BookALook.</h2>
          </div>
          <Link className={`${st.btn} ${st.btnWhite} ${st.btnLg}`} href="/partner#enquiry-section">
            Register your salon →
          </Link>
        </div>
      </div>

      <footer className={c.footer}>
        <div className={`${st.wrap} ${c.grid}`}>
          <div className={c.brand}>
            <Image src="/logo-app-light.png" alt="BookALook" width={170} height={44} />
            <p className={c.tag}>No waiting. Start booking. Verified salons, live slots and QR check-in.</p>
            {/* [PLACEHOLDER] Store badge URLs — replace with the real Customer App listings. */}
            <div className={`${c.badges} ${st.onDark}`}>
              <StoreBadge store="google" url={CUSTOMER_PLAY_STORE_URL} label="Google Play" />
              <StoreBadge store="apple" url={CUSTOMER_APP_STORE_URL} label="App Store" />
            </div>
          </div>
          <div className={c.col}>
            <p className={c.head}>Customers</p>
            <Link className={c.flink} href="/#salons">Explore cities</Link>
            <Link className={c.flink} href="/#services">Top categories</Link>
            <Link className={c.flink} href="/#how-it-works">How it works</Link>
            <Link className={c.flink} href="/#download">Download the app</Link>
            <a className={c.flink} href={`mailto:${CONTACT_EMAIL}`}>Support</a>
          </div>
          <div className={c.col}>
            <p className={c.head}>Company</p>
            <Link className={c.flink} href="/about">About BookALook</Link>
            <Link className={c.flink} href="/terms">Terms &amp; Conditions</Link>
            <Link className={c.flink} href="/privacy">Privacy Policy</Link>
            <Link className={c.flink} href="/cancellation-refund">Cancellation &amp; Refund Policy</Link>
            <Link className={c.flink} href="/partner-terms">Salon Partner Policy</Link>
            <Link className={c.flink} href="/delete-account">Delete account</Link>
          </div>
          <div className={c.col}>
            <p className={c.head}>Contact</p>
            <span className={c.flink}>{CONTACT_COMPANY}</span>
            <span className={c.flink}>{CONTACT_ADDRESS}</span>
            <a className={c.flink} href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>
            <div className={c.social}>
              <a href={SOCIAL_URLS.instagram} target="_blank" rel="noopener noreferrer">Instagram</a>
              <a href={SOCIAL_URLS.facebook} target="_blank" rel="noopener noreferrer">Facebook</a>
              <a href={SOCIAL_URLS.x} target="_blank" rel="noopener noreferrer">X</a>
            </div>
          </div>
        </div>
        <div className={`${st.wrap} ${c.bottom}`}>
          <span>© {new Date().getFullYear()} BookALook. All rights reserved.</span>
          <Link href="/partner">Salon owner? Partner with us</Link>
        </div>
      </footer>
    </>
  );
}
