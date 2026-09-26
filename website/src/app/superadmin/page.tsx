'use client';

import React, { useEffect, useState } from 'react';
import Link from 'next/link';
import {
  XAxis, YAxis, CartesianGrid, Tooltip as RechartsTooltip, ResponsiveContainer,
  PieChart, Pie, Cell, AreaChart, Area
} from 'recharts';
import Icon, { type IconName } from '@/components/admin/Icon';
import { useChartPalette } from '@/lib/theme';
import styles from './dashboard.module.css';
// --- SKELETON PLACEHOLDERS ---
const SKELETON_ROWS = [1, 2, 3];

const PRESETS = [
  { key: '7d', label: '7D', days: 7 },
  { key: '30d', label: '30D', days: 30 },
  { key: '90d', label: '90D', days: 90 },
] as const;

const GRANULARITIES = ['daily', 'weekly', 'monthly'] as const;

interface TrendPoint {
  date: string;
  label: string;
  bookings: number;
  revenue: number;
}

interface SalonRow {
  id: string;
  name: string;
  city: string;
  bookings: number;
  revenue: number;
}

interface ServiceRow {
  service: string;
  category: string;
  bookings: number;
  revenue: number;
}

interface PendingSalon {
  id: string;
  name: string;
  city: string;
  created_at: string;
}

interface DashboardData {
  generated_at: string;
  range: { from: string; to: string; granularity: string };
  kpis: {
    active_bookings: { today: number; yesterday: number };
    revenue: { today: number; yesterday: number };
    pending_approvals: number;
    active_salons: number;
  };
  bookings: {
    total: number;
    completed: number;
    cancelled: number;
    no_show: number;
    active: number;
    scheduled: number;
    online: number;
    walk_in: number;
  };
  revenue_trend: TrendPoint[];
  top_salons: SalonRow[];
  top_services: ServiceRow[];
}

