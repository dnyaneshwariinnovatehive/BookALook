'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import {
  Alert, Badge, Button, DataTable, DescriptionList, Drawer, PageHeader, SearchInput, Segmented, StatCard,
  cx, formatINR, useConfirm, type DataColumn, type Tone,
} from '@/components/admin/ui';
import styles from './dues.module.css';

/**
 * Commission Model salons that owe BookALook, where each one stands on the
 * ladder set in Policy → Commission dues, and the controls for one salon:
 * push its due date out, pause the steps, apply a step by hand, remind the
 * owner, or record a payment made outside the app.
 */

type Step = 'reminder' | 'banner' | 'force_advance' | 'deduct' | 'stop_bookings' | 'full_lock';

interface DuesState {
  applies: boolean;
  owed: number;
  payouts: number;
  under_review: number;
  oldest_cycle_end: string | null;
  due_date: string | null;
  scheduled_due_date: string | null;
  days_overdue: number | null;
  actions: Step[];
  stage: Step | null;
  next: { step: Step; label: string; on: string } | null;
  paused: boolean;
  extended_until: string | null;
  override: Step | 'none' | null;
  override_reason: string | null;
  below_minimum: boolean;
}

interface Row {
  salon: {
    id: string;
    name: string;
    city: string | null;
    status: string;
    owner: { name: string; phone: string } | null;
    commission_percentage: number;
  };
  state: DuesState;
  last_reminded_at: string | null;
}

type Filter = 'all' | 'overdue' | 'restricted' | 'controlled';

const STEP_TONE: Record<Step, Tone> = {
  reminder: 'info',
  banner: 'warning',
  force_advance: 'warning',
  deduct: 'warning',
  stop_bookings: 'danger',
  full_lock: 'danger',
};

const STEP_ORDER: Step[] = ['reminder', 'banner', 'force_advance', 'deduct', 'stop_bookings', 'full_lock'];

const fmtDay = (v: string | null) =>
  v ? new Date(`${v}T00:00:00`).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' }) : '—';
const fmtWhen = (v: string | null) =>
  v ? new Date(v).toLocaleString('en-IN', { day: '2-digit', month: 'short', hour: 'numeric', minute: '2-digit' }) : 'Never';
const tomorrow = () => {
  const d = new Date();
  d.setDate(d.getDate() + 1);
  return d.toISOString().slice(0, 10);
};

const overdueText = (s: DuesState) => {
  if (s.days_overdue === null) return '—';
  if (s.days_overdue < 0) return `due in ${-s.days_overdue} day${s.days_overdue === -1 ? '' : 's'}`;
  if (s.days_overdue === 0) return 'due today';
  return `${s.days_overdue} day${s.days_overdue === 1 ? '' : 's'} overdue`;
};

