'use client';

import Image from 'next/image';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import StoreBadge from '@/components/site/StoreBadge';
import { CONTACT_EMAIL, CUSTOMER_APP_STORE_URL, CUSTOMER_PLAY_STORE_URL } from '@/lib/site-links';
import { useCity, useSalonCities } from '@/lib/site-city';
import { Parallax, QrCode, Reveal, useOrigin } from './motion';
import { AppScreen, Phone, SalonScreen } from './phone';
import HowItWorks from './home/HowItWorks';
import InsideApp from './home/InsideApp';
import Reviews from './home/Reviews';
import TrendingSalons, { type Category } from './home/TrendingSalons';
import st from './site.module.css';
import h from './home/home.module.css';

/* ============================================================================
   BOOKALOOK HOME — written for customers: find a salon, see live slots, walk
   in with a QR code, and download the app to do it.

   Salon owners have their own page at /partner (features, pricing and the
   registration form). The header and footer live in `./layout.tsx`, and the
   store URLs in `@/lib/site-links`, so this file is only the page body.
   ============================================================================ */

const HERO_TRUST = ['Verified salons', 'Zero waiting time', '₹0 booking fee', 'Live free slots'];

const BAND = ['Haircut', 'Hair spa', 'Beard trim', 'Facial', 'Nail art', 'Bridal makeup', 'Massage', 'Hair colour', 'Clean-up', 'Keratin', 'Manicure', 'Pedicure'];

/**
 * Explore by Look. `match` is what to look for in the live category names, so
 * a tile can filter the salon list below when the catalogue has that category.
 */
const LOOKS = [
  { key: 'hair', img: '/site/hair.jpg', title: 'Hair & Styling', sub: 'Haircuts · Hair Spa · Keratin · Blowdry', match: ['hair'] },
  { key: 'beard', img: '/site/beard.jpg', title: 'Beard & Grooming', sub: 'Beard Shaping · Royal Shave · Detan', match: ['groom', 'beard'] },
  { key: 'skin', img: '/site/skin.jpg', title: 'Skin & Glow', sub: 'Hydrating Facials · Clean-ups · Bleach', match: ['skin', 'facial'] },
  { key: 'nails', img: '/site/nails.jpg', title: 'Nails & Lash', sub: 'Gel Nails · Nail Art · Manicure · Pedicure', match: ['nail', 'lash'] },
  { key: 'bridal', img: '/site/makeup.jpg', title: 'Bridal & Make-Up', sub: 'Pre-bridal Packages · Party Makeup', match: ['bridal', 'makeup', 'make-up', 'make up'] },
  { key: 'spa', img: '/site/spa.jpg', title: 'Spas & Wellness', sub: 'Swedish Massage · Aromatherapy · Foot Reflexology', match: ['spa', 'wellness', 'massage'] },
];

const OLD_WAY = [
  'Calling salons repeatedly to check availability',
  'Waiting 45 minutes at the salon',
  'Unexpected service costs',
  'Sharing personal details at reception',
  'Forgetting appointments',
];

const NEW_WAY = [
  'Live stylist availability',
  'Reserved appointment time',
  'Transparent pricing',
  'QR-based check-in',
  'WhatsApp confirmations and reminders',
];

/** Only things the app does today. */
const PERKS = [
  { icon: '🏷️', title: '₹0 booking fee', desc: 'BookALook is free for customers. You pay the salon’s price, nothing on top.' },
  { icon: '🎁', title: 'First-visit offers', desc: 'Welcome discounts from salons that are new to you, applied at checkout.' },
  { icon: '🔁', title: 'Easy rescheduling', desc: 'Move or cancel from the app, within the salon’s cut-off time.' },
  { icon: '❤️', title: 'Favourites', desc: 'Save your go-to salon and rebook it in two taps.' },
];

// [PLACEHOLDER] Customer FAQ answers are provisional copy — confirm with the business team.
const CUSTOMER_FAQ = [
  {
    q: 'Is there any extra booking fee for customers?',
    a: 'No. BookALook is free for customers. You only pay the salon’s standard service price.',
  },
  {
    q: 'What if I need to cancel or change my time?',
    a: 'You can cancel or reschedule from the app up to the salon’s cut-off time, which is shown before you book.',
  },
  {
    q: 'How does QR check-in work?',
    a: 'Every booking has a QR code in the app. Show it at the salon and they check you in — no names to spell out, no token numbers.',
  },
  {
    q: 'Can I book for someone else?',
    a: 'Yes. Choose “someone else” at checkout and add their name, so the salon knows who to expect.',
  },
];

