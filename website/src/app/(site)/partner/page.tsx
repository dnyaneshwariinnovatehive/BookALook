'use client';

import StoreBadge from '@/components/site/StoreBadge';
import { PARTNER_APP_STORE_URL, PARTNER_PLAY_STORE_URL } from '@/lib/site-links';
import { Parallax, QrCode, Reveal, useOrigin } from '../motion';
import { PartnerScreen, Phone } from '../phone';
import st from '../site.module.css';
import EnquiryForm from './EnquiryForm';
import PricingSection from './PricingSection';
import p from './partner.module.css';

/* ============================================================================
   BOOKALOOK FOR SALONS — the page for owners, the people who buy plans.

   Everything a salon owner needs sits here, away from the customer home page:
   why to join, what the Partner App does, live plans and pricing, the four
   steps to go live and the registration form (see EnquiryForm, whose behaviour
   is unchanged from the old landing page).
   ============================================================================ */

/** What owners stop losing, and what replaces it. */
const GAINS = [
  {
    pain: 'Empty chairs on weekday afternoons',
    title: 'New customers find you in the app',
    desc: 'Your salon, services and live free slots are listed for customers searching nearby, every hour of the day.',
  },
  {
    pain: 'Registers, calls and WhatsApp chaos',
    title: 'One app runs the whole salon',
    desc: 'Bookings, walk-ins, staff hours, billing and reports — on your phone, for every branch.',
  },
  {
    pain: 'Double bookings and mix-ups',
    title: 'A live calendar for every stylist',
    desc: 'Real-time availability per person, so a slot is only ever given once.',
  },
];

const OWNER_FEATURES = [
  { icon: '🗓️', title: 'Online bookings, no double-booking', desc: 'Real-time availability per stylist, so a slot is only ever sold once.' },
  { icon: '👥', title: 'Staff, hours and leave', desc: 'Shifts, breaks and leave per person. Change salon hours and staff follow.' },
  { icon: '🛍️', title: 'Walk-ins and billing', desc: 'Add walk-ins, add services mid-visit, collect payment and send invoices.' },
  { icon: '📲', title: 'QR check-in', desc: 'Customers scan at the door; you know who is in the chair and when.' },
  { icon: '💬', title: 'Booking updates on WhatsApp', desc: 'Confirmations and reminders go to customers automatically.' },
  { icon: '📈', title: 'Revenue insights', desc: 'See busy hours, best services and quiet stylists — and what to do next.' },
  { icon: '🏬', title: 'Every branch, one login', desc: 'Run more than one salon? Switch between them in one tap.' },
  { icon: '🪙', title: 'Reward coins', desc: 'Welcome coins for new salons that you can put towards your plan.' },
];

const START_STEPS = [
  { title: 'Send the form', desc: 'Two minutes: your salon, area and contact. Bank details are optional.' },
  { title: 'We verify your salon', desc: 'Our team checks the details, usually with a quick visit or call.' },
  { title: 'Pick your plan', desc: 'A monthly plan, or the Commission Model. Use your welcome coins towards it.' },
  { title: 'Go live and take bookings', desc: 'Set up services and staff in the Partner App and start receiving bookings.' },
];

const SALON_ROLES = [
  {
    tag: 'Salon owner',
    title: 'Run every branch',
    desc: 'Bookings, staff, services and reports for each of your salons — switch between branches in one tap.',
  },
  {
    tag: 'Stylists & staff',
    title: 'Their day, on their phone',
    desc: 'Each stylist sees their own appointments, checks customers in, adds walk-ins and requests leave.',
  },
];

// [PLACEHOLDER] FAQ answers are provisional copy — confirm with the business team.
const FAQ_ITEMS = [
  {
    q: 'How much does BookALook cost my salon?',
    a: 'Choose a monthly Subscription Plan (the current plans and prices are shown above, straight from our system), or the Commission Model, where there is no monthly fee and you pay an agreed percentage on app bookings only. Walk-ins are never charged commission.',
  },
  {
    q: 'Can my staff use it, and do I need a separate app?',
    a: 'One Partner App serves everyone. You log in as the owner; each stylist logs in with their own number and sees only their own work. If you run more than one salon, you switch between them in the same app.',
  },
  {
    q: 'Do I need bank details to register?',
    a: 'No. You can register and go live without them, and add them later from the Partner App. They are only needed before your first payout.',
  },
];

const HERO_TRUST = ['One app for owner and staff', 'No double-bookings', 'Works for every branch'];

