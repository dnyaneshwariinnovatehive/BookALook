'use client';

import { useEffect, useState } from 'react';
import { Parallax, Reveal } from '../motion';
import st from '../site.module.css';
import p from './partner.module.css';

/** A plan as `/api/public/subscription-plans` returns it. */
interface Plan {
  id: string;
  name: string;
  price: string | number;
  validity_days: number;
  is_active: boolean;
  is_commission_plan?: boolean;
  has_customer_segmentation?: boolean;
  has_advanced_insights?: boolean;
  has_upsell_recommendations?: 'none' | 'basic' | 'advanced' | string;
  has_cross_sell_recommendations?: 'none' | 'basic' | 'advanced' | string;
}

/** What every salon gets, whichever way it pays. */
const EVERY_PLAN = [
  'Online bookings from the BookALook app',
  'Staff, services and working hours',
  'Walk-ins, billing and invoices',
  'QR check-in at your door',
  'WhatsApp booking updates for customers',
  'Reports on bookings and revenue',
];

const inr = (v: string | number) => `₹${Math.round(Number(v) || 0).toLocaleString('en-IN')}`;

/** The extras a plan's flags switch on, in the words an owner uses. */
function extras(plan: Plan): string[] {
  const out: string[] = [];
  if (plan.has_advanced_insights) out.push('Advanced revenue and booking insights');
  else out.push('Essential booking and revenue reports');
  if (plan.has_upsell_recommendations === 'advanced') out.push('Smart upsell suggestions for every service');
  else if (plan.has_upsell_recommendations === 'basic') out.push('Basic upsell suggestions');
  if (plan.has_cross_sell_recommendations && plan.has_cross_sell_recommendations !== 'none') {
    out.push(plan.has_cross_sell_recommendations === 'advanced' ? 'Cross-sell ideas to grow each bill' : 'Cross-sell ideas');
  }
  if (plan.has_customer_segmentation) out.push('Know your regulars and big spenders');
  return out;
}

const cycle = (days: number) => (days === 30 ? 'month' : days === 365 ? 'year' : `${days} days`);

/**
 * Pricing, read live from the plans SuperAdmin manages, so the page never
 * shows a price the app does not charge. The Commission Model sits beside the
 * plans for salons that would rather pay only when they earn.
 */
export default function PricingSection() {
  const [plans, setPlans] = useState<Plan[] | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let cancelled = false;
    fetch(`${process.env.NEXT_PUBLIC_BACKEND_URL}/api/public/subscription-plans`, { headers: { Accept: 'application/json' } })
      .then((r) => r.json())
      .then((json) => {
        if (cancelled) return;
        const list: Plan[] = Array.isArray(json?.plans) ? json.plans : Array.isArray(json?.data) ? json.data : [];
        setPlans(list.filter((p) => p.is_active).sort((a, b) => Number(a.price) - Number(b.price)));
      })
      .catch(() => !cancelled && setFailed(true));
    return () => {
      cancelled = true;
    };
  }, []);

  const commissionPlan = plans?.find((p) => p.is_commission_plan);
  // The richest plan is the one to point at.
  const featuredId = plans && plans.length > 1
    ? [...plans].sort((a, b) => extras(b).length - extras(a).length || Number(b.price) - Number(a.price))[0].id
    : null;

  return (
    <section id="pricing" className={`${st.sec} ${p.pricing}`}>
      <Parallax speed={-0.12} className={p.pricingOrb} />
      <div className={st.wrap}>
        <Reveal className={st.center}>
          <p className={st.kicker}>Plans &amp; pricing</p>
          <h2 className={st.big}>Pay monthly, or <em>only when you earn.</em></h2>
          <p className={st.lead}>
            Pick a monthly plan, or the Commission Model if you would rather pay only when bookings come in.
            New salons get welcome reward coins they can put towards their first plan.
          </p>
        </Reveal>

        {plans === null && !failed ? (
          <div className={p.plans} aria-busy="true">
            {[0, 1, 2].map((i) => <div key={i} className={`${p.plan} ${p.skeleton}`} />)}
          </div>
        ) : (
          <div className={p.plans}>
            {(plans ?? []).map((plan, i) => {
              const featured = plan.id === featuredId;
              return (
                <Reveal as="article" key={plan.id} delay={i * 90} className={`${p.plan} ${featured ? p.planHot : ''}`}>
                  {featured && <span className={p.ribbon}>Most popular</span>}
                  <h3 className={p.planName}>{plan.name}</h3>
                  <p className={p.price}>
                    <b>{inr(plan.price)}</b>
                    <span>/ {cycle(plan.validity_days)}</span>
                  </p>
                  <ul className={p.planList}>
                    {EVERY_PLAN.slice(0, 3).map((f) => <li key={f}>{f}</li>)}
                    <li className={p.planAll}>+ everything in every plan</li>
                    {extras(plan).map((f) => <li key={f} className={p.planExtra}>{f}</li>)}
                  </ul>
                  <a className={`${st.btn} ${st.btnBlock} ${featured ? '' : st.btnGhost}`} href="#enquiry-section">
                    Start with {plan.name}
                  </a>
                </Reveal>
              );
            })}

            <Reveal as="article" delay={(plans ?? []).length * 90} className={`${p.plan} ${p.planCommission}`}>
              <h3 className={p.planName}>Commission Model</h3>
              <p className={p.price}>
                <b>Pay as you earn</b>
                <span>no monthly fee</span>
              </p>
              <ul className={p.planList}>
                <li>A small agreed percentage on app bookings only</li>
                <li>Walk-ins stay commission-free</li>
                <li>Settled once a month</li>
                {commissionPlan && <li className={p.planExtra}>Includes {commissionPlan.name} plan features</li>}
              </ul>
              <a className={`${st.btn} ${st.btnBlock} ${st.btnGhost}`} href="#enquiry-section">Ask about commission</a>
            </Reveal>
          </div>
        )}

        <Reveal className={p.everyPlan}>
          <p>Every salon gets</p>
          <ul>
            {EVERY_PLAN.map((f) => <li key={f}>{f}</li>)}
          </ul>
        </Reveal>
      </div>
    </section>
  );
}
