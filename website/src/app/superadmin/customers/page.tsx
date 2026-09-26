'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip as RechartsTooltip, ResponsiveContainer,
  PieChart, Pie, Cell,
} from 'recharts';
import Icon from '@/components/admin/Icon';
import {
  Alert, Avatar, Badge, Button, Card, Drawer, EmptyState, PageHeader, Pagination, Person,
  SearchInput, Segmented, Skeleton, SortHeader, StatCard, Tabs, clickableRow, cx, downloadCSV,
  formatINR, ui, useDebounced, type Tone,
} from '@/components/admin/ui';
import { useChartPalette } from '@/lib/theme';
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

/* eslint-disable @typescript-eslint/no-explicit-any -- the customers API is untyped JSON */

const money = (v: any) => formatINR(Number(v || 0), 2);
const moneyShort = (v: any) => formatINR(Number(v || 0));

const int = (v: any) => Number(v || 0).toLocaleString('en-IN');

const fmtDate = (d: any) => {
  if (!d) return '—';
  const date = new Date(d);
  if (isNaN(date.getTime())) return '—';
  return date.toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' });
};

const GRANULARITIES = [
  { value: 'day', label: 'Daily' },
  { value: 'week', label: 'Weekly' },
  { value: 'month', label: 'Monthly' },
];

const GROWTH_COPY: Record<string, string> = {
  day: 'New registrations per day',
  week: 'New registrations per week',
  month: 'New registrations per month',
};

