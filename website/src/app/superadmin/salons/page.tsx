'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import Link from 'next/link';
import {
  Badge, Button, DataTable, PageHeader, SearchInput, StatCard, cx, formatINR, ui,
  useConfirm, useDebounced, useTableState,
  type DataColumn, type SortDir, type Tone,
} from '@/components/admin/ui';
import Icon from '@/components/admin/Icon';
import styles from './page.module.css';

interface Salon {
  id: string;
  name: string;
  status: string;
  created_at: string;
  gender_focus?: string | null;
  city?: { id: string; name: string } | null;
  sub_area?: { id: string; name: string } | null;
  admin?: { name: string; phone?: string | null } | null;
  assigned_collaborator?: { id: string; name: string } | null;
  current_plan?: CurrentPlan | null;
  stats?: RowStats;
}

/** The plan the salon is on right now; null when it has none. */
interface CurrentPlan {
  name: string;
  billing_type: 'subscription' | 'commission' | string;
  billing_label: string;
  end_date: string | null;
  days_left: number | null;
  lapsed: boolean;
}

interface RowStats {
  bookings: number;
  completed: number;
  revenue: number;
  avg_ticket: number;
  rating: number | null;
  reviews: number;
  staff: number;
  services: number;
  last_booking_at: string | null;
}

interface Summary {
  total: number;
  active: number;
  pending: number;
  suspended: number;
  with_live_plan: number;
  unassigned: number;
  revenue: number;
  bookings: number;
}

interface FilterOptions {
  cities: { id: string; name: string }[];
  sub_areas: { id: string; name: string; city_id: string }[];
  plans: { id: string; name: string }[];
  gender_focus: string[];
}

interface Collaborator {
  id: string;
  name: string;
}

interface Meta {
  current_page: number;
  last_page: number;
  per_page: number;
  total: number;
}

const STATUS_TONE: Record<string, Tone> = {
  active: 'success',
  pending_approval: 'warning',
  needs_correction: 'warning',
  rejected: 'danger',
  suspended: 'danger',
  deactivated: 'neutral',
};

/** "Sort by" presets, for the orderings a header click cannot express in one go. */
const SORT_PRESETS: { value: string; label: string; key: string; dir: SortDir }[] = [
  { value: 'newest', label: 'Newest first', key: 'created_at', dir: 'desc' },
  { value: 'oldest', label: 'Oldest first', key: 'created_at', dir: 'asc' },
  { value: 'bookings_desc', label: 'Most bookings', key: 'bookings', dir: 'desc' },
  { value: 'bookings_asc', label: 'Fewest bookings', key: 'bookings', dir: 'asc' },
  { value: 'revenue_desc', label: 'Highest revenue', key: 'revenue', dir: 'desc' },
  { value: 'revenue_asc', label: 'Lowest revenue', key: 'revenue', dir: 'asc' },
  { value: 'completed_desc', label: 'Most completed visits', key: 'completed', dir: 'desc' },
  { value: 'rating_desc', label: 'Highest rated', key: 'rating', dir: 'desc' },
  { value: 'rating_asc', label: 'Lowest rated', key: 'rating', dir: 'asc' },
  { value: 'staff_desc', label: 'Most staff', key: 'staff', dir: 'desc' },
  { value: 'last_booking_desc', label: 'Recently booked', key: 'last_booking', dir: 'desc' },
  { value: 'last_booking_asc', label: 'Longest without a booking', key: 'last_booking', dir: 'asc' },
  { value: 'name_asc', label: 'Name A–Z', key: 'name', dir: 'asc' },
];

const EMPTY_FILTERS = {
  status: '',
  cityId: '',
  subAreaId: '',
  billing: '',
  planId: '',
  planState: '',
  collaboratorId: '',
  gender: '',
};
type Filters = typeof EMPTY_FILTERS;

const formatStatus = (value: string) => value.replace(/_/g, ' ');

const formatDate = (value: string) => {
  const d = new Date(value);
  return Number.isNaN(d.getTime())
    ? '—'
    : d.toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' });
};

