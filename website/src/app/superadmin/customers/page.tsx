'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip as RechartsTooltip, ResponsiveContainer,
  PieChart, Pie, Cell, BarChart, Bar } from 'recharts';
import styles from './page.module.css';

/**
 * Customers — the owner's complete view of the customer base.
 *
 * Read-only intelligence pulled from /api/proxy/superadmin/customers:
 * headline KPIs (registrations, actives, conversion, retention, value), the
 * signup growth curve, city split, a value leaderboard and a searchable
 * directory. Clicking a row opens a drawer with that customer's profile,
 * appointment history and reviews. Everything can be exported to CSV.
 */

const money = (v: any) => {
  const n = Number(v || 0);
  return '₹' + n.toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
};

const int = (v: any) => Number(v || 0).toLocaleString('en-IN');

const initials = (name: string) =>
  (name || '?').split(' ').map((w) => w.charAt(0)).slice(0, 2).join('').toUpperCase();

const fmtDate = (d: any) => {
  if (!d) return '—';
  const date = new Date(d);
  if (isNaN(date.getTime())) return '—';
  return date.toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' });
};

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

const GRANULARITIES = [
  { key: 'day', label: 'Daily' },
  { key: 'week', label: 'Weekly' },
  { key: 'month', label: 'Monthly' },
] as const;

