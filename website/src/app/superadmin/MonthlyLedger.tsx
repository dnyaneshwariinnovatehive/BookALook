'use client';

import { Fragment, useEffect, useMemo, useRef, useState } from 'react';
import Link from 'next/link';
import Icon from '@/components/admin/Icon';
import { useChartPalette } from '@/lib/theme';
import styles from './dashboard.module.css';
import lg from './ledger.module.css';
import { EmptyState } from './DashboardParts';

interface Month {
  key: string;
  label: string;
  subscriptions: number;
  commission: number;
  total: number;
  coins: number;
  payments: number;
  paying_salons: number;
  new_paying_salons: number;
  growth_pct: number | null;
  is_current: boolean;
}

interface Item { kind: 'subscription' | 'commission'; label: string; amount: number; coins: number; at: string }

interface SalonMonth { subscriptions: number; commission: number; total: number; coins: number; items: Item[] }

interface SalonRow {
  id: string;
  name: string;
  city: string;
  billing: string | null;
  subscriptions: number;
  commission: number;
  total: number;
  coins: number;
  payments: number;
  active_months: number;
  first_paid: string | null;
  months: Record<string, SalonMonth>;
}

interface LedgerData {
  range: { from: string; to: string; months: number };
  months: Month[];
  salons: SalonRow[];
  insights: {
    month_to_date: number;
    last_month_same_point: number;
    average_month: number;
    best_month: { label: string; total: number } | null;
    annual_run_rate: number;
    paying_salons: number;
    repeat_salons: number;
    coins_share_pct: number;
  };
  pending_by_salon: { id: string; name: string; city: string; amount: number; payouts: number; oldest_cycle: string | null }[];
  upcoming_renewals: { amount: number; count: number; items: { id: string; name: string; plan: string; price: number; end_date: string; auto_renew: boolean }[] };
}

type View = 'month' | 'salon';
type SalonSort = 'total' | 'commission' | 'subscriptions' | 'name';

const SPANS = [3, 6, 12, 24] as const;

const inr = (n: number | undefined) => '₹' + Math.round(Number(n) || 0).toLocaleString('en-IN');

const short = (n: number) => {
  const v = Number(n) || 0;
  if (v >= 1e7) return `₹${(v / 1e7).toFixed(1).replace(/\.0$/, '')}Cr`;
  if (v >= 1e5) return `₹${(v / 1e5).toFixed(1).replace(/\.0$/, '')}L`;
  if (v >= 1e4) return `₹${(v / 1e3).toFixed(0)}k`;
  return inr(v);
};

const day = (iso: string) => new Date(iso).toLocaleDateString('en-IN', { day: '2-digit', month: 'short' });
const monthLabel = (key: string) => new Date(`${key}-01T00:00:00`).toLocaleDateString('en-IN', { month: 'short', year: '2-digit' });

const daysUntil = (iso: string) => Math.max(0, Math.round((new Date(`${iso}T00:00:00`).getTime() - new Date().setHours(0, 0, 0, 0)) / 86400000));

