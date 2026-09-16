'use client';

import React, { useEffect, useState } from 'react';
import Link from 'next/link';
import {
  BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip as RechartsTooltip, ResponsiveContainer,
  PieChart, Pie, Cell, Legend, AreaChart, Area
} from 'recharts';
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

  const bookingStatusData = data?.bookings
    ? [
        { name: 'Completed', value: data.bookings.completed, color: '#16a34a' },
        { name: 'Active', value: data.bookings.active, color: '#3b82f6' },
        { name: 'Cancelled', value: data.bookings.cancelled, color: '#f97316' },
        { name: 'No-Show', value: data.bookings.no_show, color: '#dc2626' },
      ].filter((d) => d.value > 0)
    : [];

  if (bookingStatusData.length === 0 && !loading) {
    bookingStatusData.push({ name: 'No Data', value: 1, color: '#cbd5e1' });
  }

  const rangeLabel = from && to ? `${formatFullDate(from)} – ${formatFullDate(to)}` : '';

  return (
    <div>
      <header className={styles.pageHeader}>
        <h1 className={styles.pageTitle}>Dashboard Overview</h1>
        <p className={styles.pageSubtitle}>Welcome back. Here is what is happening across the marketplace today.</p>
      </header>

      {/* CONTROLS BAR */}
      <div className={styles.controlsBar}>
        <div className={styles.controlsGroup}>
          <div className={styles.presetGroup}>
            {PRESETS.map((p) => (
              <button
                key={p.key}
                type="button"
                className={`${styles.presetBtn} ${preset === p.key ? styles.presetBtnActive : ''}`}
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
            <span className={styles.dateSep}>→</span>
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
          <div className={styles.granularityToggle}>
            {GRANULARITIES.map((g) => (
              <button
                key={g}
                type="button"
                className={`${styles.granularityBtn} ${granularity === g ? styles.granularityBtnActive : ''}`}
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
            {refreshing ? 'Refreshing…' : '↻ Refresh'}
          </button>
          <button
            type="button"
            className={`${styles.updatedAt}`}
            onClick={() => setAutoRefresh((v) => !v)}
            title={autoRefresh ? 'Auto-refresh: ON (click to pause)' : 'Auto-refresh: OFF (click to enable)'}
          >
            <span className={`${styles.liveDot} ${autoRefresh ? styles.liveDotActive : ''}`} />
            <span className={styles.autoLabel}>{autoRefresh ? 'Auto ON' : 'Auto OFF'}</span>
            <span className={styles.autoTime}>
              {lastUpdated
                ? ` · ${lastUpdated.toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit' })}`
                : ' · …'}
            </span>
          </button>
        </div>
      </div>

      {/* KPI GRID */}
      <div className={styles.kpiGrid}>
        <Link href="/superadmin/appointments" className={`${styles.kpiCard} ${styles.clickableCard}`}>
          <div className={styles.kpiHeader}>
            <span className={styles.kpiLabel}>Active Bookings Today</span>
            <div className={`${styles.kpiIcon} ${styles.kpiIconBlue}`}>📅</div>
          </div>
          <div className={styles.kpiValue}>
            {loading ? '…' : activeBookingsToday}
          </div>
          <div className={styles.kpiTrend}>
            <span className={bookingDelta.dir === 'up' ? styles.trendUp : bookingDelta.dir === 'down' ? styles.trendDown : styles.trendNeutral}>
              {bookingDelta.dir === 'up' ? '▲' : bookingDelta.dir === 'down' ? '▼' : '—'} {bookingDelta.pct}%
            </span>
            <span className={styles.trendSub}>vs {activeBookingsYesterday} yesterday</span>
          </div>
        </Link>

        <div className={styles.kpiCard}>
          <div className={styles.kpiHeader}>
            <span className={styles.kpiLabel}>Revenue Today</span>
            <div className={`${styles.kpiIcon} ${styles.kpiIconGreen}`}>₹</div>
          </div>
          <div className={styles.kpiValue}>
            {loading ? '…' : formatINR(revenueToday)}
          </div>
          <div className={styles.kpiTrend}>
            <span className={revenueDelta.dir === 'up' ? styles.trendUp : revenueDelta.dir === 'down' ? styles.trendDown : styles.trendNeutral}>
              {revenueDelta.dir === 'up' ? '▲' : revenueDelta.dir === 'down' ? '▼' : '—'} {revenueDelta.pct}%
            </span>
            <span className={styles.trendSub}>vs {formatINR(revenueYesterday)} yesterday</span>
          </div>
        </div>

        <Link href="/superadmin/salon-approval" className={`${styles.kpiCard} ${styles.clickableCard}`}>
          <div className={styles.kpiHeader}>
            <span className={styles.kpiLabel}>Pending Approvals</span>
            <div className={`${styles.kpiIcon} ${styles.kpiIconOrange}`}>⏳</div>
          </div>
          <div className={styles.kpiValue}>
            {loading ? '…' : pendingApprovals}
          </div>
          <div className={styles.kpiTrend}>
            <span className={styles.trendNeutral}>Salons awaiting review</span>
          </div>
        </Link>

        <Link href="/superadmin/salons" className={`${styles.kpiCard} ${styles.clickableCard}`}>
          <div className={styles.kpiHeader}>
            <span className={styles.kpiLabel}>Active Salons</span>
            <div className={`${styles.kpiIcon} ${styles.kpiIconPurple}`}>🏪</div>
          </div>
          <div className={styles.kpiValue}>
            {loading ? '…' : activeSalons}
          </div>
          <div className={styles.kpiTrend}>
            <span className={styles.trendNeutral}>Current network size</span>
          </div>
        </Link>
      </div>

      {/* REVENUE TREND (full width) */}
      <div className={`${styles.chartCard} ${styles.fullWidthCard}`}>
        <div className={styles.chartHeaderRow}>
          <div>
            <h2 className={styles.cardTitle}>Revenue & Bookings Trend</h2>
            <p className={styles.chartSubtext}>
              {rangeLabel} · {formatINR(rangeRevenue)} · {rangeBookings.toLocaleString('en-IN')} completed bookings
            </p>
          </div>
          <div className={styles.chartLegend}>
            <span className={styles.legendItem}>
              <span className={styles.legendDot} style={{ background: '#3b82f6' }} /> Revenue
            </span>
            <span className={styles.legendItem}>
              <span className={styles.legendDot} style={{ background: '#22c55e' }} /> Bookings
            </span>
          </div>
        </div>
        <div style={{ width: '100%', height: 320 }}>
          {loading ? (
            <div className={styles.chartLoading}>Loading chart…</div>
          ) : trend.length > 0 ? (
            <ResponsiveContainer width="100%" height="100%">
              <AreaChart data={trend} margin={{ top: 10, right: 10, left: 0, bottom: 5 }}>
                <defs>
                  <linearGradient id="revGrad" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor="#3b82f6" stopOpacity={0.25} />
                    <stop offset="95%" stopColor="#3b82f6" stopOpacity={0} />
                  </linearGradient>
                  <linearGradient id="bookGrad" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor="#22c55e" stopOpacity={0.25} />
                    <stop offset="95%" stopColor="#22c55e" stopOpacity={0} />
                  </linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="#e2e8f0" />
                <XAxis
                  dataKey="label"
                  axisLine={false}
                  tickLine={false}
                  tick={{ fontSize: 12, fill: '#64748b' }}
                  minTickGap={32}
                />
                <YAxis
                  yAxisId="rev"
                  axisLine={false}
                  tickLine={false}
                  tick={{ fontSize: 12, fill: '#64748b' }}
                  tickFormatter={(v) => `₹${Math.round(v).toLocaleString('en-IN')}`}
                  width={80}
                />
                <YAxis
                  yAxisId="bookings"
                  orientation="right"
                  axisLine={false}
                  tickLine={false}
                  tick={{ fontSize: 12, fill: '#64748b' }}
                  tickCount={4}
                  width={40}
                />
                <RechartsTooltip
                  formatter={(value, name) =>
                    name === 'Revenue'
                      ? [`₹${Math.round(Number(value)).toLocaleString('en-IN')}`, 'Revenue']
                      : [`${Math.round(Number(value)).toLocaleString('en-IN')}`, 'Bookings']
                  }
                  labelFormatter={(label) => {
                    const l = String(label ?? '');
                    return trend.find((t) => t.label === l)?.date ?? l;
                  }}
                  contentStyle={{
                    borderRadius: 8,
                    border: '1px solid #e2e8f0',
                    boxShadow: 'var(--card-shadow)',
                  }}
                />
                <Area yAxisId="rev" type="monotone" dataKey="revenue" stroke="#3b82f6" strokeWidth={2} fill="url(#revGrad)" name="Revenue" />
                <Area yAxisId="bookings" type="monotone" dataKey="bookings" stroke="#22c55e" strokeWidth={2} fill="url(#bookGrad)" name="Bookings" />
              </AreaChart>
            </ResponsiveContainer>
          ) : (
            <div className={styles.chartLoading}>No data available</div>
          )}
        </div>
      </div>

      {/* CHARTS GRID */}
      <div className={styles.chartsGrid}>
        <div className={styles.chartCard}>
          <div className={styles.chartHeaderRow}>
            <h2 className={styles.cardTitle}>Top Performing Salons</h2>
            <Link href="/superadmin/salons" className={styles.viewAllBtn}>View Directory</Link>
          </div>
          <div style={{ width: '100%', height: 280, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            {loading ? (
              <div style={{ color: 'var(--text-body)' }}>Loading chart…</div>
            ) : topSalons.length > 0 ? (
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={topSalons} margin={{ top: 20, right: 30, left: 0, bottom: 5 }}>
                  <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="#e2e8f0" />
                  <XAxis dataKey="name" axisLine={false} tickLine={false} tick={{ fontSize: 12, fill: '#64748b' }} />
                  <YAxis axisLine={false} tickLine={false} tick={{ fontSize: 12, fill: '#64748b' }} tickFormatter={(v) => formatINR(v)} />
                  <RechartsTooltip
                    cursor={{ fill: '#f8fafc' }}
                    formatter={(value) => [`₹${Math.round(Number(value)).toLocaleString('en-IN')}`, 'Revenue']}
                  />
                  <Bar dataKey="revenue" fill="#3b82f6" radius={[4, 4, 0, 0]} maxBarSize={50} />
                </BarChart>
              </ResponsiveContainer>
            ) : (
              <div style={{ color: 'var(--text-body)' }}>No data available</div>
            )}
          </div>
        </div>

        <div className={styles.chartCard}>
          <h2 className={styles.cardTitle}>Booking Status Distribution</h2>
          <div style={{ width: '100%', height: 280, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            {loading ? (
              <div style={{ color: 'var(--text-body)' }}>Loading chart…</div>
            ) : (
              <ResponsiveContainer width="100%" height="100%">
                <PieChart>
                  <Pie
                    data={bookingStatusData}
                    cx="50%"
                    cy="50%"
                    innerRadius={55}
                    outerRadius={95}
                    paddingAngle={5}
                    dataKey="value"
                    nameKey="name"
                  >
                    {bookingStatusData.map((entry, index) => (
                      <Cell key={`cell-${index}`} fill={entry.color} />
                    ))}
                  </Pie>
                  <RechartsTooltip formatter={(value) => [`${Number(value).toLocaleString('en-IN')}`, 'Bookings']} />
                  <Legend verticalAlign="bottom" height={36} />
                </PieChart>
              </ResponsiveContainer>
            )}
          </div>
        </div>
      </div>

      {/* TABLES GRID */}
      <div className={styles.tablesGrid}>
        <div className={styles.tableContainer}>
          <div className={styles.tableHeader}>
            <h2 className={styles.tableTitle}>Top Performing Services</h2>
            <Link href="/superadmin/catalog" className={styles.viewAllBtn}>View Catalog</Link>
          </div>
          <table className={styles.table}>
            <thead>
              <tr>
                <th className={styles.th}>#</th>
                <th className={styles.th}>Service</th>
                <th className={styles.th}>Category</th>
                <th className={styles.th}>Bookings</th>
                <th className={styles.th}>Revenue</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                SKELETON_ROWS.map((id) => (
                  <tr key={id} className={styles.tr}>
                    <td className={styles.td}>...</td>
                    <td className={styles.td}>...</td>
                    <td className={styles.td}>...</td>
                    <td className={styles.td}>...</td>
                    <td className={styles.td}>...</td>
                  </tr>
                ))
              ) : topServices.length > 0 ? (
                topServices.slice(0, 5).map((svc, idx) => (
                  <tr key={`${svc.service}-${idx}`} className={styles.tr}>
                    <td className={styles.td}>
                      <span className={styles.rankBadge}>{idx + 1}</span>
                    </td>
                    <td className={styles.td} style={{ fontWeight: 500 }}>{svc.service}</td>
                    <td className={styles.td}>
                      <span className={styles.categoryBadge}>{svc.category}</span>
                    </td>
                    <td className={styles.td}>{svc.bookings}</td>
                    <td className={styles.td} style={{ color: '#16a34a', fontWeight: 500 }}>{formatINR(svc.revenue)}</td>
                  </tr>
                ))
              ) : (
                <tr>
                  <td colSpan={5} className={styles.td} style={{ textAlign: 'center', color: '#64748b' }}>No services booked in this period.</td>
                </tr>
              )}
            </tbody>
          </table>
        </div>

        <div className={styles.tableContainer}>
          <div className={styles.tableHeader}>
            <h2 className={styles.tableTitle}>Pending Salon Approvals</h2>
            <Link href="/superadmin/salon-approval" className={styles.viewAllBtn}>View All</Link>
          </div>
          <table className={styles.table}>
            <thead>
              <tr>
                <th className={styles.th}>Salon Name</th>
                <th className={styles.th}>City</th>
                <th className={styles.th}>Applied Date</th>
                <th className={styles.th}>Status</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                SKELETON_ROWS.map((id) => (
                  <tr key={id} className={styles.tr}>
                    <td className={styles.td}>...</td>
                    <td className={styles.td}>...</td>
                    <td className={styles.td}>...</td>
                    <td className={styles.td}>...</td>
                  </tr>
                ))
              ) : pendingSalons.length > 0 ? (
                pendingSalons.slice(0, 5).map((salon) => (
                  <tr key={salon.id} className={styles.tr}>
                    <td className={styles.td} style={{ fontWeight: 500 }}>{salon.name}</td>
                    <td className={styles.td}>
                      {typeof salon.city === 'object' ? (salon.city as any)?.name : salon.city || 'Unknown'}
                    </td>
                    <td className={styles.td}>{new Date(salon.created_at).toLocaleDateString('en-IN')}</td>
                    <td className={styles.td}>
                      <span className={`${styles.badge} ${styles.badgeWarning}`}>Pending</span>
                    </td>
                  </tr>
                ))
              ) : (
                <tr>
                  <td colSpan={4} className={styles.td} style={{ textAlign: 'center', color: '#64748b' }}>No pending approvals.</td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}