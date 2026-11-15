'use client';

import { useEffect, useRef, useState } from 'react';
import { Parallax, Reveal } from '../motion';
import { AppScreen, PhoneStack, type ScreenName } from '../phone';
import st from '../site.module.css';
import h from './home.module.css';

/* ============================================================================
   Inside the app — pick a feature, the phone shows that screen.

   Until somebody touches it the walkthrough steps through the features by
   itself (only while it is on screen, and never under reduced motion), so the
   section reads as a demo rather than a list. The first click, tap or key
   press hands control over for good.
   ============================================================================ */

const FEATURES: { screen: ScreenName; icon: string; title: string; desc: string }[] = [
  { screen: 'slots', icon: '⏱️', title: 'Real-Time Free Slots', desc: 'The exact times your stylist is free today — nothing you cannot actually book.' },
  { screen: 'menu', icon: '🧾', title: 'Transparent Menus & Rate Cards', desc: 'Every service and its price, before you leave home.' },
  { screen: 'ticket', icon: '📲', title: 'Flash & Walk-In (QR Check-In)', desc: 'Your booking is a QR ticket. One scan at the door.' },
  { screen: 'family', icon: '👨‍👩‍👧', title: 'Book For Friends & Family', desc: 'Book for a parent, partner or friend — the salon knows who to expect.' },
  { screen: 'reminders', icon: '💬', title: 'WhatsApp Reminders', desc: 'A confirmation the moment you book and a nudge before you go.' },
  { screen: 'reschedule', icon: '🔁', title: 'Reschedule In A Tap', desc: 'Plans changed? Move your slot from the app, within the salon’s cut-off.' },
];

const SCREENS = FEATURES.map((f) => f.screen);

export default function InsideApp({ qr }: { qr: string }) {
  const [current, setCurrent] = useState<ScreenName>('slots');
  const [auto, setAuto] = useState(true);
  const section = useRef<HTMLElement>(null);

  useEffect(() => {
    const el = section.current;
    if (!el || !auto) return;
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;

    let timer: ReturnType<typeof setInterval> | undefined;
    const io = new IntersectionObserver(([entry]) => {
      clearInterval(timer);
      if (entry.isIntersecting) {
        timer = setInterval(() => {
          setCurrent((now) => SCREENS[(SCREENS.indexOf(now) + 1) % SCREENS.length]);
        }, 3200);
      }
    }, { threshold: 0.35 });
    io.observe(el);

    return () => {
      io.disconnect();
      clearInterval(timer);
    };
  }, [auto]);

  const pick = (screen: ScreenName) => {
    setAuto(false);
    setCurrent(screen);
  };

  const tab = (f: (typeof FEATURES)[number]) => (
    <button
      key={f.screen}
      type="button"
      aria-pressed={current === f.screen}
      aria-controls="app-demo-phone"
      className={`${h.tab} ${current === f.screen ? h.tabOn : ''}`}
      onClick={() => pick(f.screen)}
    >
      <i aria-hidden="true">{f.icon}</i>
      <span><b>{f.title}</b><span>{f.desc}</span></span>
    </button>
  );

  const active = FEATURES.find((f) => f.screen === current)!;

  return (
    <section id="app" ref={section} className={`${st.sec} ${h.inside}`}>
      <Parallax speed={0.2} className={h.insideGlow} />
      <Parallax speed={-0.14} className={h.insideGlow2} />
      <div className={st.wrap}>
        <Reveal className={st.center}>
          <p className={`${st.kicker} ${h.kickerLight}`}>Inside the app</p>
          <h2 className={st.big}>Tap a feature. <em>Watch it work.</em></h2>
          <p className={`${st.lead} ${h.leadLight}`}>Everything you need to book a salon the way you would book a cab.</p>
        </Reveal>

        <div className={h.demo} role="group" aria-label="App features">
          <Parallax speed={0.05} className={h.tabCol}>{FEATURES.slice(0, 3).map(tab)}</Parallax>

          <Parallax speed={-0.06} className={h.demoPhone}>
            <div id="app-demo-phone">
              <PhoneStack
                screens={SCREENS}
                current={current}
                render={(name) => <AppScreen name={name} qr={qr} />}
                label={`BookALook app screen: ${active.title}`}
              />
            </div>
          </Parallax>

          <Parallax speed={0.05} className={h.tabCol}>{FEATURES.slice(3).map(tab)}</Parallax>
        </div>
      </div>
    </section>
  );
}
