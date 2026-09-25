"use client";

import Image from 'next/image';
import Link from 'next/link';
import { useEffect, useState } from 'react';
import './globals.css';

/* ============================================================================
   BOOKALOOK LANDING CONTENT — added sections
   Static frontend content only. The existing salon enquiry form (see below)
   is a fixed anchor point and is intentionally left byte-for-byte untouched.
   ============================================================================ */

// [PLACEHOLDER] App store listing URLs — replace with the real live listings.
// Mirrors the same placeholders used in the superadmin settings policy page.
const CUSTOMER_APP_STORE_URL = 'https://apps.apple.com/in/app/bookalook/id0000000000'; // [PLACEHOLDER]
const CUSTOMER_PLAY_STORE_URL = 'https://play.google.com/store/apps/details?id=com.bookalook.customer'; // [PLACEHOLDER]
const PARTNER_APP_STORE_URL = 'https://apps.apple.com/in/app/bookalook-partner/id0000000000'; // [PLACEHOLDER]
const PARTNER_PLAY_STORE_URL = 'https://play.google.com/store/apps/details?id=com.bookalook.partner'; // [PLACEHOLDER]

// [PLACEHOLDER] Social handles — replace with the real branded profiles.
const SOCIAL_URLS = {
  instagram: 'https://www.instagram.com/bookalook', // [PLACEHOLDER]
  facebook: 'https://www.facebook.com/bookalook', // [PLACEHOLDER]
  x: 'https://x.com/bookalook', // [PLACEHOLDER]
};

const CUSTOMER_STEPS = [
  { title: 'Discover', desc: 'Browse verified salons and services near you.' },
  { title: 'Book', desc: 'Pick a salon, service, and time that suits you.' },
  { title: 'Pay Advance', desc: 'Pay a small advance securely to lock your slot.' },
  { title: 'QR Check-in', desc: 'Show your QR code at the salon to check in.' },
  { title: 'Enjoy', desc: 'Walk out happy — no waiting, no confusion.' },
];

const CUSTOMER_FLOW = [
  {
    icon: 'search',
    title: 'Discover Top Salons',
    desc: 'Browse rated stylists, view service menus, and transparent upfront costs.',
  },
  {
    icon: 'check-calendar',
    title: 'Reserve & Secure Slot',
    desc: 'Pick your preferred date and time, and place a small guaranteed deposit.',
  },
  {
    icon: 'qr',
    title: 'Check In Instantly',
    desc: 'Walk in, scan your instant QR code, and bypass the waiting lounge straight to the chair.',
  },
];

const SALON_ROLES = [
  {
    icon: 'bag',
    title: 'Admin',
    role: 'Salon Owner',
    desc: 'Register your salon, manage staff and services, and track revenue and payouts.',
  },
  {
    icon: 'clock',
    title: 'Service Provider',
    role: 'Staff',
    desc: 'Manage your schedule, handle walk-ins, and track your earnings.',
  },
  {
    icon: 'users',
    title: 'Collaborator',
    role: 'Field Partner',
    desc: 'Onboard salons on the ground and earn through subscription commissions.',
  },
];

// [PLACEHOLDER] Partnership step wording — confirmed with the business team if
// these need adjustment. Kept at 4 steps as spec'd.
const PARTNER_STEPS = [
  { title: 'Tell us about your salon', desc: 'Register online, or submit the enquiry form right on this page.' },
  { title: 'Get verified', desc: 'Our team confirms your salon with an on-ground visit or review.' },
  { title: 'Get approved', desc: 'You are approved and your salon goes live on BookALook.' },
  { title: 'Manage everything', desc: 'Run staff, services, bookings, and payouts from the Partner App.' },
];

const WHY_FEATURES = [
  { icon: 'check-calendar', title: 'No double-booking', desc: 'Real-time availability means every slot is reserved once.' },
  { icon: 'lock', title: 'Secure advance payments', desc: 'Advances are held securely and applied to your bill.' },
  { icon: 'chat', title: 'WhatsApp booking updates', desc: 'Instant confirmations and reminders, right on WhatsApp.' },
  { icon: 'wallet', title: 'Wallet rewards for salons', desc: 'Earn wallet credits on every completed booking.' },
  { icon: 'shield', title: 'Verified salons', desc: 'Every salon is checked before it goes live.' },
  { icon: 'qr', title: 'QR check-in', desc: 'Customers verify in seconds at the door with a QR code.' },
];