export default function CommissionDuesPage() {
  const [rows, setRows] = useState<Row[]>([]);
  const [labels, setLabels] = useState<Record<Step, string>>({} as Record<Step, string>);
  const [summary, setSummary] = useState({ salons: 0, owed: 0, overdue: 0, under_review: 0, by_stage: {} as Record<Step, number> });
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [filter, setFilter] = useState<Filter>('all');
  const [search, setSearch] = useState('');
  const [selected, setSelected] = useState<Row | null>(null);
  const [busy, setBusy] = useState(false);
  const [confirm, confirmDialog] = useConfirm();

  // Drawer form state
  const [until, setUntil] = useState('');
  const [reason, setReason] = useState('');
  const [stage, setStage] = useState('automatic');
  const [reference, setReference] = useState('');

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await fetch('/api/proxy/superadmin/commission-dues', { cache: 'no-store' });
      const json = await res.json();
      if (!res.ok || !json.success) throw new Error(json.message || 'Could not load overdue salons.');
      setRows(json.data);
      setSummary(json.summary);
      setLabels(json.labels);
      setError('');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not load overdue salons.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    const t = setTimeout(load, 0);
    return () => clearTimeout(t);
  }, [load]);

  const open = (r: Row) => {
    setSelected(r);
    setUntil(r.state.extended_until ?? '');
    setReason('');
    setStage(r.state.override ?? 'automatic');
    setReference('');
  };

  const post = async (path: string, body: object, done?: string) => {
    if (!selected) return;
    setBusy(true);
    try {
      const res = await fetch(`/api/proxy/superadmin/commission-dues/${selected.salon.id}/${path}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });
      const json = await res.json();
      if (!res.ok || !json.success) {
        const first = json.errors ? Object.values(json.errors as Record<string, string[]>)[0]?.[0] : null;
        throw new Error(first || json.message || 'That did not work.');
      }
      setNotice(done ?? json.message);
      if (json.row) setSelected(json.row);
      load();
    } catch (e) {
      setNotice('');
      setError(e instanceof Error ? e.message : 'That did not work.');
    } finally {
      setBusy(false);
    }
  };

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    return rows.filter((r) => {
      if (q && !`${r.salon.name} ${r.salon.city ?? ''} ${r.salon.owner?.name ?? ''}`.toLowerCase().includes(q)) return false;
      if (filter === 'overdue') return (r.state.days_overdue ?? -1) >= 0;
      if (filter === 'restricted') return r.state.actions.some((a) => a === 'stop_bookings' || a === 'full_lock');
      if (filter === 'controlled') return r.state.paused || !!r.state.override || !!r.state.extended_until;
      return true;
    });
  }, [rows, filter, search]);

  const stepBadge = (s: DuesState) => {
    if (s.paused) return <Badge tone="neutral">Paused</Badge>;
    if (s.below_minimum) return <Badge tone="neutral">Below minimum</Badge>;
    if (!s.stage) return <Badge tone="neutral">{s.under_review > 0 && !s.applies ? 'Payment under review' : 'No step yet'}</Badge>;
    return <Badge tone={STEP_TONE[s.stage]} pulse={s.stage === 'full_lock'}>{labels[s.stage] ?? s.stage}</Badge>;
  };

  const columns: DataColumn<Row>[] = [
    {
      key: 'salon',
      header: 'Salon',
      render: (r) => (
        <div className={styles.salonCell}>
          <b>{r.salon.name}</b>
          <span>{[r.salon.city, r.salon.owner?.name].filter(Boolean).join(' · ')}</span>
        </div>
      ),
      sortValue: (r) => r.salon.name,
    },
    {
      key: 'owed',
      header: 'Owes',
      align: 'right',
      render: (r) => (
        <div className={styles.owedCell}>
          <b>{formatINR(r.state.owed)}</b>
          <span>
            {r.state.payouts} cycle{r.state.payouts === 1 ? '' : 's'}
            {r.state.under_review > 0 ? ` · ${r.state.under_review} under review` : ''}
          </span>
        </div>
      ),
      sortValue: (r) => r.state.owed,
    },
    {
      key: 'due',
      header: 'Due',
      render: (r) => (
        <div className={styles.dueCell}>
          <b className={(r.state.days_overdue ?? -1) >= 0 ? styles.late : ''}>{overdueText(r.state)}</b>
          <span>
            {fmtDay(r.state.due_date)}
            {r.state.extended_until ? ' · extended' : ''}
          </span>
        </div>
      ),
      sortValue: (r) => r.state.days_overdue ?? -999,
    },
    {
      key: 'stage',
      header: 'Current step',
      render: (r) => (
        <div className={styles.stageCell}>
          {stepBadge(r.state)}
          {r.state.override && <span className={styles.manual}>set by hand</span>}
        </div>
      ),
      sortValue: (r) => (r.state.stage ? STEP_ORDER.indexOf(r.state.stage) : -1),
      csvValue: (r) => (r.state.stage ? labels[r.state.stage] : ''),
    },
    {
      key: 'next',
      header: 'Next',
      render: (r) =>
        r.state.next ? (
          <div className={styles.nextCell}>
            <span>{r.state.next.label}</span>
            <small>{fmtDay(r.state.next.on)}</small>
          </div>
        ) : (
          <span className={styles.muted}>—</span>
        ),
      csvValue: (r) => (r.state.next ? `${r.state.next.label} on ${r.state.next.on}` : ''),
    },
  ];

  const s = selected?.state;

  return (
    <div className={styles.page}>
      <PageHeader
        eyebrow="Salons"
        title="Overdue salons"
        subtitle="Commission Model salons that owe BookALook. Steps follow Policy → Commission dues and lift by themselves once the salon pays."
        actions={<Link href="/superadmin/settings/policy" className={styles.policyLink}>Edit the steps</Link>}
      />

      {notice && <Alert tone="success" onClose={() => setNotice('')}>{notice}</Alert>}
      {error && <Alert tone="error" onClose={() => setError('')}>{error}</Alert>}

      <div className={styles.stats}>
        <StatCard label="Salons owing" value={summary.salons} icon="store" loading={loading && rows.length === 0} />
        <StatCard label="Total owed" value={formatINR(summary.owed)} icon="rupee" tone="warning" loading={loading && rows.length === 0} />
        <StatCard label="Past due date" value={summary.overdue} icon="clock" tone="danger" loading={loading && rows.length === 0}
          sub={`${summary.under_review} payment${summary.under_review === 1 ? '' : 's'} under review`} />
        <StatCard
          label="Bookings stopped / locked"
          value={`${summary.by_stage?.stop_bookings ?? 0} / ${summary.by_stage?.full_lock ?? 0}`}
          icon="alert"
          tone="danger"
          loading={loading && rows.length === 0}
        />
      </div>

      <DataTable
        columns={columns}
        rows={filtered}
        rowKey={(r) => r.salon.id}
        loading={loading && rows.length === 0}
        noun="salons"
        exportName="overdue-salons"
        onRowClick={open}
        empty={{
          title: rows.length === 0 ? 'No salon owes commission' : 'No salon matches',
          hint: rows.length === 0
            ? 'Commission Model salons appear here when a closed month leaves them owing BookALook.'
            : 'Try another filter or clear the search.',
        }}
        toolbar={
          <div className={styles.toolbar}>
            <Segmented<Filter>
              ariaLabel="Show"
              value={filter}
              onChange={setFilter}
              options={[
                { value: 'all', label: 'All', count: rows.length },
                { value: 'overdue', label: 'Past due', count: rows.filter((r) => (r.state.days_overdue ?? -1) >= 0).length },
                { value: 'restricted', label: 'Stopped or locked', count: rows.filter((r) => r.state.actions.some((a) => a === 'stop_bookings' || a === 'full_lock')).length },
                { value: 'controlled', label: 'Overridden', count: rows.filter((r) => r.state.paused || !!r.state.override || !!r.state.extended_until).length },
              ]}
            />
            <SearchInput value={search} onChange={setSearch} placeholder="Search salon, city or owner" className={styles.search} />
          </div>
        }
      />

      <Drawer
        open={!!selected}
        onClose={() => setSelected(null)}
        title={selected?.salon.name ?? ''}
        description={selected ? `${formatINR(selected.state.owed)} owed · ${overdueText(selected.state)}` : undefined}
      >
        {selected && s && (
          <div className={styles.drawer}>
            <div className={styles.stageBox}>
              <div className={styles.stageNow}>
                <span>Now</span>
                {stepBadge(s)}
              </div>
              <div className={styles.ladder}>
                {STEP_ORDER.map((step) => (
                  <span key={step} className={s.actions.includes(step) ? styles.rungOn : styles.rung} title={labels[step]}>
                    {labels[step]}
                  </span>
                ))}
              </div>
              {s.next && (
                <p className={styles.nextLine}>
                  Next: <b>{s.next.label}</b> on {fmtDay(s.next.on)}
                </p>
              )}
              {s.override_reason && <p className={styles.reason}>Note: {s.override_reason}</p>}
            </div>

            <DescriptionList
              items={[
                ['Owner', selected.salon.owner ? `${selected.salon.owner.name} · ${selected.salon.owner.phone}` : '—'],
                ['Owes', `${formatINR(s.owed)} over ${s.payouts} cycle${s.payouts === 1 ? '' : 's'}`],
                ['Due', `${fmtDay(s.due_date)}${s.extended_until ? ` (was ${fmtDay(s.scheduled_due_date)})` : ''}`],
                ['Payments under review', String(s.under_review)],
                ['Last reminder', fmtWhen(selected.last_reminded_at)],
                ['Settlements', <Link key="p" href="/superadmin/payouts">Open Payouts</Link>],
              ]}
            />

            <section className={styles.block}>
              <h3>Extend the due date</h3>
              <div className={styles.inline}>
                <input type="date" className={styles.input} min={tomorrow()} value={until} onChange={(e) => setUntil(e.target.value)} />
                <Button
                  onClick={() => post('extend', { until, reason: reason || 'Extended by SuperAdmin' })}
                  disabled={busy || !until}
                >
                  Extend
                </Button>
              </div>
              <p className={styles.help}>Every step moves back by the same amount. The owner is told the new date.</p>
            </section>

            <section className={styles.block}>
              <h3>Apply a step by hand</h3>
              <div className={styles.inline}>
                <select className={styles.input} value={stage} onChange={(e) => setStage(e.target.value)}>
                  <option value="automatic">Automatic (follow the schedule)</option>
                  <option value="none">No steps at all</option>
                  {STEP_ORDER.map((step) => <option key={step} value={step}>Up to: {labels[step]}</option>)}
                </select>
                <Button onClick={() => post('stage', { stage, reason: reason || undefined })} disabled={busy}>Apply</Button>
              </div>
              <p className={styles.help}>Stays until you change it or the salon pays. A stricter step tells the owner.</p>
            </section>

            <section className={styles.block}>
              <h3>Note (optional)</h3>
              <textarea
                className={styles.textarea}
                rows={2}
                maxLength={500}
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                placeholder="Why — saved with extensions, pauses and manual steps, and in the audit log."
              />
            </section>

            <div className={styles.buttons}>
              <Button onClick={() => post('pause', { paused: !s.paused, reason: reason || undefined })} disabled={busy}>
                {s.paused ? 'Resume steps' : 'Pause all steps'}
              </Button>
              <Button icon="bell" onClick={() => post('remind', {})} disabled={busy || !s.applies}>Send reminder now</Button>
            </div>

            <section className={cx(styles.block, styles.payBlock)}>
              <h3>Record a payment</h3>
              <p className={styles.help}>Money received outside the app (cash, bank transfer, UPI). Settles all {s.payouts} cycle{s.payouts === 1 ? '' : 's'} and lifts every step.</p>
              <div className={styles.inline}>
                <input className={styles.input} placeholder="Reference, e.g. UPI 4512…" value={reference} onChange={(e) => setReference(e.target.value)} />
                <Button
                  variant="primary"
                  disabled={busy || !reference.trim() || !s.applies}
                  onClick={async () => {
                    const ok = await confirm({
                      title: `Record ${formatINR(s.owed)} from ${selected.salon.name}?`,
                      body: 'This marks every cycle the salon owes as paid. It cannot be undone from here.',
                      confirmLabel: 'Record payment',
                      tone: 'accent',
                    });
                    if (ok) post('record-payment', { reference: reference.trim(), note: reason || undefined });
                  }}
                >
                  Record payment
                </Button>
              </div>
            </section>
          </div>
        )}
      </Drawer>
      {confirmDialog}
    </div>
  );
}

