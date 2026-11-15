'use client';

import Image from 'next/image';
import type { ReactNode } from 'react';
import { QrCode } from './motion';
import st from './site.module.css';

/* ============================================================================
   The phone mockup and the app screens drawn inside it.

   These are illustrations of the Customer App (and one of the Partner App),
   rebuilt in HTML so they stay sharp at any size and can change on scroll or
   on a tap. The names, times and prices in them are examples, not listings.
   ============================================================================ */

export type ScreenName =
  | 'discover'
  | 'slots'
  | 'menu'
  | 'ticket'
  | 'family'
  | 'reminders'
  | 'reschedule';

function Photo({ src, sizes }: { src: string; sizes: string }) {
  return <Image src={src} alt="" fill sizes={sizes} />;
}

function StatusBar() {
  return (
    <div className={st.sb} aria-hidden="true">
      <span>9:41</span>
      <span>● ● ●</span>
    </div>
  );
}

function Stylists() {
  return (
    <div className={st.sty}>
      <div className={st.on}>
        <span className={st.avatar}><Photo src="/site/stylist-1.jpg" sizes="30px" /></span>
        Riya<small>● Free now</small>
      </div>
      <div>
        <span className={st.avatar}><Photo src="/site/stylist-2.jpg" sizes="30px" /></span>
        Aman<small>● Free 5:30</small>
      </div>
      <div>
        <span className={st.avatar}><Photo src="/site/makeup.jpg" sizes="30px" /></span>
        Neha<small>● Free 6:00</small>
      </div>
    </div>
  );
}

/** A salon's page with its stylists and today's live slots. */
export function SalonScreen() {
  return (
    <>
      <StatusBar />
      <div className={st.shot}>
        <Photo src="/site/salon-1.jpg" sizes="280px" />
        <span>✓ Verified salon</span>
      </div>
      <div className={st.pad}>
        <div className={st.sTitle}>Glow Studio</div>
        <div className={st.sMeta}>★ 4.8 · 1.2 km · Open till 9 PM</div>
        <div className={st.lbl}>Choose stylist</div>
        <Stylists />
        <div className={st.lbl}>Today · live slots</div>
        <div className={st.slots}>
          <span className={st.off}>4:30</span><span>5:00</span><span>5:30</span>
          <span className={st.on}>6:30</span><span>7:00</span><span className={st.off}>7:30</span>
        </div>
        <div className={st.pBtn}>Confirm 6:30 PM slot</div>
      </div>
    </>
  );
}

function DiscoverScreen() {
  const salons = [
    { img: '/site/salon-1.jpg', name: 'Glow Studio', meta: '★ 4.8 · 1.2 km · from ₹199' },
    { img: '/site/salon-2.jpg', name: 'Urban Trim', meta: '★ 4.7 · 1.8 km · from ₹149' },
    { img: '/site/salon-3.jpg', name: 'Aura Lounge', meta: '★ 4.9 · 2.0 km · from ₹349' },
    { img: '/site/salon-4.jpg', name: 'The Nail Bar', meta: '★ 4.6 · 2.4 km · from ₹299' },
  ];
  return (
    <>
      <StatusBar />
      <div className={st.pad}>
        <div className={st.sMeta}>Good evening</div>
        <div className={st.sTitle}>Find a salon near you</div>
        <div className={st.srch}>🔍 Search haircut, facial, spa…</div>
        <div className={st.chips}>
          <span className={st.on}>Hair</span><span>Skin</span><span>Nails</span><span>Spa</span>
        </div>
        {salons.map((s) => (
          <div className={st.sCard} key={s.name}>
            <span className={st.thumb}><Photo src={s.img} sizes="54px" /></span>
            <div><b>{s.name}</b><small>{s.meta}</small></div>
            <i>Book</i>
          </div>
        ))}
      </div>
    </>
  );
}