/** Links that used to land on this page and now belong to /partner. */
const MOVED_TO_PARTNER = ['#for-salons', '#enquiry-section', '#pricing', '#features', '#get-started'];

export default function LandingPage() {
  const router = useRouter();
  const origin = useOrigin();
  const downloadUrl = `${origin}/download?app=customer`;

  const cities = useSalonCities();
  const [cityId, setCityId] = useCity();
  const [categories, setCategories] = useState<Category[]>([]);
  // The category the salon list is filtered by, and the one picked in the
  // hero search but not yet applied.
  const [category, setCategory] = useState('');
  const [pendingCategory, setPendingCategory] = useState('');

  // Old bookmarks and printed links to the salon form keep working.
  useEffect(() => {
    const forward = () => {
      const hash = window.location.hash;
      if (MOVED_TO_PARTNER.includes(hash)) {
        router.replace(`/partner${hash === '#for-salons' ? '' : hash}`);
      }
    };
    forward();
    window.addEventListener('hashchange', forward);
    return () => window.removeEventListener('hashchange', forward);
  }, [router]);

  useEffect(() => {
    let live = true;
    fetch(`${process.env.NEXT_PUBLIC_BACKEND_URL}/api/customer/categories`, { headers: { Accept: 'application/json' } })
      .then((r) => r.json())
      .then((json) => live && setCategories(Array.isArray(json?.categories) ? json.categories : []))
      .catch(() => live && setCategories([]));
    return () => {
      live = false;
    };
  }, []);

  const showSalons = () => document.getElementById('salons')?.scrollIntoView({ behavior: 'smooth', block: 'start' });

  const explore = (e: React.FormEvent) => {
    e.preventDefault();
    setCategory(pendingCategory);
    showSalons();
  };

  /** A look tile: filter by its category when the catalogue has one. */
  const pickLook = (match: string[]) => {
    const found = categories.find((c) => match.some((m) => c.name.toLowerCase().includes(m)));
    setCategory(found?.id ?? '');
    setPendingCategory(found?.id ?? '');
    showSalons();
  };

  const canSearch = cities.length > 0 || categories.length > 0;

  return (
    <main className={h.page}>
      {/* ============ HERO ============ */}
      <section id="top" className={h.hero}>
        <Parallax speed={0.22} className={h.heroBlobA} />
        <Parallax speed={-0.12} className={h.heroBlobB} />
        <div className={`${st.wrap} ${h.heroGrid}`}>
          <Parallax speed={0.07} className={h.heroText}>
            <p className={st.eyebrow}>⚡ Zero Waiting. 100% Confirmed Slots.</p>
            <h1 className={h.h1}>Skip the Waiting Bench. <em>Book Top Salons</em> in Seconds.</h1>
            <p className={h.sub}>
              Discover verified salons and spas near you, explore real-time stylist availability, and lock your
              slot in a few taps. Just walk in and show your QR code.
            </p>

            {canSearch && (
              <form className={h.search} onSubmit={explore} aria-label="Find salons">
                {cities.length > 0 && (
                  <label className={h.searchField}>
                    <small>Where</small>
                    <span>
                      <i aria-hidden="true">📍</i>
                      <select value={cities.some((c) => c.id === cityId) ? cityId : ''} onChange={(e) => setCityId(e.target.value)}>
                        <option value="">Select city</option>
                        {cities.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
                      </select>
                    </span>
                  </label>
                )}
                {categories.length > 0 && (
                  <label className={h.searchField}>
                    <small>What</small>
                    <span>
                      <i aria-hidden="true">✂️</i>
                      <select value={pendingCategory} onChange={(e) => setPendingCategory(e.target.value)}>
                        <option value="">Any service</option>
                        {categories.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
                      </select>
                    </span>
                  </label>
                )}
                <button type="submit" className={`${st.btn} ${h.searchBtn}`}>Explore Salons →</button>
              </form>
            )}

            <div className={`${st.cta} ${h.heroCta}`}>
              <StoreBadge store="google" url={CUSTOMER_PLAY_STORE_URL} label="Google Play" />
              <StoreBadge store="apple" url={CUSTOMER_APP_STORE_URL} label="App Store" />
              <span className={`${st.qrCard} ${h.heroQr}`}>
                <QrCode value={downloadUrl} size={58} label="QR code to download the BookALook app" />
                <span><b>Scan to download</b>Point your phone camera<br />at the code</span>
              </span>
            </div>

            <ul className={st.trust}>
              {HERO_TRUST.map((t) => (
                <li key={t}><span className={st.tick} aria-hidden="true">✓</span>{t}</li>
              ))}
            </ul>
          </Parallax>

          <div className={h.stage}>
            <Parallax speed={0.1} rotate={0.4} className={h.ring} />
            <Parallax speed={-0.06} rotate={-0.3} className={`${h.ring} ${h.ring2}`} />
            <span className={h.halo} aria-hidden="true" />
            <Parallax speed={-0.1} className={h.stagePhone}>
              <Phone className={h.tilt} label="BookALook app preview: a salon page with stylists and live free slots">
                <SalonScreen />
              </Phone>
            </Parallax>
            <Parallax speed={-0.26} className={`${h.fl} ${h.fl1}`}>
              <div className={`${st.float} ${st.bob}`}><i>🛡️</i><span>Verified Salons<small>Checked by our team</small></span></div>
            </Parallax>
            <Parallax speed={0.16} className={`${h.fl} ${h.fl2}`}>
              <div className={`${st.float} ${st.bob2}`}><i>⏱️</i><span>Zero Wait Time<small>Your chair is ready</small></span></div>
            </Parallax>
            <Parallax speed={-0.18} className={`${h.fl} ${h.fl3}`}>
              <div className={`${st.float} ${st.bob3}`}><i>🏷️</i><span>₹0 Booking Fee<small>Pay the salon’s price</small></span></div>
            </Parallax>
            <Parallax speed={0.24} rotate={0.5} className={`${h.fl} ${h.ticketWrap}`}>
              <div className={h.ticket} aria-hidden="true">
                <QrCode value={downloadUrl} size={140} label="" />
                <b>Your QR ticket</b>
                <small>Today · 6:30 PM · Riya</small>
              </div>
            </Parallax>
          </div>
        </div>
      </section>

      {/* ============ SERVICE BAND — slides sideways as the page scrolls ============ */}
      <div className={h.band} aria-hidden="true">
        <Parallax axis="x" speed={-0.35} className={h.bandTrack}>
          {[0, 1, 2].map((copy) => BAND.map((word) => (
            <span key={`${copy}-${word}`}>{word}<i>✦</i></span>
          )))}
        </Parallax>
      </div>

      {/* ============ EXPLORE BY LOOK ============ */}
      <section id="services" className={st.sec}>
        <div className={st.wrap}>
          <Reveal>
            <p className={st.kicker}>Explore by Look</p>
            <h2 className={st.big}>Whatever the look,<br /><em>there’s a chair for it.</em></h2>
          </Reveal>
          <div className={h.bento}>
            {LOOKS.map((look, i) => (
              <Reveal key={look.key} delay={(i % 3) * 90} variant="zoom" className={`${h.tileWrap} ${h[`tile_${look.key}`]}`}>
                <div className={h.tile}>
                  {/* The photo is taller than its frame and drifts inside it. */}
                  <Parallax speed={-0.09} className={h.tileImg}>
                    <Image src={look.img} alt="" fill sizes="(max-width: 760px) 100vw, 40vw" />
                  </Parallax>
                  <span className={h.tileShade} aria-hidden="true" />
                  <span className={h.tileNum} aria-hidden="true">{String(i + 1).padStart(2, '0')}</span>
                  <span className={h.tileGo} aria-hidden="true">↗</span>
                  <button type="button" className={h.tileText} onClick={() => pickLook(look.match)} aria-label={`${look.title}: see salons`}>
                    <b>{look.title}</b>
                    <span>{look.sub}</span>
                  </button>
                </div>
              </Reveal>
            ))}
          </div>
        </div>
      </section>

      {/* ============ OLD WAY vs BOOKALOOK WAY ============ */}
      <section className={`${st.sec} ${h.cmp}`}>
        <div className={st.wrap}>
          <Reveal className={st.center}>
            <p className={st.kicker}>The Old Way vs. The BookALook Way</p>
            <h2 className={st.big}>Same salon. <em>None of the waiting.</em></h2>
          </Reveal>
          <div className={h.cmpGrid}>
            <Parallax speed={0.08} className={h.cmpCol}>
              <Reveal variant="left" className={h.old}>
                <h3>Without BookALook</h3>
                <ul>
                  {OLD_WAY.map((line) => (
                    <li key={line}><i className={h.x} aria-hidden="true">✕</i><span>{line}</span></li>
                  ))}
                </ul>
              </Reveal>
            </Parallax>
            <Parallax speed={-0.08} className={`${h.cmpCol} ${h.cmpColNew}`}>
              <Reveal variant="right" delay={160} className={h.new}>
                <span className={h.vs} aria-hidden="true">VS</span>
                <h3>With BookALook</h3>
                <ul>
                  {NEW_WAY.map((line) => (
                    <li key={line}><i className={h.v} aria-hidden="true">✓</i><span>{line}</span></li>
                  ))}
                </ul>
              </Reveal>
            </Parallax>
          </div>
        </div>
      </section>

      <InsideApp qr={downloadUrl} />

      <TrendingSalons categories={categories} category={category} onCategory={(id) => { setCategory(id); setPendingCategory(id); }} />

      {/* ============ APP PERKS ============ */}
      <section id="perks" className={h.perks}>
        <div className={st.wrap}>
          <Reveal variant="zoom" className={h.perkBox}>
            <Parallax speed={0.2} className={h.perkOrbA} />
            <Parallax speed={-0.16} className={h.perkOrbB} />
            <p className={`${st.kicker} ${h.perkKicker}`}>App Exclusives &amp; Perks</p>
            <h2 className={`${st.big} ${h.perkTitle}`}>Better in the app. Every single time.</h2>
            <div className={h.perkGrid}>
              {PERKS.map((perk, i) => (
                <Parallax key={perk.title} speed={i % 2 ? -0.07 : 0.07}>
                  <article className={h.perk}>
                    <i aria-hidden="true">{perk.icon}</i>
                    <h3>{perk.title}</h3>
                    <p>{perk.desc}</p>
                  </article>
                </Parallax>
              ))}
            </div>
          </Reveal>
        </div>
      </section>

      <HowItWorks qr={downloadUrl} />

      <Reviews />

      {/* ============ DOWNLOAD ============ */}
      <section id="download" className={h.dl}>
        <div className={st.wrap}>
          <Reveal variant="zoom" className={`${h.dlBox} ${st.onDark}`}>
            <Parallax speed={0.14} className={h.dlGlow} />
            <div className={h.dlText}>
              <h2>Ready for a Better Salon Experience?</h2>
              <p>Download the BookALook app on Android or iOS and enjoy a smarter way to book your salon appointments.</p>
              <div className={`${st.cta} ${h.dlCta}`}>
                <StoreBadge store="google" url={CUSTOMER_PLAY_STORE_URL} label="Google Play" />
                <StoreBadge store="apple" url={CUSTOMER_APP_STORE_URL} label="App Store" />
                <span className={st.qrCard}>
                  <QrCode value={downloadUrl} size={64} label="QR code to download the BookALook app" />
                  <span><b>Scan to download</b>One code for Android<br />and iPhone</span>
                </span>
              </div>
            </div>
            <div className={h.dlPhoneCol}>
              <Parallax speed={-0.16} rotate={0.3} className={h.dlPhone}>
                <Phone className={h.dlTilt} label="BookALook app preview: a booking's QR ticket">
                  <AppScreen name="ticket" qr={downloadUrl} />
                </Phone>
              </Parallax>
            </div>
          </Reveal>
        </div>
      </section>

      {/* ============ FAQ ============ */}
      <section id="faq" className={`${st.sec} ${h.faqSec}`}>
        <div className={`${st.wrap} ${st.faq}`}>
          <Reveal className={st.faqHead}>
            <p className={st.kicker}>FAQ</p>
            <h2 className={st.big}>Questions, <em>answered.</em></h2>
            <p className={st.lead}>
              Still unsure? Write to us at <a className={h.mail} href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>.
              Own a salon? <Link className={h.mail} href="/partner">See the partner page</Link>.
            </p>
          </Reveal>
          <div>
            {CUSTOMER_FAQ.map((item, i) => (
              <details className={st.q} key={item.q} open={i === 0 || undefined}>
                <summary>{item.q}</summary>
                <p>{item.a}</p>
              </details>
            ))}
          </div>
        </div>
      </section>
    </main>
  );
}