/** "3 d ago", "5 mo ago" — the last booking, at a glance. */
const relTime = (value?: string | null) => {
  if (!value) return null;
  const then = new Date(value).getTime();
  if (Number.isNaN(then)) return null;
  const days = Math.floor((Date.now() - then) / 86_400_000);
  if (days <= 0) return 'Today';
  if (days === 1) return 'Yesterday';
  if (days < 30) return `${days} d ago`;
  if (days < 365) return `${Math.floor(days / 30)} mo ago`;
  return `${Math.floor(days / 365)} y ago`;
};

/** One line for the CSV and the cell's tooltip. */
const planSummary = (plan?: CurrentPlan | null) => {
  if (!plan) return 'No active plan';
  const until = plan.end_date ? ` until ${formatDate(plan.end_date)}` : '';
  return `${plan.name} · ${plan.billing_label}${until}${plan.lapsed ? ' (lapsed)' : ''}`;
};

const place = (s: Salon) => [s.sub_area?.name, s.city?.name].filter(Boolean).join(', ');

export default function SalonDirectory() {
  const [salons, setSalons] = useState<Salon[]>([]);
  const [meta, setMeta] = useState<Meta>({ current_page: 1, last_page: 1, per_page: 20, total: 0 });
  const [summary, setSummary] = useState<Summary | null>(null);
  const [options, setOptions] = useState<FilterOptions>({ cities: [], sub_areas: [], plans: [], gender_focus: [] });
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [collaborators, setCollaborators] = useState<Collaborator[]>([]);
  const [assigningId, setAssigningId] = useState<string | null>(null);
  const [justAssignedIds, setJustAssignedIds] = useState<string[]>([]);

  const [search, setSearch] = useState('');
  const [filters, setFilters] = useState<Filters>(EMPTY_FILTERS);
  const [preset, setPreset] = useState('newest');

  const debouncedSearch = useDebounced(search, 400);
  const [confirm, confirmDialog] = useConfirm();

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const res = await fetch('/api/proxy/superadmin/collaborators');
        if (!res.ok) return;
        const json = await res.json();
        if (!cancelled) setCollaborators(json.data || []);
      } catch {
        // The filter falls back to "All collaborators"; not worth an alert.
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  const handleAssign = useCallback(
    async (salon: Salon, collId: string) => {
      const current = salon.assigned_collaborator?.id || '';
      if (collId === current) return;

      const nextName = collaborators.find((c) => c.id === collId)?.name;
      const ok = await confirm({
        title: current ? 'Change assigned collaborator?' : 'Assign a collaborator?',
        body: `${salon.name} will move to ${nextName || 'Unassigned'}.`,
        confirmLabel: 'Save',
        tone: 'accent',
      });
      if (!ok) return;

      setAssigningId(salon.id);
      const previous = salon.assigned_collaborator ?? null;
      // Optimistic: the select already shows the new value, so reflect it now
      // and put it back if the save fails.
      setSalons((prev) =>
        prev.map((s) =>
          s.id === salon.id
            ? { ...s, assigned_collaborator: collId ? { id: collId, name: nextName || '' } : null }
            : s,
        ),
      );

      try {
        const res = await fetch(`/api/proxy/superadmin/salons/${salon.id}/assign-collaborator`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ collaborator_id: collId || null }),
        });
        const json = await res.json();
        if (!res.ok || !json.success) throw new Error(json.message || 'Failed to assign');

        setJustAssignedIds((prev) => [...prev, salon.id]);
        setTimeout(() => {
          setJustAssignedIds((prev) => prev.filter((id) => id !== salon.id));
        }, 2000);
      } catch (err) {
        setSalons((prev) =>
          prev.map((s) => (s.id === salon.id ? { ...s, assigned_collaborator: previous } : s)),
        );
        setError(err instanceof Error ? err.message : 'Failed to assign collaborator');
      } finally {
        setAssigningId(null);
      }
    },
    [collaborators, confirm],
  );

  const columns = useMemo<DataColumn<Salon>[]>(
    () => [
      {
        key: 'name',
        header: 'Salon',
        sortValue: (s) => s.name,
        csvValue: (s) => s.name,
        render: (s) => (
          <div className={styles.salonCell}>
            <span className={styles.salonAvatar} aria-hidden>{s.name.charAt(0).toUpperCase()}</span>
            <div className={styles.stack}>
              <Link href={`/superadmin/salons/${s.id}`} className={styles.salonName}>{s.name}</Link>
              <span className={styles.muted}>
                <Icon name="pin" size={12} /> {place(s) || 'No location'}
              </span>
            </div>
          </div>
        ),
      },
      {
        key: 'city',
        header: 'City',
        sortValue: (s) => s.city?.name,
        csvValue: (s) => place(s),
        render: (s) => (
          <div className={styles.stack}>
            <span>{s.city?.name || '—'}</span>
            {s.sub_area?.name && <span className={styles.muted}>{s.sub_area.name}</span>}
          </div>
        ),
      },
      {
        key: 'admin',
        header: 'Owner',
        sortValue: (s) => s.admin?.name,
        csvValue: (s) => [s.admin?.name, s.admin?.phone].filter(Boolean).join(' · '),
        render: (s) => (
          <div className={styles.stack}>
            <span className={styles.strong}>{s.admin?.name || '—'}</span>
            {s.admin?.phone && <span className={styles.muted}>{s.admin.phone}</span>}
          </div>
        ),
      },
      {
        key: 'plan',
        header: 'Plan',
        sortValue: (s) => s.current_plan?.name,
        csvValue: (s) => planSummary(s.current_plan),
        render: (s) => {
          const plan = s.current_plan;
          if (!plan) return <span className={styles.planNone}>No active plan</span>;

          const commission = plan.billing_type === 'commission';
          const soon = !plan.lapsed && plan.days_left !== null && plan.days_left <= 5;

          return (
            <div className={styles.stack} title={planSummary(plan)}>
              <span className={styles.planName}>
                {plan.name}
                {plan.lapsed && <Badge tone="danger" dot={false}>Lapsed</Badge>}
                {soon && <Badge tone="warning" dot={false}>{plan.days_left === 0 ? 'Ends today' : `${plan.days_left}d left`}</Badge>}
              </span>
              <span className={styles.muted}>
                {commission ? 'Commission' : 'Subscription'}
                {plan.end_date && ` · ${formatDate(plan.end_date)}`}
              </span>
            </div>
          );
        },
      },
      {
        key: 'bookings',
        header: 'Bookings',
        align: 'right',
        sortValue: (s) => s.stats?.bookings ?? 0,
        csvValue: (s) => s.stats?.bookings ?? 0,
        render: (s) => (
          <div className={cx(styles.stack, styles.right)}>
            <span className={styles.figure}>{(s.stats?.bookings ?? 0).toLocaleString('en-IN')}</span>
            <span className={styles.muted}>{s.stats?.completed ?? 0} completed</span>
          </div>
        ),
      },
      {
        key: 'revenue',
        header: 'Revenue',
        align: 'right',
        sortValue: (s) => s.stats?.revenue ?? 0,
        csvValue: (s) => s.stats?.revenue ?? 0,
        render: (s) => (
          <div className={cx(styles.stack, styles.right)}>
            <span className={styles.figure}>{formatINR(s.stats?.revenue ?? 0)}</span>
            <span className={styles.muted}>
              {s.stats?.avg_ticket ? `${formatINR(s.stats.avg_ticket)} avg` : 'No visits yet'}
            </span>
          </div>
        ),
      },
      {
        key: 'rating',
        header: 'Rating',
        align: 'right',
        sortValue: (s) => s.stats?.rating ?? 0,
        csvValue: (s) => s.stats?.rating ?? '',
        render: (s) =>
          s.stats?.rating ? (
            <div className={cx(styles.stack, styles.right)}>
              <span className={styles.rating}><Icon name="star" size={13} /> {s.stats.rating.toFixed(1)}</span>
              <span className={styles.muted}>{s.stats.reviews} review{s.stats.reviews === 1 ? '' : 's'}</span>
            </div>
          ) : (
            <span className={styles.muted}>No reviews</span>
          ),
      },
      {
        key: 'staff',
        header: 'Team',
        align: 'right',
        sortValue: (s) => s.stats?.staff ?? 0,
        csvValue: (s) => `${s.stats?.staff ?? 0} staff / ${s.stats?.services ?? 0} services`,
        render: (s) => (
          <div className={cx(styles.stack, styles.right)}>
            <span className={styles.strong}>{s.stats?.staff ?? 0} staff</span>
            <span className={styles.muted}>{s.stats?.services ?? 0} services</span>
          </div>
        ),
      },
      {
        key: 'last_booking',
        header: 'Last booking',
        sortValue: (s) => s.stats?.last_booking_at ?? '',
        csvValue: (s) => s.stats?.last_booking_at ?? '',
        render: (s) => {
          const rel = relTime(s.stats?.last_booking_at);
          return rel ? <span className={styles.dateCell}>{rel}</span> : <span className={styles.muted}>Never</span>;
        },
      },
      {
        key: 'collaborator',
        header: 'Collaborator',
        sortValue: (s) => s.assigned_collaborator?.name,
        // The cell is a control, so spell out the value for the CSV instead.
        csvValue: (s) => s.assigned_collaborator?.name || 'Unassigned',
        render: (s) => (
          <div className={styles.collaboratorCell}>
            <select
              className={cx(styles.cellSelect, !s.assigned_collaborator && styles.cellSelectEmpty)}
              value={s.assigned_collaborator?.id || ''}
              onChange={(e) => handleAssign(s, e.target.value)}
              disabled={assigningId === s.id}
              aria-label={`Collaborator for ${s.name}`}
            >
              <option value="">Unassigned</option>
              {collaborators.map((c) => (
                <option key={c.id} value={c.id}>{c.name}</option>
              ))}
            </select>
            {justAssignedIds.includes(s.id) && <span className={styles.savedFlag}>Saved</span>}
          </div>
        ),
      },
      {
        key: 'status',
        header: 'Status',
        sortValue: (s) => s.status,
        csvValue: (s) => formatStatus(s.status),
        render: (s) => (
          <div className={styles.stack}>
            <Badge tone={STATUS_TONE[s.status] ?? 'neutral'} dot={false}>{formatStatus(s.status)}</Badge>
            <span className={styles.muted}>Joined {formatDate(s.created_at)}</span>
          </div>
        ),
      },
      {
        key: 'action',
        header: '',
        align: 'right',
        render: (s) => (
          <Link href={`/superadmin/salons/${s.id}`} className={styles.actionButton}>
            View <Icon name="chevronRight" size={14} />
          </Link>
        ),
      },
    ],
    [collaborators, assigningId, justAssignedIds, handleAssign],
  );

  // Server mode: the directory can hold every salon on the platform.
  const table = useTableState<Salon>({
    rows: salons,
    columns,
    mode: 'server',
    total: meta.total,
    lastPage: meta.last_page,
  });

  const { page, perPage, sort } = table;

  // A header click wins over the "Sort by" preset; picking a preset clears it.
  const presetSort = SORT_PRESETS.find((p) => p.value === preset) ?? SORT_PRESETS[0];
  const effectiveSort = sort ?? { key: presetSort.key, dir: presetSort.dir };

  // Rapid paging or header clicks can land out of order; only the newest wins.
  const requestId = useRef(0);

  const load = useCallback(async () => {
    const id = ++requestId.current;
    setLoading(true);
    try {
      const params = new URLSearchParams({ page: String(page), per_page: String(perPage) });
      if (debouncedSearch) params.set('search', debouncedSearch);
      const map: [keyof Filters, string][] = [
        ['status', 'status'], ['cityId', 'city_id'], ['subAreaId', 'sub_area_id'], ['billing', 'billing'],
        ['planId', 'plan_id'], ['planState', 'plan_state'], ['collaboratorId', 'collaborator_id'], ['gender', 'gender_focus'],
      ];
      map.forEach(([k, param]) => filters[k] && params.set(param, filters[k]));
      params.set('column', effectiveSort.key);
      params.set('direction', effectiveSort.dir);

      const res = await fetch(`/api/proxy/superadmin/salons?${params}`, { cache: 'no-store' });
      const json = await res.json();
      if (id !== requestId.current) return;
      if (!json.success) throw new Error(json.message || 'Error loading salons');

      setSalons(json.data || []);
      if (json.meta) setMeta(json.meta);
      if (json.summary) setSummary(json.summary);
      if (json.filters) setOptions(json.filters);
      setError('');
    } catch (err) {
      if (id !== requestId.current) return;
      setError(err instanceof Error ? err.message : 'Error loading salons');
    } finally {
      if (id === requestId.current) setLoading(false);
    }
  }, [debouncedSearch, filters, effectiveSort.key, effectiveSort.dir, page, perPage]);

  useEffect(() => {
    const timer = setTimeout(load, 0);
    return () => clearTimeout(timer);
  }, [load]);

  const setFilter = (key: keyof Filters, value: string) => {
    setFilters((prev) => ({
      ...prev,
      [key]: value,
      // An area belongs to one city; changing the city drops it.
      ...(key === 'cityId' ? { subAreaId: '' } : {}),
    }));
    table.setPage(1);
  };

  const onSearch = (value: string) => {
    setSearch(value);
    table.setPage(1);
  };

  const onPreset = (value: string) => {
    setPreset(value);
    table.clearSort();
  };

  const subAreas = filters.cityId ? options.sub_areas.filter((a) => a.city_id === filters.cityId) : options.sub_areas;
  const activeFilterCount = Object.values(filters).filter(Boolean).length;

  const clearAll = () => {
    setFilters(EMPTY_FILTERS);
    setSearch('');
    setPreset('newest');
    table.clearSort();
  };

  /** One-tap views from the summary cards. */
  const quick = (patch: Partial<Filters>) => {
    setFilters({ ...EMPTY_FILTERS, ...patch });
    table.setPage(1);
  };

  const filterSelect = (key: keyof Filters, label: string, opts: { value: string; label: string }[]) => (
    <label className={styles.filterField}>
      <span>{label}</span>
      <select
        className={cx(styles.selectInput, filters[key] && styles.selectActive)}
        value={filters[key]}
        onChange={(e) => setFilter(key, e.target.value)}
        aria-label={`Filter by ${label.toLowerCase()}`}
      >
        {opts.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
      </select>
    </label>
  );

  return (
    <div className={styles.container}>
      {confirmDialog}

      <PageHeader
        eyebrow="Directory"
        title="Salons"
        subtitle="Every salon on the platform — how it is doing, what it pays, and who looks after it."
      />

      <div className={cx(ui.statGrid, styles.summaryGrid)}>
        <button type="button" className={styles.statButton} onClick={() => quick({})}>
          <StatCard label="All salons" icon="store" tone="accent" loading={!summary} value={summary?.total ?? 0}
            sub={summary ? `${summary.active} active · ${summary.pending} awaiting approval` : undefined} />
        </button>
        <button type="button" className={styles.statButton} onClick={() => quick({ planState: 'active' })}>
          <StatCard label="On a live plan" icon="crown" tone="success" loading={!summary} value={summary?.with_live_plan ?? 0}
            sub="Tap to see them" />
        </button>
        <button type="button" className={styles.statButton} onClick={() => quick({ collaboratorId: 'unassigned' })}>
          <StatCard label="No collaborator" icon="userX" tone={summary?.unassigned ? 'warning' : 'neutral'} loading={!summary}
            value={summary?.unassigned ?? 0} sub="Need someone assigned" />
        </button>
        <StatCard label="Completed revenue" icon="rupee" tone="info" loading={!summary} value={formatINR(summary?.revenue ?? 0)}
          sub={summary ? `${summary.bookings.toLocaleString('en-IN')} bookings in all` : undefined} />
      </div>

      <section className={styles.filterPanel} aria-label="Filters">
        <div className={styles.filterHead}>
          <span className={styles.filterTitle}>
            <Icon name="sliders" size={16} /> Filters
            {activeFilterCount > 0 && <Badge tone="accent" dot={false}>{activeFilterCount} on</Badge>}
          </span>
          {(activeFilterCount > 0 || search || preset !== 'newest' || sort) && (
            <Button size="sm" variant="ghost" onClick={clearAll}>Clear all</Button>
          )}
        </div>
        <div className={styles.filterGrid}>
          {filterSelect('status', 'Status', [
            { value: '', label: 'Any status' },
            { value: 'active', label: 'Active' },
            { value: 'pending_approval', label: 'Pending approval' },
            { value: 'needs_correction', label: 'Needs correction' },
            { value: 'suspended', label: 'Suspended' },
            { value: 'deactivated', label: 'Deactivated' },
            { value: 'rejected', label: 'Rejected' },
          ])}
          {filterSelect('cityId', 'City', [
            { value: '', label: 'All cities' },
            ...options.cities.map((c) => ({ value: c.id, label: c.name })),
          ])}
          {filterSelect('subAreaId', 'Area', [
            { value: '', label: filters.cityId ? 'All areas' : 'All areas (any city)' },
            ...subAreas.map((a) => ({ value: a.id, label: a.name })),
          ])}
          {filterSelect('billing', 'Model', [
            { value: '', label: 'Any model' },
            { value: 'subscription', label: 'Subscription' },
            { value: 'commission', label: 'Commission' },
            { value: 'none', label: 'No live plan' },
          ])}
          {filterSelect('planId', 'Plan', [
            { value: '', label: 'Any plan' },
            ...options.plans.map((p) => ({ value: p.id, label: p.name })),
            { value: 'none', label: 'No plan' },
          ])}
          {filterSelect('planState', 'Plan state', [
            { value: '', label: 'Any' },
            { value: 'active', label: 'Live' },
            { value: 'expiring', label: 'Ending in 5 days' },
            { value: 'none', label: 'Lapsed or none' },
          ])}
          {filterSelect('collaboratorId', 'Collaborator', [
            { value: '', label: 'Anyone' },
            { value: 'unassigned', label: 'Unassigned' },
            ...collaborators.map((c) => ({ value: c.id, label: c.name })),
          ])}
          {options.gender_focus.length > 0 && filterSelect('gender', 'Serves', [
            { value: '', label: 'Everyone' },
            ...options.gender_focus.map((g) => ({ value: g, label: g.charAt(0).toUpperCase() + g.slice(1) })),
          ])}
        </div>
      </section>

      <div className={styles.tableShell}>
        <DataTable
          columns={columns}
          rows={salons}
          rowKey={(s) => s.id}
          loading={loading && salons.length === 0}
          error={error || undefined}
          sort={sort}
          onSort={table.toggleSort}
          page={page}
          lastPage={meta.last_page}
          total={meta.total}
          onPage={table.setPage}
          perPage={perPage}
          onPerPageChange={table.changePerPage}
          noun="salons"
          exportName="salon-directory"
          caption="Every salon on the platform"
          rowClassName={(s) => cx(justAssignedIds.includes(s.id) && styles.rowSuccess)}
          empty={{
            title: search ? `No salon matches “${search}”` : 'No salons found',
            hint: search || activeFilterCount ? 'Try clearing the filters.' : undefined,
          }}
          toolbar={
            <>
              <SearchInput
                value={search}
                onChange={onSearch}
                placeholder="Search salon, area, city, owner or phone…"
                ariaLabel="Search salons"
                className={styles.searchField}
              />
              <label className={styles.sortField}>
                <Icon name="sortBoth" size={15} />
                <select
                  className={styles.sortSelect}
                  value={sort ? '' : preset}
                  onChange={(e) => onPreset(e.target.value)}
                  aria-label="Sort salons"
                >
                  {sort && <option value="">Sorted by column</option>}
                  {SORT_PRESETS.map((p) => <option key={p.value} value={p.value}>{p.label}</option>)}
                </select>
              </label>
            </>
          }
        />
      </div>
    </div>
  );
}