export default function CustomersPage() {
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [data, setData] = useState<any>(null);

  const [search, setSearch] = useState('');
  const [debouncedSearch, setDebouncedSearch] = useState('');
  const [page, setPage] = useState(1);
  const [granularity, setGranularity] = useState('day');
  const [sortBy, setSortBy] = useState('joined_at');
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('desc');

  const [detail, setDetail] = useState<any>(null);
  const [detailLoading, setDetailLoading] = useState(false);

  useEffect(() => {
    const t = setTimeout(() => {
      setDebouncedSearch(search);
      setPage(1);
    }, 350);
    return () => clearTimeout(t);
  }, [search]);

  const load = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const q = new URLSearchParams();
      q.append('page', String(page));
      q.append('per_page', '10');
      if (granularity) q.append('granularity', granularity);
      if (debouncedSearch) q.append('search', debouncedSearch);
      if (sortBy) q.append('sort_by', sortBy);
      if (sortDir) q.append('sort_dir', sortDir);
      const res = await fetch(`/api/proxy/superadmin/customers?${q}`);
      if (!res.ok) throw new Error('Could not load customers.');
      setData(await res.json());
    } catch (e: any) {
      setError(e.message || 'Could not load customers.');
    } finally {
      setLoading(false);
    }
  }, [page, debouncedSearch, granularity, sortBy, sortDir]);

  useEffect(() => {
    load();
  }, [load]);

  const handleSort = (col: string) => {
    setPage(1);
    if (sortBy === col) {
      setSortDir(sortDir === 'asc' ? 'desc' : 'asc');
    } else {
      setSortBy(col);
      setSortDir('desc');
    }
  };

  const openDetail = async (id: string) => {
    setDetailLoading(true);
    setDetail(null);
    try {
      const res = await fetch(`/api/proxy/superadmin/customers/${id}`);
      if (!res.ok) throw new Error('Could not load customer.');
      setDetail(await res.json());
    } catch (e: any) {
      setDetail({ error: e.message || 'Could not load customer.' });
    } finally {
      setDetailLoading(false);
    }
  };

  const exportDirectory = () => {
    const dir = data?.directory?.data ?? [];
    downloadCSV(
      'customers.csv',
      ['Name', 'Phone', 'Email', 'City', 'Gender', 'Joined', 'Last seen', 'Status', 'Bookings', 'Completed', 'Cancelled', 'No-show', 'Spend'],
      dir.map((c: any) => [
        c.name, c.phone, c.email ?? '', c.city ?? '', c.gender, c.joined_at, c.last_seen ?? '',
        c.is_active ? 'Active' : 'Inactive', c.bookings, c.completed, c.cancelled, c.no_show, money(c.spend),
      ])
    );
  };

  const growthData = useMemo(() => {
    return (data?.summary?.growth ?? []).slice();
  }, [data]);

  const s = data?.summary ?? {};
  const dir = data?.directory ?? {};
  const rows = dir.data ?? [];
  const conversion = s.total > 0 ? Math.round(((s.booked ?? 0) / s.total) * 100) : 0;
  const retention = s.booked > 0 ? Math.round(((s.retained ?? 0) / s.booked) * 100) : 0;

  const activeShare = s.total > 0
    ? [
        { name: 'Active', value: s.active ?? 0 },
        { name: 'Inactive', value: (s.total ?? 0) - (s.active ?? 0) },
      ]
    : [];

  const cities = (s.cities ?? []).slice(0, 8);
  const noShowLeaders = s.top_no_shows ?? [];

  return (
    <div className={styles.container}>
      {/* ---- header banner ---- */}
      <div className={styles.header}>
        <div className={styles.headerLeft}>
          <div className={styles.titleRow}>
            <h1 className={styles.title}>Customers</h1>
            <span className={styles.badge}><span className={styles.badgeDot} /> Read-only</span>
          </div>
          <p className={styles.subtitle}>
            A complete, cross-platform view of your customer base — registrations, activity, retention and value.
          </p>
          {data?.generated_at && (
            <p className={styles.generatedAt}>
              Generated {new Date(data.generated_at).toLocaleString('en-IN', {
                day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit',
              })}
            </p>
          )}
        </div>
      </div>

      <div className={styles.content}>
        {/* ---- skeleton ---- */}
        {loading && !data && (
          <>
            <div className={styles.skeletonGrid}>
              {[1, 2, 3, 4].map((i) => <div key={i} className={`${styles.skeletonKpi} ${styles.skeleton}`} />)}
            </div>
            <div className={`${styles.skeletonCard} ${styles.skeleton}`} />
            <div className={`${styles.skeletonCard} ${styles.skeleton}`} />
            <p className={styles.loadingLabel}>Gathering customer intelligence…</p>
          </>
        )}

        {/* ---- error ---- */}
        {!loading && error && (
          <div className={styles.errorCard}>
            <p className={styles.errorTitle}>Unable to load customers</p>
            <p className={styles.errorMessage}>{error}</p>
            <button className={styles.retryButton} onClick={load}>Try again</button>
          </div>
        )}

        {data && (
          <>
            {/* ---- KPI cards ---- */}
            <div className={styles.kpiGrid}>
              <KPI label="Registered customers" value={int(s.total)} sub={`${int(s.new_today)} today · ${int(s.new_this_month)} this month`} dotColor="#7c3aed" accent />
              <KPI label="Booked at least once" value={int(s.booked)} sub={`${conversion}% of all customers`} dotColor="#6366f1" />
              <KPI label="Repeat customers" value={int(s.retained)} sub={`${retention}% retention of bookers`} dotColor="#10b981" />
              <KPI label="Average value" value={money(s.avg_spend)} sub={`${s.avg_bookings} bookings per customer`} dotColor="#ec4899" />
            </div>

            {/* ---- two-column: growth + activity ---- */}
            <div className={styles.splitRow}>
              <div className={`${styles.card} ${styles.cardAccent} ${styles.growCard}`}>
                <div className={styles.cardHeader}>
                  <div>
                    <h2 className={styles.cardTitle}>Customer growth</h2>
                    <p className={styles.cardDesc}>New registrations over the last 30 days.</p>
                  </div>
                  <div className={styles.seg}>
                    {GRANULARITIES.map((g) => (
                      <button
                        key={g.key}
                        className={`${styles.segBtn} ${granularity === g.key ? styles.segActive : ''}`}
                        onClick={() => setGranularity(g.key)}
                      >
                        {g.label}
                      </button>
                    ))}
                  </div>
                </div>
                <div className={styles.chartBox}>
                  <ResponsiveContainer width="100%" height="100%">
                    <AreaChart data={growthData} margin={{ top: 6, right: 8, left: -18, bottom: 0 }}>
                      <defs>
                        <linearGradient id="growthFill" x1="0" y1="0" x2="0" y2="1">
                          <stop offset="0%" stopColor="#7c3aed" stopOpacity={0.28} />
                          <stop offset="100%" stopColor="#7c3aed" stopOpacity={0.02} />
                        </linearGradient>
                      </defs>
                      <CartesianGrid strokeDasharray="3 3" stroke="#f0eef6" vertical={false} />
                      <XAxis dataKey="label" tick={{ fontSize: 10, fill: '#9ca3af' }} tickLine={false} axisLine={false} interval="preserveStartEnd" minTickGap={28} />
                      <YAxis allowDecimals={false} tick={{ fontSize: 10, fill: '#9ca3af' }} tickLine={false} axisLine={false} />
                      <RechartsTooltip contentStyle={{ borderRadius: 10, border: '1px solid #e5e7eb', fontSize: 12 }} />
                      <Area type="monotone" dataKey="customers" name="New customers" stroke="#7c3aed" strokeWidth={2.4} fill="url(#growthFill)" />
                    </AreaChart>
                  </ResponsiveContainer>
                </div>
              </div>

              <div className={`${styles.card} ${styles.cardAccent} ${styles.donutCard}`}>
                <div className={styles.cardHeader}>
                  <div>
                    <h2 className={styles.cardTitle}>Account status</h2>
                    <p className={styles.cardDesc}>Active vs inactive customer accounts.</p>
                  </div>
                </div>
                <div className={styles.donutWrap}>
                  <ResponsiveContainer width="100%" height={210}>
                    <PieChart>
                      <Pie data={activeShare} dataKey="value" nameKey="name" cx="50%" cy="50%" innerRadius={58} outerRadius={82} paddingAngle={3} strokeWidth={0}>
                        <Cell fill="#7c3aed" />
                        <Cell fill="#e3e0ee" />
                      </Pie>
                      <RechartsTooltip contentStyle={{ borderRadius: 10, border: '1px solid #e5e7eb', fontSize: 12 }} />
                    </PieChart>
                  </ResponsiveContainer>
                  <div className={styles.donutCenter}>
                    <div className={styles.donutValue}>{int(s.active)}</div>
                    <div className={styles.donutLabel}>ACTIVE</div>
                  </div>
                </div>
                <div className={styles.chipRow}>
                  <Chip color="#7c3aed" label="Active" value={int(s.active)} />
                  <Chip color="#9ca3af" label="Inactive" value={int((s.total ?? 0) - (s.active ?? 0))} />
                </div>
              </div>
            </div>

            {/* ---- cities ---- */}
            <div className={`${styles.card} ${styles.cardAccent}`}>
              <div className={styles.cardHeader}>
                <div>
                  <h2 className={styles.cardTitle}>Where customers are</h2>
                  <p className={styles.cardDesc}>Customer distribution across cities.</p>
                </div>
              </div>
              <div className={styles.chartBox}>
                {cities.length === 0 ? (
                  <p className={styles.muted}>No customers with a city assigned yet.</p>
                ) : (
                  <ResponsiveContainer width="100%" height={190 + cities.length * 8}>
                    <BarChart data={cities} layout="vertical" margin={{ top: 4, right: 18, left: 0, bottom: 0 }}>
                      <CartesianGrid strokeDasharray="3 3" stroke="#f0eef6" horizontal={false} />
                      <XAxis type="number" allowDecimals={false} tick={{ fontSize: 10, fill: '#9ca3af' }} tickLine={false} axisLine={false} />
                      <YAxis type="category" dataKey="city" width={104} tick={{ fontSize: 11, fill: '#4b5563' }} tickLine={false} axisLine={false} />
                      <RechartsTooltip contentStyle={{ borderRadius: 10, border: '1px solid #e5e7eb', fontSize: 12 }}
                        formatter={(value: any) => [`${value} customer${value === 1 ? '' : 's'}`, 'Customers']} />
                      <Bar dataKey="customers" name="Customers" fill="#8b5cf6" radius={[0, 6, 6, 0]} barSize={18} />
                    </BarChart>
                  </ResponsiveContainer>
                )}
              </div>
            </div>

            {/* ---- leaderboards: value + no-show risk ---- */}
            <div className={styles.leaderGrid}>
              <div className={`${styles.card} ${styles.cardAccent} ${styles.leaderCard}`}>
                <div className={styles.cardHeader}>
                  <div>
                    <h2 className={styles.cardTitle}>Most valuable customers</h2>
                    <p className={styles.cardDesc}>Top customers by total spend on completed appointments.</p>
                  </div>
                </div>
                {(s.top_customers ?? []).length === 0 ? (
                  <p className={styles.muted}>No completed bookings yet.</p>
                ) : (
                  <div className={styles.miniList}>
                    {(s.top_customers ?? []).map((c: any, idx: number) => (
                      <div className={styles.vipRow} key={c.id} onClick={() => openDetail(c.id)}>
                        <span className={`${styles.rankBadge} ${idx === 0 ? styles.rank1 : idx === 1 ? styles.rank2 : idx === 2 ? styles.rank3 : styles.rankN}`}>{idx + 1}</span>
                        <div className={`${styles.vipAvatar} ${styles.vipAvatarBrand}`}>{initials(c.name)}</div>
                        <div className={styles.vipInfo}>
                          <div className={styles.vipName}>{c.name}</div>
                          <div className={styles.vipMeta}>{c.phone ?? '—'}</div>
                        </div>
                        <div className={styles.vipStats}>
                          <div className={styles.vipStat}><span className={styles.vipStatLabel}>Bookings</span><b>{int(c.bookings)}</b></div>
                          <div className={styles.vipStat}><span className={styles.vipStatLabel}>Spend</span><b className={styles.vipSpend}>{money(c.spend)}</b></div>
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </div>

              <div className={`${styles.card} ${styles.cardAccentWarn} ${styles.leaderCard}`}>
                <div className={styles.cardHeader}>
                  <div>
                    <h2 className={styles.cardTitle}>Most no-shows</h2>
                    <p className={styles.cardDesc}>Who keeps missing bookings, ranked by no-show count.</p>
                  </div>
                </div>
                {noShowLeaders.length === 0 ? (
                  <p className={styles.muted}>No no-shows recorded yet — your record is clean.</p>
                ) : (
                  <div className={styles.miniList}>
                    {noShowLeaders.map((c: any, idx: number) => {
                      const rate = c.bookings > 0 ? Math.round((c.no_shows / c.bookings) * 100) : 100;
                      return (
                        <div className={styles.vipRow} key={c.id} onClick={() => openDetail(c.id)}>
                          <span className={`${styles.rankBadge} ${idx === 0 ? styles.rank1 : idx === 1 ? styles.rank2 : idx === 2 ? styles.rank3 : styles.rankN}`}>{idx + 1}</span>
                          <div className={`${styles.vipAvatar} ${styles.vipAvatarBrand}`}>{initials(c.name)}</div>
                          <div className={styles.vipInfo}>
                            <div className={styles.vipName}>{c.name}</div>
                            <div className={styles.vipMeta}>{c.phone ?? '—'}</div>
                          </div>
                          <div className={styles.vipStats}>
                            <div className={styles.vipStat}><span className={styles.vipStatLabel}>No-shows</span><b className={styles.noShowNum}>{int(c.no_shows)}</b></div>
                            <div className={styles.vipStat}><span className={styles.vipStatLabel}>Rate</span><b>{rate}%</b></div>
                          </div>
                        </div>
                      );
                    })}
                  </div>
                )}
              </div>
            </div>

            {/* ---- directory ---- */}
            <div className={`${styles.card} ${styles.cardAccent}`}>
              <div className={styles.cardHeader}>
                <div>
                  <h2 className={styles.cardTitle}>Customer directory</h2>
                  <p className={styles.cardDesc}>
                    {int(dir.total)} customer{dir.total === 1 ? '' : 's'} registered · search by name, phone or email.
                  </p>
                </div>
                <div className={styles.dirActions}>
                  <div className={styles.searchBox}>
                    <span className={styles.searchIcon}>⌕</span>
                    <input
                      type="text"
                      value={search}
                      placeholder="Search customers…"
                      onChange={(e) => setSearch(e.target.value)}
                      className={styles.searchInput}
                    />
                  </div>
                  <button className={styles.smallButton} onClick={exportDirectory}>↓ CSV</button>
                </div>
              </div>

              {rows.length === 0 ? (
                <p className={styles.muted}>No customers match your search.</p>
              ) : (
                <>
                  <div className={styles.tableScroll}>
                    <table className={styles.table}>
                      <thead>
                        <tr>
                          <SortHeader label="Customer" sortKey="name" sortBy={sortBy} sortDir={sortDir} onSort={handleSort} />
                          <SortHeader label="Location" sortKey="city" sortBy={sortBy} sortDir={sortDir} onSort={handleSort} />
                          <SortHeader label="Joined" sortKey="joined_at" sortBy={sortBy} sortDir={sortDir} onSort={handleSort} />
                          <SortHeader label="Bookings" sortKey="bookings" sortBy={sortBy} sortDir={sortDir} onSort={handleSort} />
                          <SortHeader label="Completed" sortKey="completed" sortBy={sortBy} sortDir={sortDir} onSort={handleSort} />
                          <SortHeader label="Cancelled" sortKey="cancelled" sortBy={sortBy} sortDir={sortDir} onSort={handleSort} />
                          <SortHeader label="No-show" sortKey="no_show" sortBy={sortBy} sortDir={sortDir} onSort={handleSort} />
                          <SortHeader label="Spend" sortKey="spend" sortBy={sortBy} sortDir={sortDir} onSort={handleSort} align="right" />
                          <SortHeader label="Status" sortKey="status" sortBy={sortBy} sortDir={sortDir} onSort={handleSort} />
                        </tr>
                      </thead>
                      <tbody>
                        {rows.map((c: any) => (
                          <tr key={c.id} className={styles.clickableRow} onClick={() => openDetail(c.id)}>
                            <td>
                              <div className={styles.custCell}>
                                <div className={styles.custAvatar}>{initials(c.name)}</div>
                                <div>
                                  <div className={styles.custName}>{c.name}</div>
                                  <div className={styles.custMeta}>{c.phone}{c.email ? ` · ${c.email}` : ''}</div>
                                </div>
                              </div>
                            </td>
                            <td>{c.city ?? '—'}{c.sub_area ? `, ${c.sub_area}` : ''}</td>
                            <td>{fmtDate(c.joined_at)}</td>
                            <td>{int(c.bookings)}</td>
                            <td>{int(c.completed)}</td>
                            <td>{int(c.cancelled)}</td>
                            <td>{c.no_show > 0 ? <b className={styles.noShowBadge}>{int(c.no_show)}</b> : <span className={styles.mutedCell}>0</span>}</td>
                            <td className={styles.textRightBold}>{money(c.spend)}</td>
                            <td><StatusPill active={c.is_active} /></td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>

                  {/* ---- pagination ---- */}
                  {dir.last_page > 1 && (
                    <div className={styles.pagination}>
                      <button className={styles.pageBtn} disabled={page <= 1} onClick={() => setPage(page - 1)}>← Prev</button>
                      <span className={styles.pageInfo}>
                        Page {int(dir.current_page)} of {int(dir.last_page)}
                        {debouncedSearch ? '' : ` · ${int(dir.total)} customers`}
                      </span>
                      <button className={styles.pageBtn} disabled={page >= dir.last_page} onClick={() => setPage(page + 1)}>Next →</button>
                    </div>
                  )}
                </>
              )}
            </div>
          </>
        )}
      </div>

      {/* ---- detail drawer ---- */}
      {(detail || detailLoading) && (
        <div className={styles.drawerBackdrop} onClick={() => setDetail(null)}>
          <div className={styles.drawer} onClick={(e) => e.stopPropagation()}>
            <button className={styles.drawerClose} onClick={() => setDetail(null)}>✕</button>
            {detailLoading ? (
              <div>
                <div className={`${styles.skeletonCard} ${styles.skeleton}`} style={{ height: 120 }} />
                <div className={`${styles.skeletonCard} ${styles.skeleton}`} style={{ height: 220, marginTop: 14 }} />
              </div>
            ) : detail?.error ? (
              <div className={styles.errorCard}>
                <p className={styles.errorTitle}>Could not load customer</p>
                <p className={styles.errorMessage}>{detail.error}</p>
              </div>
            ) : detail?.customer ? (
              <DetailPanel detail={detail} onExport={() => exportCustomer(detail)} />
            ) : null}
          </div>
        </div>
      )}
    </div>
  );
}

function exportCustomer(detail: any) {
  const c = detail.customer;
  downloadCSV(
    `customer-${c.name.replace(/\s+/g, '-').toLowerCase()}.csv`,
    ['Appointment', 'Salon', 'Status', 'Bookings', 'Date', 'Start', 'Source', 'Billed'],
    (detail.appointments ?? []).map((a: any) => [
      a.id, a.salon ?? '—', a.status, a.booking_source, a.date, a.start, a.source, money(a.billed),
    ])
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

function Chip({ color, label, value }: { color: string; label: string; value: string }) {
  return (
    <div className={styles.chip}>
      <span className={styles.chipDot} style={{ background: color }} />
      <span className={styles.chipLabel}>{label}</span>
      <b>{value}</b>
    </div>
  );
}

function SortHeader({ label, sortKey, sortBy, sortDir, onSort, align }: {
  label: string;
  sortKey: string;
  sortBy: string;
  sortDir: string;
  onSort: (key: string) => void;
  align?: 'left' | 'right';
}) {
  const active = sortKey === sortBy;
  return (
    <th style={align === 'right' ? { textAlign: 'right' } : undefined}>
      <button
        type="button"
        className={`${styles.sortHeader} ${active ? styles.sortHeaderActive : ''}`}
        onClick={() => onSort(sortKey)}
        aria-sort={active ? (sortDir === 'asc' ? 'ascending' : 'descending') : 'none'}
      >
        <span>{label}</span>
        <span className={`${styles.sortIcon} ${active ? styles.sortIconShown : ''}`}>
          {active ? (sortDir === 'asc' ? '↑' : '↓') : '↕'}
        </span>
      </button>
    </th>
  );
}

function StatusPill({ active }: { active: boolean }) {
  return (
    <span className={`${styles.statusPill} ${active ? styles.sActive : styles.sInactive}`}>
      {active ? 'Active' : 'Inactive'}
    </span>
  );
}

function DetailPanel({ detail, onExport }: { detail: any; onExport: () => void }) {
  const c = detail.customer;
  const [appSort, setAppSort] = useState<{ key: string; dir: 'asc' | 'desc' }>({ key: 'date', dir: 'desc' });

  const appointments = useMemo(() => {
    const rows = [...(detail.appointments ?? [])];
    const dir = appSort.dir === 'asc' ? 1 : -1;
    rows.sort((x: any, y: any) => {
      const va = x[appSort.key];
      const vb = y[appSort.key];
      if (va == null && vb == null) return 0;
      if (va == null) return 1;
      if (vb == null) return -1;
      const cmp = typeof va === 'number' ? va - vb : String(va).localeCompare(String(vb));
      return cmp * dir;
    });
    return rows;
  }, [detail, appSort]);

  const toggleSort = (key: string) => {
    setAppSort((p) => ({
      key,
      dir: key === p.key && p.dir === 'asc' ? 'desc' : 'asc',
    }));
  };

  return (
    <div>
      <div className={styles.detailHead}>
        <div className={styles.detailAvatar}>{initials(c.name)}</div>
        <div>
          <h2 className={styles.detailTitle}>{c.name}</h2>
          <p className={styles.detailMeta}>{c.phone}{c.email ? ` · ${c.email}` : ''}</p>
          <p className={styles.detailMeta}>
            {c.city ?? 'No city'} · Joined {fmtDate(c.joined_at)}
            {c.last_seen ? ` · Last seen ${fmtDate(c.last_seen)}` : ''}
          </p>
        </div>
      </div>

      <div className={styles.detailStats}>
        <div className={styles.detailStat}><span>Total bookings</span><b>{int(c.bookings)}</b></div>
        <div className={styles.detailStat}><span>Completed</span><b>{int(c.completed)}</b></div>
        <div className={styles.detailStat}><span>Cancelled</span><b>{int(c.cancelled)}</b></div>
        <div className={styles.detailStat}><span>No-show</span><b>{int(c.no_show)}</b></div>
        <div className={`${styles.detailStat} ${styles.detailStatAccent}`}><span>Lifetime value</span><b>{money(c.spend)}</b></div>
      </div>

      <h3 className={styles.detailSectionTitle}>Recent appointments</h3>
      {appointments.length === 0 ? (
        <p className={styles.muted}>No appointments recorded.</p>
      ) : (
        <div className={styles.tableScroll}>
          <table className={styles.table}>
            <thead>
              <tr>
                <SortHeader label="Salon" sortKey="salon" sortBy={appSort.key} sortDir={appSort.dir} onSort={toggleSort} />
                <SortHeader label="Date" sortKey="date" sortBy={appSort.key} sortDir={appSort.dir} onSort={toggleSort} />
                <SortHeader label="Start" sortKey="start" sortBy={appSort.key} sortDir={appSort.dir} onSort={toggleSort} />
                <SortHeader label="Billed" sortKey="billed" sortBy={appSort.key} sortDir={appSort.dir} onSort={toggleSort} align="right" />
                <SortHeader label="Status" sortKey="status" sortBy={appSort.key} sortDir={appSort.dir} onSort={toggleSort} />
              </tr>
            </thead>
            <tbody>
              {appointments.map((a: any) => (
                <tr key={a.id}>
                  <td><strong>{a.salon ?? '—'}</strong></td>
                  <td>{a.date}</td>
                  <td>{a.start ?? '—'}</td>
                  <td className={styles.textRightBold}>{money(a.billed)}</td>
                  <td><APill status={a.status} /></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <div className={styles.detailActions}>
        <h3 className={styles.detailSectionTitle}>Reviews</h3>
        <button className={styles.smallButton} onClick={onExport}>↓ CSV</button>
      </div>
      {(detail.reviews ?? []).length === 0 ? (
        <p className={styles.muted}>No reviews written by this customer yet.</p>
      ) : (
        <div className={styles.reviewList}>
          {(detail.reviews ?? []).map((r: any) => (
            <div className={styles.reviewItem} key={r.id}>
              <span className={styles.stars}>{'★'.repeat(r.rating)}<span className={styles.starsDim}>{'★'.repeat(5 - r.rating)}</span></span>
              <span className={styles.reviewText}>{r.comment || 'No comment.'}</span>
              <span className={styles.reviewMeta}>{r.salon ?? '—'} · {fmtDate(r.created_at)}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

const appTone: Record<string, string> = {
  completed: styles.aCompleted,
  cancelled: styles.aCancelled,
  no_show: styles.aNoShow,
  scheduled: styles.aScheduled,
  in_progress: styles.aActive,
  pending_payment: styles.aPending,
  rescheduled: styles.aScheduled,
  awaiting_reschedule: styles.aScheduled,
};

function APill({ status }: { status: string }) {
  return (
    <span className={`${styles.statusPill} ${appTone[status] ?? styles.aDefault}`}>
      {(status ?? 'unknown').replace(/_/g, ' ')}
    </span>
  );
}