function downloadCsv(name: string, rows: (string | number)[][]) {
  const esc = (v: string | number) => {
    let s = String(v);
    if (/^[=+\-@]/.test(s)) s = `'${s}`;
    return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  const blob = new Blob(['﻿' + rows.map((r) => r.map(esc).join(',')).join('\n')], { type: 'text/csv;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = name;
  a.click();
  URL.revokeObjectURL(url);
}

/**
 * BookALook's month-by-month ledger: what it earned each month and from which
 * salon, with the money still on its way (open commission, renewals due).
 */
export default function MonthlyLedger({ refreshKey }: { refreshKey: number }) {
  const palette = useChartPalette();
  const [span, setSpan] = useState<number>(12);
  const [view, setView] = useState<View>('month');
  const [data, setData] = useState<LedgerData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [open, setOpen] = useState<string | null>(null);
  const [query, setQuery] = useState('');
  const [sort, setSort] = useState<SalonSort>('total');
  const seq = useRef(0);

  useEffect(() => {
    const id = ++seq.current;
    const run = async () => {
      setLoading(true);
      try {
        const res = await fetch(`/api/proxy/superadmin/reports/platform-revenue/monthly?months=${span}`, { cache: 'no-store' });
        const json = await res.json();
        if (id !== seq.current) return;
        if (!res.ok || !json.success) throw new Error(json.message || 'Could not load the monthly ledger.');
        setData(json as LedgerData);
        setError('');
      } catch (e) {
        if (id === seq.current) setError(e instanceof Error ? e.message : 'Could not load the monthly ledger.');
      } finally {
        if (id === seq.current) setLoading(false);
      }
    };
    const timer = setTimeout(run, 0);
    return () => clearTimeout(timer);
  }, [span, refreshKey]);

  const months = useMemo(() => [...(data?.months ?? [])].reverse(), [data]);
  const sum = useMemo(() => {
    const m = data?.months ?? [];
    return {
      subscriptions: m.reduce((s, x) => s + x.subscriptions, 0),
      commission: m.reduce((s, x) => s + x.commission, 0),
      total: m.reduce((s, x) => s + x.total, 0),
      coins: m.reduce((s, x) => s + x.coins, 0),
      payments: m.reduce((s, x) => s + x.payments, 0),
      newSalons: m.reduce((s, x) => s + x.new_paying_salons, 0),
    };
  }, [data]);
  const maxMonth = Math.max(1, ...(data?.months ?? []).map((m) => m.total));

  const salons = useMemo(() => {
    const q = query.trim().toLowerCase();
    const rows = (data?.salons ?? []).filter((s) => !q || s.name.toLowerCase().includes(q) || s.city.toLowerCase().includes(q));
    return [...rows].sort((a, b) => (sort === 'name' ? a.name.localeCompare(b.name) : b[sort] - a[sort]));
  }, [data, query, sort]);
  const maxCell = Math.max(1, ...(data?.salons ?? []).flatMap((s) => Object.values(s.months).map((m) => m.total)));

  const ins = data?.insights;
  const mtdDelta = ins && ins.last_month_same_point > 0
    ? Math.round(((ins.month_to_date - ins.last_month_same_point) / ins.last_month_same_point) * 100)
    : null;
  const pendingTotal = (data?.pending_by_salon ?? []).reduce((s, x) => s + x.amount, 0);

  const exportCsv = () => {
    if (!data) return;
    if (view === 'month') {
      downloadCsv(`bookalook-revenue-by-month-${data.range.to.slice(0, 7)}.csv`, [
        ['Month', 'Plan payments', 'Commission', 'Total revenue', 'Coins given', 'Payments', 'Paying salons', 'New paying salons', 'vs previous month %'],
        ...data.months.map((m) => [m.label, m.subscriptions, m.commission, m.total, m.coins, m.payments, m.paying_salons, m.new_paying_salons, m.growth_pct ?? '']),
      ]);
    } else {
      downloadCsv(`bookalook-revenue-by-salon-${data.range.to.slice(0, 7)}.csv`, [
        ['Salon', 'City', 'Billing now', ...data.months.map((m) => m.label), 'Plan payments', 'Commission', 'Total revenue', 'Coins given'],
        ...salons.map((s) => [
          s.name, s.city, s.billing ?? '',
          ...data.months.map((m) => s.months[m.key]?.total ?? 0),
          s.subscriptions, s.commission, s.total, s.coins,
        ]),
      ]);
    }
  };

  const monthBreakdown = (key: string) =>
    (data?.salons ?? [])
      .filter((s) => s.months[key])
      .map((s) => ({ salon: s, m: s.months[key] }))
      .sort((a, b) => b.m.total - a.m.total);

  return (
    <section className={`${styles.card} ${lg.ledger}`}>
      <div className={lg.head}>
        <div>
          <h2 className={styles.cardTitle}>Monthly ledger</h2>
          <p className={styles.cardSubtitle}>What BookALook earned each month, and from which salon</p>
        </div>
        <div className={lg.controls}>
          <div className={lg.segment} role="group" aria-label="Months shown">
            {SPANS.map((n) => (
              <button key={n} type="button" className={n === span ? lg.segOn : ''} onClick={() => setSpan(n)} aria-pressed={n === span}>
                {n}M
              </button>
            ))}
          </div>
          <div className={lg.segment} role="group" aria-label="View">
            <button type="button" className={view === 'month' ? lg.segOn : ''} onClick={() => setView('month')} aria-pressed={view === 'month'}>
              <Icon name="calendar" size={14} /> By month
            </button>
            <button type="button" className={view === 'salon' ? lg.segOn : ''} onClick={() => setView('salon')} aria-pressed={view === 'salon'}>
              <Icon name="store" size={14} /> By salon
            </button>
          </div>
          <button type="button" className={lg.exportBtn} onClick={exportCsv} disabled={!data}>
            <Icon name="download" size={14} /> CSV
          </button>
        </div>
      </div>

      {/* INSIGHTS */}
      <div className={lg.insights}>
        <div className={lg.insight}>
          <span>This month so far</span>
          <b>{loading && !data ? '—' : inr(ins?.month_to_date)}</b>
          <em className={mtdDelta == null ? '' : mtdDelta >= 0 ? lg.up : lg.down}>
            {mtdDelta == null ? 'Nothing last month to compare' : `${mtdDelta >= 0 ? '▲' : '▼'} ${Math.abs(mtdDelta)}% vs last month by today`}
          </em>
        </div>
        <div className={lg.insight}>
          <span>Average month</span>
          <b>{loading && !data ? '—' : inr(ins?.average_month)}</b>
          <em>Completed months shown</em>
        </div>
        <div className={lg.insight}>
          <span>Best month</span>
          <b>{ins?.best_month ? inr(ins.best_month.total) : '—'}</b>
          <em>{ins?.best_month?.label ?? 'No revenue yet'}</em>
        </div>
        <div className={lg.insight}>
          <span>Yearly run rate</span>
          <b>{loading && !data ? '—' : short(ins?.annual_run_rate ?? 0)}</b>
          <em>Last 3 full months, yearly</em>
        </div>
        <div className={lg.insight}>
          <span>Paying again</span>
          <b>{ins ? `${ins.repeat_salons} / ${ins.paying_salons}` : '—'}</b>
          <em>Salons that paid in 2+ months</em>
        </div>
        <div className={lg.insight}>
          <span>Coins share</span>
          <b>{ins ? `${ins.coins_share_pct}%` : '—'}</b>
          <em>Of value taken as coins, not cash</em>
        </div>
      </div>

      {error && !data ? (
        <div className={lg.error} role="alert">{error}</div>
      ) : loading && !data ? (
        <div className={`${styles.skeleton} ${styles.skeletonChart}`} />
      ) : !data || sum.total + sum.coins === 0 ? (
        <EmptyState icon="receipt" title="No revenue in these months" hint="Approved plan payments and settled commission are listed here month by month." />
      ) : view === 'month' ? (
        <div className={lg.tableWrap}>
          <table className={lg.table}>
            <thead>
              <tr>
                <th>Month</th>
                <th className={lg.num}>Plan payments</th>
                <th className={lg.num}>Commission</th>
                <th className={lg.num}>Total revenue</th>
                <th className={lg.num}>Coins given</th>
                <th className={lg.num}>Paying salons</th>
                <th className={lg.num}>New</th>
                <th className={lg.num}>vs prev.</th>
              </tr>
            </thead>
            <tbody>
              {months.map((m) => {
                const isOpen = open === m.key;
                const rows = isOpen ? monthBreakdown(m.key) : [];
                return (
                  <Fragment key={m.key}>
                    <tr
                      className={`${lg.monthRow} ${isOpen ? lg.rowOpen : ''} ${m.total + m.coins === 0 ? lg.rowEmpty : ''}`}
                      onClick={() => m.payments > 0 && setOpen(isOpen ? null : m.key)}
                      aria-expanded={m.payments > 0 ? isOpen : undefined}
                    >
                      <td>
                        <span className={lg.monthCell}>
                          {m.payments > 0 ? (
                            <Icon name="chevronRight" size={14} className={isOpen ? lg.chevOpen : lg.chev} />
                          ) : (
                            <span className={lg.chevSpace} />
                          )}
                          <b>{m.label}</b>
                          {m.is_current && <span className={lg.live}>so far</span>}
                        </span>
                      </td>
                      <td className={lg.num}>{inr(m.subscriptions)}</td>
                      <td className={lg.num}>{inr(m.commission)}</td>
                      <td className={lg.num}>
                        <span className={lg.totalCell}>
                          <span className={lg.miniBar}>
                            <span style={{ width: `${(m.subscriptions / maxMonth) * 100}%`, background: palette.c1 }} />
                            <span style={{ width: `${(m.commission / maxMonth) * 100}%`, background: palette.c2 }} />
                          </span>
                          <b>{inr(m.total)}</b>
                        </span>
                      </td>
                      <td className={`${lg.num} ${lg.coins}`}>{m.coins > 0 ? inr(m.coins) : '—'}</td>
                      <td className={lg.num}>{m.paying_salons}</td>
                      <td className={lg.num}>{m.new_paying_salons > 0 ? <span className={lg.newTag}>+{m.new_paying_salons}</span> : '—'}</td>
                      <td className={lg.num}>
                        {m.growth_pct == null ? '—' : (
                          <span className={m.growth_pct >= 0 ? lg.up : lg.down}>
                            {m.growth_pct >= 0 ? '▲' : '▼'} {Math.abs(m.growth_pct)}%
                          </span>
                        )}
                      </td>
                    </tr>
                    {isOpen && (
                      <tr className={lg.detailRow}>
                        <td colSpan={8}>
                          <div className={lg.detail}>
                            <div className={lg.detailHead}>
                              <span>Salon</span>
                              <span>What they paid for</span>
                              <span className={lg.num}>Plans</span>
                              <span className={lg.num}>Commission</span>
                              <span className={lg.num}>Total</span>
                              <span className={lg.num}>Share</span>
                            </div>
                            {rows.map(({ salon, m: sm }) => (
                              <div key={salon.id} className={lg.detailLine}>
                                <span className={lg.salonCell}>
                                  <Link href={`/superadmin/salons/${salon.id}`} onClick={(e) => e.stopPropagation()}>{salon.name}</Link>
                                  <small>{salon.city}</small>
                                </span>
                                <span className={lg.items}>
                                  {sm.items.map((it, i) => (
                                    <span key={i} className={it.kind === 'commission' ? lg.chipComm : lg.chipPlan} title={`${day(it.at)} · ${inr(it.amount)}${it.coins > 0 ? ` + ${inr(it.coins)} coins` : ''}`}>
                                      {it.label} · {day(it.at)}
                                    </span>
                                  ))}
                                </span>
                                <span className={lg.num}>{sm.subscriptions > 0 ? inr(sm.subscriptions) : '—'}</span>
                                <span className={lg.num}>{sm.commission > 0 ? inr(sm.commission) : '—'}</span>
                                <span className={lg.num}>
                                  <b>{inr(sm.total)}</b>
                                  {sm.coins > 0 && <small className={lg.coins}>+ {inr(sm.coins)} coins</small>}
                                </span>
                                <span className={lg.num}>{m.total > 0 ? `${Math.round((sm.total / m.total) * 100)}%` : '—'}</span>
                              </div>
                            ))}
                          </div>
                        </td>
                      </tr>
                    )}
                  </Fragment>
                );
              })}
            </tbody>
            <tfoot>
              <tr>
                <td>{data.range.months} months</td>
                <td className={lg.num}>{inr(sum.subscriptions)}</td>
                <td className={lg.num}>{inr(sum.commission)}</td>
                <td className={lg.num}><b>{inr(sum.total)}</b></td>
                <td className={`${lg.num} ${lg.coins}`}>{inr(sum.coins)}</td>
                <td className={lg.num}>{ins?.paying_salons ?? 0}</td>
                <td className={lg.num}>+{sum.newSalons}</td>
                <td />
              </tr>
            </tfoot>
          </table>
        </div>
      ) : (
        <>
          <div className={lg.salonTools}>
            <label className={lg.search}>
              <Icon name="search" size={15} />
              <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search salon or city" />
            </label>
            <label className={lg.sortBox}>
              Sort
              <select value={sort} onChange={(e) => setSort(e.target.value as SalonSort)}>
                <option value="total">Highest total</option>
                <option value="commission">Highest commission</option>
                <option value="subscriptions">Highest plan payments</option>
                <option value="name">Name A–Z</option>
              </select>
            </label>
            <span className={lg.count}>{salons.length} paying salon{salons.length === 1 ? '' : 's'}</span>
          </div>
          <div className={lg.tableWrap}>
            <table className={`${lg.table} ${lg.matrix}`}>
              <thead>
                <tr>
                  <th className={lg.sticky}>Salon</th>
                  {data.months.map((m) => <th key={m.key} className={lg.num}>{monthLabel(m.key)}</th>)}
                  <th className={lg.num}>Plans</th>
                  <th className={lg.num}>Commission</th>
                  <th className={lg.num}>Total</th>
                </tr>
              </thead>
              <tbody>
                {salons.map((s) => (
                  <tr key={s.id}>
                    <td className={lg.sticky}>
                      <span className={lg.salonCell}>
                        <Link href={`/superadmin/salons/${s.id}`}>{s.name}</Link>
                        <small>
                          {s.city}
                          {s.billing && <> · <span className={s.billing === 'Commission Model' ? lg.tagComm : lg.tagPlan}>{s.billing}</span></>}
                        </small>
                      </span>
                    </td>
                    {data.months.map((m) => {
                      const c = s.months[m.key];
                      if (!c) return <td key={m.key} className={`${lg.num} ${lg.cellEmpty}`}>·</td>;
                      const strength = 0.1 + 0.55 * (c.total / maxCell);
                      return (
                        <td
                          key={m.key}
                          className={`${lg.num} ${lg.heat}`}
                          style={{ ['--heat' as string]: strength.toFixed(2) }}
                          title={[
                            `${s.name} · ${m.label}`,
                            ...c.items.map((it) => `${it.label} (${day(it.at)}): ${inr(it.amount)}${it.coins > 0 ? ` + ${inr(it.coins)} coins` : ''}`),
                          ].join('\n')}
                        >
                          {short(c.total)}
                        </td>
                      );
                    })}
                    <td className={lg.num}>{inr(s.subscriptions)}</td>
                    <td className={lg.num}>{inr(s.commission)}</td>
                    <td className={lg.num}>
                      <b>{inr(s.total)}</b>
                      {s.coins > 0 && <small className={lg.coins}>+ {inr(s.coins)} coins</small>}
                    </td>
                  </tr>
                ))}
              </tbody>
              <tfoot>
                <tr>
                  <td className={lg.sticky}>All salons</td>
                  {data.months.map((m) => <td key={m.key} className={lg.num}>{m.total > 0 ? short(m.total) : '—'}</td>)}
                  <td className={lg.num}>{inr(sum.subscriptions)}</td>
                  <td className={lg.num}>{inr(sum.commission)}</td>
                  <td className={lg.num}><b>{inr(sum.total)}</b></td>
                </tr>
              </tfoot>
            </table>
          </div>
        </>
      )}

      {/* MONEY ON ITS WAY */}
      <div className={lg.onWay}>
        <div className={lg.onWayCard}>
          <div className={lg.onWayHead}>
            <span className={lg.onWayIcon} style={{ color: palette.c2 }}><Icon name="percent" size={16} /></span>
            <div>
              <b>Commission waiting to be settled</b>
              <span>{inr(pendingTotal)} across {data?.pending_by_salon.length ?? 0} salon{data?.pending_by_salon.length === 1 ? '' : 's'}</span>
            </div>
            <Link href="/superadmin/payouts" className={lg.onWayLink}>Payouts <Icon name="arrowRight" size={13} /></Link>
          </div>
          {data && data.pending_by_salon.length > 0 ? (
            <ul className={lg.onWayList}>
              {data.pending_by_salon.slice(0, 8).map((p) => (
                <li key={p.id}>
                  <span className={lg.salonCell}>
                    <Link href={`/superadmin/salons/${p.id}`}>{p.name}</Link>
                    <small>{p.city} · {p.payouts} payout{p.payouts === 1 ? '' : 's'}{p.oldest_cycle ? ` · since ${day(p.oldest_cycle)}` : ''}</small>
                  </span>
                  <b>{inr(p.amount)}</b>
                </li>
              ))}
            </ul>
          ) : (
            <p className={lg.onWayEmpty}>No open commission. Every calculated cycle has been settled.</p>
          )}
        </div>

        <div className={lg.onWayCard}>
          <div className={lg.onWayHead}>
            <span className={lg.onWayIcon} style={{ color: palette.c1 }}><Icon name="repeat" size={16} /></span>
            <div>
              <b>Plan renewals due in 30 days</b>
              <span>{inr(data?.upcoming_renewals.amount)} if all {data?.upcoming_renewals.count ?? 0} renew</span>
            </div>
            <Link href="/superadmin/subscriptions" className={lg.onWayLink}>Plans <Icon name="arrowRight" size={13} /></Link>
          </div>
          {data && data.upcoming_renewals.items.length > 0 ? (
            <ul className={lg.onWayList}>
              {data.upcoming_renewals.items.map((r) => {
                const d = daysUntil(r.end_date);
                return (
                  <li key={`${r.id}-${r.end_date}`}>
                    <span className={lg.salonCell}>
                      <Link href={`/superadmin/salons/${r.id}`}>{r.name}</Link>
                      <small>
                        {r.plan} · ends {day(r.end_date)}{' '}
                        <span className={d <= 7 ? lg.soon : ''}>({d === 0 ? 'today' : `${d} day${d === 1 ? '' : 's'}`})</span>
                        {r.auto_renew && <> · auto-renew</>}
                      </small>
                    </span>
                    <b>{inr(r.price)}</b>
                  </li>
                );
              })}
            </ul>
          ) : (
            <p className={lg.onWayEmpty}>No plan ends in the next 30 days.</p>
          )}
        </div>
      </div>
    </section>
  );
}