export default function PartnerPage() {
  const origin = useOrigin();

  return (
    <main className={p.page}>
      {/* ============ HERO ============ */}
      <section className={p.hero}>
        <Parallax speed={0.18} className={p.heroGlow} />
        <Parallax speed={-0.1} className={p.heroGlow2} />
        <div className={`${st.wrap} ${p.heroGrid}`}>
          <Parallax speed={0.06}>
            <p className={`${st.eyebrow} ${p.eyebrow}`}>💈 For salon owners &amp; barbers</p>
            <h1 className={p.h1}>Fill every chair. <em>Run your salon</em> from one app.</h1>
            <p className={p.sub}>
              New customers find you in the BookALook app and book your free slots. You run bookings, walk-ins,
              staff, billing and reports from one Partner App.
            </p>
            <div className={`${st.cta} ${p.heroCta}`}>
              <a className={`${st.btn} ${st.btnLg}`} href="#enquiry-section">Register your salon →</a>
              <a className={`${st.btn} ${st.btnLg} ${p.btnDark}`} href="#pricing">See plans &amp; pricing</a>
            </div>
            <ul className={`${st.trust} ${p.trust}`}>
              {HERO_TRUST.map((t) => (
                <li key={t}><span className={st.tick} aria-hidden="true">✓</span>{t}</li>
              ))}
            </ul>
          </Parallax>

          <div className={p.stage}>
            <Parallax speed={-0.08} className={p.stagePhone}>
              <Phone className={p.tilt} label="BookALook Partner App preview: today's bookings for a salon">
                <PartnerScreen />
              </Phone>
            </Parallax>
            <Parallax speed={-0.22} className={`${p.fl} ${p.fl1}`}>
              <div className={`${st.float} ${st.bob}`}><i>🔔</i><span>New booking<small>Haircut · 6:30 PM</small></span></div>
            </Parallax>
            <Parallax speed={0.14} className={`${p.fl} ${p.fl2}`}>
              <div className={`${st.float} ${st.bob2}`}><i>📲</i><span>QR scanned<small>Customer checked in</small></span></div>
            </Parallax>
            <Parallax speed={-0.16} className={`${p.fl} ${p.fl3}`}>
              <div className={`${st.float} ${st.bob3}`}><i>📈</i><span>Busy hours<small>See them in reports</small></span></div>
            </Parallax>
          </div>
        </div>
      </section>

      {/* ============ WHY ============ */}
      <section id="why" className={st.sec}>
        <div className={st.wrap}>
          <Reveal className={st.center}>
            <p className={st.kicker}>Why salons join</p>
            <h2 className={st.big}>Less chaos. <em>More full chairs.</em></h2>
          </Reveal>
          <div className={p.gains}>
            {GAINS.map((g, i) => (
              <Parallax key={g.title} speed={[0.05, -0.05, 0.05][i]}>
                <Reveal as="article" delay={i * 110} className={`${p.gain} ${i === 1 ? p.gainHot : ''}`}>
                  <s>{g.pain}</s>
                  <h3>{g.title}</h3>
                  <p>{g.desc}</p>
                </Reveal>
              </Parallax>
            ))}
          </div>
        </div>
      </section>

      {/* ============ FEATURES ============ */}
      <section id="features" className={`${st.sec} ${p.tint}`}>
        <Parallax speed={0.14} className={p.tintOrb} />
        <div className={st.wrap}>
          <Reveal>
            <p className={st.kicker}>Everything in the Partner App</p>
            <h2 className={st.big}>Built for how a salon <em>actually runs.</em></h2>
          </Reveal>
          <div className={p.fgrid}>
            {OWNER_FEATURES.map((f, i) => (
              <Reveal as="article" key={f.title} delay={(i % 4) * 80} className={p.fc}>
                <span className={p.fcIcon} aria-hidden="true">{f.icon}</span>
                <h3>{f.title}</h3>
                <p>{f.desc}</p>
              </Reveal>
            ))}
          </div>
        </div>
      </section>

      <PricingSection />

      {/* ============ GET STARTED + FORM ============ */}
      <section id="get-started" className={`${st.sec} ${p.tint}`}>
        <div className={`${st.wrap} ${p.start}`}>
          <div className={p.startText}>
            <Reveal variant="left">
              <p className={st.kicker}>Get started</p>
              <h2 className={st.big}>Your salon on BookALook in <em>four steps.</em></h2>
              <ol className={p.steps}>
                {START_STEPS.map((step, i) => (
                  <li key={step.title}>
                    <span className={p.stepNum}>{i + 1}</span>
                    <div><b>{step.title}</b><p>{step.desc}</p></div>
                  </li>
                ))}
              </ol>
              <div className={p.qrBox}>
                <QrCode value={`${origin}/download?app=partner`} size={96} label="QR code to download the BookALook Partner app" />
                <div>
                  <b>Prefer your phone?</b>
                  <p>Scan to get the Partner App and register your salon yourself.</p>
                  <div className={p.qrBadges}>
                    <StoreBadge store="google" url={PARTNER_PLAY_STORE_URL} label="Google Play" />
                    <StoreBadge store="apple" url={PARTNER_APP_STORE_URL} label="App Store" />
                  </div>
                </div>
              </div>
            </Reveal>
          </div>

          <Reveal variant="right">
            <EnquiryForm />
          </Reveal>
        </div>
      </section>

      {/* ============ TEAM ============ */}
      <section className={st.sec}>
        <div className={st.wrap}>
          <Reveal className={st.center}>
            <p className={st.kicker}>One app for the whole team</p>
            <h2 className={st.big}>You and your stylists, <em>in the same app.</em></h2>
          </Reveal>
          <div className={p.roles}>
            {SALON_ROLES.map((r, i) => (
              <Parallax key={r.tag} speed={i === 0 ? 0.05 : -0.05}>
                <Reveal as="article" delay={i * 110} className={`${p.role} ${i === 1 ? p.roleTint : ''}`}>
                  <small>{r.tag}</small>
                  <h3>{r.title}</h3>
                  <p>{r.desc}</p>
                </Reveal>
              </Parallax>
            ))}
          </div>
        </div>
      </section>

      {/* ============ FAQ ============ */}
      <section id="faq" className={`${st.sec} ${p.faqSec}`}>
        <div className={`${st.wrap} ${st.faq}`}>
          <Reveal className={st.faqHead}>
            <p className={st.kicker}>Owner FAQ</p>
            <h2 className={st.big}>Before you <em>sign up.</em></h2>
            <p className={st.lead}>Anything else? The form above reaches our team directly.</p>
          </Reveal>
          <div>
            {FAQ_ITEMS.map((item, i) => (
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
