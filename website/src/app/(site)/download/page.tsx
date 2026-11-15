'use client';

import { Suspense, useEffect, useState } from 'react';
import { useSearchParams } from 'next/navigation';
import StoreBadge from '@/components/site/StoreBadge';
import {
  CUSTOMER_APP_STORE_URL,
  CUSTOMER_PLAY_STORE_URL,
  PARTNER_APP_STORE_URL,
  PARTNER_PLAY_STORE_URL,
} from '@/lib/site-links';
import st from '../site.module.css';

/**
 * Where the site's QR codes point. A phone that scans one is sent straight to
 * its own store — App Store on an iPhone, Play Store on Android — so one code
 * works for everybody. Anything else gets both buttons.
 */
function DownloadInner() {
  const params = useSearchParams();
  const partner = params.get('app') === 'partner';
  const ios = partner ? PARTNER_APP_STORE_URL : CUSTOMER_APP_STORE_URL;
  const android = partner ? PARTNER_PLAY_STORE_URL : CUSTOMER_PLAY_STORE_URL;
  const [redirecting, setRedirecting] = useState(false);

  useEffect(() => {
    const ua = navigator.userAgent || '';
    const target = /iPhone|iPad|iPod/i.test(ua) ? ios : /Android/i.test(ua) ? android : null;
    if (!target) return;
    const t = setTimeout(() => {
      setRedirecting(true);
      window.location.replace(target);
    }, 0);
    return () => clearTimeout(t);
  }, [ios, android]);

  return (
    <main className={st.simple}>
      <div className={st.wrap}>
        <p className={st.kicker}>{partner ? 'BookALook Partner' : 'BookALook'}</p>
        <h1>{redirecting ? 'Opening your app store…' : `Get the ${partner ? 'Partner ' : ''}app`}</h1>
        <p className={st.lead} style={{ marginLeft: 'auto', marginRight: 'auto' }}>
          {partner
            ? 'Run your salon’s bookings, staff, billing and payouts from your phone.'
            : 'Book your next salon visit in a minute — no calls, no waiting.'}
        </p>
        <div className={st.cta}>
          <StoreBadge store="google" url={android} label="Google Play" />
          <StoreBadge store="apple" url={ios} label="App Store" />
        </div>
      </div>
    </main>
  );
}

export default function DownloadPage() {
  return (
    <Suspense fallback={null}>
      <DownloadInner />
    </Suspense>
  );
}
