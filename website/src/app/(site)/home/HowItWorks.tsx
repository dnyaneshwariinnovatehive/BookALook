'use client';

import { useEffect, useRef, useState, type CSSProperties } from 'react';
import { onFrame, Reveal } from '../motion';
import { AppScreen, Phone, PhoneStack } from '../phone';
import st from '../site.module.css';
import h from './home.module.css';

/* ============================================================================
   How it works — the pinned, scroll-driven story.

   On a wide screen the stage sticks to the viewport for three screens' worth
   of scrolling. The page scrolls normally the whole time (nothing is hijacked):
   the scroll position is only *read*, eased a little so the motion glides
   instead of stepping, and written to three CSS variables on the stage:

     --prog  0 → 1 across the whole section (rail fill, giant word, glow hue)
     --turn  0 → 1 → 0 around each step change (the phone turns, the glow
             blooms, the ring spins — the moment you notice a new step)
     --step  the step index, for the rolling counter

   Every layer reads those at its own strength, which is where the depth comes
   from. Phones, and anyone who asks for reduced motion, get the three steps
   stacked one after another instead — same content, no pinning.
   ============================================================================ */

const STEPS = [
  {
    key: 'discover',
    screen: 'discover',
    label: 'Discover',
    word: 'Discover',
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
    word: 'Reserve',
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
    word: 'Relax',
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
const N = STEPS.length;

const clamp01 = (v: number) => Math.min(1, Math.max(0, v));
const smooth = (t: number) => t * t * (3 - 2 * t);
/** Where step [i] sits on the 0 → 1 progress line; layers drift around it. */
const centreOf = (i: number) => (i + 0.5) / N;

export default function HowItWorks({ qr }: { qr: string }) {
  const track = useRef<HTMLDivElement>(null);
  const stage = useRef<HTMLDivElement>(null);
  const [step, setStep] = useState(0);

  useEffect(() => {
    const el = track.current;
    const target = stage.current;
    if (!el || !target) return;

    let goal = 0;
    let shown = -1;
    let raf = 0;
    let lastStep = -1;

    const apply = (p: number) => {
      const b = p * N;
      const index = Math.min(N - 1, Math.floor(b));
      // 1 exactly at a step change, fading to 0 half a step either side.
      let turn = 0;
      for (let k = 1; k < N; k++) turn = Math.max(turn, 1 - Math.min(1, Math.abs(b - k) / 0.5));
      const s = target.style;
      s.setProperty('--prog', p.toFixed(4));
      s.setProperty('--turn', smooth(turn).toFixed(4));
      if (index !== lastStep) {
        lastStep = index;
        s.setProperty('--step', String(index));
        setStep(index);
      }
    };

    // Ease towards the scroll position so the motion glides rather than
    // jumping with each wheel notch. Runs only while catching up.
    const tick = () => {
      shown += (goal - shown) * 0.12;
      if (Math.abs(goal - shown) < 0.0005) shown = goal;
      apply(shown);
      raf = shown === goal ? 0 : requestAnimationFrame(tick);
    };

    const stop = onFrame(() => {
      const rect = el.getBoundingClientRect();
      const travel = rect.height - window.innerHeight;
      if (travel <= 0) return;
      goal = clamp01(-rect.top / travel);
      if (shown < 0) {
        shown = goal;
        apply(goal);
      } else if (!raf) {
        raf = requestAnimationFrame(tick);
      }
    });

    return () => {
      stop();
      cancelAnimationFrame(raf);
    };
  }, []);

  /** Clicking a step scrolls the page to it — still ordinary scrolling. */
  const goTo = (index: number) => {
    const el = track.current;
    if (!el) return;
    const travel = el.offsetHeight - window.innerHeight;
    const top = el.getBoundingClientRect().top + window.scrollY + travel * centreOf(index);
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
            <div className={h.wordTrack}>
              {STEPS.map((s) => (
                <span key={s.key}>{s.word}</span>
              ))}
            </div>
            <span className={`${h.orb} ${h.orbA}`} />
            <span className={`${h.orb} ${h.orbB}`} />
            <span className={`${h.orb} ${h.orbC}`} />
            <span className={h.gridLines} />
          </div>

          <div className={`${st.wrap} ${h.stageGrid}`}>
            <div className={h.chapters}>
              <div className={h.counter} aria-hidden="true">
                <span className={h.counterWindow}>
                  <span className={h.counterReel}>
                    {STEPS.map((s, i) => (
                      <span key={s.key}>{String(i + 1).padStart(2, '0')}</span>
                    ))}
                  </span>
                </span>
                <span className={h.counterOf}>/ {String(N).padStart(2, '0')}</span>
              </div>

              <div className={h.chapterStack}>
                {STEPS.map((s, i) => (
                  <div
                    key={s.key}
                    className={`${h.chapterText} ${i === step ? h.on : ''} ${i < step ? h.past : ''}`}
                    style={{ '--c': centreOf(i) } as CSSProperties}
                    aria-hidden={i !== step}
                  >
                    <p className={h.stepLabel}>Step {String(i + 1).padStart(2, '0')} · {s.label}</p>
                    <h3>{s.title}</h3>
                    <p className={h.stepDesc}>{s.desc}</p>
                  </div>
                ))}
              </div>

              <div className={h.rail} role="tablist" aria-label="Booking steps">
                <span className={h.railTrack} aria-hidden="true">
                  <span className={h.railFill} />
                </span>
                {STEPS.map((s, i) => (
                  <button
                    key={s.key}
                    type="button"
                    role="tab"
                    aria-selected={i === step}
                    aria-label={`Step ${i + 1}: ${s.label}`}
                    className={`${h.railStep} ${i <= step ? h.railDone : ''} ${i === step ? h.railOn : ''}`}
                    style={{ left: `${(i / N) * 100}%` }}
                    onClick={() => goTo(i)}
                  >
                    <b>{i + 1}</b>
                    <span>{s.label}</span>
                  </button>
                ))}
              </div>
              <span className={h.scrollHint} aria-hidden="true">
                <i />
                Scroll to see each step
              </span>
            </div>

            <div className={h.phoneCol}>
              <span className={h.aurora} aria-hidden="true" />
              <span className={h.howRing} aria-hidden="true" />
              <div className={h.phoneTilt}>
                <PhoneStack
                  screens={SCREENS}
                  current={STEPS[step].screen}
                  render={(name) => <AppScreen name={name} qr={qr} />}
                  className={h.howPhone}
                  label={`BookALook app, step ${step + 1}: ${STEPS[step].label}`}
                />
                <span className={h.sheen} aria-hidden="true" />
              </div>
              <span className={h.phoneShadow} aria-hidden="true" />
            </div>

            <div className={h.chipCol} aria-hidden="true">
              {STEPS.map((s, i) => (
                <div
                  key={s.key}
                  className={`${h.chipSet} ${i === step ? h.on : ''} ${i < step ? h.past : ''}`}
                  style={{ '--c': centreOf(i) } as CSSProperties}
                >
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
