'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { Pagination, SortHeader } from '@/components/admin/ui';
import styles from './page.module.css';

type CycleType = 'weekly' | 'monthly';

interface Payout {
  id: string;
  salon_id: string;
  salon_name: string | null;
  cycle_type: CycleType;
  cycle_label: string;
  cycle_start_date: string;
  cycle_end_date: string;
  appointments_count: number;
  appointment_revenue: number;
  gross_amount: number;
  billing_type: string;
  billing_label: string;
  commission_percentage: number;
  commission_deducted: number;
  refund_adjustment: number;
  wallet_redeemed_amount: number;
  net_amount: number;
  status: string;
  distributed_at: string | null;
  distribution_reference: string | null;
}

interface Totals {
  salons: number;
  appointment_revenue: number;
  advances_held: number;
  commission_deducted: number;
  net_to_distribute: number;
  distributed: number;
}

/* Built from local parts: toISOString() shifts to UTC and can land a Monday
   on the Sunday before it. */
const toKey = (d: Date) =>
  `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;

/** Monday of the week containing `date`, as YYYY-MM-DD. */
const mondayOf = (date: Date) => {
  const d = new Date(date);
  const day = (d.getDay() + 6) % 7; // Monday = 0
  d.setDate(d.getDate() - day);
  return toKey(d);
};

/** First of the month containing `date`, as YYYY-MM-DD. */
const firstOf = (date: Date) => {
  const d = new Date(date);
  d.setDate(1);
  return toKey(d);
};

/** Where the cycle each arrangement settles on begins. */
const startOfCycle = (cycle: CycleType, date: Date) =>
  cycle === 'monthly' ? firstOf(date) : mondayOf(date);

const money = (value: number) =>
  `₹${Number(value ?? 0).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;


function getCycleOptions(type: CycleType) {
  const options: { value: string; label: string }[] = [];
  const now = new Date();

  if (type === 'weekly') {
    for (let i = 0; i < 24; i++) {
      const d = new Date(now);
      d.setDate(d.getDate() - (i * 7));
      const start = mondayOf(d);
      
      const sDate = new Date(start);
      const eDate = new Date(start);
      eDate.setDate(eDate.getDate() + 6);

      const sLabel = sDate.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
      const eLabel = eDate.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
      
      let label = `${sLabel} - ${eLabel}`;
      if (i === 0) label = `This week (${label})`;
      else if (i === 1) label = `Last week (${label})`;
      else label = `${i} weeks ago (${label})`;

      if (!options.find(o => o.value === start)) {
         options.push({ value: start, label });
      }
    }
  } else {
    for (let i = 0; i < 24; i++) {
      const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
      const start = firstOf(d);
      const mLabel = d.toLocaleDateString('en-US', { month: 'long', year: 'numeric' });
      
      let label = mLabel;
      if (i === 0) label = `This month (${label})`;
      else if (i === 1) label = `Last month (${label})`;

      if (!options.find(o => o.value === start)) {
         options.push({ value: start, label });
      }
    }
  }
  return options;
}

export default function PayoutsPage() {
  const lastWeek = new Date();
  lastWeek.setDate(lastWeek.getDate() - 7);

  const [cycleType, setCycleType] = useState<CycleType>('weekly');
  const [cycleStart, setCycleStart] = useState(mondayOf(lastWeek));
  const [statusFilter, setStatusFilter] = useState('');
  const [payouts, setPayouts] = useState<Payout[]>([]);
  const [totals, setTotals] = useState<Totals | null>(null);
  const [cycleEnd, setCycleEnd] = useState('');
  const [cycleLabel, setCycleLabel] = useState('');
  const [isLoading, setIsLoading] = useState(true);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [error, setError] = useState('');
  const [distributeTarget, setDistributeTarget] = useState<Payout | null>(null);
  const [distributeReference, setDistributeReference] = useState('');

  const [page, setPage] = useState(1);
  const [perPage, setPerPage] = useState(20);
  const [sort, setSort] = useState<{ key: string; dir: 'asc' | 'desc' } | null>(null);
  const [meta, setMeta] = useState({ current_page: 1, last_page: 1, per_page: 20, total: 0 });

  // Paging and header clicks can land out of order; only the newest request renders.
  const listSeq = useRef(0);

  const authHeaders = (): Record<string, string> => {
    return {
      'Content-Type': 'application/json',
    };
  };

  const fetchPayouts = useCallback(async () => {
    const seq = ++listSeq.current;
    setIsLoading(true);
    setError('');
    try {
      const query = new URLSearchParams({
        cycle_type: cycleType,
        cycle_start: cycleStart,
        page: String(page),
        per_page: String(perPage),
      });
      if (statusFilter) query.append('status', statusFilter);
      if (sort) {
        query.append('column', sort.key);
        query.append('direction', sort.dir);
      }

      const res = await fetch(`/api/proxy/superadmin/payouts?${query}`, { headers: authHeaders() });
      const data = await res.json();
      if (seq !== listSeq.current) return;

      if (!res.ok || !data.success) throw new Error(data.message || 'Could not load payouts.');

      setPayouts(Array.isArray(data?.payouts) ? data.payouts : []);
      setTotals(data.totals);
      setCycleEnd(data.cycle_end);
      setCycleLabel(data.cycle_label);
      if (data.meta) setMeta(data.meta);
    } catch (e: unknown) {
      if (seq !== listSeq.current) return;
      setError(e instanceof Error ? e.message : 'Could not load payouts.');
    } finally {
      if (seq === listSeq.current) setIsLoading(false);
    }
  }, [cycleType, cycleStart, statusFilter, page, perPage, sort]);

  useEffect(() => {
    const timer = setTimeout(fetchPayouts, 0);
    return () => clearTimeout(timer);
  }, [fetchPayouts]);

  /** asc -> desc -> unsorted, and always back to page 1. */
  const onSortColumn = (key: string) => {
    setSort((prev) => {
      if (prev?.key !== key) return { key, dir: 'asc' };
      if (prev.dir === 'asc') return { key, dir: 'desc' };
      return null;
    });
    setPage(1);
  };

  /* Recalculates the cycle from its completed appointments. */
  const generate = async () => {
    setBusyId('generate');
    setError('');
    try {
      const res = await fetch('/api/proxy/superadmin/payouts/generate', {
        method: 'POST',
        headers: authHeaders(),
        body: JSON.stringify({ cycle_type: cycleType, cycle_start: cycleStart }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.message || 'Could not calculate the cycle.');
      // The new cycle can be shorter than the page we were on.
      setPage(1);
      await fetchPayouts();
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : 'Could not calculate the cycle.');
    } finally {
      setBusyId(null);
    }
  };

  // Recalculate automatically whenever the cycle (type or start date) changes,
  // so the table stays in sync without having to press "Calculate" each time.
  // Skipped on first render — only reacts to an actual filter change.
  const mounted = useRef(false);
  useEffect(() => {
    if (!mounted.current) {
      mounted.current = true;
      return;
    }
    generate();
    // generate intentionally left out — it is recreated every render.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cycleType, cycleStart]);

  const confirmDistribute = (payout: Payout) => {
    setDistributeTarget(payout);
    setDistributeReference('');
  };

  const act = async (payout: Payout, action: 'approve' | 'distribute', reference?: string) => {
    setBusyId(payout.id);
    setError('');

    try {
      const res = await fetch(`/api/proxy/superadmin/payouts/${payout.id}/${action}`, {
        method: 'POST',
        headers: authHeaders(),
        body: JSON.stringify(action === 'distribute' ? { distribution_reference: reference ?? '' } : {}),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.message || 'That did not work.');
      await fetchPayouts();
      if (action === 'distribute') {
        setDistributeTarget(null);
      }
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : 'That did not work.');
    } finally {
      setBusyId(null);
    }
  };

  const statusPill = (status: string) => {
    const cls =
      status === 'distributed'
        ? styles.pillDistributed
        : status === 'approved'
          ? styles.pillApproved
          : styles.pillPending;
    return <span className={`${styles.pill} ${cls}`}>{status}</span>;
  };

  return (
    <div className={styles.container}>
      <h1 className={styles.title}>Payouts &amp; distribution</h1>
      <p style={{ color: 'var(--text-body)', fontSize: 14, marginTop: -8 }}>
        {cycleType === 'monthly'
          ? 'Monthly settlement for salons on the Commission Model, run on the 1st for the month just finished. Commission comes off inside this cycle, and settling extends the salon\u2019s access into the next month.'
          : 'Weekly settlement for salons on a Subscription Plan. They have already paid for access, so this only hands back the advances the platform collected on their behalf.'}
      </p>

      <div className={styles.toolbar}>
        <div className={styles.field}>
          <label htmlFor="cycle">Settlement run</label>
          <select
            id="cycle"
            value={cycleType}
            onChange={(e) => {
              const next = e.target.value as CycleType;
              setCycleType(next);
              // The same date sits in a different cycle depending on the
              // rhythm, so the anchor moves with it.
              setCycleStart(startOfCycle(next, new Date(cycleStart)));
              setPage(1);
            }}
          >
            <option value="weekly">Weekly &middot; Subscription Plan</option>
            <option value="monthly">Monthly &middot; Commission Model</option>
          </select>
        </div>

        <div className={styles.field}>
          <label htmlFor="cycle-start">
            {cycleType === 'monthly' ? 'Month' : 'Week'}
          </label>
          <select
            id="cycle-start"
            value={cycleStart}
            onChange={(e) => { setCycleStart(e.target.value); setPage(1); }}
          >
            {getCycleOptions(cycleType).map(opt => (
              <option key={opt.value} value={opt.value}>{opt.label}</option>
            ))}
          </select>
        </div>

        <div className={styles.field}>
          <label htmlFor="status">Status</label>
          <select
            id="status"
            value={statusFilter}
            onChange={(e) => { setStatusFilter(e.target.value); setPage(1); }}
          >
            <option value="">All</option>
            <option value="pending">Pending</option>
            <option value="approved">Approved</option>
            <option value="distributed">Distributed</option>
          </select>
        </div>

        <button className={styles.button} onClick={generate} disabled={busyId === 'generate'}>
          {busyId === 'generate'
            ? 'Calculating…'
            : cycleType === 'monthly'
              ? 'Calculate this month'
              : 'Calculate this week'}
        </button>
      </div>

      {cycleEnd && (
        <p style={{ color: 'var(--text-body)', fontSize: 13, marginTop: -8 }}>
          {cycleLabel} · {cycleStart} → {cycleEnd}
        </p>
      )}

      {error && <p style={{ color: 'var(--color-danger)' }}>{error}</p>}

      {totals && (
        <div className={styles.summaryGrid}>
          <div className={styles.summaryTile}>
            <div className={styles.summaryLabel}>Salons</div>
            <div className={styles.summaryValue}>{totals.salons}</div>
          </div>
          <div className={styles.summaryTile}>
            <div className={styles.summaryLabel}>Billed by salons</div>
            <div className={styles.summaryValue}>{money(totals.appointment_revenue)}</div>
          </div>
          <div className={styles.summaryTile}>
            <div className={styles.summaryLabel}>Advances held</div>
            <div className={styles.summaryValue}>{money(totals.advances_held)}</div>
          </div>
          <div className={styles.summaryTile}>
            <div className={styles.summaryLabel}>Commission earned</div>
            <div className={styles.summaryValue} style={{ color: 'var(--color-success)' }}>
              {money(totals.commission_deducted)}
            </div>
          </div>
          <div className={styles.summaryTile}>
            <div className={styles.summaryLabel}>Still to distribute</div>
            <div className={styles.summaryValue}>{money(totals.net_to_distribute)}</div>
          </div>
          <div className={styles.summaryTile}>
            <div className={styles.summaryLabel}>Distributed</div>
            <div className={styles.summaryValue} style={{ color: 'var(--color-success)' }}>
              {money(totals.distributed)}
            </div>
          </div>
        </div>
      )}

      {isLoading ? (
        <p>Loading…</p>
      ) : payouts.length === 0 ? (
        <div className={styles.card}>
          No {cycleType === 'monthly' ? 'Commission Model' : 'Subscription Plan'} payouts
          for this cycle yet — built from completed appointments as soon as the
          cycle has data.
        </div>
      ) : (
        <table className={styles.table}>
          <thead>
            <tr>
              <SortHeader label="Salon" active={sort?.key === 'salon'} dir={sort?.key === 'salon' ? sort.dir : null} onClick={() => onSortColumn('salon')} />
              <th>Billing</th>
              <SortHeader label="Appts" align="right" active={sort?.key === 'appointments_count'} dir={sort?.key === 'appointments_count' ? sort.dir : null} onClick={() => onSortColumn('appointments_count')} />
              <SortHeader label="Billed" align="right" active={sort?.key === 'appointment_revenue'} dir={sort?.key === 'appointment_revenue' ? sort.dir : null} onClick={() => onSortColumn('appointment_revenue')} />
              <SortHeader label="Advances held" align="right" active={sort?.key === 'gross_amount'} dir={sort?.key === 'gross_amount' ? sort.dir : null} onClick={() => onSortColumn('gross_amount')} />
              <SortHeader label="Commission earned" align="right" active={sort?.key === 'commission_deducted'} dir={sort?.key === 'commission_deducted' ? sort.dir : null} onClick={() => onSortColumn('commission_deducted')} />
              <th>Adjustments</th>
              <SortHeader label="Net payable" align="right" active={sort?.key === 'net_amount'} dir={sort?.key === 'net_amount' ? sort.dir : null} onClick={() => onSortColumn('net_amount')} />
              <SortHeader label="Status" active={sort?.key === 'status'} dir={sort?.key === 'status' ? sort.dir : null} onClick={() => onSortColumn('status')} />
              <th style={{ textAlign: 'right' }}>Action</th>
            </tr>
          </thead>
          <tbody>
            {payouts.map((p) => (
              <tr key={p.id}>
                <td>
                  <strong>{p.salon_name ?? '—'}</strong>
                  {p.distribution_reference && (
                    <>
                      <br />
                      <small style={{ color: 'var(--text-body)' }}>ref {p.distribution_reference}</small>
                    </>
                  )}
                </td>
                <td>
                  <span
                    className={`${styles.pill} ${
                      p.billing_type === 'commission' ? styles.pillCommission : styles.pillSubscription
                    }`}
                  >
                    {p.billing_label}
                  </span>
                </td>
                <td>{p.appointments_count}</td>
                <td>{money(p.appointment_revenue)}</td>
                <td>{money(p.gross_amount)}</td>
                <td className={p.commission_deducted > 0 ? styles.earned : undefined}>
                  {p.commission_deducted > 0 ? `+ ${money(p.commission_deducted)}` : '—'}
                  {p.commission_percentage > 0 && (
                    <>
                      <br />
                      <small style={{ color: 'var(--text-body)' }}>at {p.commission_percentage}%</small>
                    </>
                  )}
                </td>
                <td>
                  {p.refund_adjustment > 0 && (
                    <div className={styles.deduction}>− {money(p.refund_adjustment)} refunds</div>
                  )}
                  {p.wallet_redeemed_amount > 0 && (
                    <div style={{ color: 'var(--color-success)' }}>
                      + {money(p.wallet_redeemed_amount)} coins
                    </div>
                  )}
                  {p.refund_adjustment === 0 && p.wallet_redeemed_amount === 0 && '—'}
                </td>
                <td className={styles.net}>{money(p.net_amount)}</td>
                <td>{statusPill(p.status)}</td>
                <td style={{ textAlign: 'right' }}>
                  <div className={styles.rowActions} style={{ justifyContent: 'flex-end' }}>
                    {p.status === 'pending' && (
                      <button
                        className={styles.smallButton}
                        disabled={busyId === p.id}
                        onClick={() => act(p, 'approve')}
                      >
                        Approve
                      </button>
                    )}
                    {p.status !== 'distributed' && (
                      <button
                        className={`${styles.smallButton} ${styles.payButton}`}
                        disabled={busyId === p.id}
                        onClick={() => confirmDistribute(p)}
                      >
                        Distribute
                      </button>
                    )}
                    {p.status === 'distributed' && (
                      <small style={{ color: 'var(--text-body)' }}>
                        {p.distributed_at ? new Date(p.distributed_at).toLocaleDateString() : 'done'}
                      </small>
                    )}
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      {payouts.length > 0 && (
        <div className={styles.pager}>
          <Pagination
            page={meta.current_page}
            lastPage={meta.last_page}
            total={meta.total}
            noun="payouts"
            onChange={setPage}
            perPage={perPage}
            onPerPageChange={(n) => { setPerPage(n); setPage(1); }}
            disabled={isLoading}
          />
        </div>
      )}
    
      {distributeTarget && (
        <div className={styles.modalOverlay} onClick={() => setDistributeTarget(null)}>
          <div className={styles.modalContent} onClick={e => e.stopPropagation()} style={{ maxWidth: '460px' }}>
            <h2 style={{ fontSize: '1.25rem', fontWeight: 600, marginBottom: '16px' }}>Distribute Payout</h2>
            <p style={{ color: 'var(--text-strong)', fontSize: '0.95rem', marginBottom: '16px', lineHeight: 1.5 }}>
              Distribute <strong>{money(distributeTarget.net_amount)}</strong> to <strong>{distributeTarget.salon_name}</strong>?<br/><br/>
              {money(distributeTarget.commission_deducted)} commission is earned in this cycle.
              {distributeTarget.cycle_type === 'monthly' ? ' Settling also extends their access into the next month.' : ''}<br/><br/>
              <em>This cannot be undone.</em>
            </p>
            <div className={styles.formGroup}>
              <label htmlFor="ref">Payment Reference (optional)</label>
              <input
                id="ref"
                type="text"
                placeholder="e.g. NEFT / UTR number"
                value={distributeReference}
                onChange={e => setDistributeReference(e.target.value)}
                style={{ padding: '10px 14px', borderRadius: '8px', border: '1px solid var(--border-strong)', background: 'var(--surface-color)', color: 'var(--text-heading)', width: '100%', fontSize: '0.95rem' }}
              />
            </div>
            <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '12px', marginTop: '24px' }}>
              <button 
                onClick={() => setDistributeTarget(null)}
                style={{ padding: '8px 16px', borderRadius: '8px', border: '1px solid var(--border-strong)', background: 'var(--surface-color)', color: 'var(--text-strong)', cursor: 'pointer', fontWeight: 500 }}
              >
                Cancel
              </button>
              <button 
                onClick={() => act(distributeTarget, 'distribute', distributeReference)}
                disabled={busyId === distributeTarget.id}
                style={{ padding: '8px 16px', borderRadius: '8px', border: 'none', background: 'var(--accent-gradient, #4F46E5)', color: 'white', cursor: 'pointer', fontWeight: 500 }}
              >
                {busyId === distributeTarget.id ? 'Confirming...' : 'Confirm Distribution'}
              </button>
            </div>
          </div>
        </div>
      )}

    </div>
  );
}