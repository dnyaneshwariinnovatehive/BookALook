'use client';

import { useCallback, useEffect, useState } from 'react';
import styles from './page.module.css';

/**
 * Platform Reporting — the owner's single view across the whole network.
 *
 * Pulls read-only aggregates from /api/proxy/superadmin/reports/* and lays
 * them out as KPI cards plus per-salon, per-area and per-service tables. Every
 * table can be exported to CSV, which opens straight into Excel. Nothing on
 * this screen writes back to the platform — it is a reporting surface only.
 */

const money = (v: any) => {
  const n = Number(v || 0);
  return '₹' + n.toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
};

const int = (v: any) => Number(v || 0).toLocaleString('en-IN');

const pct = (v: any) => (v == null ? '—' : `${Number(v)}%`);

/** Trigger a CSV download that opens cleanly in Excel. */
function downloadCSV(filename: string, headers: string[], rows: any[][]) {
  const escape = (v: any) => {
    const s = String(v ?? '');
    return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  const lines = [headers.map(escape).join(','), ...rows.map((r) => r.map(escape).join(','))];
  const csv = '\uFEFF' + lines.join('\n');
  const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

export default function ReportsPage() {
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');

  const [overview, setOverview] = useState<any>(null);
  const [salons, setSalons] = useState<any[]>([]);
  const [salonTotals, setSalonTotals] = useState<any>(null);
  const [cities, setCities] = useState<any[]>([]);
  const [services, setServices] = useState<any[]>([]);

  const authHeaders = (): Record<string, string> => {
    const token = localStorage.getItem('sa_token');
    return {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    };
  };

  const handleUnauthorized = (res: Response) => {
    if (res.status === 401) {
      localStorage.removeItem('sa_token');
      window.location.href = '/superadmin/login';
      return true;
    }
    return false;
  };

  const load = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const q = new URLSearchParams();
      if (from) q.append('from', from);
      if (to) q.append('to', to);
      const suffix = q.toString() ? `?${q}` : '';

      const [ovRes, salRes, cityRes, svcRes] = await Promise.all([
        fetch('/api/proxy/superadmin/reports/overview', { headers: authHeaders() }),
        fetch(`/api/proxy/superadmin/reports/salons${suffix}`, { headers: authHeaders() }),
        fetch(`/api/proxy/superadmin/reports/cities${suffix}`, { headers: authHeaders() }),
        fetch(`/api/proxy/superadmin/reports/services${suffix}`, { headers: authHeaders() }),
      ]);

      for (const r of [ovRes, salRes, cityRes, svcRes]) {
        if (handleUnauthorized(r)) return;
        if (!r.ok) throw new Error('Could not load reports.');
      }

      const ov = await ovRes.json();
      const sal = await salRes.json();
      const city = await cityRes.json();
      const svc = await svcRes.json();

      setOverview(ov);
      setSalons(sal.salons ?? []);
      setSalonTotals(sal.totals ?? null);
      setCities(city.cities ?? []);
      setServices(svc.services ?? []);
    } catch (e: any) {
      setError(e.message || 'Could not load reports.');
    } finally {
      setLoading(false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [from, to]);

  useEffect(() => {
    load();
  }, [load]);

  const exportSalons = () =>
    downloadCSV(
      'salon-report.csv',
      ['Salon', 'City', 'Status', 'Bookings', 'Completed', 'Cancelled', 'No-Show', 'Cancellation %', 'No-Show %', 'Revenue', 'Avg Rating'],
      salons.map((s) => [
        s.name, s.city, s.status, s.bookings, s.completed, s.cancelled,
        s.no_show, pct(s.cancellation_rate), pct(s.no_show_rate), money(s.revenue), s.avg_rating,
      ])
    );

  const exportCities = () =>
    downloadCSV(
      'area-report.csv',
      ['City', 'Salons', 'Bookings', 'Completed', 'Revenue'],
      cities.map((c) => [c.city, c.salons, c.bookings, c.completed, money(c.revenue)])
    );

  const exportServices = () =>
    downloadCSV(
      'service-report.csv',
      ['Service', 'Category', 'Bookings', 'Revenue'],
      services.map((s) => [s.service, s.category, s.bookings, money(s.revenue)])
    );

  const exportTopSalons = () =>
    downloadCSV(
      'top-salons.csv',
      ['Salon', 'City', 'Bookings', 'Revenue'],
      (overview?.top_salons ?? []).map((s: any) => [s.name, s.city, s.bookings, money(s.revenue)])
    );

  /* -------- skeleton loading state -------- */
  if (loading && !overview) {
    return (
      <div className={styles.container}>
        <div className={styles.header}>
          <div className={styles.headerLeft}>
            <div className={styles.titleRow}>
              <h1 className={styles.title}>Platform Reporting</h1>
              <span className={styles.badge}><span className={styles.badgeDot} /> Loading</span>
            </div>
            <p className={styles.subtitle}>Gathering analytics from across the network…</p>
          </div>
        </div>
        <div className={styles.content}>
          <div className={`${styles.skeletonHeader} ${styles.skeleton}`} />
          <div className={styles.skeletonGrid}>
            {[1, 2, 3, 4, 5, 6].map((i) => (
              <div key={i} className={`${styles.skeletonKpi} ${styles.skeleton}`} />
            ))}
          </div>
          <div className={`${styles.skeletonCard} ${styles.skeleton}`} />
          <div className={`${styles.skeletonCard} ${styles.skeleton}`} />
          <div className={`${styles.skeletonCard} ${styles.skeleton}`} />
          <p className={styles.loadingLabel}>Fetching data…</p>
        </div>
      </div>
    );
  }

  /* -------- error state -------- */
  if (error) {
    return (
      <div className={styles.container}>
        <div className={styles.header}>
          <div className={styles.headerLeft}>
            <div className={styles.titleRow}>
              <h1 className={styles.title}>Platform Reporting</h1>
            </div>
            <p className={styles.subtitle}>Analytics and analysis across the platform.</p>
          </div>
        </div>
        <div className={styles.content}>
          <div className={styles.errorCard}>
            <p className={styles.errorTitle}>Unable to load reports</p>
            <p className={styles.errorMessage}>{error}</p>
            <button className={styles.retryButton} onClick={load}>Try again</button>
          </div>
        </div>
      </div>
    );
  }

  const b = overview?.bookings ?? {};
  const sa = overview?.salons ?? {};
  const r = overview?.rating ?? {};
  const rev = overview?.revenue ?? {};
  const topSalons = overview?.top_salons ?? [];
  const topCities = overview?.cities ?? [];

  const hasBookings = (b.total ?? 0) > 0;

  return (
    <div className={styles.container}>
      {/* ---- header banner ---- */}
      <div className={styles.header}>
        <div className={styles.headerLeft}>
          <div className={styles.titleRow}>
            <h1 className={styles.title}>Platform Reporting</h1>
            <span className={styles.badge}>
              <span className={styles.badgeDot} />
              Read-only
            </span>
          </div>
          <p className={styles.subtitle}>
            A complete view of every salon, area and service on the platform.
          </p>
          {overview?.generated_at && (
            <p className={styles.generatedAt}>
              Generated {new Date(overview.generated_at).toLocaleString('en-IN', {
                day: 'numeric', month: 'short', year: 'numeric',
                hour: '2-digit', minute: '2-digit',
              })}
            </p>
          )}
        </div>
      </div>

      <div className={styles.content}>
        {/* ---- filter bar ---- */}
        <div className={styles.rangeBar}>
          <div className={styles.field}>
            <label htmlFor="rep-from">From</label>
            <input id="rep-from" type="date" value={from} onChange={(e) => setFrom(e.target.value)} />
          </div>
          <div className={styles.field}>
            <label htmlFor="rep-to">To</label>
            <input id="rep-to" type="date" value={to} onChange={(e) => setTo(e.target.value)} />
          </div>
          <button className={styles.button} onClick={load}>Apply</button>
          <span className={styles.rangeHint}>
            Filters the Salon / Area / Service tables below. KPI cards always show today, this week and this month.
          </span>
        </div>

        {/* ---- KPI cards ---- */}
        <div className={styles.kpiGrid}>
          <KPI label="Active salons" value={int(sa.active)} sub={`${int(sa.total)} total · ${int(sa.pending)} pending`} dotColor="#22c55e" />
          <KPI label="Total bookings" value={int(b.total)} sub={`${int(b.today)} today · ${int(b.week)} this week · ${int(b.month)} this month`} dotColor="#6366f1" />
          <KPI label="Completed" value={int(b.completed)} sub={`${int(b.online)} online · ${int(b.walk_in)} walk-in`} dotColor="#14b8a6" />
          <KPI label="Average rating" value={r.average ? r.average.toFixed(2) : '—'} sub={`${int(r.review_count)} reviews`} accent dotColor="#f59e0b" />
          <KPI label="Billed by salons" value={money(rev.billed_by_salons)} sub="from completed appointments" dotColor="#ec4899" />
          <KPI label="Commission earned" value={money(rev.commission_earned)} sub={`${money(rev.net_to_salons)} net to salons`} accent dotColor="#7c3aed" />
        </div>

        {/* ---- booking health ---- */}
        <Section title="Booking health" desc="Platform-wide cancellation and no-show performance." accent>
          <div className={styles.healthRow}>
            <HealthStat label="Cancellation rate" value={pct(b.cancellation_rate)} tone="warn" hint="Target: below 15%" />
            <HealthStat label="No-show rate" value={pct(b.no_show_rate)} tone="bad" hint="Target: below 10%" />
            <HealthStat label="Review coverage" value={`${int(r.review_count)}`} tone="ok" hint="Total reviews collected" />
          </div>
          {!hasBookings && (
            <p className={styles.muted}>No bookings worth calculating rates from yet.</p>
          )}
        </Section>

        {/* ---- top performing salons ---- */}
        <Section title="Top performing salons" desc="Highest revenue-generating salons across the platform." accent action={
          <button className={styles.smallButton} onClick={exportTopSalons}>↓ CSV</button>
        }>
          {topSalons.length === 0 ? (
            <p className={styles.muted}>No completed appointments yet.</p>
          ) : (
            <div className={styles.tableScroll}>
              <table className={styles.table}>
                <thead>
                  <tr>
                    <th style={{ width: 50 }}>#</th>
                    <th>Salon</th><th>City</th><th>Bookings</th><th style={{ textAlign: 'right' }}>Revenue</th>
                  </tr>
                </thead>
                <tbody>
                  {topSalons.map((s2: any, idx: number) => (
                    <tr key={s2.id}>
                      <td>
                        <span className={`${styles.rankBadge} ${idx === 0 ? styles.rank1 : idx === 1 ? styles.rank2 : idx === 2 ? styles.rank3 : styles.rankN}`}>
                          {idx + 1}
                        </span>
                      </td>
                      <td><strong>{s2.name}</strong></td>
                      <td>{s2.city ?? '—'}</td>
                      <td>{int(s2.bookings)}</td>
                      <td className={styles.textRightBold}>{money(s2.revenue)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Section>

        {/* ---- per-salon report ---- */}
        <Section title="Salons — cancellation & no-show" desc="Per-salon booking health, revenue and ratings." accent action={
          <button className={styles.smallButton} onClick={exportSalons}>↓ CSV</button>
        }>
          {salons.length === 0 ? (
            <p className={styles.muted}>No salons with bookings in this range.</p>
          ) : (
            <>
              <div className={styles.tableScroll}>
                <table className={styles.table}>
                  <thead>
                    <tr>
                      <th>Salon</th><th>City</th><th>Status</th><th>Bookings</th>
                      <th>Completed</th><th>Cancelled</th><th>No-show</th>
                      <th>Cancellation %</th><th>No-show %</th>
                      <th style={{ textAlign: 'right' }}>Revenue</th><th>Rating</th>
                    </tr>
                  </thead>
                  <tbody>
                    {salons.map((s2) => (
                      <tr key={s2.id}>
                        <td><strong>{s2.name}</strong></td>
                        <td>{s2.city ?? '—'}</td>
                        <td><StatusPill status={s2.status} /></td>
                        <td>{int(s2.bookings)}</td>
                        <td>{int(s2.completed)}</td>
                        <td>{int(s2.cancelled)}</td>
                        <td>{int(s2.no_show)}</td>
                        <td className={s2.cancellation_rate > 15 ? styles.warnText : styles.okText}>{pct(s2.cancellation_rate)}</td>
                        <td className={s2.no_show_rate > 15 ? styles.warnText : styles.okText}>{pct(s2.no_show_rate)}</td>
                        <td className={styles.textRightBold}>{money(s2.revenue)}</td>
                        <td>{s2.avg_rating ? s2.avg_rating.toFixed(1) : '—'}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              {salonTotals && (
                <div className={styles.totalsRow}>
                  <span className={styles.totalsLabel}>Totals</span>
                  <span>·</span>
                  <span>{int(salonTotals.bookings)} bookings</span>
                  <span>·</span>
                  <span>{int(salonTotals.completed)} completed</span>
                  <span>·</span>
                  <span>{pct(salonTotals.cancellation_rate)} cancelled</span>
                  <span>·</span>
                  <span>{pct(salonTotals.no_show_rate)} no-show</span>
                  <span>·</span>
                  <span>{money(salonTotals.revenue)} revenue</span>
                </div>
              )}
            </>
          )}
        </Section>

        {/* ---- areas / cities ---- */}
        <Section title="Areas & cities" desc="Breakdown of salon and booking activity by city." accent action={
          <button className={styles.smallButton} onClick={exportCities}>↓ CSV</button>
        }>
          {cities.length === 0 ? (
            <p className={styles.muted}>No cities with booking activity in this range.</p>
          ) : (
            <>
              <div className={styles.tableScroll}>
                <table className={styles.table}>
                  <thead>
                    <tr>
                      <th>City</th><th>Salons</th><th>Bookings</th><th>Completed</th><th style={{ textAlign: 'right' }}>Revenue</th>
                    </tr>
                  </thead>
                  <tbody>
                    {cities.map((c, i) => (
                      <tr key={i}>
                        <td><strong>{c.city}</strong></td>
                        <td>{int(c.salons)}</td>
                        <td>{int(c.bookings)}</td>
                        <td>{int(c.completed)}</td>
                        <td className={styles.textRightBold}>{money(c.revenue)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              {topCities.length > 0 && (
                <div className={styles.totalsRow}>
                  <span className={styles.totalsLabel}>Leading areas</span>
                  {topCities.map((c: any) => (
                    <span key={c.city}>{c.city} ({money(c.revenue)})</span>
                  ))}
                </div>
              )}
            </>
          )}
        </Section>

        {/* ---- services & categories ---- */}
        <Section title="Services & categories" desc="Most booked services and their revenue contribution." accent action={
          <button className={styles.smallButton} onClick={exportServices}>↓ CSV</button>
        }>
          {services.length === 0 ? (
            <p className={styles.muted}>No service bookings in this range.</p>
          ) : (
            <div className={styles.tableScroll}>
              <table className={styles.table}>
                <thead>
                  <tr>
                    <th>Service</th><th>Category</th><th style={{ textAlign: 'right' }}>Bookings</th><th style={{ textAlign: 'right' }}>Revenue</th>
                  </tr>
                </thead>
                <tbody>
                  {services.map((sv, i) => (
                    <tr key={i}>
                      <td><strong>{sv.service}</strong></td>
                      <td>{sv.category}</td>
                      <td className={styles.textRight}>{int(sv.bookings)}</td>
                      <td className={styles.textRightBold}>{money(sv.revenue)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Section>

        {/* ---- reviews placeholder ---- */}
        <Section title="Customer reviews" desc="Service-level sentiment and per-salon ratings will live here." accent>
          <div className={styles.placeholderBox}>
            <div className={styles.placeholderIcon}>★</div>
            <p className={styles.placeholderTitle}>
              {r.enabled
                ? `${int(r.review_count)} review${r.review_count === 1 ? '' : 's'} · ${r.average ? r.average.toFixed(1) : '—'} / 5`
                : 'Review system not active yet'}
            </p>
            <p className={styles.placeholderText}>
              {r.enabled
                ? 'Ratings are being collected. A full review analysis — sentiment, themes, per-salon breakdown — will appear here.'
                : 'Leave space for a review analysis surface — service-level sentiment, '
                  + 'per-salon ratings and comment themes will live here once reviews are '
                  + 'turned on.'}
            </p>
          </div>
        </Section>
      </div>
    </div>
  );
}

/* ---------------------------------------------------------------- helpers */

function KPI({ label, value, sub, accent, dotColor }: { label: string; value: string; sub: string; accent?: boolean; dotColor?: string }) {
  return (
    <div className={`${styles.kpi} ${accent ? styles.kpiAccent : ''}`}>
      <div className={styles.kpiLabel}>
        <span className={styles.kpiDot} style={{ background: dotColor ?? '#6b7280' }} />
        {label}
      </div>
      <div className={styles.kpiValue}>{value}</div>
      <div className={styles.kpiSub}>{sub}</div>
    </div>
  );
}

function Section({ title, desc, children, accent, action }: { title: string; desc?: string; children?: React.ReactNode; accent?: boolean; action?: React.ReactNode }) {
  return (
    <div className={`${styles.card} ${accent ? styles.cardAccent : ''}`}>
      <div className={styles.cardHeader}>
        <div>
          <h2 className={styles.cardTitle}>{title}</h2>
          {desc && <p className={styles.cardDesc}>{desc}</p>}
        </div>
        {action && <div>{action}</div>}
      </div>
      {children}
    </div>
  );
}

function HealthStat({ label, value, tone, hint }: { label: string; value: string; tone: 'ok' | 'warn' | 'bad'; hint?: string }) {
  return (
    <div className={styles.healthStat}>
      <div className={`${styles.healthDot} ${styles['healthDot_' + tone]}`} />
      <div className={`${styles.healthValue} ${styles['tone_' + tone]}`}>{value}</div>
      <div className={styles.healthLabel}>{label}</div>
      {hint && <div className={styles.healthHint}>{hint}</div>}
    </div>
  );
}

const statusTone: Record<string, string> = {
  active: styles.sActive,
  pending_approval: styles.sPending,
  suspended: styles.sSuspended,
};

function StatusPill({ status }: { status: string }) {
  return (
    <span className={`${styles.statusPill} ${statusTone[status] ?? ''}`}>
      {(status ?? 'unknown').replace(/_/g, ' ')}
    </span>
  );
}
