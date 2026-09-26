'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import Icon, { type IconName } from '@/components/admin/Icon';
import {
  Alert, Badge, Button, Card, DescriptionList, Drawer, EmptyState, Field, IconButton, Modal,
  PageHeader, Pagination, Person, SearchInput, Segmented, Skeleton, SortHeader, Tabs,
  clickableRow, cx, downloadCSV, formatINR, localISODate, ui, useDebounced, type Tone,
} from '@/components/admin/ui';
import styles from './page.module.css';

// The API is Laravel, so every relation arrives snake_cased.
interface UserRef {
  id?: string;
  name?: string;
  phone?: string;
  email?: string;
  role?: string;
}

interface ProviderRef {
  id?: string;
  user?: UserRef;
}

interface ServiceRef {
  id?: string;
  price?: string | number;
  template?: { name?: string; estimated_duration_minutes?: number };
}

interface ServiceLine {
  id: string;
  service?: ServiceRef;
  combo_id?: string | null;
  price_at_booking?: string | number;
  original_service_price?: string | number;
  duration_minutes_at_booking?: number;
  line_status?: string;
  serving_provider?: ProviderRef | null;
}

interface ServiceAddition {
  id: string;
  service?: ServiceRef;
  provider?: ProviderRef;
  added_by?: UserRef;
  price_at_addition?: string | number;
  duration_minutes_at_addition?: number;
  status?: string;
  added_at?: string;
}

interface SalonRef {
  id: string;
  name: string;
  phone?: string;
  email?: string;
  address?: string;
  status?: string;
}

interface Appointment {
  id: string;
  salon: SalonRef;
  customer?: UserRef | null;
  appointed_provider?: ProviderRef | null;
  serving_provider?: ProviderRef | null;
  services?: ServiceLine[];
  service_additions?: ServiceAddition[];
  cancelled_by_user?: UserRef | null;

  booking_source?: string;
  appointment_date: string;
  start_time: string;
  end_time?: string;
  status: string;

  payment_option?: string;
  total_amount: string;
  advance_amount?: string;
  balance_amount?: string;
  final_billed_amount?: string | null;

  walk_in_customer_name?: string | null;
  walk_in_customer_phone?: string | null;
  walk_in_customer_gender?: string | null;

  verification_method?: string;
  qr_verified_at?: string | null;
  cancelled_by?: string | null;
  cancellation_reason?: string | null;
  cancelled_at?: string | null;
  rescheduled_from_id?: string | null;
  reschedule_reason?: string | null;
  salon_closure_id?: string | null;
  closure_notified_at?: string | null;
  salon_closure?: { id?: string; closed_date?: string; reason?: string | null } | null;
  started_at?: string | null;
  completed_at?: string | null;
  no_show_at?: string | null;
  created_at?: string;
}

interface Meta {
  current_page: number;
  last_page: number;
  total: number;
}

interface Salon {
  id: string;
  name: string;
}

type DateMode = 'specific' | 'week' | 'month' | 'lifetime';
type DetailsTab = 'overview' | 'services' | 'payment' | 'timeline';

// Mid-appointment additions are driven from the partner app for now; the
// admin form stays wired up but hidden until it gets real pickers.
const ADD_SERVICE_ENABLED = false;

const POLL_MS = 5000;

const STATUS_META: Record<string, { label: string; tone: Tone; pulse?: boolean }> = {
  scheduled: { label: 'Scheduled', tone: 'info' },
  in_progress: { label: 'In progress', tone: 'accent', pulse: true },
  completed: { label: 'Completed', tone: 'success' },
  cancelled: { label: 'Cancelled', tone: 'neutral' },
  no_show: { label: 'No-show', tone: 'danger' },
  awaiting_reschedule: { label: 'Awaiting reschedule', tone: 'warning' },
};

// Statuses where a balance can still be collected at the salon.
const OPEN_STATUSES = new Set(['scheduled', 'in_progress', 'awaiting_reschedule']);

const STATUS_FILTERS = [
  { value: '', label: 'All' },
  ...Object.entries(STATUS_META).map(([value, m]) => ({ value, label: m.label })),
];

const SOURCE_META: Record<string, { label: string; icon: IconName }> = {
  online: { label: 'Customer app', icon: 'smartphone' },
  walk_in: { label: 'Walk-in', icon: 'walkIn' },
  phone: { label: 'Phone', icon: 'phone' },
};

// ---------------------------------------------------------------- display

const statusMeta = (status: string) =>
  STATUS_META[status] ?? { label: status.replace(/_/g, ' '), tone: 'neutral' as Tone };