// [PLACEHOLDER] FAQ answers are provisional copy — replace with final wording.
const FAQ_ITEMS = [
  {
    q: 'Is it free for salons to list?',
    a: 'Yes — getting your salon listed on BookALook is free. You can go live, receive bookings, and manage services without paying anything. Optional paid features and plans are always shown clearly before you choose, so there are no hidden charges.',
  },
  {
    q: 'How does the advance payment work?',
    a: 'When a customer books, they pay a small advance — usually a percentage of the service price — to confirm the slot. The secure payment is held and adjusted against the final bill at the salon, so no one pays twice for the same appointment.',
  },
  {
    q: 'What happens if I need to cancel?',
    a: 'Refunds depend on the salon\u2019s cancellation policy, which is always shown before you book. Cancel within the window and you\u2019re refunded automatically. If the salon cancels, you\u2019re refunded in full — every time.',
  },
  {
    q: 'How do I become a Collaborator?',
    a: 'Collaborators are field partners who onboard salons in their area and earn commissions on subscriptions. To get started, submit the enquiry form on this page or email us at hello@bookalook.in, and our team will walk you through everything.',
  },
];

function Icon({ name, className }: { name: string; className?: string }) {
  const common = {
    fill: 'none',
    stroke: 'currentColor',
    strokeWidth: 2,
    strokeLinecap: 'round' as const,
    strokeLinejoin: 'round' as const,
    viewBox: '0 0 24 24',
    className,
    'aria-hidden': true,
  };
  switch (name) {
    case 'search':
      return <svg {...common}><circle cx="11" cy="11" r="7" /><path d="m21 21-4.35-4.35" /></svg>;
    case 'calendar':
      return <svg {...common}><rect x="3" y="4" width="18" height="17" rx="3" /><path d="M16 2v4M8 2v4M3 10h18" /></svg>;
    case 'card':
      return <svg {...common}><rect x="2" y="5" width="20" height="14" rx="3" /><path d="M2 10h20" /></svg>;
    case 'qr':
      return <svg {...common}><rect x="3" y="3" width="7" height="7" rx="1.5" /><rect x="14" y="3" width="7" height="7" rx="1.5" /><rect x="3" y="14" width="7" height="7" rx="1.5" /><path d="M14 14h3v3h-3z" /><path d="M20 14h1M14 20h1M18 18h3v3h-3z" /></svg>;
    case 'smile':
      return <svg {...common}><circle cx="12" cy="12" r="9" /><path d="M8.5 14.5a4.5 4.5 0 0 0 7 0" /><path d="M9 9h.01M15 9h.01" /></svg>;
    case 'shield':
      return <svg {...common}><path d="M12 2.5 4.5 5v5.5c0 4.8 3.3 8.5 7.5 11 4.2-2.5 7.5-6.2 7.5-11V5z" /><path d="m8.6 11.8 2.3 2.3 4.4-4.4" /></svg>;
    case 'lock':
      return <svg {...common}><rect x="4" y="10" width="16" height="11" rx="3" /><path d="M8 10V7a4 4 0 0 1 8 0v3" /></svg>;
    case 'chat':
      return <svg {...common}><path d="M21 12a8.6 8.6 0 0 1-8.6 8.6c-1.5 0-2.9-.36-4.1-1L3 21l1.5-4.9a8.6 8.6 0 1 1 16.5-4.1z" /><path d="M8 10h8M8 14h5" /></svg>;
    case 'wallet':
      return <svg {...common}><rect x="3" y="6" width="18" height="14" rx="3" /><path d="M3 10h18" /><path d="M16.5 14.5h.01" /></svg>;
    case 'check-calendar':
      return <svg {...common}><rect x="3" y="4" width="18" height="17" rx="3" /><path d="M16 2v4M8 2v4M3 10h18" /><path d="m9 15 2 2 4-4" /></svg>;
    case 'bag':
      return <svg {...common}><path d="M6 3 3 6v13a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-3z" /><path d="M3 6h18" /><path d="M16 10a4 4 0 0 1-8 0" /></svg>;
    case 'clock':
      return <svg {...common}><rect x="3" y="4" width="18" height="17" rx="3" /><path d="M16 2v4M8 2v4M3 10h18" /><circle cx="12" cy="16" r="2.5" /><path d="M12 14.5V16l1.2 1" /></svg>;
    case 'users':
      return <svg {...common}><circle cx="9" cy="8" r="3.5" /><path d="M2.5 20a6.5 6.5 0 0 1 13 0" /><path d="M16.5 4.5a3.5 3.5 0 0 1 0 7" /><path d="M16.8 13.4a6.5 6.5 0 0 1 4.7 6.6" /></svg>;
    case 'spark':
      return <svg {...common}><path d="m12 2 2.1 6.4L20.5 10l-6.4 1.9L12 18.3l-2.1-6.4L3.5 10l6.4-1.6z" /></svg>;
    case 'arrow':
      return <svg {...common}><path d="M5 12h14" /><path d="m13 6 6 6-6 6" /></svg>;
    case 'check':
      return <svg {...common}><path d="m4.5 12.5 5 5 10-10" /></svg>;
    case 'scissors':
      return <svg {...common}><circle cx="6" cy="6" r="3" /><circle cx="6" cy="18" r="3" /><path d="M8.5 8.2 20.5 20M8.5 15.8 20.5 4" /></svg>;
    case 'comb':
      return <svg {...common}><path d="M5 3v18" /><path d="M5 3h12" /><path d="M5 7h10M5 11h12M5 15h10M5 19h12" /></svg>;
    case 'bell':
      return <svg {...common}><path d="M6 16v-5a6 6 0 0 1 12 0v5l1.5 2.4h-15z" /><path d="M10 20.5a2 2 0 0 0 4 0" /></svg>;
    default:
      return <svg {...common}><circle cx="12" cy="12" r="9" /></svg>;
  }
}

