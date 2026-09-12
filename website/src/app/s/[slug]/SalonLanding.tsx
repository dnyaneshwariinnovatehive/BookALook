'use client';

import { useCallback, useEffect, useState } from 'react';
import styles from './page.module.css';

interface Salon {
  id: string;
  slug: string;
  name: string;
  description: string | null;
  address: string | null;
  city: string | null;
  state: string | null;
  cover_photo_url: string | null;
  avg_rating: number;
  review_count: number;
  is_bookable: boolean;
}

interface AppLinks {
  android_app_url: string | null;
  ios_app_url: string | null;
  android_apk_url: string | null;
  has_android: boolean;
  has_ios: boolean;
}

interface Props {
  salon: Salon;
  deepLink: string;
  androidIntentLink: string;
  appLinks: AppLinks;
}

type Platform = 'android' | 'ios' | 'other';

/** Which phone is holding this, so the page offers one obvious next step. */
const detectPlatform = (): Platform => {
  if (typeof navigator === 'undefined') return 'other';

  const ua = navigator.userAgent || '';

  if (/android/i.test(ua)) return 'android';
  // iPadOS reports itself as a Mac, so touch points are the giveaway.
  if (/iPad|iPhone|iPod/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1)) {
    return 'ios';
  }

  return 'other';
};

export default function SalonLanding({ salon, deepLink, androidIntentLink, appLinks }: Props) {
  const [platform, setPlatform] = useState<Platform>('other');
  const [tried, setTried] = useState(false);

  /**
   * Ask the phone to hand over to the app.
   *
   * There is no reliable way to ask "is this app installed" from a web page, so
   * this simply attempts the handover. If it works the browser is backgrounded
   * and nothing else matters; if it does not, the page is still sitting here
   * with download buttons on it.
   */
  const openInApp = useCallback(() => {
    setTried(true);

    if (platform === 'android') {
      // Chrome on Android swallows a bare custom scheme but honours intent://,
      // which also carries its own fallback URL.
      window.location.href = androidIntentLink;
      return;
    }

    window.location.href = deepLink;
  }, [platform, deepLink, androidIntentLink]);

  useEffect(() => {
    setPlatform(detectPlatform());
  }, []);

  useEffect(() => {
    if (platform === 'other') return;

    // A beat, so the salon's name is on screen before the phone may switch
    // away. Someone who does not have the app should still register where they
    // just landed.
    const timer = setTimeout(openInApp, 700);
    return () => clearTimeout(timer);
  }, [platform, openInApp]);

  const androidLink = appLinks.android_app_url || appLinks.android_apk_url;
  const rating = Number(salon.avg_rating || 0);

  return (
    <main className={styles.page}>
      <div className={styles.card}>
        <div
          className={styles.cover}
          style={
            salon.cover_photo_url
              ? { backgroundImage: `url(${salon.cover_photo_url})` }
              : undefined
          }
        >
          <span className={styles.brand}>BookALook</span>
        </div>

        <div className={styles.body}>
          <h1 className={styles.name}>{salon.name}</h1>

          <div className={styles.meta}>
            {rating > 0 && (
              <span className={styles.rating}>
                ★ {rating.toFixed(1)}
                {salon.review_count > 0 && (
                  <span className={styles.reviewCount}> ({salon.review_count})</span>
                )}
              </span>
            )}
            {salon.city && <span className={styles.city}>{salon.city}</span>}
          </div>

          {salon.address && <p className={styles.address}>{salon.address}</p>}
          {salon.description && <p className={styles.description}>{salon.description}</p>}

          {!salon.is_bookable && (
            <p className={styles.notice}>
              This salon is not taking online bookings at the moment.
            </p>
          )}

          <div className={styles.actions}>
            <button type="button" className={styles.primary} onClick={openInApp}>
              Open in the BookALook app
            </button>

            {/* Only shown once the handover has been attempted: before that it
                would be answering a question nobody has asked yet. */}
            {tried && (
              <p className={styles.hint}>
                Nothing happened? You probably don&apos;t have the app yet.
              </p>
            )}

            {appLinks.has_android || appLinks.has_ios ? (
              <div className={styles.stores}>
                {androidLink && (platform === 'android' || platform === 'other') && (
                  <a className={styles.store} href={androidLink}>
                    <span className={styles.storeIcon}>▶</span>
                    <span>
                      <small>
                        {appLinks.android_app_url ? 'Get it on' : 'Download for'}
                      </small>
                      <strong>{appLinks.android_app_url ? 'Google Play' : 'Android'}</strong>
                    </span>
                  </a>
                )}

                {appLinks.ios_app_url && (platform === 'ios' || platform === 'other') && (
                  <a className={styles.store} href={appLinks.ios_app_url}>
                    <span className={styles.storeIcon}></span>
                    <span>
                      <small>Download on the</small>
                      <strong>App Store</strong>
                    </span>
                  </a>
                )}
              </div>
            ) : (
              // Honest rather than a dead button: the apps are not published
              // yet, and sending somebody to an empty store page is worse
              // than telling them to come back.
              <p className={styles.comingSoon}>
                The BookALook app is launching shortly. Ask at the counter to book
                in the meantime.
              </p>
            )}
          </div>
        </div>
      </div>

      <p className={styles.footer}>Scanned at {salon.name}</p>
    </main>
  );
}