// --- DATE HELPERS ---
const toISODate = (d: Date) =>
  `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;

const todayISO = () => toISODate(new Date());

const addDaysISO = (iso: string, days: number) => {
  const d = new Date(iso + 'T00:00:00');
  d.setDate(d.getDate() + days);
  return toISODate(d);
};

const daySpan = (from: string, to: string) => {
  const ms = new Date(to + 'T00:00:00').getTime() - new Date(from + 'T00:00:00').getTime();
  return Math.round(ms / 86400000) + 1;
};

const guessGranularity = (from: string, to: string) => {
  const days = daySpan(from, to);
  return days <= 31 ? 'daily' : days <= 120 ? 'weekly' : 'monthly';
};

const formatFullDate = (iso: string) => {
  const [y, m, d] = iso.split('-').map(Number);
  return new Date(y, m - 1, d).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' });
};

const formatINR = (n: number | undefined) =>
  '₹' + Math.round(Number(n) || 0).toLocaleString('en-IN');

/** Direction-sensitive delta for the KPI trend chips. */
const computeDelta = (curr: number, prev: number) => {
  if (!prev) return curr > 0 ? { pct: 100, dir: 'up' as const } : { pct: 0, dir: 'flat' as const };
  const pct = Math.round(((curr - prev) / prev) * 100);
  return { pct: Math.abs(pct), dir: pct > 0 ? ('up' as const) : pct < 0 ? ('down' as const) : ('flat' as const) };
};

export default function AdminDashboard() {
  const [from, setFrom] = useState(() => addDaysISO(todayISO(), -29));
  const [to, setTo] = useState(() => todayISO());
  const [granularity, setGranularity] = useState<'daily' | 'weekly' | 'monthly'>('daily');
  const [preset, setPreset] = useState('30d');

  const [data, setData] = useState<DashboardData | null>(null);
  const [pendingSalons, setPendingSalons] = useState<PendingSalon[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null);
  const [autoRefresh, setAutoRefresh] = useState(true);

  const fetchDashboard = async () => {
    const params = new URLSearchParams({ from, to, granularity });
    const dashUrl = `/api/proxy/superadmin/reports/dashboard?${params.toString()}`;

    const [dashRes, pendingRes] = await Promise.all([
      fetch(dashUrl),
      fetch('/api/proxy/superadmin/salons/pending'),
    ]);

    if (dashRes.ok) {
      setData((await dashRes.json()) as DashboardData);
    }
    if (pendingRes.ok) {
      const p = await pendingRes.json();
      const list: PendingSalon[] = Array.isArray(p.data)
        ? p.data
        : Array.isArray(p.salons)
          ? p.salons
          : [];
      setPendingSalons(list);
    }
    setLastUpdated(new Date());
  };

  // Initial load + whenever the date range or granularity changes.
  useEffect(() => {
    let cancelled = false;
    const run = async () => {
      try {
        setLoading(true);
        await fetchDashboard();
      } catch (error) {
        if (!cancelled) console.error('Failed to fetch dashboard data:', error);
      } finally {
        if (!cancelled) setLoading(false);
      }
    };
    run();
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [from, to, granularity]);

  // Silent auto-refresh keeps the KPI cards "today"-accurate.
  useEffect(() => {
    if (!autoRefresh) return;
    const id = setInterval(() => {
      fetchDashboard().catch(() => {});
    }, 60000);
    return () => clearInterval(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [autoRefresh, from, to, granularity]);

  const handleManualRefresh = async () => {
    setRefreshing(true);
    try {
      await fetchDashboard();
    } catch (error) {
      console.error('Failed to refresh dashboard data:', error);
    } finally {
      setRefreshing(false);
    }
  };

  const applyPreset = (p: { key: string; days: number }) => {
    const t = todayISO();
    const f = addDaysISO(t, -(p.days - 1));
    setPreset(p.key);
    setFrom(f);
    setTo(t);
    setGranularity(guessGranularity(f, t));
  };

  const handleFromChange = (value: string) => {
    setPreset('custom');
    setFrom(value);
    if (value && to && value <= to) setGranularity(guessGranularity(value, to));
  };

  const handleToChange = (value: string) => {
    setPreset('custom');
    setTo(value);
    if (from && value && from <= value) setGranularity(guessGranularity(from, value));
  };

  // --- DERIVED / FORMATTED DATA ---
  const palette = useChartPalette();
  const kpis = data?.kpis;
  const activeBookingsToday = kpis?.active_bookings?.today ?? 0;
  const activeBookingsYesterday = kpis?.active_bookings?.yesterday ?? 0;
  const revenueToday = kpis?.revenue?.today ?? 0;
  const revenueYesterday = kpis?.revenue?.yesterday ?? 0;
  const pendingApprovals = kpis?.pending_approvals ?? 0;
  const activeSalons = kpis?.active_salons ?? 0;

  const bookingDelta = computeDelta(activeBookingsToday, activeBookingsYesterday);
  const revenueDelta = computeDelta(revenueToday, revenueYesterday);

  const trend = data?.revenue_trend ?? [];
  const topSalons = data?.top_salons ?? [];
  const topServices = data?.top_services ?? [];
  const rangeRevenue = trend.reduce((s, p) => s + (Number(p.revenue) || 0), 0);
  const rangeBookings = trend.reduce((s, p) => s + (Number(p.bookings) || 0), 0);
  const maxSalonRevenue = Math.max(1, ...topSalons.map((s) => Number(s.revenue) || 0));
  const maxServiceRevenue = Math.max(1, ...topServices.map((s) => Number(s.revenue) || 0));

  const bookingStatusData = data?.bookings
    ? [
        { name: 'Completed', value: data.bookings.completed, color: palette.c2 },
        { name: 'Active', value: data.bookings.active, color: palette.c1 },
        { name: 'Cancelled', value: data.bookings.cancelled, color: palette.c3 },
        { name: 'No-show', value: data.bookings.no_show, color: palette.c4 },
      ].filter((d) => d.value > 0)
    : [];
  const statusTotal = bookingStatusData.reduce((s, d) => s + d.value, 0);

  const online = data?.bookings?.online ?? 0;
  const walkIn = data?.bookings?.walk_in ?? 0;
  const channelTotal = online + walkIn;
  const onlinePct = channelTotal ? Math.round((online / channelTotal) * 100) : 0;

  const rangeLabel = from && to ? `${formatFullDate(from)} – ${formatFullDate(to)}` : '';

  const hour = new Date().getHours();
  const greeting = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';
  const todayLabel = new Date().toLocaleDateString('en-IN', { weekday: 'long', day: 'numeric', month: 'long' });

  return (
    <div className={styles.page}>
      <header className={styles.pageHeader}>
        <div>
          <p className={styles.eyebrow} suppressHydrationWarning>{todayLabel}</p>
          <h1 className={styles.pageTitle} suppressHydrationWarning>{greeting}, Admin</h1>
          <p className={styles.pageSubtitle}>Here is what is happening across the marketplace.</p>
        </div>
        <button
          type="button"
          className={`${styles.livePill} ${autoRefresh ? styles.livePillOn : ''}`}
          onClick={() => setAutoRefresh((v) => !v)}
          title={autoRefresh ? 'Auto-refresh every minute — click to pause' : 'Auto-refresh paused — click to resume'}
        >
          <span className={`${styles.liveDot} ${autoRefresh ? styles.liveDotActive : ''}`} />
          {autoRefresh ? 'Live' : 'Paused'}
          <span className={styles.autoTime}>
            {lastUpdated ? lastUpdated.toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit' }) : '—'}
          </span>
        </button>
      </header>

      {/* CONTROLS BAR */}
      <div className={styles.controlsBar}>
        <div className={styles.controlsGroup}>
          <div className={styles.segmented} role="group" aria-label="Date range preset">
            {PRESETS.map((p) => (
              <button
                key={p.key}
                type="button"
                className={`${styles.segBtn} ${preset === p.key ? styles.segBtnActive : ''}`}
                aria-pressed={preset === p.key}
                onClick={() => applyPreset(p)}
              >
                {p.label}
              </button>
            ))}
          </div>
          <div className={styles.dateInputs}>
            <label className={styles.dateField}>
              <span className={styles.dateLabel}>From</span>
              <input
                type="date"
                className={styles.dateInput}
                value={from}
                max={to}
                onChange={(e) => handleFromChange(e.target.value)}
              />
            </label>
            <Icon name="arrowRight" size={14} className={styles.dateSep} />
            <label className={styles.dateField}>
              <span className={styles.dateLabel}>To</span>
              <input
                type="date"
                className={styles.dateInput}
                value={to}
                min={from}
                onChange={(e) => handleToChange(e.target.value)}
              />
            </label>
          </div>
        </div>

        <div className={styles.controlsGroup}>
          <div className={styles.segmented} role="group" aria-label="Granularity">
            {GRANULARITIES.map((g) => (
              <button
                key={g}
                type="button"
                className={`${styles.segBtn} ${granularity === g ? styles.segBtnActive : ''}`}
                aria-pressed={granularity === g}
                onClick={() => setGranularity(g)}
              >
                {g.charAt(0).toUpperCase() + g.slice(1)}
              </button>
            ))}
          </div>
          <button
            type="button"
            className={styles.refreshBtn}
            onClick={handleManualRefresh}
            disabled={refreshing}
          >
            <Icon name="refresh" size={15} className={refreshing ? styles.spin : undefined} />
            {refreshing ? 'Refreshing' : 'Refresh'}
          </button>
        </div>
      </div>

      {/* KPI GRID */}
      <div className={styles.kpiGrid}>
        <KpiCard
          href="/superadmin/appointments"
          label="Active bookings today"
          icon="calendar"
          tone="violet"
          loading={loading}
          value={activeBookingsToday.toLocaleString('en-IN')}
          delta={bookingDelta}
          sub={`vs ${activeBookingsYesterday} yesterday`}
        />
        <KpiCard
          label="Revenue today"
          icon="rupee"
          tone="teal"
          loading={loading}
          value={formatINR(revenueToday)}
          delta={revenueDelta}
          sub={`vs ${formatINR(revenueYesterday)} yesterday`}
        />
        <KpiCard
          href="/superadmin/salon-approval"
          label="Pending approvals"
          icon="clock"
          tone="amber"
          loading={loading}
          value={pendingApprovals.toLocaleString('en-IN')}
          sub={pendingApprovals ? 'Salons awaiting your review' : 'All caught up'}
        />
        <KpiCard
          href="/superadmin/salons"
          label="Active salons"
          icon="store"
          tone="blue"
          loading={loading}
          value={activeSalons.toLocaleString('en-IN')}
          sub="Current network size"
        />
      </div>

      {/* REVENUE TREND + BOOKING MIX */}
      <div className={styles.chartsGrid}>
        <section className={styles.card}>
          <div className={styles.cardHeader}>
            <div>
              <h2 className={styles.cardTitle}>Revenue &amp; bookings</h2>
              <p className={styles.cardSubtitle}>{rangeLabel}</p>
            </div>
            <div className={styles.trendTotals}>
              <div className={styles.trendTotal}>
                <span className={styles.legendDot} style={{ background: palette.c1 }} />
                <div>
                  <div className={styles.trendTotalValue}>{loading ? '—' : formatINR(rangeRevenue)}</div>
                  <div className={styles.trendTotalLabel}>Revenue</div>
                </div>
              </div>
              <div className={styles.trendTotal}>
                <span className={styles.legendDot} style={{ background: palette.c2 }} />
                <div>
                  <div className={styles.trendTotalValue}>{loading ? '—' : rangeBookings.toLocaleString('en-IN')}</div>
                  <div className={styles.trendTotalLabel}>Completed bookings</div>
                </div>
              </div>
            </div>
          </div>
          <div className={styles.trendChart}>
            {loading ? (
              <div className={`${styles.skeleton} ${styles.skeletonChart}`} />
            ) : trend.length > 0 ? (
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={trend} margin={{ top: 10, right: 4, left: 0, bottom: 0 }}>
                  <defs>
                    <linearGradient id="revGrad" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="0%" stopColor={palette.c1} stopOpacity={0.32} />
                      <stop offset="100%" stopColor={palette.c1} stopOpacity={0} />
                    </linearGradient>
                    <linearGradient id="bookGrad" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="0%" stopColor={palette.c2} stopOpacity={0.22} />
                      <stop offset="100%" stopColor={palette.c2} stopOpacity={0} />
                    </linearGradient>
                  </defs>
                  <CartesianGrid strokeDasharray="4 4" vertical={false} stroke={palette.grid} />
                  <XAxis dataKey="label" axisLine={false} tickLine={false} tick={{ fontSize: 12, fill: palette.axis }} minTickGap={32} dy={6} />
                  <YAxis
                    yAxisId="rev"
                    axisLine={false}
                    tickLine={false}
                    tick={{ fontSize: 12, fill: palette.axis }}
                    tickFormatter={(v) => compactINR(Number(v))}
                    width={56}
                  />
                  <YAxis yAxisId="bookings" orientation="right" axisLine={false} tickLine={false} tick={{ fontSize: 12, fill: palette.axis }} tickCount={4} width={32} />
                  <RechartsTooltip
                    cursor={{ stroke: palette.grid, strokeWidth: 1 }}
                    formatter={(value, name) =>
                      name === 'Revenue'
                        ? [formatINR(Number(value)), 'Revenue']
                        : [Math.round(Number(value)).toLocaleString('en-IN'), 'Bookings']
                    }
                    labelFormatter={(label) => {
                      const l = String(label ?? '');
                      const iso = trend.find((t) => t.label === l)?.date;
                      return iso ? formatFullDate(iso) : l;
                    }}
                  />
                  <Area yAxisId="rev" type="monotone" dataKey="revenue" stroke={palette.c1} strokeWidth={2.4} fill="url(#revGrad)" name="Revenue" activeDot={{ r: 5, strokeWidth: 2, stroke: 'var(--surface-color)' }} />
                  <Area yAxisId="bookings" type="monotone" dataKey="bookings" stroke={palette.c2} strokeWidth={2} fill="url(#bookGrad)" name="Bookings" activeDot={{ r: 4, strokeWidth: 2, stroke: 'var(--surface-color)' }} />
                </AreaChart>
              </ResponsiveContainer>
            ) : (
              <EmptyState icon="chart" title="No activity in this range" hint="Try a wider date range." />
            )}
          </div>
        </section>

        <section className={styles.card}>
          <div className={styles.cardHeader}>
            <div>
              <h2 className={styles.cardTitle}>Booking mix</h2>
              <p className={styles.cardSubtitle}>Status of bookings in range</p>
            </div>
          </div>
          {loading ? (
            <div className={`${styles.skeleton} ${styles.skeletonDonut}`} />
          ) : statusTotal === 0 ? (
            <EmptyState icon="calendar" title="No bookings yet" hint="Status split appears once bookings come in." />
          ) : (
            <>
              <div className={styles.donutWrap}>
                <ResponsiveContainer width="100%" height="100%">
                  <PieChart>
                    <Pie
                      data={bookingStatusData}
                      cx="50%"
                      cy="50%"
                      innerRadius="68%"
                      outerRadius="92%"
                      paddingAngle={2}
                      cornerRadius={4}
                      dataKey="value"
                      nameKey="name"
                      stroke="none"
                    >
                      {bookingStatusData.map((entry) => (
                        <Cell key={entry.name} fill={entry.color} />
                      ))}
                    </Pie>
                    <RechartsTooltip formatter={(value, name) => [Number(value).toLocaleString('en-IN'), name]} />
                  </PieChart>
                </ResponsiveContainer>
                <div className={styles.donutCenter}>
                  <div className={styles.donutValue}>{statusTotal.toLocaleString('en-IN')}</div>
                  <div className={styles.donutLabel}>bookings</div>
                </div>
              </div>
              <ul className={styles.statusList}>
                {bookingStatusData.map((d) => (
                  <li key={d.name} className={styles.statusRow}>
                    <span className={styles.legendDot} style={{ background: d.color }} />
                    <span className={styles.statusName}>{d.name}</span>
                    <span className={styles.statusValue}>{d.value.toLocaleString('en-IN')}</span>
                    <span className={styles.statusPct}>{Math.round((d.value / statusTotal) * 100)}%</span>
                  </li>
                ))}
              </ul>
              {channelTotal > 0 && (
                <div className={styles.channel}>
                  <div className={styles.channelHead}>
                    <span>Online <strong>{onlinePct}%</strong></span>
                    <span>Walk-in <strong>{100 - onlinePct}%</strong></span>
                  </div>
                  <div className={styles.channelBar} aria-label={`${onlinePct}% online, ${100 - onlinePct}% walk-in`}>
                    <span style={{ width: `${onlinePct}%`, background: palette.c1 }} />
                    <span style={{ width: `${100 - onlinePct}%`, background: palette.c5 }} />
                  </div>
                </div>
              )}
            </>
          )}
        </section>
      </div>

      {/* LEADERBOARDS */}
      <div className={styles.tablesGrid}>
        <section className={styles.card}>
          <div className={styles.cardHeader}>
            <div>
              <h2 className={styles.cardTitle}>Top salons</h2>
              <p className={styles.cardSubtitle}>By revenue in range</p>
            </div>
            <Link href="/superadmin/salons" className={styles.viewAllBtn}>
              Directory <Icon name="arrowRight" size={14} />
            </Link>
          </div>
          {loading ? (
            <SkeletonRows />
          ) : topSalons.length === 0 ? (
            <EmptyState icon="store" title="No salon revenue yet" hint="Rankings appear after the first completed booking." />
          ) : (
            <ol className={styles.rankList}>
              {topSalons.slice(0, 6).map((salon, idx) => (
                <li key={salon.id ?? salon.name} className={styles.rankRow}>
                  <span className={`${styles.rankBadge} ${idx < 3 ? styles[`rank${idx + 1}` as 'rank1'] : ''}`}>{idx + 1}</span>
                  <div className={styles.rankBody}>
                    <div className={styles.rankTop}>
                      <span className={styles.rankName}>{salon.name}</span>
                      <span className={styles.rankValue}>{formatINR(salon.revenue)}</span>
                    </div>
                    <div className={styles.rankMeta}>
                      <span>{cityName(salon.city)}</span>
                      <span>{Number(salon.bookings).toLocaleString('en-IN')} bookings</span>
                    </div>
                    <div className={styles.meter}>
                      <span style={{ width: `${(Number(salon.revenue) / maxSalonRevenue) * 100}%` }} />
                    </div>
                  </div>
                </li>
              ))}
            </ol>
          )}
        </section>

        <section className={styles.card}>
          <div className={styles.cardHeader}>
            <div>
              <h2 className={styles.cardTitle}>Top services</h2>
              <p className={styles.cardSubtitle}>Most booked across all salons</p>
            </div>
            <Link href="/superadmin/catalog" className={styles.viewAllBtn}>
              Catalog <Icon name="arrowRight" size={14} />
            </Link>
          </div>
          {loading ? (
            <SkeletonRows />
          ) : topServices.length === 0 ? (
            <EmptyState icon="catalog" title="No services booked" hint="Nothing was booked in this period." />
          ) : (
            <ol className={styles.rankList}>
              {topServices.slice(0, 6).map((svc, idx) => (
                <li key={`${svc.service}-${idx}`} className={styles.rankRow}>
                  <span className={styles.rankBadge}>{idx + 1}</span>
                  <div className={styles.rankBody}>
                    <div className={styles.rankTop}>
                      <span className={styles.rankName}>{svc.service}</span>
                      <span className={styles.rankValue}>{formatINR(svc.revenue)}</span>
                    </div>
                    <div className={styles.rankMeta}>
                      <span className={styles.categoryBadge}>{svc.category}</span>
                      <span>{Number(svc.bookings).toLocaleString('en-IN')} bookings</span>
                    </div>
                    <div className={`${styles.meter} ${styles.meterTeal}`}>
                      <span style={{ width: `${(Number(svc.revenue) / maxServiceRevenue) * 100}%` }} />
                    </div>
                  </div>
                </li>
              ))}
            </ol>
          )}
        </section>

        <section className={styles.card}>
          <div className={styles.cardHeader}>
            <div>
              <h2 className={styles.cardTitle}>Awaiting approval</h2>
              <p className={styles.cardSubtitle}>Newest salon applications</p>
            </div>
            <Link href="/superadmin/salon-approval" className={styles.viewAllBtn}>
              Queue <Icon name="arrowRight" size={14} />
            </Link>
          </div>
          {loading ? (
            <SkeletonRows />
          ) : pendingSalons.length === 0 ? (
            <EmptyState icon="approval" title="All caught up" hint="No salons are waiting for review." />
          ) : (
            <ul className={styles.pendingList}>
              {pendingSalons.slice(0, 5).map((salon) => {
                const city = cityName(salon.city);
                return (
                  <li key={salon.id}>
                    <Link href={`/superadmin/salon-approval/${salon.id}`} className={styles.pendingRow}>
                      <span className={styles.pendingAvatar}>{initialsOf(salon.name)}</span>
                      <div className={styles.pendingBody}>
                        <div className={styles.rankName}>{salon.name}</div>
                        <div className={styles.rankMeta}>
                          <span>{city || 'Unknown city'}</span>
                          <span>Applied {new Date(salon.created_at).toLocaleDateString('en-IN', { day: 'numeric', month: 'short' })}</span>
                        </div>
                      </div>
                      <span className={styles.reviewChip}>Review</span>
                    </Link>
                  </li>
                );
              })}
            </ul>
          )}
        </section>
      </div>
    </div>
  );
}

// --- PRESENTATIONAL PIECES ---

const TONES = {
  violet: styles.toneViolet,
  teal: styles.toneTeal,
  amber: styles.toneAmber,
  blue: styles.toneBlue,
} as const;

function KpiCard({
  href, label, icon, tone, loading, value, delta, sub,
}: {
  href?: string;
  label: string;
  icon: IconName;
  tone: keyof typeof TONES;
  loading: boolean;
  value: string;
  delta?: { pct: number; dir: 'up' | 'down' | 'flat' };
  sub: string;
}) {
  const body = (
    <>
      <div className={styles.kpiHeader}>
        <span className={`${styles.kpiIcon} ${TONES[tone]}`}><Icon name={icon} size={20} /></span>
        {href && <Icon name="arrowRight" size={16} className={styles.kpiArrow} />}
      </div>
      <div className={styles.kpiLabel}>{label}</div>
      {loading ? (
        <div className={`${styles.skeleton} ${styles.skeletonValue}`} />
      ) : (
        <div className={styles.kpiValue}>{value}</div>
      )}
      <div className={styles.kpiTrend}>
        {delta && !loading && (
          <span className={`${styles.deltaChip} ${delta.dir === 'up' ? styles.deltaUp : delta.dir === 'down' ? styles.deltaDown : styles.deltaFlat}`}>
            {delta.dir !== 'flat' && <Icon name={delta.dir === 'up' ? 'trendUp' : 'trendDown'} size={13} strokeWidth={2.2} />}
            {delta.pct}%
          </span>
        )}
        <span className={styles.trendSub}>{sub}</span>
      </div>
    </>
  );

  return href ? (
    <Link href={href} className={`${styles.kpiCard} ${styles.clickableCard}`}>{body}</Link>
  ) : (
    <div className={styles.kpiCard}>{body}</div>
  );
}

function EmptyState({ icon, title, hint }: { icon: IconName; title: string; hint: string }) {
  return (
    <div className={styles.empty}>
      <span className={styles.emptyIcon}><Icon name={icon} size={20} /></span>
      <div className={styles.emptyTitle}>{title}</div>
      <div className={styles.emptyHint}>{hint}</div>
    </div>
  );
}

function SkeletonRows() {
  return (
    <div className={styles.skeletonList}>
      {SKELETON_ROWS.map((id) => (
        <div key={id} className={styles.skeletonRow}>
          <span className={`${styles.skeleton} ${styles.skeletonDot}`} />
          <span className={`${styles.skeleton} ${styles.skeletonLine}`} />
        </div>
      ))}
    </div>
  );
}

/** The API returns city as a name or as a { name } object depending on the endpoint. */
const cityName = (city: unknown): string =>
  city && typeof city === 'object' ? String((city as { name?: string }).name ?? '') : String(city ?? '');

const initialsOf = (name: string) =>
  (name || '?').split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0]).join('').toUpperCase();

const compactINR = (n: number) => {
  if (n >= 1e7) return `₹${(n / 1e7).toFixed(1).replace(/\.0$/, '')}Cr`;
  if (n >= 1e5) return `₹${(n / 1e5).toFixed(1).replace(/\.0$/, '')}L`;
  if (n >= 1e3) return `₹${(n / 1e3).toFixed(0)}k`;
  return `₹${Math.round(n)}`;
};