export default function CustomersPage() {
  const [error, setError] = useState('');
  const [data, setData] = useState<any>(null);

  const [search, setSearch] = useState('');
  const debouncedSearch = useDebounced(search);
  const [page, setPage] = useState(1);
  const [granularity, setGranularity] = useState('day');
  const [sortBy, setSortBy] = useState('joined_at');
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('desc');

  const [detail, setDetail] = useState<any>(null);
  const [detailOpen, setDetailOpen] = useState(false);
  const [detailLoading, setDetailLoading] = useState(false);

  const palette = useChartPalette();

  // Loading is derived: true until a response for the current query lands.
  const queryKey = [page, debouncedSearch, granularity, sortBy, sortDir].join('|');
  const [loadedKey, setLoadedKey] = useState<string | null>(null);
  const loading = loadedKey !== queryKey;

  const load = useCallback(async () => {
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
      setError('');
    } catch (e: any) {
      setError(e.message || 'Could not load customers.');
    } finally {
      setLoadedKey(queryKey);
    }
  }, [page, debouncedSearch, granularity, sortBy, sortDir, queryKey]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- state is only set after the network responds
    load();
  }, [load]);

  const handleSearch = (v: string) => {
    setSearch(v);
    setPage(1);
  };

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
    setDetailOpen(true);
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
    const rows = data?.directory?.data ?? [];
    downloadCSV(
      `customers-page-${page}.csv`,
      ['Name', 'Phone', 'Email', 'City', 'Area', 'Gender', 'Joined', 'Last seen', 'Status', 'Bookings', 'Completed', 'Cancelled', 'No-show', 'Spend'],
      rows.map((c: any) => [
        c.name, c.phone, c.email ?? '', c.city ?? '', c.sub_area ?? '', c.gender, c.joined_at, c.last_seen ?? '',
        c.is_active ? 'Active' : 'Inactive', c.bookings, c.completed, c.cancelled, c.no_show, money(c.spend),
      ]),
    );
  };

  const growthData = useMemo(() => (data?.summary?.growth ?? []).slice(), [data]);

  const s = data?.summary ?? {};
  const dir = data?.directory ?? {};
  const rows = dir.data ?? [];
  const conversion = s.total > 0 ? Math.round(((s.booked ?? 0) / s.total) * 100) : 0;
  const retention = s.booked > 0 ? Math.round(((s.retained ?? 0) / s.booked) * 100) : 0;
  const inactive = Math.max(0, (s.total ?? 0) - (s.active ?? 0));
  const activePct = s.total > 0 ? Math.round(((s.active ?? 0) / s.total) * 100) : 0;
  const growthTotal = growthData.reduce((n: number, g: any) => n + (Number(g.customers) || 0), 0);

  const cities = (s.cities ?? []).slice(0, 8);
  const maxCity = Math.max(1, ...cities.map((c: any) => Number(c.customers) || 0));
  const noShowLeaders = s.top_no_shows ?? [];
  const firstLoad = loading && !data;

  return (
    <div className={styles.container}>
      <PageHeader
        eyebrow={<>Customers <Badge tone="neutral">Read-only</Badge></>}
        title="Customer intelligence"
        subtitle="Registrations, activity, retention and value across the whole platform."
        actions={
          data?.generated_at && (
            <span className={styles.generated}>
              <Icon name="clock" size={14} />
              Updated {new Date(data.generated_at).toLocaleString('en-IN', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })}
            </span>
          )
        }
      />

      {!loading && error && !data && (
        <Card padded>
          <EmptyState
            icon="alert"
            title="Unable to load customers"
            hint={error}
            action={<Button variant="primary" icon="refresh" onClick={() => { setLoadedKey(null); load(); }}>Try again</Button>}
          />
        </Card>
      )}

      {(data || firstLoad) && (
        <>
          {/* ---- KPIs ---- */}
          <div className={ui.statGrid}>
            <StatCard
              label="Registered customers"
              icon="users"
              tone="accent"
              loading={firstLoad}
              value={int(s.total)}
              sub={`+${int(s.new_today)} today · +${int(s.new_this_month)} this month`}
            />
            <StatCard
              label="Booked at least once"
              icon="calendar"
              tone="info"
              loading={firstLoad}
              value={int(s.booked)}
              sub={`${conversion}% conversion from sign-up`}
            />
            <StatCard
              label="Repeat customers"
              icon="repeat"
              tone="success"
              loading={firstLoad}
              value={int(s.retained)}
              sub={`${retention}% of bookers came back`}
            />
            <StatCard
              label="Average lifetime value"
              icon="rupee"
              tone="warning"
              loading={firstLoad}
              value={money(s.avg_spend)}
              sub={`${s.avg_bookings ?? 0} bookings per customer`}
            />
          </div>

          {/* ---- growth + account status ---- */}
          <div className={styles.splitRow}>
            <Card
              title="Customer growth"
              subtitle={`${GROWTH_COPY[granularity]} · ${int(growthTotal)} in view`}
              actions={
                <Segmented ariaLabel="Granularity" value={granularity} onChange={(g) => { setGranularity(g); setPage(1); }} options={GRANULARITIES} />
              }
              padded
            >
              <div className={styles.chartBox}>
                {firstLoad ? (
                  <Skeleton height="100%" radius={12} />
                ) : growthData.length === 0 ? (
                  <EmptyState icon="chart" title="No sign-ups in this period" />
                ) : (
                  <ResponsiveContainer width="100%" height="100%">
                    <AreaChart data={growthData} margin={{ top: 8, right: 6, left: -18, bottom: 0 }}>
                      <defs>
                        <linearGradient id="growthFill" x1="0" y1="0" x2="0" y2="1">
                          <stop offset="0%" stopColor={palette.c1} stopOpacity={0.3} />
                          <stop offset="100%" stopColor={palette.c1} stopOpacity={0} />
                        </linearGradient>
                      </defs>
                      <CartesianGrid strokeDasharray="4 4" stroke={palette.grid} vertical={false} />
                      <XAxis dataKey="label" tick={{ fontSize: 11, fill: palette.axis }} tickLine={false} axisLine={false} interval="preserveStartEnd" minTickGap={28} dy={6} />
                      <YAxis allowDecimals={false} tick={{ fontSize: 11, fill: palette.axis }} tickLine={false} axisLine={false} />
                      <RechartsTooltip cursor={{ stroke: palette.grid }} />
                      <Area
                        type="monotone"
                        dataKey="customers"
                        name="New customers"
                        stroke={palette.c1}
                        strokeWidth={2.4}
                        fill="url(#growthFill)"
                        activeDot={{ r: 5, strokeWidth: 2, stroke: 'var(--surface-color)' }}
                        isAnimationActive={false}
                      />
                    </AreaChart>
                  </ResponsiveContainer>
                )}
              </div>
            </Card>

            <Card title="Account status" subtitle="Active vs deactivated accounts" padded>
              {firstLoad ? (
                <Skeleton width={180} height={180} radius={999} />
              ) : (
                <>
                  <div className={styles.donutWrap}>
                    <ResponsiveContainer width="100%" height="100%">
                      <PieChart>
                        <Pie
                          data={[{ name: 'Active', value: s.active ?? 0 }, { name: 'Inactive', value: inactive }]}
                          dataKey="value"
                          nameKey="name"
                          cx="50%"
                          cy="50%"
                          innerRadius="70%"
                          outerRadius="94%"
                          paddingAngle={2}
                          cornerRadius={4}
                          stroke="none"
                          startAngle={90}
                          endAngle={-270}
                        >
                          <Cell fill={palette.c1} />
                          <Cell fill={palette.track} />
                        </Pie>
                        <RechartsTooltip formatter={(v) => [int(v), 'Customers']} />
                      </PieChart>
                    </ResponsiveContainer>
                    <div className={styles.donutCenter}>
                      <div className={styles.donutValue}>{activePct}%</div>
                      <div className={styles.donutLabel}>active</div>
                    </div>
                  </div>
                  <div className={styles.legend}>
                    <div className={styles.legendRow}>
                      <span className={styles.legendDot} style={{ background: palette.c1 }} />
                      Active <b>{int(s.active)}</b>
                    </div>
                    <div className={styles.legendRow}>
                      <span className={styles.legendDot} style={{ background: palette.track, boxShadow: 'inset 0 0 0 1px var(--border-strong)' }} />
                      Inactive <b>{int(inactive)}</b>
                    </div>
                  </div>
                </>
              )}
            </Card>
          </div>

          {/* ---- cities + leaderboards ---- */}
          <div className={styles.triRow}>
            <Card title="Where customers are" subtitle="Top cities by registered customers" padded>
              {firstLoad ? (
                <ListSkeleton />
              ) : cities.length === 0 ? (
                <EmptyState icon="pin" title="No cities yet" hint="Customers appear here once they pick a city." />
              ) : (
                <ol className={styles.meterList}>
                  {cities.map((c: any) => (
                    <li key={c.city} className={styles.meterRow}>
                      <div className={styles.meterTop}>
                        <span className={styles.meterName}>{c.city}</span>
                        <span className={styles.meterValue}>{int(c.customers)}</span>
                      </div>
                      <div className={styles.meter}>
                        <span style={{ width: `${(Number(c.customers) / maxCity) * 100}%` }} />
                      </div>
                    </li>
                  ))}
                </ol>
              )}
            </Card>

            <Card title="Most valuable" subtitle="By spend on completed appointments" padded>
              {firstLoad ? (
                <ListSkeleton />
              ) : (s.top_customers ?? []).length === 0 ? (
                <EmptyState icon="star" title="No completed bookings yet" />
              ) : (
                <ol className={styles.leaderList}>
                  {(s.top_customers ?? []).slice(0, 5).map((c: any, idx: number) => (
                    <li key={c.id}>
                      <button type="button" className={styles.leaderRow} onClick={() => openDetail(c.id)}>
                        <span className={cx(styles.rank, idx < 3 && styles[`rank${idx + 1}`])}>{idx + 1}</span>
                        <Avatar name={c.name} size={34} />
                        <span className={styles.leaderInfo}>
                          <span className={styles.leaderName}>{c.name}</span>
                          <span className={styles.leaderMeta}>{int(c.bookings)} bookings</span>
                        </span>
                        <span className={styles.leaderValue}>{moneyShort(c.spend)}</span>
                      </button>
                    </li>
                  ))}
                </ol>
              )}
            </Card>

            <Card title="No-show watch" subtitle="Customers who keep missing bookings" padded>
              {firstLoad ? (
                <ListSkeleton />
              ) : noShowLeaders.length === 0 ? (
                <EmptyState icon="checkCircle" title="A clean record" hint="No no-shows recorded yet." />
              ) : (
                <ol className={styles.leaderList}>
                  {noShowLeaders.slice(0, 5).map((c: any) => {
                    const rate = c.bookings > 0 ? Math.round((c.no_shows / c.bookings) * 100) : 100;
                    return (
                      <li key={c.id}>
                        <button type="button" className={styles.leaderRow} onClick={() => openDetail(c.id)}>
                          <Avatar name={c.name} size={34} tone="danger" />
                          <span className={styles.leaderInfo}>
                            <span className={styles.leaderName}>{c.name}</span>
                            <span className={styles.leaderMeta}>{int(c.no_shows)} of {int(c.bookings)} bookings missed</span>
                          </span>
                          <Badge tone={rate >= 50 ? 'danger' : 'warning'} dot={false}>{rate}%</Badge>
                        </button>
                      </li>
                    );
                  })}
                </ol>
              )}
            </Card>
          </div>

          {/* ---- directory ---- */}
          <Card>
            <div className={ui.toolbar}>
              <div className={styles.dirTitle}>
                <h2 className={ui.cardTitle}>Directory</h2>
                <p className={ui.cardSubtitle}>
                  {firstLoad ? 'Loading…' : `${int(dir.total)} customer${dir.total === 1 ? '' : 's'}${debouncedSearch ? ` matching “${debouncedSearch}”` : ''}`}
                </p>
              </div>
              <SearchInput
                className={styles.dirSearch}
                value={search}
                onChange={handleSearch}
                placeholder="Search name, phone or email…"
              />
              <Button icon="download" onClick={exportDirectory} disabled={rows.length === 0} title="Exports the customers on this page">
                Export page
              </Button>
            </div>

            {error && data && (
              <div className={styles.inlineAlert}><Alert tone="error">{error}</Alert></div>
            )}

            <div className={cx(ui.tableWrap, loading && data && styles.refreshing)}>
              <table className={ui.table}>
                <thead>
                  <tr>
                    <SortHeader label="Customer" active={sortBy === 'name'} dir={sortDir} onClick={() => handleSort('name')} />
                    <SortHeader label="Location" active={sortBy === 'city'} dir={sortDir} onClick={() => handleSort('city')} />
                    <SortHeader label="Joined" active={sortBy === 'joined_at'} dir={sortDir} onClick={() => handleSort('joined_at')} />
                    <SortHeader label="Bookings" active={sortBy === 'bookings'} dir={sortDir} onClick={() => handleSort('bookings')} />
                    <SortHeader label="No-show" active={sortBy === 'no_show'} dir={sortDir} onClick={() => handleSort('no_show')} />
                    <SortHeader label="Spend" active={sortBy === 'spend'} dir={sortDir} onClick={() => handleSort('spend')} align="right" />
                    <SortHeader label="Status" active={sortBy === 'status'} dir={sortDir} onClick={() => handleSort('status')} />
                  </tr>
                </thead>
                <tbody>
                  {firstLoad ? (
                    Array.from({ length: 6 }, (_, i) => (
                      <tr key={i}>
                        <td><div className={ui.personCell}><Skeleton width={34} height={34} radius={11} /><Skeleton width={140} /></div></td>
                        <td><Skeleton width={110} /></td>
                        <td><Skeleton width={80} /></td>
                        <td><Skeleton width={90} /></td>
                        <td><Skeleton width={30} /></td>
                        <td><Skeleton width={70} /></td>
                        <td><Skeleton width={64} height={22} radius={999} /></td>
                      </tr>
                    ))
                  ) : rows.length === 0 ? (
                    <tr>
                      <td colSpan={7}>
                        <EmptyState
                          icon="users"
                          title={debouncedSearch ? 'No customers match your search' : 'No customers yet'}
                          action={debouncedSearch ? <Button size="sm" onClick={() => handleSearch('')}>Clear search</Button> : undefined}
                        />
                      </td>
                    </tr>
                  ) : (
                    rows.map((c: any) => (
                      <tr key={c.id} {...clickableRow(() => openDetail(c.id))} aria-label={`Open ${c.name}`}>
                        <td>
                          <Person name={c.name} sub={[c.phone, c.email].filter(Boolean).join(' · ')} size={34} />
                        </td>
                        <td>
                          <div className={ui.cellPrimary}>{c.city ?? '—'}</div>
                          {c.sub_area && <div className={ui.cellSub}>{c.sub_area}</div>}
                        </td>
                        <td className={ui.num}>{fmtDate(c.joined_at)}</td>
                        <td>
                          <div className={cx(ui.cellPrimary, ui.num)}>{int(c.bookings)}</div>
                          <div className={cx(ui.cellSub, ui.num)}>{int(c.completed)} done · {int(c.cancelled)} cancelled</div>
                        </td>
                        <td>
                          {c.no_show > 0 ? <Badge tone="danger" dot={false}>{int(c.no_show)}</Badge> : <span className={styles.zero}>0</span>}
                        </td>
                        <td className={cx(ui.alignRight, ui.cellPrimary, ui.num)}>{money(c.spend)}</td>
                        <td>
                          <Badge tone={c.is_active ? 'success' : 'neutral'}>{c.is_active ? 'Active' : 'Inactive'}</Badge>
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>

            {!firstLoad && (
              <Pagination
                page={dir.current_page ?? page}
                lastPage={dir.last_page ?? 1}
                total={dir.total}
                noun="customers"
                onChange={setPage}
              />
            )}
          </Card>
        </>
      )}

      {/* ---- detail drawer ---- */}
      <Drawer
        open={detailOpen}
        onClose={() => setDetailOpen(false)}
        title={detail?.customer?.name ?? 'Customer'}
        header={
          detail?.customer ? (
            <ProfileHeader c={detail.customer} />
          ) : (
            <div className={styles.profileHead}>
              <Skeleton width={56} height={56} radius={16} />
              <div style={{ flex: 1 }}>
                <Skeleton width="60%" height={18} />
                <div style={{ height: 8 }} />
                <Skeleton width="80%" height={12} />
              </div>
            </div>
          )
        }
        footer={
          detail?.customer && (
            <>
              <Button icon="download" onClick={() => exportCustomer(detail)} disabled={!(detail.appointments ?? []).length}>
                Export appointments
              </Button>
              <Button variant="primary" onClick={() => setDetailOpen(false)}>Done</Button>
            </>
          )
        }
      >
        {detailLoading ? (
          <div className={styles.drawerSkeleton}>
            <Skeleton height={76} radius={14} />
            <Skeleton height={220} radius={14} />
          </div>
        ) : detail?.error ? (
          <EmptyState icon="alert" title="Could not load customer" hint={detail.error} />
        ) : detail?.customer ? (
          <DetailPanel detail={detail} />
        ) : null}
      </Drawer>
    </div>
  );
}

function exportCustomer(detail: any) {
  const c = detail.customer;
  downloadCSV(
    `customer-${String(c.name || 'customer').replace(/\s+/g, '-').toLowerCase()}.csv`,
    ['Appointment', 'Salon', 'Status', 'Date', 'Start', 'Source', 'Billed'],
    (detail.appointments ?? []).map((a: any) => [
      a.id, a.salon ?? '—', a.status, a.date, a.start ?? '', a.source ?? a.booking_source ?? '', money(a.billed),
    ]),
  );
}

/* ---------------------------------------------------------------- pieces */

function ListSkeleton() {
  return (
    <div className={styles.listSkeleton}>
      {[1, 2, 3, 4].map((i) => (
        <div key={i} className={styles.listSkeletonRow}>
          <Skeleton width={34} height={34} radius={11} />
          <Skeleton height={12} />
        </div>
      ))}
    </div>
  );
}

function ProfileHeader({ c }: { c: any }) {
  return (
    <div className={styles.profileHead}>
      <Avatar name={c.name} size={56} />
      <div className={styles.profileText}>
        <div className={styles.profileName}>
          {c.name}
          {c.is_active !== undefined && <Badge tone={c.is_active ? 'success' : 'neutral'}>{c.is_active ? 'Active' : 'Inactive'}</Badge>}
        </div>
        <div className={styles.profileMeta}>
          {c.phone && <span><Icon name="phone" size={13} />{c.phone}</span>}
          {c.email && <span><Icon name="mail" size={13} />{c.email}</span>}
        </div>
        <div className={styles.profileMeta}>
          <span><Icon name="pin" size={13} />{c.city ?? 'No city'}</span>
          <span>Joined {fmtDate(c.joined_at)}</span>
          {c.last_seen && <span>Last seen {fmtDate(c.last_seen)}</span>}
        </div>
      </div>
    </div>
  );
}

const APP_TONE: Record<string, Tone> = {
  completed: 'success',
  cancelled: 'neutral',
  no_show: 'danger',
  scheduled: 'info',
  in_progress: 'accent',
  pending_payment: 'warning',
  rescheduled: 'info',
  awaiting_reschedule: 'warning',
};

function DetailPanel({ detail }: { detail: any }) {
  const c = detail.customer;
  const [tab, setTab] = useState<'appointments' | 'reviews'>('appointments');
  const [appSort, setAppSort] = useState<{ key: string; dir: 'asc' | 'desc' }>({ key: 'date', dir: 'desc' });

  const appointments = useMemo(() => {
    const list = [...(detail.appointments ?? [])];
    const dir = appSort.dir === 'asc' ? 1 : -1;
    list.sort((x: any, y: any) => {
      const va = x[appSort.key];
      const vb = y[appSort.key];
      if (va == null && vb == null) return 0;
      if (va == null) return 1;
      if (vb == null) return -1;
      const cmp = typeof va === 'number' ? va - vb : String(va).localeCompare(String(vb));
      return cmp * dir;
    });
    return list;
  }, [detail, appSort]);

  const toggleSort = (key: string) =>
    setAppSort((p) => ({ key, dir: key === p.key && p.dir === 'asc' ? 'desc' : 'asc' }));

  const reviews = detail.reviews ?? [];
  const completion = c.bookings > 0 ? Math.round((c.completed / c.bookings) * 100) : 0;

  return (
    <>
      <div className={styles.profileStats}>
        <div className={cx(styles.profileStat, styles.profileStatAccent)}>
          <span>Lifetime value</span>
          <b>{money(c.spend)}</b>
        </div>
        <div className={styles.profileStat}>
          <span>Bookings</span>
          <b>{int(c.bookings)}</b>
        </div>
        <div className={styles.profileStat}>
          <span>Completion</span>
          <b>{completion}%</b>
        </div>
        <div className={styles.profileStat}>
          <span>No-shows</span>
          <b className={c.no_show > 0 ? styles.danger : undefined}>{int(c.no_show)}</b>
        </div>
      </div>

      <Tabs
        value={tab}
        onChange={setTab}
        tabs={[
          { value: 'appointments', label: `Appointments (${appointments.length})` },
          { value: 'reviews', label: `Reviews (${reviews.length})` },
        ]}
      />

      <div className={styles.tabBody}>
        {tab === 'appointments' && (
          appointments.length === 0 ? (
            <EmptyState icon="calendar" title="No appointments recorded" />
          ) : (
            <div className={cx(ui.tableWrap, styles.drawerTable)}>
              <table className={ui.table}>
                <thead>
                  <tr>
                    <SortHeader label="Salon" active={appSort.key === 'salon'} dir={appSort.dir} onClick={() => toggleSort('salon')} />
                    <SortHeader label="When" active={appSort.key === 'date'} dir={appSort.dir} onClick={() => toggleSort('date')} />
                    <SortHeader label="Billed" active={appSort.key === 'billed'} dir={appSort.dir} onClick={() => toggleSort('billed')} align="right" />
                    <SortHeader label="Status" active={appSort.key === 'status'} dir={appSort.dir} onClick={() => toggleSort('status')} />
                  </tr>
                </thead>
                <tbody>
                  {appointments.map((a: any) => (
                    <tr key={a.id}>
                      <td className={ui.cellPrimary}>{a.salon ?? '—'}</td>
                      <td className={ui.num}>
                        {fmtDate(a.date)}
                        {a.start && <div className={ui.cellSub}>{String(a.start).slice(0, 5)}</div>}
                      </td>
                      <td className={cx(ui.alignRight, ui.num, ui.cellPrimary)}>{money(a.billed)}</td>
                      <td>
                        <Badge tone={APP_TONE[a.status] ?? 'neutral'}>{String(a.status ?? 'unknown').replace(/_/g, ' ')}</Badge>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )
        )}

        {tab === 'reviews' && (
          reviews.length === 0 ? (
            <EmptyState icon="star" title="No reviews yet" hint="This customer hasn't reviewed a salon." />
          ) : (
            <ul className={styles.reviewList}>
              {reviews.map((r: any) => (
                <li className={styles.reviewItem} key={r.id}>
                  <div className={styles.reviewTop}>
                    <span className={styles.stars} aria-label={`${r.rating} out of 5`}>
                      {'★'.repeat(r.rating)}
                      <span className={styles.starsDim}>{'★'.repeat(Math.max(0, 5 - r.rating))}</span>
                    </span>
                    <span className={styles.reviewMeta}>{r.salon ?? '—'} · {fmtDate(r.created_at)}</span>
                  </div>
                  <p className={styles.reviewText}>{r.comment || <em>No comment.</em>}</p>
                </li>
              ))}
            </ul>
          )
        )}
      </div>
    </>
  );
}