const StatusBadge = ({ status }: { status: string }) => {
  const m = statusMeta(status);
  return <Badge tone={m.tone} pulse={m.pulse}>{m.label}</Badge>;
};

const providerName = (apt: Appointment) =>
  apt.serving_provider?.user?.name || apt.appointed_provider?.user?.name || null;

const serviceName = (line: { service?: ServiceRef }) =>
  line.service?.template?.name || 'Unnamed service';

const serviceNames = (apt: Appointment) => [
  ...(apt.services || []).map(serviceName),
  ...(apt.service_additions || []).map(serviceName),
];

const customerName = (apt: Appointment) =>
  apt.customer?.name || apt.walk_in_customer_name || 'Walk-in';

const customerPhone = (apt: Appointment) =>
  apt.customer?.phone || apt.walk_in_customer_phone || null;

const sourceLabel = (source?: string) => SOURCE_META[source ?? '']?.label ?? source ?? '—';

const money = (value?: string | number | null) => formatINR(value, 2);

const verificationLabel = (method?: string) => {
  if (!method) return undefined;
  if (method === 'qr') return 'QR scan';
  if (method.length <= 3) return method.toUpperCase();
  return method.replace(/_/g, ' ');
};

const dateTime = (value?: string | null) =>
  value ? new Date(value).toLocaleString('en-IN', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }) : '—';

/** "2026-09-25" → a local date (new Date(iso) would be UTC midnight). */
const parseDay = (iso: string) => {
  const [y, m, d] = iso.slice(0, 10).split('-').map(Number);
  return new Date(y, (m || 1) - 1, d || 1);
};

const dayLabel = (iso: string) =>
  parseDay(iso).toLocaleDateString('en-IN', { weekday: 'short', day: 'numeric', month: 'short' });

/** "14:30:00" → "2:30 pm" */
const clock = (t?: string) => {
  if (!t) return '';
  const [h, m] = t.split(':').map(Number);
  if (Number.isNaN(h)) return t;
  const d = new Date();
  d.setHours(h, m || 0, 0, 0);
  return d.toLocaleTimeString('en-IN', { hour: 'numeric', minute: '2-digit' });
};

const addDays = (iso: string, days: number) => {
  const d = parseDay(iso);
  d.setDate(d.getDate() + days);
  return localISODate(d);
};

