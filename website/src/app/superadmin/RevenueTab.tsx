'use client';

import { useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import {
  Bar, BarChart, CartesianGrid, Cell, ComposedChart, Legend, Line, Pie, PieChart,
  ResponsiveContainer, Tooltip as RechartsTooltip, XAxis, YAxis,
} from 'recharts';
import Icon from '@/components/admin/Icon';
import { useChartPalette } from '@/lib/theme';
import styles from './dashboard.module.css';
import rev from './revenue.module.css';
import { EmptyState, KpiCard } from './DashboardParts';
import MonthlyLedger from './MonthlyLedger';

interface Totals {
  total: number;
  subscriptions: number;
  subscription_payments: number;
  commission: number;
  commission_settlements: number;
  coins_given: number;
  paying_salons: number;
  per_paying_salon: number;
}

interface TrendPoint {
  date: string;
  label: string;
  subscriptions: number;
  commission: number;
  total: number;
  coins: number;
}

interface Group {
  id?: string;
  name: string;
  city?: string;
  subscriptions: number;
  commission: number;
  total: number;
}

interface RevenueData {
  range: { from: string; to: string; granularity: string; previous_from: string; previous_to: string };
  totals: Totals;
  previous_totals: Totals;
  pending_commission: { amount: number; payouts: number };
  all_time: Totals;
  trend: TrendPoint[];
  by_plan: { name: string; amount: number; count: number }[];
  by_city: Group[];
  top_salons: Group[];
  recent: { kind: 'subscription' | 'commission'; salon: string; label: string; amount: number; coins: number; at: string }[];
}

const formatINR = (n: number | undefined) => '₹' + Math.round(Number(n) || 0).toLocaleString('en-IN');

const compactINR = (n: number) => {
  const v = Number(n) || 0;
  if (v >= 1e7) return `₹${(v / 1e7).toFixed(1).replace(/\.0$/, '')}Cr`;
  if (v >= 1e5) return `₹${(v / 1e5).toFixed(1).replace(/\.0$/, '')}L`;
  if (v >= 1e3) return `₹${(v / 1e3).toFixed(0)}k`;
  return `₹${Math.round(v)}`;
};

const delta = (curr: number, prev: number) => {
  if (!prev) return curr > 0 ? { pct: 100, dir: 'up' as const } : { pct: 0, dir: 'flat' as const };
  const pct = Math.round(((curr - prev) / prev) * 100);
  return { pct: Math.abs(pct), dir: pct > 0 ? ('up' as const) : pct < 0 ? ('down' as const) : ('flat' as const) };
};

const fmtDay = (iso: string) =>
  new Date(iso).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' });

/**
 * BookALook's own revenue: approved plan payments and settled commission.
 * Coins are shown beside the cash, never inside it.
 */
export default function RevenueTab({ from, to, granularity, rangeLabel, refreshKey }: {
  from: string;
  to: string;
  granularity: string;
  rangeLabel: string;
  refreshKey: number;
}) {
  const palette = useChartPalette();
  const [data, setData] = useState<RevenueData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const seq = useRef(0);

  useEffect(() => {
    const id = ++seq.current;
    const run = async () => {
      setLoading(true);
      try {
        const params = new URLSearchParams({ from, to, granularity });
        const res = await fetch(`/api/proxy/superadmin/reports/platform-revenue?${params}`, { cache: 'no-store' });
        const json = await res.json();
        if (id !== seq.current) return;
        if (!res.ok || !json.success) throw new Error(json.message || 'Could not load revenue.');
        setData(json as RevenueData);
        setError('');
      } catch (e) {
        if (id === seq.current) setError(e instanceof Error ? e.message : 'Could not load revenue.');
      } finally {
        if (id === seq.current) setLoading(false);
      }
    };
    const timer = setTimeout(run, 0);
    return () => clearTimeout(timer);
  }, [from, to, granularity, refreshKey]);

  const t = data?.totals;
  const p = data?.previous_totals;
  const showLoading = loading && !data;
  const mixColors = [palette.c1, palette.c2, palette.c5, palette.c3, palette.c4];
  const mixTotal = (data?.by_plan ?? []).reduce((s, x) => s + x.amount, 0);
  const maxSalon = Math.max(1, ...(data?.top_salons ?? []).map((s) => s.total));
  const prevLabel = data ? `vs ${fmtDay(data.range.previous_from)} – ${fmtDay(data.range.previous_to)}` : '';

  const tooltipStyle = {
    borderRadius: 12,
    border: `1px solid ${palette.grid}`,
    boxShadow: '0 8px 24px rgba(0,0,0,0.08)',
    fontSize: 12,
  };

  if (error && !data) {
    return <div className={rev.errorBox} role="alert">{error}</div>;
  }

  return (
    <>
      <div className={styles.kpiGrid}>
        <KpiCard
          label="BookALook revenue"
          icon="rupee"
          tone="violet"
          loading={showLoading}
          value={formatINR(t?.total)}
          delta={t && p ? delta(t.total, p.total) : undefined}
          sub={prevLabel || 'Plans + settled commission'}
        />
        <KpiCard
          href="/superadmin/subscriptions"
          label="Plan payments"
          icon="crown"
          tone="teal"
          loading={showLoading}
          value={formatINR(t?.subscriptions)}
          delta={t && p ? delta(t.subscriptions, p.subscriptions) : undefined}
          sub={`${t?.subscription_payments ?? 0} approved payment${t?.subscription_payments === 1 ? '' : 's'}`}
        />
        <KpiCard
          href="/superadmin/payouts"
          label="Commission settled"
          icon="percent"
          tone="blue"
          loading={showLoading}
          value={formatINR(t?.commission)}
          delta={t && p ? delta(t.commission, p.commission) : undefined}
          sub={`${formatINR(data?.pending_commission.amount)} still pending in ${data?.pending_commission.payouts ?? 0} payout${data?.pending_commission.payouts === 1 ? '' : 's'}`}
        />
        <KpiCard
          label="Coins given away"
          icon="coins"
          tone="amber"
          loading={showLoading}
          value={formatINR(t?.coins_given)}
          sub={t ? `${t.paying_salons} paying salon${t.paying_salons === 1 ? '' : 's'} · ${formatINR(t.per_paying_salon)} each` : 'Not counted as revenue'}
        />
      </div>

      <div className={rev.allTime}>
        <Icon name="sparkle" size={15} />
        <span>All time: <b>{formatINR(data?.all_time.total)}</b></span>
        <span className={rev.sep}>·</span>
        <span>{formatINR(data?.all_time.subscriptions)} plans</span>
        <span className={rev.sep}>·</span>
        <span>{formatINR(data?.all_time.commission)} commission</span>
        <span className={rev.sep}>·</span>
        <span>{formatINR(data?.all_time.coins_given)} in coins</span>
      </div>

      {/* TREND + MIX */}
      <div className={styles.chartsGrid}>
        <section className={styles.card}>
          <div className={styles.cardHeader}>
            <div>
              <h2 className={styles.cardTitle}>Revenue over time</h2>
              <p className={styles.cardSubtitle}>{rangeLabel} · plan payments and settled commission</p>
            </div>
          </div>
          <div className={styles.trendChart}>
            {showLoading ? (
              <div className={`${styles.skeleton} ${styles.skeletonChart}`} />
            ) : data && data.trend.some((x) => x.total > 0 || x.coins > 0) ? (
              <ResponsiveContainer width="100%" height="100%">
                <ComposedChart data={data.trend} margin={{ top: 10, right: 8, left: 0, bottom: 0 }}>
                  <CartesianGrid strokeDasharray="3 3" vertical={false} stroke={palette.grid} />
                  <XAxis dataKey="label" tick={{ fontSize: 11, fill: palette.axis }} tickLine={false} axisLine={false} minTickGap={16} />
                  <YAxis tick={{ fontSize: 11, fill: palette.axis }} tickLine={false} axisLine={false} tickFormatter={compactINR} width={56} />
                  <RechartsTooltip
                    contentStyle={tooltipStyle}
                    formatter={(v, name) => [formatINR(Number(v)), String(name)]}
                    cursor={{ fill: palette.track }}
                  />
                  <Legend iconType="circle" wrapperStyle={{ fontSize: 12 }} />
                  <Bar dataKey="subscriptions" name="Plan payments" stackId="r" fill={palette.c1} radius={[0, 0, 0, 0]} maxBarSize={36} />
                  <Bar dataKey="commission" name="Commission" stackId="r" fill={palette.c2} radius={[6, 6, 0, 0]} maxBarSize={36} />
                  <Line type="monotone" dataKey="coins" name="Coins given" stroke={palette.c3} strokeWidth={2} dot={false} strokeDasharray="5 4" />
                </ComposedChart>
              </ResponsiveContainer>
            ) : (
              <EmptyState icon="chart" title="No revenue in this range" hint="Approved plan payments and settled commission show up here." />
            )}
          </div>
        </section>

        <section className={styles.card}>
          <div className={styles.cardHeader}>
            <div>
              <h2 className={styles.cardTitle}>Where it comes from</h2>
              <p className={styles.cardSubtitle}>By plan, with commission as its own slice</p>
            </div>
          </div>
          {showLoading ? (
            <div className={`${styles.skeleton} ${styles.skeletonChart}`} />
          ) : data && mixTotal > 0 ? (
            <>
              <div className={rev.donutWrap}>
                <ResponsiveContainer width="100%" height={200}>
                  <PieChart>
                    <Pie data={data.by_plan} dataKey="amount" nameKey="name" innerRadius={58} outerRadius={86} paddingAngle={2} stroke="none">
                      {data.by_plan.map((entry, i) => (
                        <Cell key={entry.name} fill={mixColors[i % mixColors.length]} />
                      ))}
                    </Pie>
                    <RechartsTooltip contentStyle={tooltipStyle} formatter={(v, name) => [formatINR(Number(v)), String(name)]} />
                  </PieChart>
                </ResponsiveContainer>
                <div className={rev.donutCenter}>
                  <b>{compactINR(mixTotal)}</b>
                  <span>in range</span>
                </div>
              </div>
              <ul className={rev.legendList}>
                {data.by_plan.map((x, i) => (
                  <li key={x.name}>
                    <span className={rev.swatch} style={{ background: mixColors[i % mixColors.length] }} />
                    <span className={rev.legendName}>{x.name}</span>
                    <span className={rev.legendCount}>{x.count}×</span>
                    <b>{formatINR(x.amount)}</b>
                    <em>{Math.round((x.amount / mixTotal) * 100)}%</em>
                  </li>
                ))}
              </ul>
            </>
          ) : (
            <EmptyState icon="crown" title="Nothing yet" hint="No plan payments or commission in this range." />
          )}
        </section>
      </div>

      {/* SALONS + CITIES */}
      <div className={styles.chartsGrid}>
        <section className={styles.card}>
          <div className={styles.cardHeader}>
            <div>
              <h2 className={styles.cardTitle}>Top paying salons</h2>
              <p className={styles.cardSubtitle}>What each salon paid BookALook in this range</p>
            </div>
          </div>
          {showLoading ? (
            <div className={`${styles.skeleton} ${styles.skeletonChart}`} />
          ) : data && data.top_salons.length > 0 ? (
            <ol className={rev.rankList}>
              {data.top_salons.map((s, i) => (
                <li key={s.id ?? s.name}>
                  <span className={rev.rank}>{i + 1}</span>
                  <div className={rev.rankMain}>
                    <div className={rev.rankTop}>
                      {s.id ? <Link href={`/superadmin/salons/${s.id}`}>{s.name}</Link> : <span>{s.name}</span>}
                      <b>{formatINR(s.total)}</b>
                    </div>
                    <div className={rev.stackBar}>
                      <span style={{ width: `${(s.subscriptions / maxSalon) * 100}%`, background: palette.c1 }} />
                      <span style={{ width: `${(s.commission / maxSalon) * 100}%`, background: palette.c2 }} />
                    </div>
                    <div className={rev.rankSub}>
                      {s.city} · {formatINR(s.subscriptions)} plans · {formatINR(s.commission)} commission
                    </div>
                  </div>
                </li>
              ))}
            </ol>
          ) : (
            <EmptyState icon="store" title="No paying salons yet" hint="Salons appear here once they pay for a plan or settle commission." />
          )}
        </section>

        <section className={styles.card}>
          <div className={styles.cardHeader}>
            <div>
              <h2 className={styles.cardTitle}>Revenue by city</h2>
              <p className={styles.cardSubtitle}>Plans and commission, per market</p>
            </div>
          </div>
          {showLoading ? (
            <div className={`${styles.skeleton} ${styles.skeletonChart}`} />
          ) : data && data.by_city.length > 0 ? (
            <div className={rev.cityChart}>
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={data.by_city} layout="vertical" margin={{ top: 4, right: 16, left: 8, bottom: 4 }}>
                  <CartesianGrid strokeDasharray="3 3" horizontal={false} stroke={palette.grid} />
                  <XAxis type="number" tick={{ fontSize: 11, fill: palette.axis }} tickLine={false} axisLine={false} tickFormatter={compactINR} />
                  <YAxis type="category" dataKey="name" tick={{ fontSize: 12, fill: palette.axis }} tickLine={false} axisLine={false} width={90} />
                  <RechartsTooltip contentStyle={tooltipStyle} formatter={(v, name) => [formatINR(Number(v)), String(name)]} cursor={{ fill: palette.track }} />
                  <Bar dataKey="subscriptions" name="Plan payments" stackId="c" fill={palette.c1} maxBarSize={22} />
                  <Bar dataKey="commission" name="Commission" stackId="c" fill={palette.c2} radius={[0, 6, 6, 0]} maxBarSize={22} />
                </BarChart>
              </ResponsiveContainer>
            </div>
          ) : (
            <EmptyState icon="pin" title="No city data" hint="Nothing was paid in this range." />
          )}
        </section>
      </div>

      {/* MONTH BY MONTH */}
      <MonthlyLedger refreshKey={refreshKey} />

      {/* RECENT */}
      <section className={styles.card}>
        <div className={styles.cardHeader}>
          <div>
            <h2 className={styles.cardTitle}>Latest money in</h2>
            <p className={styles.cardSubtitle}>The most recent plan payments and commission settlements</p>
          </div>
        </div>
        {showLoading ? (
          <div className={`${styles.skeleton} ${styles.skeletonChart}`} />
        ) : data && data.recent.length > 0 ? (
          <ul className={rev.recentList}>
            {data.recent.map((r, i) => (
              <li key={`${r.at}-${i}`}>
                <span className={rev.recentIcon} style={{ color: r.kind === 'commission' ? palette.c2 : palette.c1 }}>
                  <Icon name={r.kind === 'commission' ? 'percent' : 'crown'} size={16} />
                </span>
                <div className={rev.recentMain}>
                  <b>{r.salon}</b>
                  <span>{r.label} · {fmtDay(r.at)}</span>
                </div>
                <div className={rev.recentAmount}>
                  <b>{formatINR(r.amount)}</b>
                  {r.coins > 0 && <span>+ {formatINR(r.coins)} in coins</span>}
                </div>
              </li>
            ))}
          </ul>
        ) : (
          <EmptyState icon="receipt" title="No payments yet" hint="Approved plan payments and settled commission are listed here." />
        )}
      </section>
    </>
  );
}