function StoreBadge({ store, url, label }: { store: 'apple' | 'google'; url: string; label: string }) {
  return (
    <a className="blk-badge" href={url} target="_blank" rel="noopener noreferrer" aria-label={`Download on ${label}`}>
      {store === 'apple' ? (
        <svg className="blk-badge__icon" viewBox="0 0 24 24" aria-hidden="true">
          <path d="M16.365 1.43c0 1.14-.493 2.27-1.177 3.08-.744.9-1.99 1.57-2.987 1.57-.12 0-.23-.01-.33-.02-.124-.85.357-2.02 1.09-2.82.727-.79 1.96-1.45 2.96-1.41.09.2.138.4.138.6z" />
          <path d="M21 16.05c-.26.66-.38.96-.72 1.55-.47.82-1.13 1.85-1.95 1.85-.75 0-1.04-.47-2.16-.46-.91 0-1.34.47-2.15.47-.82 0-1.45-.96-1.93-1.78-1.03-1.79-1.83-5.05-.7-7.26.5-1 1.3-1.58 2.2-1.58.8 0 1.5.47 2.25.47.44 0 .71-.09 1.09-.28 1.15-.59 2.3-2.03 2.47-2.03.09 0 .05.04-.1.32-.6.9-1.03 1.7-1.16 2.6-.18 1.25.5 2.5 1.89 3.43-.15.34-.31.66-.48.96z" />
        </svg>
      ) : (
        <svg className="blk-badge__icon" viewBox="0 0 24 24" aria-hidden="true">
          <path d="M3 20.5v-17c0-.59.34-1.11.84-1.35L13.69 12l-9.85 9.85c-.5-.25-.84-.76-.84-1.35zm13.81-5.38L6.05 21.34l8.49-8.49 2.27 2.27zm3.35-4.31c.34.27.59.68.59 1.19s-.22.9-.57 1.18l-2.29 1.32-2.5-2.5 2.5-2.5 2.27 1.31zM6.05 2.66l10.76 6.22-2.27 2.27-8.49-8.49z" />
        </svg>
      )}
      <span className="blk-badge__text">
        <span className="blk-badge__small">Download on the</span>
        <span className="blk-badge__name">{label}</span>
      </span>
    </a>
  );
}

// [PLACEHOLDER] Decorative QR placeholder for the download banner. It is NOT
// scannable — replace with a real QR generated from the live store URL once the
// Customer App listings go live.
function QrPlaceholder() {
  const size = 13;
  const cells: boolean[][] = Array.from({ length: size }, () => Array(size).fill(false));
  const set = (r: number, c: number, on: boolean) => {
    cells[r][c] = on;
  };
  const finder = (r: number, c: number) => {
    for (let i = 0; i < 7; i++) {
      for (let j = 0; j < 7; j++) {
        const edge = i === 0 || i === 6 || j === 0 || j === 6;
        const core = i >= 2 && i <= 4 && j >= 2 && j <= 4;
        set(r + i, c + j, edge || core);
      }
    }
    if (r + 7 < size && c + 4 < size) set(r + 7, c + 4, true);
    if (r + 4 < size && c + 7 < size) set(r + 4, c + 7, true);
  };
  finder(0, 0);
  finder(0, size - 7);
  finder(size - 7, 0);
  let h = 0;
  for (let k = 0; k < 'bookalook'.length; k++) h = (h * 31 + 'bookalook'.charCodeAt(k)) >>> 0;
  const rand = () => {
    h = (h * 1664525 + 1013904223) >>> 0;
    return h / 4294967296;
  };
  for (let r = 0; r < size; r++) {
    for (let c = 0; c < size; c++) {
      if (cells[r][c] || (r < 9 && c < 9)) continue;
      set(r, c, rand() > 0.5);
    }
  }
  return (
    <div className="blk-download__qr" role="img" aria-label="QR code placeholder for the app download">
      {cells.map((row, r) => (
        <span className="blk-download__qr-row" key={r}>
          {row.map((on, c) => <i className={on ? 'is-on' : ''} key={c} />)}
        </span>
      ))}
    </div>
  );
}

