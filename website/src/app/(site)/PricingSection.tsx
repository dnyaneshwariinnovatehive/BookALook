'use client';

import { useEffect, useState } from 'react';
import s from './landing.module.css';

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
  'Advance payments that cut no-shows',
  'Staff, services and working hours',
  'Walk-ins, billing and invoices',
  'QR check-in at your door',
  'Online advances paid out to your bank',
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
    <section id="pricing" className={s.section}>
      <div className={s.container}>
        <p className={s.kicker}>Pricing</p>
        <h2 className={s.title}>Simple plans. No booking fees on top.</h2>
        <p className={s.lead}>
          Pick a monthly plan, or the Commission Model if you would rather pay only when bookings come in.
          New salons get welcome reward coins they can put towards their first plan.
        </p>

        {plans === null && !failed ? (
          <div className={s.planGrid} aria-busy="true">
            {[0, 1, 2].map((i) => <div key={i} className={`${s.planCard} ${s.skeleton}`} />)}
          </div>
        ) : (
          <div className={s.planGrid}>
            {(plans ?? []).map((plan) => {
              const featured = plan.id === featuredId;
              return (
                <article key={plan.id} className={`${s.planCard} ${featured ? s.planFeatured : ''}`}>
                  {featured && <span className={s.planRibbon}>Most popular</span>}
                  <h3 className={s.planName}>{plan.name}</h3>
                  <p className={s.planPrice}>
                    <b>{inr(plan.price)}</b>
                    <span>/ {cycle(plan.validity_days)}</span>
                  </p>
                  <ul className={s.planList}>
                    {EVERY_PLAN.slice(0, 3).map((f) => <li key={f}>{f}</li>)}
                    <li className={s.planAll}>+ everything in every plan</li>
                    {extras(plan).map((f) => <li key={f} className={s.planExtra}>{f}</li>)}
                  </ul>
                  <a className={`${s.btn} ${featured ? s.btnPrimary : s.btnSoft}`} href="#enquiry-section">
                    Start with {plan.name}
                  </a>
                </article>
              );
            })}

            <article className={`${s.planCard} ${s.planCommission}`}>
              <h3 className={s.planName}>Commission Model</h3>
              <p className={s.planPrice}>
                <b>Pay as you earn</b>
                <span>no monthly fee</span>
              </p>
              <ul className={s.planList}>
                <li>A small agreed percentage on app bookings only</li>
                <li>Walk-ins stay commission-free</li>
                <li>Settled once a month from your payouts</li>
                {commissionPlan && <li className={s.planExtra}>Includes {commissionPlan.name} plan features</li>}
              </ul>
              <a className={`${s.btn} ${s.btnSoft}`} href="#enquiry-section">Ask about commission</a>
            </article>
          </div>
        )}

        <div className={s.everyPlan}>
          <p>Every salon gets</p>
          <ul>
            {EVERY_PLAN.map((f) => <li key={f}>{f}</li>)}
          </ul>
        </div>
      </div>
    </section>
  );
}
