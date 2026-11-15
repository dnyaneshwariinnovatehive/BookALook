'use client';

import { useEffect, useRef, useState } from 'react';
import { onFrame, Reveal } from '../motion';
import { AppScreen, Phone, PhoneStack } from '../phone';
import st from '../site.module.css';
import h from './home.module.css';

/* ============================================================================
   How it works — the pinned, scroll-driven story.

   On a wide screen the stage sticks to the viewport for three screens' worth
   of scrolling. The page scrolls normally the whole time (nothing is hijacked):
   the scroll position is only *read*, and turned into which step is showing
   and how far the background layers have drifted. Each layer moves at its own
   speed, which is where the depth comes from.

   Phones, and anyone who asks for reduced motion, get the three steps stacked
   one after another instead — same content, no pinning.
   ============================================================================ */

const STEPS = [
  {
    key: 'discover',
    screen: 'discover',
    label: 'Discover',
    title: 'Find Your Perfect Salon.',
    desc: 'Explore verified salons, compare services, and choose your preferred stylist.',
    chips: [
      { icon: '🛡️', title: 'Verified salon', sub: 'Checked by our team' },
      { icon: '⭐', title: 'Real ratings', sub: 'From people who visited' },
      { icon: '💇', title: 'Pick your stylist', sub: 'See who is free' },
    ],
  },
  {
    key: 'reserve',
    screen: 'confirmed',
    label: 'Reserve',
    title: 'Your Slot. Your Time.',
    desc: 'Check live availability, choose your preferred time and stylist, and confirm in a tap.',
    chips: [
      { icon: '🗓️', title: 'Pick a day', sub: 'Today or later this week' },
      { icon: '⏱️', title: 'Live free slots', sub: 'Only times you can book' },
      { icon: '✅', title: 'Booking confirmed', sub: 'Sent to you on WhatsApp' },
    ],
  },
  {
    key: 'walk-in',
    screen: 'ticket',
    label: 'Walk in & relax',
    title: 'Skip the Queue. Enjoy Your Moment.',
    desc: 'Walk into the salon, show your digital QR ticket, and get checked in.',
    chips: [
      { icon: '📲', title: 'Scanned at the door', sub: 'One scan, you are in' },
      { icon: '💺', title: 'Your chair is ready', sub: 'No waiting bench' },
      { icon: '💜', title: 'Look great', sub: 'Rebook in two taps' },
    ],
  },
] as const;

type StepScreen = (typeof STEPS)[number]['screen'];
const SCREENS = STEPS.map((s) => s.screen) as readonly StepScreen[];

export default function HowItWorks({ qr }: { qr: string }) {
  const track = useRef<HTMLDivElement>(null);
  const stage = useRef<HTMLDivElement>(null);
  const [step, setStep] = useState(0);

  useEffect(() => {
    const el = track.current;
    const target = stage.current;
    if (!el || !target) return;
    let last = -1;
    return onFrame(() => {
      const rect = el.getBoundingClientRect();
      const travel = rect.height - window.innerHeight;
      if (travel <= 0) return;
      const progress = Math.min(1, Math.max(0, -rect.top / travel));
      // Read by the CSS: every layer scales this by its own speed.
      target.style.setProperty('--p', progress.toFixed(4));
      const next = Math.min(STEPS.length - 1, Math.floor(progress * STEPS.length));
      if (next !== last) {
        last = next;
        setStep(next);
      }
    });
  }, []);

  /** Clicking a dot scrolls the page to that step — still ordinary scrolling. */
  const goTo = (index: number) => {
    const el = track.current;
    if (!el) return;
    const travel = el.offsetHeight - window.innerHeight;
    const top = el.getBoundingClientRect().top + window.scrollY + travel * ((index + 0.5) / STEPS.length);
    window.scrollTo({ top, behavior: 'smooth' });
  };

  return (
    <section id="how-it-works" className={h.how}>
      <div className={`${st.wrap} ${st.center} ${h.howHead}`}>
        <Reveal>
          <p className={st.kicker}>How it works</p>
          <h2 className={st.big}>Three steps. <em>Zero waiting.</em></h2>
        </Reveal>
      </div>

      {/* ---------- Wide screens: pinned stage ---------- */}
      <div ref={track} className={h.track}>
        <div ref={stage} className={h.sticky}>
          <div className={h.layers} aria-hidden="true">
            <span className={`${h.orb} ${h.orbA}`} />
            <span className={`${h.orb} ${h.orbB}`} />
            <span className={`${h.orb} ${h.orbC}`} />
            <span className={h.gridLines} />
            <span className={h.howRing} />
          </div>

          <div className={`${st.wrap} ${h.stageGrid}`}>
            <div className={h.chapters}>
              <span className={h.bigNum} aria-hidden="true">{step + 1}</span>
              {STEPS.map((s, i) => (
                <div key={s.key} className={`${h.chapterText} ${i === step ? h.on : ''} ${i < step ? h.past : ''}`} aria-hidden={i !== step}>
                  <p className={h.stepLabel}>Step {String(i + 1).padStart(2, '0')} · {s.label}</p>
                  <h3>{s.title}</h3>
                  <p className={h.stepDesc}>{s.desc}</p>
                </div>
              ))}
              <div className={h.dots} role="tablist" aria-label="Booking steps">
                {STEPS.map((s, i) => (
                  <button
                    key={s.key}
                    type="button"
                    role="tab"
                    aria-selected={i === step}
                    aria-label={`Step ${i + 1}: ${s.label}`}
                    className={`${h.dot} ${i === step ? h.dotOn : ''}`}
                    onClick={() => goTo(i)}
                  />
                ))}
                <span className={h.dotHint}>Keep scrolling</span>
              </div>
            </div>

            <div className={h.phoneCol}>
              <PhoneStack
                screens={SCREENS}
                current={STEPS[step].screen}
                render={(name) => <AppScreen name={name} qr={qr} />}
                className={h.howPhone}
                label={`BookALook app, step ${step + 1}: ${STEPS[step].label}`}
              />
            </div>

            <div className={h.chipCol} aria-hidden="true">
              {STEPS.map((s, i) => (
                <div key={s.key} className={`${h.chipSet} ${i === step ? h.on : ''} ${i < step ? h.past : ''}`}>
                  {s.chips.map((chip, n) => (
                    <div key={chip.title} className={`${st.float} ${h.chip} ${h[`chip${n}`]}`}>
                      <i>{chip.icon}</i>
                      <span>{chip.title}<small>{chip.sub}</small></span>
                    </div>
                  ))}
                </div>
              ))}
            </div>
          </div>

          <span className={h.progress} aria-hidden="true"><span /></span>
        </div>
      </div>

      {/* ---------- Phones and reduced motion: stacked ---------- */}
      <ol className={`${st.wrap} ${h.stack}`}>
        {STEPS.map((s, i) => (
          <Reveal as="li" key={s.key} className={h.stackItem}>
            <span className={h.stackNum} aria-hidden="true">{i + 1}</span>
            <p className={h.stepLabel}>Step {String(i + 1).padStart(2, '0')} · {s.label}</p>
            <h3>{s.title}</h3>
            <p className={h.stepDesc}>{s.desc}</p>
            <Phone className={h.stackPhone} label={`BookALook app: ${s.label}`}>
              <AppScreen name={s.screen} qr={qr} />
            </Phone>
          </Reveal>
        ))}
      </ol>
    </section>
  );
}