function SlotsScreen({ confirmed = false }: { confirmed?: boolean }) {
  return (
    <>
      <StatusBar />
      <div className={st.pad}>
        <div className={st.sTitle}>Pick your time</div>
        <div className={st.sMeta}>Glow Studio · Haircut · 30 min</div>
        {!confirmed && (
          <>
            <div className={st.lbl}>Stylist</div>
            <Stylists />
          </>
        )}
        <div className={st.lbl}>Date</div>
        <div className={st.chips}>
          <span className={confirmed ? '' : st.on}>Today</span>
          <span className={confirmed ? st.on : ''}>Sat 16</span>
          <span>Sun 17</span><span>Mon 18</span>
        </div>
        <div className={st.lbl}>Live free slots</div>
        <div className={st.slots}>
          <span className={st.off}>4:00</span><span className={st.off}>4:30</span><span>5:00</span>
          <span>5:30</span><span>6:00</span><span className={st.on}>6:30</span>
          <span>7:00</span><span className={st.off}>7:30</span><span>8:00</span>
        </div>
        {confirmed ? (
          <>
            <div className={st.okBox}>
              <span className={st.ok}>✓ Confirmed</span>
              <div className={st.sTitle} style={{ marginTop: 8, fontSize: 14 }}>Sat 16 Nov · 6:30 PM</div>
              <div className={st.sMeta}>with Riya · Glow Studio</div>
            </div>
            <div className={st.pBtn}>View my booking</div>
          </>
        ) : (
          <div className={st.pBtn}>Confirm 6:30 PM slot</div>
        )}
      </div>
    </>
  );
}

function MenuScreen() {
  const rows = [
    ['Haircut', '30 min', '₹199'],
    ['Beard trim', '20 min', '₹99'],
    ['Hair spa', '45 min', '₹599'],
    ['Clean-up facial', '40 min', '₹449'],
    ['Hair colour', '90 min', '₹1,299'],
    ['Head massage', '30 min', '₹249'],
  ];
  return (
    <>
      <StatusBar />
      <div className={st.pad}>
        <div className={st.sTitle}>Services &amp; prices</div>
        <div className={st.sMeta}>Glow Studio · what you see is what you pay</div>
        <div className={st.chips}>
          <span className={st.on}>All</span><span>Hair</span><span>Skin</span><span>Grooming</span>
        </div>
        <div className={st.menu}>
          {rows.map(([name, mins, price]) => (
            <div key={name}>
              <div><b>{name}</b><small>{mins}</small></div>
              <span>{price}<i>Add</i></span>
            </div>
          ))}
        </div>
      </div>
    </>
  );
}

function TicketScreen({ qr }: { qr: string }) {
  return (
    <>
      <StatusBar />
      <div className={st.tk}>
        <span className={st.ok}>✓ Booking confirmed</span>
        <QrCode value={qr} size={150} label="Sample booking QR code" />
        <div className={st.sTitle}>Show this at the salon</div>
        <div className={st.sMeta}>Glow Studio · Haircut</div>
        <div className={st.tkRow}>
          <div><small>Date</small><b>Sat, 16 Nov</b></div>
          <div><small>Time</small><b>6:30 PM</b></div>
          <div><small>Stylist</small><b>Riya</b></div>
        </div>
      </div>
      <div className={st.pad} style={{ paddingTop: 0 }}>
        <div className={st.sCard} style={{ marginTop: 0 }}>
          <span className={st.thumb}>💬</span>
          <div><b>Reminder sent on WhatsApp</b><small>1 hour before your slot</small></div>
        </div>
      </div>
    </>
  );
}

function FamilyScreen() {
  return (
    <>
      <StatusBar />
      <div className={st.pad}>
        <div className={st.sTitle}>Who is this booking for?</div>
        <div className={st.sMeta}>Glow Studio · Haircut · Sat 6:30 PM</div>
        <div className={st.lbl}>Booking for</div>
        <div className={st.who}>
          <span>Myself</span>
          <span className={st.on}>Someone else</span>
        </div>
        <div className={st.lbl}>Their details</div>
        <div className={st.field}><small>Name</small>Papa</div>
        <div className={st.field}><small>Gender</small>Male</div>
        <div className={st.field}><small>Phone (optional)</small>98••• ••210</div>
        <div className={st.okBox} style={{ background: 'var(--soft2)' }}>
          <div className={st.sMeta}>The salon will expect <b>Papa</b>. The booking stays in your app.</div>
        </div>
        <div className={st.pBtn}>Continue</div>
      </div>
    </>
  );
}

