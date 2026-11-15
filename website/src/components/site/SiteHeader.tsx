'use client';

import Image from 'next/image';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useEffect, useState } from 'react';
import { useCity, useSalonCities } from '@/lib/site-city';
import st from '@/app/(site)/site.module.css';
import c from './chrome.module.css';

/**
 * The public site header: a floating bar that sits over the hero and tightens
 * up once the page scrolls.
 *
 * The nav targets are absolute (`/#services`, not `#services`) because these
 * anchors live on the home page. As bare fragments they resolved against
 * whatever page you were on, so "How it works" from the Terms page would have
 * scrolled to nothing.
 *
 * The salon-owner page gets its own set of links and its own main button:
 * someone reading about the Partner App wants "Register", not "Download".
 */

const CUSTOMER_LINKS = [
  { href: '/#services', label: 'Services' },
  { href: '/#how-it-works', label: 'How it works' },
  { href: '/#perks', label: 'App perks' },
  { href: '/#reviews', label: 'Reviews' },
];

const PARTNER_LINKS = [
  { href: '/partner#why', label: 'Why BookALook' },
  { href: '/partner#features', label: 'Features' },
  { href: '/partner#pricing', label: 'Pricing' },
  { href: '/partner#get-started', label: 'Get started' },
  { href: '/partner#faq', label: 'FAQ' },
];

function CityPicker({ className }: { className?: string }) {
  const cities = useSalonCities();
  const [cityId, setCityId] = useCity();

  // Nothing to choose from (or the list has not arrived): show nothing rather
  // than an empty dropdown.
  if (cities.length === 0) return null;

  return (
    <label className={`${c.city} ${className ?? ''}`}>
      <span aria-hidden="true">📍</span>
      <span className={c.srOnly}>Your city</span>
      <select value={cities.some((x) => x.id === cityId) ? cityId : ''} onChange={(e) => setCityId(e.target.value)}>
        <option value="">Select city</option>
        {cities.map((city) => (
          <option key={city.id} value={city.id}>{city.name}</option>
        ))}
      </select>
    </label>
  );
}

export default function SiteHeader() {
  const pathname = usePathname();
  const partner = pathname?.startsWith('/partner') ?? false;
  const links = partner ? PARTNER_LINKS : CUSTOMER_LINKS;
  const [scrolled, setScrolled] = useState(false);
  const [open, setOpen] = useState(false);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 24);
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, []);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && setOpen(false);
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open]);

  const close = () => setOpen(false);

  return (
    <header className={`${c.header} ${scrolled ? c.scrolled : ''}`}>
      <div className={st.wrap}>
        <div className={c.bar}>
          <Link href="/" className={c.logo} aria-label="BookALook home" onClick={close}>
            <Image src="/logo-app.png" alt="BookALook" width={131} height={34} priority />
          </Link>

          {!partner && <CityPicker className={c.cityDesk} />}

          <nav className={c.nav} aria-label="Primary">
            {links.map((link) => (
              <Link key={link.label} className={c.link} href={link.href}>{link.label}</Link>
            ))}
          </nav>

          {partner ? (
            <Link className={c.owner} href="/#download">Looking to book? <b>Get the app →</b></Link>
          ) : (
            <Link className={c.owner} href="/partner">Salon owner? <b>Partner with us →</b></Link>
          )}

          <Link className={`${st.btn} ${c.cta}`} href={partner ? '/partner#enquiry-section' : '/#download'} onClick={close}>
            {partner ? 'Register your salon' : 'Download app'}
          </Link>

          <button
            type="button"
            className={c.burger}
            aria-label={open ? 'Close menu' : 'Open menu'}
            aria-expanded={open}
            aria-controls="site-menu"
            onClick={() => setOpen((v) => !v)}
          >
            <span className={open ? c.burgerOpen : ''} aria-hidden="true" />
          </button>
        </div>

        <div id="site-menu" className={c.menu} hidden={!open}>
          {links.map((link) => (
            <Link key={link.label} className={c.menuLink} href={link.href} onClick={close}>
              {link.label}
            </Link>
          ))}
          {!partner && <CityPicker className={c.cityMenu} />}
          {partner ? (
            <Link className={c.menuOwner} href="/#download" onClick={close}>Looking to book? <b>Get the app →</b></Link>
          ) : (
            <Link className={c.menuOwner} href="/partner" onClick={close}>Salon owner? <b>Partner with us →</b></Link>
          )}
        </div>
      </div>
    </header>
  );
}