export default function LandingPage() {
  const [formData, setFormData] = useState({
    salon_name: '',
    owner_name: '',
    phone: '',
    state: '',
    city_id: '',
    sub_area_id: '',
    street_address: '',
    pincode: '',
    message: ''
  });
  const [status, setStatus] = useState<'idle' | 'submitting' | 'success' | 'error'>('idle');
  const [errorMessage, setErrorMessage] = useState('');

  // City and area are picked, never typed. Typed cities left this table holding
  // "navi mumbai" and "Pimpri Chinchwad", which no collaborator could be
  // matched against.
  const [cities, setCities] = useState<{ id: string; name: string; state: string }[]>([]);
  const [states, setStates] = useState<string[]>([]);
  const [subAreas, setSubAreas] = useState<{ id: string; name: string }[]>([]);
  const [loadingAreas, setLoadingAreas] = useState(false);

  useEffect(() => {
    fetch(`${process.env.NEXT_PUBLIC_BACKEND_URL}/api/cities`, { headers: { Accept: 'application/json' } })
      .then((r) => r.json())
      .then((list) => {
        if (Array.isArray(list)) {
          setCities(list);
          const uniqueStates = Array.from(new Set(list.map((c: any) => c.state).filter(Boolean))) as string[];
          uniqueStates.sort();
          setStates(uniqueStates);
        }
      })
      .catch(() => setCities([]));
  }, []);

  // Areas belong to a city, so the second dropdown refills whenever the first
  // changes — and clears any area already chosen, which would now be in the
  // wrong city.
  useEffect(() => {
    if (!formData.city_id) {
      setSubAreas([]);
      return;
    }

    setLoadingAreas(true);
    fetch(`${process.env.NEXT_PUBLIC_BACKEND_URL}/api/cities/${formData.city_id}/sub-areas`, {
      headers: { Accept: 'application/json' },
    })
      .then((r) => r.json())
      .then((d) => setSubAreas(d?.sub_areas ?? []))
      .catch(() => setSubAreas([]))
      .finally(() => setLoadingAreas(false));
  }, [formData.city_id]);

  const handleInputChange = (
    e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>
  ) => {
    const { name, value } = e.target;
    setFormData(prev => ({
      ...prev,
      [name]: value,
      ...(name === 'state' ? { city_id: '', sub_area_id: '' } : {}),
      ...(name === 'city_id' ? { sub_area_id: '' } : {}),
    }));
  };

  const filteredCities = formData.state 
    ? cities.filter(c => c.state === formData.state) 
    : [];

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setStatus('submitting');
    setErrorMessage('');

    try {
      const response = await fetch(`${process.env.NEXT_PUBLIC_BACKEND_URL}/api/enquiries`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: JSON.stringify(formData),
      });

      if (response.ok) {
        setStatus('success');
        setFormData({ salon_name: '', owner_name: '', phone: '', state: '', city_id: '', sub_area_id: '', street_address: '', pincode: '', message: '' });
      } else {
        const data = await response.json();
        setStatus('error');
        // Laravel returns a field map; its own wording is more use than a
        // generic failure line.
        const firstError = data?.errors ? Object.values(data.errors)[0] : null;
        setErrorMessage(
          Array.isArray(firstError)
            ? String(firstError[0])
            : data.message || 'Failed to submit enquiry. Please check your details.'
        );
      }
    } catch (error) {
      setStatus('error');
      setErrorMessage('A network error occurred. Please try again.');
    }
  };

  return (
    <div className="landing-container" style={{ minHeight: '100vh', backgroundColor: '#F5EFE3' }}>

      {/* ============ HEADER / NAV ============ */}
      <header className="blk-header">
        <div className="blk-header__inner">
          <a href="#top" className="blk-header__logo" aria-label="Back to top">
            <Image src="/logo.png" alt="BookALook" width={150} height={42} style={{ objectFit: 'contain' }} priority />
          </a>
          <nav className="blk-header__nav" aria-label="Primary">
            <a className="blk-header__link" href="#for-customers">Customers</a>
            <a className="blk-header__link" href="#for-salons">For Salons</a>
            {/* [PLACEHOLDER] No Pricing section exists yet — this nav item scrolls to the salon
                section until a dedicated pricing section is added. */}
            <a className="blk-header__link" href="#for-salons">Pricing</a>
            <a className="blk-header__link" href="#faq">FAQ</a>
          </nav>
          {/* [PLACEHOLDER] Points at the customer-badge section for now; swap to the real
              store listing URL once the Customer App listing is live. */}
          <a className="blk-btn blk-btn--gold blk-btn--sm" href="#for-customers">Get the App</a>
        </div>
      </header>

      {/* ============ HERO ============ */}
      <section id="top" className="blk-hero">
        <div className="blk-hero__bgi" aria-hidden="true">
          <Icon name="scissors" />
          <Icon name="comb" />
          <Icon name="spark" />
          <Icon name="scissors" />
          <Icon name="spark" />
        </div>
        <div className="blk-hero__grid">
          <div className="blk-hero__content">
            <p className="blk-hero__eyebrow">BookALook – Salon Appointments, Done Right</p>
            <h1 className="blk-hero__title">
              No waiting. <br />
              <span className="blk-hero__title-gold">Just booking.</span>
            </h1>
            <p className="blk-hero__sub">
              Browse top-rated salons, secure your slot with an advance, and check in with a tap.
              Zero wait times, guaranteed.
            </p>
            <div className="blk-hero__ctas">
              {/* [PLACEHOLDER] No booking flow on the landing page yet — points at the
                  customer section until the app's booking experience is linked. */}
              <a className="blk-btn blk-btn--warm" href="#for-customers">
                Book an Appointment <Icon name="arrow" />
              </a>
              <a className="blk-btn blk-btn--ghost" href="#enquiry-section">Register Your Salon</a>
            </div>
            <div className="blk-hero__proof">
              {/* [PLACEHOLDER] Review figure is provisional marketing copy — replace
                  with the real verified rating once live. */}
              <p className="blk-hero__rating">
                <span className="blk-hero__stars" aria-hidden="true">★★★★★</span>
                <span>4.9/5 from 1,200+ bookings</span>
              </p>
              <ul className="blk-hero__pills">
                <li><Icon name="check" /> Instant QR Check-in</li>
                <li><Icon name="check" /> Verified Salons</li>
                <li><Icon name="check" /> Secure Advance</li>
              </ul>
            </div>
          </div>
          <figure className="blk-phone" aria-label="BookALook app preview">
            <div className="blk-phone__frame">
              <div className="blk-phone__screen">
                <div className="blk-phone__statusbar">
                  <span>9:41</span>
                  <span aria-hidden="true">●●●</span>
                </div>
                <div className="blk-phone__appbar">
                  <span className="blk-phone__brand">Book<span>ALook</span></span>
                  <span className="blk-phone__bell"><Icon name="bell" /></span>
                </div>
                <div className="blk-phone__search">
                  <Icon name="search" />
                  <span>Find a salon, service, or stylist</span>
                </div>
                <div className="blk-phone__chips">
                  <span className="blk-phone__chip is-on">Haircut</span>
                  <span className="blk-phone__chip">Facial</span>
                  <span className="blk-phone__chip">Manicure</span>
                </div>
                <div className="blk-phone__card">
                  <p className="blk-phone__card-label">Your Next Appointment</p>
                  <p className="blk-phone__card-name">Irren Atelier</p>
                  <p className="blk-phone__card-meta">Today · 6:30 PM · Haircut + Conditioning</p>
                  <div className="blk-phone__card-row">
                    <span className="blk-phone__card-conf">Confirmed</span>
                    <span className="blk-phone__card-btn">View QR</span>
                  </div>
                </div>
                <div className="blk-phone__cal">
                  <p className="blk-phone__cal-label">This week</p>
                  <div className="blk-phone__cal-days">
                    <span className="blk-phone__day"><b>Mon</b><i>12</i></span>
                    <span className="blk-phone__day"><b>Tue</b><i>13</i></span>
                    <span className="blk-phone__day is-on"><b>Wed</b><i>14</i></span>
                    <span className="blk-phone__day"><b>Thu</b><i>15</i></span>
                    <span className="blk-phone__day"><b>Fri</b><i>16</i></span>
                  </div>
                </div>
              </div>
            </div>
          </figure>
        </div>
      </section>

      {/* ============ WHAT IS BOOKALOOK ============ */}
      <section id="what-is-bookalook" className="blk-whatis">
        <div className="blk-container">
          <p className="blk-section-kicker">What is BookALook</p>
          <h2 className="blk-section-title">Salon appointments without the waiting room</h2>
          <p className="blk-whatis__text">
            BookALook is an online appointment platform that connects customers with local salons and
            barbershops. Customers browse real salons near them, choose a service and a time, pay a small
            advance to lock it in, and check in with a QR code when they arrive. For salons, it is the same
            platform — one place to manage bookings, staff, and payments instead of juggling calls and walk-ins.
          </p>
        </div>
      </section>

      {/* ============ HOW IT WORKS — CUSTOMER JOURNEY ============ */}
      <section id="how-it-works" className="blk-journey">
        <div className="blk-container">
          <p className="blk-section-kicker">How it works</p>
          <h2 className="blk-section-title">From browse to done in five steps</h2>
          <p className="blk-section-sub">The BookALook customer journey stays quick end to end.</p>
          <ol className="blk-steps">
            {CUSTOMER_STEPS.map((step, i) => (
              <li className="blk-step" key={step.title}>
                <div className="blk-step__circle">{i + 1}</div>
                <div className="blk-step__text">
                  <p className="blk-step__title">{step.title}</p>
                  <p className="blk-step__desc">{step.desc}</p>
                </div>
              </li>
            ))}
          </ol>
        </div>
      </section>

      {/* ============ FOR CUSTOMERS ============ */}
      <section id="for-customers" className="blk-customers">
        <div className="blk-container">
          <p className="blk-section-kicker blk-pill">For Customers</p>
          <h2 className="blk-section-title">Your next haircut, booked in a minute</h2>
          <div className="blk-csteps">
            {CUSTOMER_FLOW.map((step, i) => (
              <article className="blk-cstep" key={step.title}>
                <span className="blk-cstep__icon"><Icon name={step.icon} /></span>
                <p className="blk-cstep__tag">Step {String(i + 1).padStart(2, '0')}</p>
                <h3 className="blk-cstep__title">{step.title}</h3>
                <p className="blk-cstep__desc">{step.desc}</p>
              </article>
            ))}
          </div>
          <div className="blk-download">
            <div className="blk-download__info">
              <p className="blk-download__head">Get the BookALook app today</p>
              <p className="blk-download__sub">Scan to install on iOS &amp; Android</p>
              {/* [PLACEHOLDER] Customer App store listing URLs — replace when listings go live. */}
              <div className="blk-badges blk-download__badges">
                <StoreBadge store="apple" url={CUSTOMER_APP_STORE_URL} label="App Store" />
                <StoreBadge store="google" url={CUSTOMER_PLAY_STORE_URL} label="Google Play" />
              </div>
            </div>
            <QrPlaceholder />
          </div>
        </div>
      </section>

      <section id="enquiry-section" className="enquiry-section" style={{ padding: '0 2rem 4rem 2rem', width: '100%', display: 'flex', justifyContent: 'center' }}>
        <div style={{ maxWidth: '600px', width: '100%', background: 'white', padding: '2rem', borderRadius: '12px', boxShadow: '0 4px 6px rgba(0,0,0,0.05)' }}>
          <h2 style={{ textAlign: 'center', marginBottom: '0.5rem' }}>Partner With Us</h2>
          <p style={{ textAlign: 'center', color: '#666', marginBottom: '2rem' }}>Fill out the form below and our team will get in touch to onboard your salon.</p>
          
          {status === 'success' ? (
            <div style={{ padding: '1rem', backgroundColor: '#e8f5e9', color: '#2e7d32', borderRadius: '8px', textAlign: 'center', fontWeight: 'bold' }}>
              Thank you! Your enquiry has been submitted successfully. Our team will contact you soon.
            </div>
          ) : (
            <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
              {status === 'error' && (
                <div style={{ padding: '0.75rem', backgroundColor: '#ffebee', color: '#c62828', borderRadius: '8px', fontSize: '0.9rem' }}>
                  {errorMessage}
                </div>
              )}
              
              <div>
                <label style={{ display: 'block', marginBottom: '0.5rem', fontWeight: 500 }}>Salon Name *</label>
                <input 
                  type="text" 
                  name="salon_name" 
                  required 
                  value={formData.salon_name} 
                  onChange={handleInputChange}
                  style={{ width: '100%', padding: '0.75rem', border: '1px solid #ccc', borderRadius: '8px' }}
                />
              </div>

              <div>
                <label style={{ display: 'block', marginBottom: '0.5rem', fontWeight: 500 }}>Owner Name *</label>
                <input 
                  type="text" 
                  name="owner_name" 
                  required 
                  value={formData.owner_name} 
                  onChange={handleInputChange}
                  style={{ width: '100%', padding: '0.75rem', border: '1px solid #ccc', borderRadius: '8px' }}
                />
              </div>

              <div>
                <label style={{ display: 'block', marginBottom: '0.5rem', fontWeight: 500 }}>Phone Number *</label>
                <input 
                  type="tel" 
                  name="phone" 
                  required 
                  value={formData.phone} 
                  onChange={handleInputChange}
                  style={{ width: '100%', padding: '0.75rem', border: '1px solid #ccc', borderRadius: '8px' }}
                />
              </div>

              <div>
                <label style={{ display: 'block', marginBottom: '0.5rem', fontWeight: 500 }}>State *</label>
                <select
                  name="state"
                  required
                  value={formData.state}
                  onChange={handleInputChange}
                  style={{ width: '100%', padding: '0.75rem', border: '1px solid #ccc', borderRadius: '8px', background: 'white' }}
                >
                  <option value="">Select your state</option>
                  {states.map((s) => (
                    <option key={s} value={s}>{s}</option>
                  ))}
                </select>
              </div>

              <div>
                <label style={{ display: 'block', marginBottom: '0.5rem', fontWeight: 500 }}>City *</label>
                <select
                  name="city_id"
                  required
                  disabled={!formData.state}
                  value={formData.city_id}
                  onChange={handleInputChange}
                  style={{ width: '100%', padding: '0.75rem', border: '1px solid #ccc', borderRadius: '8px', background: 'white' }}
                >
                  <option value="">
                    {!formData.state ? 'Choose a state first' : 'Select your city'}
                  </option>
                  {filteredCities.map((c) => (
                    <option key={c.id} value={c.id}>{c.name}</option>
                  ))}
                </select>
              </div>

              <div>
                <label style={{ display: 'block', marginBottom: '0.5rem', fontWeight: 500 }}>Area *</label>
                <select
                  name="sub_area_id"
                  required
                  disabled={!formData.city_id || loadingAreas}
                  value={formData.sub_area_id}
                  onChange={handleInputChange}
                  style={{ width: '100%', padding: '0.75rem', border: '1px solid #ccc', borderRadius: '8px', background: 'white' }}
                >
                  <option value="">
                    {!formData.city_id
                      ? 'Choose a city first'
                      : loadingAreas
                        ? 'Loading areas…'
                        : subAreas.length === 0
                          ? 'No areas listed for this city yet'
                          : 'Select your area'}
                  </option>
                  {subAreas.map((a) => (
                    <option key={a.id} value={a.id}>{a.name}</option>
                  ))}
                </select>
                <p style={{ marginTop: '0.4rem', fontSize: '0.8rem', color: '#777' }}>
                  Helps us send someone who already works near you.
                </p>
              </div>

              <div>
                <label style={{ display: 'block', marginBottom: '0.5rem', fontWeight: 500 }}>Street Address *</label>
                <textarea
                  name="street_address"
                  required
                  rows={2}
                  value={formData.street_address}
                  onChange={handleInputChange}
                  style={{ width: '100%', padding: '0.75rem', border: '1px solid #ccc', borderRadius: '8px' }}
                />
              </div>

              <div>
                <label style={{ display: 'block', marginBottom: '0.5rem', fontWeight: 500 }}>Pincode *</label>
                <input
                  type="text"
                  name="pincode"
                  required
                  value={formData.pincode}
                  onChange={handleInputChange}
                  style={{ width: '100%', padding: '0.75rem', border: '1px solid #ccc', borderRadius: '8px' }}
                />
              </div>

              <div>
                <label style={{ display: 'block', marginBottom: '0.5rem', fontWeight: 500 }}>Message (Optional)</label>
                <textarea 
                  name="message" 
                  rows={4}
                  value={formData.message} 
                  onChange={handleInputChange}
                  style={{ width: '100%', padding: '0.75rem', border: '1px solid #ccc', borderRadius: '8px' }}
                ></textarea>
              </div>

              <button 
                type="submit" 
                disabled={status === 'submitting'}
                style={{ 
                  padding: '1rem', 
                  backgroundColor: status === 'submitting' ? '#9c27b088' : '#9c27b0', 
                  color: 'white', 
                  border: 'none', 
                  borderRadius: '8px', 
                  fontWeight: 'bold',
                  fontSize: '1rem',
                  cursor: status === 'submitting' ? 'not-allowed' : 'pointer',
                  marginTop: '1rem'
                }}
              >
                {status === 'submitting' ? 'Submitting...' : 'Submit Enquiry'}
              </button>
            </form>
          )}
        </div>
      </section>

      {/* ============ FOR SALON BUSINESSES ============ */}
      <section id="for-salons" className="blk-salons">
        <div className="blk-container">
          <p className="blk-section-kicker">For Salon Businesses</p>
          <h2 className="blk-section-title">One app. Three ways to run your business.</h2>
          <div className="blk-salons__cards">
            {SALON_ROLES.map((role) => (
              <article className="blk-salons__card" key={role.title}>
                <span className="blk-salons__card-icon"><Icon name={role.icon} /></span>
                <h3 className="blk-salons__card-title">{role.title}</h3>
                <p className="blk-salons__card-role">{role.role}</p>
                <p className="blk-salons__card-desc">{role.desc}</p>
              </article>
            ))}
          </div>
          {/* [PLACEHOLDER] Partner App store listing URLs — this is a SEPARATE app from the
              Customer App, so it needs its own badges (not a repeat of section 5's links). */}
          <div className="blk-badges blk-badges--center">
            <StoreBadge store="apple" url={PARTNER_APP_STORE_URL} label="App Store" />
            <StoreBadge store="google" url={PARTNER_PLAY_STORE_URL} label="Google Play" />
          </div>
          <p className="blk-salons__hint">The Partner App — one download for owners, staff, and collaborators.</p>
        </div>
      </section>

      {/* ============ HOW IT WORKS — FOR PARTNERSHIP (distinct step flow) ============ */}
      <section id="partners" className="blk-partnership">
        <div className="blk-container">
          <p className="blk-section-kicker">How it works — For Salon Owners</p>
          <h2 className="blk-section-title">Getting your salon on BookALook</h2>
          <p className="blk-partnership__sub">
            A separate, simpler flow: you are not booking a service — you are joining the platform as a partner.
          </p>
          <ol className="blk-psteps">
            {PARTNER_STEPS.map((step, i) => (
              <li className="blk-pstep" key={step.title}>
                <div className="blk-pstep__badge"><span>{i + 1}</span></div>
                <div className="blk-pstep__text">
                  <p className="blk-pstep__title">{step.title}</p>
                  <p className="blk-pstep__desc">{step.desc}</p>
                </div>
              </li>
            ))}
          </ol>
          <div className="blk-partnership__cta">
            <a className="blk-btn blk-btn--gold" href="#enquiry-section">Start with the enquiry form</a>
          </div>
        </div>
      </section>

      {/* ============ WHY BOOKALOOK ============ */}
      <section id="why-bookalook" className="blk-why">
        <div className="blk-container">
          <p className="blk-section-kicker">Why BookALook</p>
          <h2 className="blk-section-title">Built so both sides actually enjoy it</h2>
          <div className="blk-why__grid">
            {WHY_FEATURES.map((feature) => (
              <article className="blk-why__card" key={feature.title}>
                <span className="blk-why__icon"><Icon name={feature.icon} /></span>
                <h3 className="blk-why__title">{feature.title}</h3>
                <p className="blk-why__desc">{feature.desc}</p>
              </article>
            ))}
          </div>
        </div>
      </section>

      {/* ============ FAQ ============ */}
      <section id="faq" className="blk-faq">
        <div className="blk-container">
          <p className="blk-section-kicker">FAQ</p>
          <h2 className="blk-section-title">Questions, answered</h2>
          <div className="blk-faq__list">
            {FAQ_ITEMS.map((item) => (
              <details className="blk-faq__item" key={item.q}>
                {/* [PLACEHOLDER] FAQ answer copy below is provisional — replace with final wording. */}
                <summary className="blk-faq__q">{item.q}</summary>
                <p className="blk-faq__a">{item.a}</p>
              </details>
            ))}
          </div>
        </div>
      </section>

      {/* ============ FOOTER ============ */}
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
            <Link className="blk-footer__link" href="/privacy">Privacy Policy</Link>
            <Link className="blk-footer__link" href="/terms">Terms &amp; Conditions</Link>
          </div>
          <div className="blk-footer__col">
            <p className="blk-footer__head">Contact</p>
            <a className="blk-footer__link" href="mailto:hello@bookalook.in">hello@bookalook.in</a>
            <a className="blk-footer__link" href="tel:+910000000000">+91 00000 00000</a>
            <div className="blk-footer__social">
              <a href={SOCIAL_URLS.instagram} target="_blank" rel="noopener noreferrer">Instagram</a>
              <a href={SOCIAL_URLS.facebook} target="_blank" rel="noopener noreferrer">Facebook</a>
              <a href={SOCIAL_URLS.x} target="_blank" rel="noopener noreferrer">X</a>
            </div>
          </div>
        </div>
        <div className="blk-footer__bottom">
          © {new Date().getFullYear()} BookALook. All rights reserved.
        </div>
      </footer>
    </div>
  );
}