function RemindersScreen() {
  return (
    <>
      <StatusBar />
      <div className={st.pad}>
        <div className={st.sTitle}>WhatsApp</div>
        <div className={st.sMeta}>BookALook · today</div>
        <div className={st.bubble}>
          <b>Booking confirmed ✅</b>
          Haircut at Glow Studio<br />Sat, 16 Nov · 6:30 PM with Riya
          <time>10:02 AM</time>
        </div>
        <div className={st.bubble}>
          <b>See you in an hour ⏰</b>
          Your 6:30 PM slot at Glow Studio is coming up. Show your QR at the door.
          <time>5:30 PM</time>
        </div>
        <div className={st.bubble}>
          <b>Thanks for visiting 💜</b>
          Your invoice is ready in the app.
          <time>7:12 PM</time>
        </div>
      </div>
    </>
  );
}

function RescheduleScreen() {
  return (
    <>
      <StatusBar />
      <div className={st.pad}>
        <div className={st.sTitle}>Move your booking</div>
        <div className={st.sMeta}>Glow Studio · Haircut with Riya</div>
        <div className={st.row2}>
          <div><b>Sat, 16 Nov · 6:30 PM</b><small>Current slot</small></div>
          <i className={st.tagAmber}>Moving</i>
        </div>
        <div className={st.lbl}>Pick a new date</div>
        <div className={st.chips}>
          <span>Sat 16</span><span className={st.on}>Sun 17</span><span>Mon 18</span><span>Tue 19</span>
        </div>
        <div className={st.lbl}>Free slots</div>
        <div className={st.slots}>
          <span>10:30</span><span className={st.on}>11:00</span><span className={st.off}>11:30</span>
          <span>12:00</span><span>4:30</span><span>5:00</span>
        </div>
        <div className={st.pBtn}>Move to Sun · 11:00 AM</div>
      </div>
    </>
  );
}

/** Today's schedule in the Partner App. */
export function PartnerScreen() {
  return (
    <>
      <StatusBar />
      <div className={st.pad}>
        <div className={st.sMeta}>Partner App · Today</div>
        <div className={st.sTitle}>Glow Studio</div>
        <div className={st.kpis}>
          <div><small>Bookings today</small><b>14</b></div>
          <div><small>Chairs free now</small><b>2</b></div>
        </div>
        <div className={st.lbl}>Up next</div>
        <div className={st.row2}><div><b>5:00 PM · Haircut</b><small>Aarav · with Riya</small></div><i className={st.tagGreen}>Checked in</i></div>
        <div className={st.row2}><div><b>5:30 PM · Beard trim</b><small>Kabir · with Aman</small></div><i className={st.tagPurple}>Booked</i></div>
        <div className={st.row2}><div><b>6:00 PM · Facial</b><small>Meera · with Neha</small></div><i className={st.tagPurple}>Booked</i></div>
        <div className={st.row2}><div><b>6:15 PM · Walk-in</b><small>Haircut · with Riya</small></div><i className={st.tagAmber}>Walk-in</i></div>
        <div className={st.pBtn}>+ Add walk-in</div>
      </div>
    </>
  );
}

/** One of the customer app screens, by name. */
export function AppScreen({ name, qr }: { name: ScreenName | 'confirmed'; qr: string }) {
  switch (name) {
    case 'discover': return <DiscoverScreen />;
    case 'slots': return <SlotsScreen />;
    case 'confirmed': return <SlotsScreen confirmed />;
    case 'menu': return <MenuScreen />;
    case 'ticket': return <TicketScreen qr={qr} />;
    case 'family': return <FamilyScreen />;
    case 'reminders': return <RemindersScreen />;
    case 'reschedule': return <RescheduleScreen />;
  }
}

/** The handset. Children are whatever is on screen. */
export function Phone({ children, className, label }: { children: ReactNode; className?: string; label: string }) {
  return (
    <div className={`${st.phone} ${className ?? ''}`} role="img" aria-label={label}>
      <div className={st.screen} aria-hidden="true">{children}</div>
    </div>
  );
}

/**
 * A handset holding several screens at once and showing one of them. The
 * others stay mounted so switching is a cross-fade, not a reload.
 */
export function PhoneStack<T extends string>({
  screens,
  current,
  render,
  className,
  label,
}: {
  screens: readonly T[];
  current: T;
  render: (name: T) => ReactNode;
  className?: string;
  label: string;
}) {
  return (
    <Phone className={className} label={label}>
      {screens.map((name) => (
        <div key={name} className={`${st.screenLayer} ${name === current ? st.screenLayerOn : ''}`}>
          {render(name)}
        </div>
      ))}
    </Phone>
  );
}