export default function GlobalAppointmentsDashboard() {
  const [appointments, setAppointments] = useState<Appointment[]>([]);
  const [meta, setMeta] = useState<Meta | null>(null);
  const [error, setError] = useState('');
  const [lastSynced, setLastSynced] = useState<Date | null>(null);

  // Filters
  const [dateMode, setDateMode] = useState<DateMode>('specific');
  const [date, setDate] = useState(() => localISODate());
  const [status, setStatus] = useState('');
  const [salonId, setSalonId] = useState('');
  const [search, setSearch] = useState('');
  const debouncedSearch = useDebounced(search);
  const [page, setPage] = useState(1);
  const [perPage, setPerPage] = useState(20);
  const [sort, setSort] = useState<{ key: string; dir: 'asc' | 'desc' } | null>(null);
  const [salons, setSalons] = useState<Salon[]>([]);

  // Overlays
  const [isAddServiceModalOpen, setIsAddServiceModalOpen] = useState(false);
  const [selectedAppointmentId, setSelectedAppointmentId] = useState('');
  const [serviceId, setServiceId] = useState('');
  const [providerId, setProviderId] = useState('');
  const [addServiceError, setAddServiceError] = useState('');
  const [infoModalData, setInfoModalData] = useState<{ type: 'salon' | 'customer'; data: SalonRef | UserRef } | null>(null);
  const [detailsAppointment, setDetailsAppointment] = useState<Appointment | null>(null);
  const [activeDetailsTab, setActiveDetailsTab] = useState<DetailsTab>('overview');

  const router = useRouter();

  // Polls overlap with filter changes; only the newest request may land.
  const requestSeq = useRef(0);

  // Loading is derived: true until a response for the current filters lands.
  const queryKey = [date, dateMode, status, salonId, debouncedSearch, page, perPage, sort?.key, sort?.dir].join('|');
  const [loadedKey, setLoadedKey] = useState<string | null>(null);
  const loading = loadedKey !== queryKey;

  const fetchAppointments = useCallback(async (isPolling = false) => {
    const seq = ++requestSeq.current;
    try {
      const queryParams = new URLSearchParams();
      const today = localISODate();
      if (dateMode === 'specific' && date) {
        queryParams.append('date', date);
      } else if (dateMode === 'week') {
        queryParams.append('start_date', today);
        queryParams.append('end_date', addDays(today, 7));
      } else if (dateMode === 'month') {
        const d = new Date();
        queryParams.append('start_date', localISODate(new Date(d.getFullYear(), d.getMonth(), 1)));
        queryParams.append('end_date', localISODate(new Date(d.getFullYear(), d.getMonth() + 1, 0)));
      }

      if (status) queryParams.append('status', status);
      if (salonId) queryParams.append('salon_id', salonId);
      if (debouncedSearch) queryParams.append('search', debouncedSearch);
      if (sort) {
        queryParams.append('column', sort.key);
        queryParams.append('direction', sort.dir);
      }
      queryParams.append('page', page.toString());
      queryParams.append('per_page', perPage.toString());

      const res = await fetch(`/api/proxy/superadmin/appointments?${queryParams.toString()}`);

      if (!res.ok) {
        if (res.status === 401) {
          router.push('/login');
          return;
        }
        const errorData = await res.json().catch(() => null);
        throw new Error(errorData?.message || 'Failed to fetch appointments');
      }

      const json = await res.json();
      if (seq !== requestSeq.current) return;
      setAppointments(Array.isArray(json.data) ? json.data : []);
      setMeta({
        current_page: json.current_page ?? 1,
        last_page: json.last_page ?? 1,
        total: json.total ?? 0,
      });
      setLastSynced(new Date());
      setError('');
      setLoadedKey(queryKey);
    } catch (err) {
      if (!isPolling && seq === requestSeq.current) setError(err instanceof Error ? err.message : 'Failed to fetch appointments');
    } finally {
      if (!isPolling && seq === requestSeq.current) setLoadedKey(queryKey);
    }
  }, [date, dateMode, status, salonId, debouncedSearch, page, perPage, sort, queryKey, router]);

  useEffect(() => {
    fetch('/api/proxy/superadmin/salons?per_page=100')
      .then((res) => (res.ok ? res.json() : null))
      .then((json) => json && setSalons(json.data || []))
      .catch((e) => console.error('Failed to fetch salons', e));
  }, []);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- state is only set after the network responds
    fetchAppointments();

    // Near-real-time: poll while the tab is visible, catch up when it returns.
    const intervalId = setInterval(() => {
      if (!document.hidden) fetchAppointments(true);
    }, POLL_MS);
    const onVisible = () => {
      if (!document.hidden) fetchAppointments(true);
    };
    document.addEventListener('visibilitychange', onVisible);

    return () => {
      clearInterval(intervalId);
      document.removeEventListener('visibilitychange', onVisible);
    };
  }, [fetchAppointments]);

  // Keep an open drawer in sync with the latest poll.
  const liveDetails = useMemo(
    () => (detailsAppointment ? appointments.find((a) => a.id === detailsAppointment.id) ?? detailsAppointment : null),
    [appointments, detailsAppointment],
  );

  const handleAddService = async (e: React.FormEvent) => {
    e.preventDefault();
    setAddServiceError('');

    try {
      const res = await fetch(`/api/proxy/superadmin/appointments/${selectedAppointmentId}/add-service`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        body: JSON.stringify({
          service_id: serviceId,
          provider_id: providerId
        })
      });

      const data = await res.json();

      if (res.ok) {
        setIsAddServiceModalOpen(false);
        setServiceId('');
        setProviderId('');
        fetchAppointments();
      } else {
        if (res.status === 401) {
          router.push('/login');
          return;
        }
        setAddServiceError(data.message || 'Failed to add service.');
      }
    } catch (err) {
      setAddServiceError(err instanceof Error ? err.message : 'Failed to add service.');
    }
  };

  const openDetails = (apt: Appointment) => {
    setDetailsAppointment(apt);
    setActiveDetailsTab('overview');
  };

  const resetPage = <T,>(setter: (v: T) => void) => (v: T) => {
    setter(v);
    setPage(1);
  };

  // asc -> desc -> unsorted, and always back to page 1.
  const onSortColumn = (key: string) => {
    setSort((prev) => {
      if (prev?.key !== key) return { key, dir: 'asc' };
      if (prev.dir === 'asc') return { key, dir: 'desc' };
      return null;
    });
    setPage(1);
  };

  const exportPage = () =>
    downloadCSV(
      `appointments-${dateMode === 'specific' ? date : dateMode}.csv`,
      ['Date', 'Start', 'End', 'Customer', 'Phone', 'Salon', 'Staff', 'Services', 'Source', 'Status', 'Total', 'Advance', 'Balance', 'Final billed'],
      appointments.map((a) => [
        a.appointment_date?.slice(0, 10), a.start_time, a.end_time ?? '', customerName(a), customerPhone(a) ?? '',
        a.salon?.name, providerName(a) ?? '', serviceNames(a).join(' | '), sourceLabel(a.booking_source),
        statusMeta(a.status).label, a.total_amount, a.advance_amount ?? '', a.balance_amount ?? '', a.final_billed_amount ?? '',
      ]),
    );

  // 3 days back to 10 days ahead, anchored on today.
  const today = localISODate();
  const dateStrip = useMemo(() => Array.from({ length: 14 }, (_, i) => addDays(today, i - 3)), [today]);
  const stripRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    stripRef.current
      ?.querySelector<HTMLElement>('[data-selected="true"]')
      ?.scrollIntoView({ block: 'nearest', inline: 'center', behavior: 'smooth' });
  }, [date, dateMode]);

  const rangeTitle =
    dateMode === 'specific'
      ? date === today ? 'Today' : dayLabel(date)
      : dateMode === 'week' ? 'Next 7 days' : dateMode === 'month' ? 'This month' : 'All time';

  return (
    <div className={styles.container}>
      <PageHeader
        eyebrow="Operations"
        title="Appointments"
        subtitle="Every booking across every salon, updated live."
        actions={
          <>
            <span className={styles.liveTag} title={lastSynced ? `Last synced ${lastSynced.toLocaleTimeString('en-IN')}` : undefined}>
              <span className={styles.liveDot} />
              Live
              {lastSynced && (
                <span className={styles.liveTime}>
                  {lastSynced.toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit', second: '2-digit' })}
                </span>
              )}
            </span>
            <Button icon="download" onClick={exportPage} disabled={appointments.length === 0}>
              Export
            </Button>
          </>
        }
      />

      {/* ---------------------------------------------------------- filters */}
      <Card className={styles.filters}>
        <div className={styles.filterRow}>
          <Segmented<DateMode>
            ariaLabel="Date range"
            value={dateMode}
            onChange={resetPage(setDateMode)}
            options={[
              { value: 'specific', label: 'Day' },
              { value: 'week', label: 'Next 7 days' },
              { value: 'month', label: 'This month' },
              { value: 'lifetime', label: 'All time' },
            ]}
          />
          <select
            className={cx(ui.control, styles.salonSelect)}
            value={salonId}
            onChange={(e) => resetPage(setSalonId)(e.target.value)}
            aria-label="Salon"
          >
            <option value="">All salons</option>
            {salons.map((s) => (
              <option key={s.id} value={s.id}>{s.name}</option>
            ))}
          </select>
          <SearchInput
            className={styles.search}
            value={search}
            onChange={resetPage(setSearch)}
            placeholder="Search customer, phone or salon…"
          />
        </div>

        {dateMode === 'specific' && (
          <div className={styles.stripRow}>
            <IconButton icon="chevronLeft" label="Previous day" onClick={() => resetPage(setDate)(addDays(date, -1))} />
            <div className={styles.dateStrip} ref={stripRef}>
              {dateStrip.map((iso) => {
                const d = parseDay(iso);
                const selected = iso === date;
                const isToday = iso === today;
                return (
                  <button
                    key={iso}
                    type="button"
                    data-selected={selected}
                    className={cx(styles.dateCard, selected && styles.dateCardSelected, isToday && styles.dateCardToday)}
                    onClick={() => resetPage(setDate)(iso)}
                    aria-pressed={selected}
                    aria-label={d.toLocaleDateString('en-IN', { weekday: 'long', day: 'numeric', month: 'long' })}
                  >
                    <span className={styles.dateCardDay}>{isToday ? 'Today' : d.toLocaleDateString('en-IN', { weekday: 'short' })}</span>
                    <span className={styles.dateCardNum}>{d.getDate()}</span>
                    <span className={styles.dateCardMonth}>{d.toLocaleDateString('en-IN', { month: 'short' })}</span>
                  </button>
                );
              })}
            </div>
            <IconButton icon="chevronRight" label="Next day" onClick={() => resetPage(setDate)(addDays(date, 1))} />
            <label className={styles.pickDate} title="Pick any date">
              <Icon name="calendar" size={17} />
              <input
                type="date"
                value={date}
                onChange={(e) => e.target.value && resetPage(setDate)(e.target.value)}
                aria-label="Pick a date"
              />
            </label>
            {date !== today && (
              <Button size="sm" variant="soft" onClick={() => resetPage(setDate)(today)}>Today</Button>
            )}
          </div>
        )}
      </Card>

      {/* ------------------------------------------------------------ table */}
      <Card>
        <div className={styles.tableHead}>
          <div>
            <h2 className={ui.cardTitle}>{rangeTitle}</h2>
            <p className={ui.cardSubtitle}>
              {meta ? `${meta.total.toLocaleString('en-IN')} appointment${meta.total === 1 ? '' : 's'}` : 'Loading…'}
              {salonId && salons.length > 0 && ` · ${salons.find((s) => s.id === salonId)?.name ?? ''}`}
            </p>
          </div>
          <Segmented
            ariaLabel="Status"
            value={status}
            onChange={resetPage(setStatus)}
            options={STATUS_FILTERS}
          />
        </div>

        {error && (
          <div className={styles.alertWrap}>
            <Alert tone="error">
              {error} <button type="button" className={styles.linkBtn} onClick={() => fetchAppointments()}>Retry</button>
            </Alert>
          </div>
        )}

        <div className={ui.tableWrap}>
          <table className={ui.table}>
            <thead>
              <tr>
                <SortHeader label="Time" active={sort?.key === 'start_time'} dir={sort?.key === 'start_time' ? sort.dir : null} onClick={() => onSortColumn('start_time')} />
                <SortHeader label="Customer" active={sort?.key === 'customer'} dir={sort?.key === 'customer' ? sort.dir : null} onClick={() => onSortColumn('customer')} />
                <SortHeader label="Salon" active={sort?.key === 'salon'} dir={sort?.key === 'salon' ? sort.dir : null} onClick={() => onSortColumn('salon')} />
                <th>Staff</th>
                <th>Services</th>
                <th>Source</th>
                <SortHeader label="Status" active={sort?.key === 'status'} dir={sort?.key === 'status' ? sort.dir : null} onClick={() => onSortColumn('status')} />
                <SortHeader label="Amount" align="right" active={sort?.key === 'amount'} dir={sort?.key === 'amount' ? sort.dir : null} onClick={() => onSortColumn('amount')} />
                <th aria-label="Open" />
              </tr>
            </thead>
            <tbody>
              {loading && appointments.length === 0 ? (
                Array.from({ length: 6 }, (_, i) => (
                  <tr key={i}>
                    <td><Skeleton width={70} /><div style={{ height: 6 }} /><Skeleton width={90} height={10} /></td>
                    <td><div className={ui.personCell}><Skeleton width={34} height={34} radius={11} /><Skeleton width={110} /></div></td>
                    <td><Skeleton width={120} /></td>
                    <td><Skeleton width={70} /></td>
                    <td><Skeleton width={140} /></td>
                    <td><Skeleton width={80} /></td>
                    <td><Skeleton width={84} height={22} radius={999} /></td>
                    <td><Skeleton width={70} /></td>
                    <td />
                  </tr>
                ))
              ) : appointments.length === 0 ? (
                <tr>
                  <td colSpan={9}>
                    <EmptyState
                      icon="calendar"
                      title={debouncedSearch || status || salonId ? 'No appointments match these filters' : 'No appointments in this range'}
                      hint={debouncedSearch || status || salonId ? 'Try clearing the search or picking another status.' : 'Bookings will appear here the moment they are made.'}
                      action={(debouncedSearch || status || salonId) ? (
                        <Button size="sm" onClick={() => { setSearch(''); setStatus(''); setSalonId(''); setPage(1); }}>
                          Clear filters
                        </Button>
                      ) : undefined}
                    />
                  </td>
                </tr>
              ) : (
                appointments.map((apt) => {
                  const names = serviceNames(apt);
                  const source = SOURCE_META[apt.booking_source ?? ''];
                  const reassigned =
                    apt.serving_provider?.user?.name &&
                    apt.appointed_provider?.user?.name &&
                    apt.serving_provider.user.name !== apt.appointed_provider.user.name;
                  return (
                    <tr key={apt.id} {...clickableRow(() => openDetails(apt))} aria-label={`Appointment for ${customerName(apt)}`}>
                      <td>
                        <div className={cx(ui.cellPrimary, ui.num)}>{clock(apt.start_time)}</div>
                        <div className={ui.cellSub}>
                          {dateMode === 'specific' ? (apt.end_time ? `until ${clock(apt.end_time)}` : '') : dayLabel(apt.appointment_date)}
                        </div>
                      </td>
                      <td>
                        <Person name={customerName(apt)} sub={customerPhone(apt) ?? (apt.customer ? undefined : 'Walk-in guest')} size={34} />
                      </td>
                      <td>
                        <button
                          type="button"
                          className={styles.salonLink}
                          onClick={(e) => {
                            e.stopPropagation();
                            setInfoModalData({ type: 'salon', data: apt.salon });
                          }}
                        >
                          {apt.salon?.name}
                        </button>
                      </td>
                      <td>
                        {providerName(apt) || <span className={styles.muted}>Unassigned</span>}
                        {reassigned && <div className={ui.cellSub}>booked with {apt.appointed_provider?.user?.name}</div>}
                      </td>
                      <td>
                        {names.length === 0 ? (
                          <span className={styles.muted}>—</span>
                        ) : (
                          <div className={styles.chips}>
                            {names.slice(0, 2).map((n, i) => <span key={i} className={styles.chip}>{n}</span>)}
                            {names.length > 2 && <span className={cx(styles.chip, styles.chipMore)}>+{names.length - 2}</span>}
                          </div>
                        )}
                      </td>
                      <td>
                        <span className={styles.source}>
                          {source && <Icon name={source.icon} size={15} />}
                          {sourceLabel(apt.booking_source)}
                        </span>
                      </td>
                      <td><StatusBadge status={apt.status} /></td>
                      <td className={ui.alignRight}>
                        <div className={cx(ui.cellPrimary, ui.num)}>{money(apt.final_billed_amount ?? apt.total_amount)}</div>
                        {Number(apt.advance_amount) > 0 && OPEN_STATUSES.has(apt.status) && (
                          <div className={cx(ui.cellSub, ui.num)}>
                            {money(apt.advance_amount)} paid · {money(apt.balance_amount)} due
                          </div>
                        )}
                      </td>
                      <td className={styles.chevronCell}>
                        <Icon name="chevronRight" size={16} />
                        {ADD_SERVICE_ENABLED && apt.status === 'in_progress' && (
                          <Button
                            size="sm"
                            icon="plus"
                            onClick={(e) => {
                              e.stopPropagation();
                              setSelectedAppointmentId(apt.id);
                              setIsAddServiceModalOpen(true);
                            }}
                          >
                            Add service
                          </Button>
                        )}
                      </td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </table>
        </div>

        {meta && (
          <Pagination
            page={meta.current_page}
            lastPage={meta.last_page}
            total={meta.total}
            noun="appointments"
            onChange={setPage}
            perPage={perPage}
            onPerPageChange={(n) => { setPerPage(n); setPage(1); }}
            disabled={loading}
          />
        )}
      </Card>

      {/* ---------------------------------------------- add-service (hidden) */}
      <Modal
        open={isAddServiceModalOpen}
        onClose={() => setIsAddServiceModalOpen(false)}
        title="Add mid-appointment service"
        footer={
          <>
            <Button variant="ghost" onClick={() => setIsAddServiceModalOpen(false)}>Cancel</Button>
            <Button variant="primary" type="submit" form="addServiceForm">Add service</Button>
          </>
        }
      >
        {addServiceError && <div style={{ marginBottom: 14 }}><Alert tone="error">{addServiceError}</Alert></div>}
        <form id="addServiceForm" onSubmit={handleAddService} className={styles.formStack}>
          <Field label="Service ID">
            <input className={ui.control} value={serviceId} onChange={(e) => setServiceId(e.target.value)} required placeholder="Service UUID" />
          </Field>
          <Field label="Provider ID" hint="Who is performing this service?">
            <input className={ui.control} value={providerId} onChange={(e) => setProviderId(e.target.value)} required placeholder="Provider UUID" />
          </Field>
        </form>
      </Modal>

      {/* ------------------------------------------------ details drawer */}
      <Drawer
        open={!!liveDetails}
        onClose={() => setDetailsAppointment(null)}
        title="Appointment details"
        header={liveDetails && (
          <div className={styles.drawerHead}>
            <div className={styles.drawerHeadTop}>
              <StatusBadge status={liveDetails.status} />
              <span className={styles.drawerWhen}>
                {dayLabel(liveDetails.appointment_date)} · {clock(liveDetails.start_time)}
                {liveDetails.end_time ? ` – ${clock(liveDetails.end_time)}` : ''}
              </span>
            </div>
            <Person
              name={customerName(liveDetails)}
              sub={`${liveDetails.salon?.name ?? ''}${providerName(liveDetails) ? ` · with ${providerName(liveDetails)}` : ''}`}
              size={44}
            />
          </div>
        )}
        footer={
          liveDetails && (
            <>
              <Link href={`/superadmin/salons/${liveDetails.salon?.id}`} className={cx(ui.btn, ui.btnGhost)}>
                Salon profile <Icon name="external" size={14} />
              </Link>
              <Button variant="primary" onClick={() => setDetailsAppointment(null)}>Done</Button>
            </>
          )
        }
      >
        {liveDetails && (
          <AppointmentDetails apt={liveDetails} tab={activeDetailsTab} onTab={setActiveDetailsTab} />
        )}
      </Drawer>

      {/* ------------------------------------------------ salon / customer info */}
      <Modal
        open={!!infoModalData}
        onClose={() => setInfoModalData(null)}
        size="sm"
        title={infoModalData?.type === 'salon' ? 'Salon' : 'Customer'}
        header={infoModalData && (
          <Person
            name={infoModalData.data.name}
            sub={infoModalData.type === 'salon' ? 'Salon' : 'Customer'}
            size={44}
          />
        )}
        footer={
          infoModalData?.type === 'salon' && 'id' in infoModalData.data && infoModalData.data.id ? (
            <Link href={`/superadmin/salons/${infoModalData.data.id}`} className={cx(ui.btn, ui.btnPrimary)}>
              View full profile <Icon name="arrowRight" size={15} />
            </Link>
          ) : (
            <Button variant="primary" onClick={() => setInfoModalData(null)}>Close</Button>
          )
        }
      >
        {infoModalData && (
          <DescriptionList
            items={[
              ['Phone', infoModalData.data.phone || '—'],
              ['Email', infoModalData.data.email || '—'],
              ...(infoModalData.type === 'salon'
                ? ([
                    ['Address', (infoModalData.data as SalonRef).address || '—'],
                    ['Status', (infoModalData.data as SalonRef).status || '—'],
                  ] as [string, string][])
                : []),
            ]}
          />
        )}
      </Modal>
    </div>
  );
}

/* --------------------------------------------------------------- drawer body */

function AppointmentDetails({ apt, tab, onTab }: { apt: Appointment; tab: DetailsTab; onTab: (t: DetailsTab) => void }) {
  const lines = apt.services || [];
  const additions = apt.service_additions || [];

  const timeline: { label: string; at?: string | null; note?: string; tone: Tone }[] = [
    { label: 'Booked', at: apt.created_at, note: sourceLabel(apt.booking_source), tone: 'info' },
    ...(apt.rescheduled_from_id ? [{ label: 'Rescheduled', at: null, note: apt.reschedule_reason || undefined, tone: 'warning' as Tone }] : []),
    ...(apt.qr_verified_at ? [{ label: 'Checked in', at: apt.qr_verified_at, note: verificationLabel(apt.verification_method), tone: 'accent' as Tone }] : []),
    ...(apt.started_at ? [{ label: 'Service started', at: apt.started_at, tone: 'accent' as Tone }] : []),
    ...(apt.completed_at ? [{ label: 'Completed', at: apt.completed_at, tone: 'success' as Tone }] : []),
    ...(apt.no_show_at ? [{ label: 'Marked no-show', at: apt.no_show_at, tone: 'danger' as Tone }] : []),
    ...(apt.cancelled_at
      ? [{
          label: 'Cancelled',
          at: apt.cancelled_at,
          note: [apt.cancelled_by && `by ${apt.cancelled_by}`, apt.cancelled_by_user?.name, apt.cancellation_reason].filter(Boolean).join(' · '),
          tone: 'neutral' as Tone,
        }]
      : []),
    ...(apt.salon_closure_id
      ? [{
          label: 'Released by salon closure',
          at: apt.closure_notified_at,
          note: [apt.salon_closure?.closed_date, apt.salon_closure?.reason].filter(Boolean).join(' — ') || 'Emergency closure',
          tone: 'warning' as Tone,
        }]
      : []),
  ];

  return (
    <>
      <div className={styles.moneyRow}>
        <div className={styles.moneyCell}>
          <span>Total</span>
          <b>{money(apt.total_amount)}</b>
        </div>
        <div className={styles.moneyCell}>
          <span>Advance</span>
          <b>{money(apt.advance_amount)}</b>
        </div>
        <div className={styles.moneyCell}>
          <span>{apt.final_billed_amount ? 'Final billed' : 'Balance due'}</span>
          <b>{money(apt.final_billed_amount ?? apt.balance_amount)}</b>
        </div>
      </div>

      <Tabs<DetailsTab>
        value={tab}
        onChange={onTab}
        tabs={[
          { value: 'overview', label: 'Overview' },
          { value: 'services', label: `Services (${lines.length + additions.length})` },
          { value: 'payment', label: 'Payment' },
          { value: 'timeline', label: 'Timeline' },
        ]}
      />

      <div className={styles.tabBody}>
        {tab === 'overview' && (
          <>
            <h3 className={ui.sectionLabel}>Customer</h3>
            <DescriptionList
              items={[
                ['Name', customerName(apt)],
                ['Phone', customerPhone(apt) || '—'],
                ['Email', apt.customer?.email || '—'],
                ...(!apt.customer ? ([['Gender', apt.walk_in_customer_gender || '—']] as [string, string][]) : []),
              ]}
            />
            <h3 className={ui.sectionLabel}>Salon &amp; staff</h3>
            <DescriptionList
              items={[
                ['Salon', apt.salon?.name || '—'],
                ['Salon phone', apt.salon?.phone || '—'],
                ['Address', apt.salon?.address || '—'],
                ['Booked with', `${apt.appointed_provider?.user?.name || 'Unassigned'}${apt.appointed_provider?.user?.phone ? ` · ${apt.appointed_provider.user.phone}` : ''}`],
                ['Served by', `${apt.serving_provider?.user?.name || 'Not started'}${apt.serving_provider?.user?.phone ? ` · ${apt.serving_provider.user.phone}` : ''}`],
              ]}
            />
            <h3 className={ui.sectionLabel}>Booking</h3>
            <DescriptionList
              items={[
                ['Appointment ID', <span key="id" className={ui.mono}>{apt.id}</span>],
                ['Source', sourceLabel(apt.booking_source)],
                ['Booked on', dateTime(apt.created_at)],
              ]}
            />
          </>
        )}

        {tab === 'services' && (
          lines.length === 0 && additions.length === 0 ? (
            <EmptyState icon="catalog" title="No service lines recorded" />
          ) : (
            <ul className={styles.serviceList}>
              {lines.map((line) => (
                <li key={line.id} className={styles.serviceItem}>
                  <div className={styles.serviceMain}>
                    <div className={ui.cellPrimary}>
                      {serviceName(line)}
                      {line.combo_id && <span className={styles.tag}>Package</span>}
                    </div>
                    <div className={ui.cellSub}>
                      {line.serving_provider?.user?.name || providerName(apt) || 'Unassigned'}
                      {line.duration_minutes_at_booking ? ` · ${line.duration_minutes_at_booking} min` : ''}
                      {line.line_status ? ` · ${line.line_status.replace(/_/g, ' ')}` : ''}
                    </div>
                  </div>
                  <div className={styles.servicePrice}>
                    <b className={ui.num}>{money(line.price_at_booking)}</b>
                    {line.original_service_price !== undefined &&
                      Number(line.original_service_price) !== Number(line.price_at_booking) && (
                        <s className={ui.cellSub}>{money(line.original_service_price)}</s>
                      )}
                  </div>
                </li>
              ))}
              {additions.map((add) => (
                <li key={add.id} className={cx(styles.serviceItem, add.status === 'voided' && styles.serviceVoided)}>
                  <div className={styles.serviceMain}>
                    <div className={ui.cellPrimary}>
                      {serviceName(add)}
                      <span className={styles.tag}>Added</span>
                    </div>
                    <div className={ui.cellSub}>
                      {add.provider?.user?.name || '—'}
                      {add.duration_minutes_at_addition ? ` · ${add.duration_minutes_at_addition} min` : ''}
                      {/* Reads as a line status so a settled extra matches the booked lines beside it. */}
                      {` · ${add.status === 'voided' ? 'removed' : (add.status || '—')}`}
                      {add.added_by?.name && ` · by ${add.added_by.name}${add.added_at ? `, ${dateTime(add.added_at)}` : ''}`}
                    </div>
                  </div>
                  <div className={styles.servicePrice}>
                    <b className={ui.num}>{money(add.price_at_addition)}</b>
                  </div>
                </li>
              ))}
            </ul>
          )
        )}

        {tab === 'payment' && (
          <DescriptionList
            items={[
              ['Option', apt.payment_option?.replace(/_/g, ' ') || '—'],
              ['Total', money(apt.total_amount)],
              ['Advance paid', money(apt.advance_amount)],
              ['Balance due', money(apt.balance_amount)],
              ['Final billed', money(apt.final_billed_amount)],
            ]}
          />
        )}

        {tab === 'timeline' && (
          <ol className={styles.timeline}>
            {timeline.map((ev, i) => (
              <li key={i} className={styles.timelineItem}>
                <span className={cx(styles.timelineDot, styles[`dot_${ev.tone}`])} />
                <div>
                  <div className={ui.cellPrimary}>{ev.label}</div>
                  <div className={ui.cellSub}>
                    {ev.at ? dateTime(ev.at) : ''}
                    {ev.at && ev.note ? ' · ' : ''}
                    {ev.note}
                  </div>
                </div>
              </li>
            ))}
            {apt.rescheduled_from_id && (
              <li className={styles.timelineFoot}>
                Rescheduled from <span className={ui.mono}>{apt.rescheduled_from_id}</span>
              </li>
            )}
          </ol>
        )}
      </div>
    </>
  );
}
