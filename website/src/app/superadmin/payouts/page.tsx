'use client';

import { useCallback, useEffect, useState } from 'react';
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

  const authHeaders = (): Record<string, string> => {
    const token = localStorage.getItem('sa_token');
    return {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    };
  };

  const fetchPayouts = useCallback(async () => {
    setIsLoading(true);
    setError('');
    try {
      const query = new URLSearchParams({ cycle_type: cycleType, cycle_start: cycleStart });
      if (statusFilter) query.append('status', statusFilter);

      const res = await fetch(`/api/proxy/superadmin/payouts?${query}`, { headers: authHeaders() });
      const data = await res.json();

      if (!res.ok || !data.success) throw new Error(data.message || 'Could not load payouts.');

      setPayouts(data.payouts);
      setTotals(data.totals);
      setCycleEnd(data.cycle_end);
      setCycleLabel(data.cycle_label);
    } catch (e: any) {
      setError(e.message);
    } finally {
      setIsLoading(false);
    }
  }, [cycleType, cycleStart, statusFilter]);

  useEffect(() => {
    fetchPayouts();
  }, [fetchPayouts]);

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
      await fetchPayouts();
    } catch (e: any) {
      setError(e.message);
    } finally {
      setBusyId(null);
    }
  };

  const act = async (payout: Payout, action: 'approve' | 'distribute') => {
    if (action === 'distribute') {
      const confirmed = confirm(
        `Distribute ${money(payout.net_amount)} to ${payout.salon_name}?\n\n` +
          `${money(payout.commission_deducted)} commission is deducted in this cycle. ` +
          (payout.cycle_type === 'monthly'
            ? 'Settling also extends their access into the next month. '
            : '') +
          `This cannot be undone.`
      );
      if (!confirmed) return;
    }

    const reference =
      action === 'distribute'
        ? prompt('Payment reference (optional), e.g. NEFT number:') ?? ''
        : '';

    setBusyId(payout.id);
    setError('');

    try {
      const res = await fetch(`/api/proxy/superadmin/payouts/${payout.id}/${action}`, {
        method: 'POST',
        headers: authHeaders(),
        body: JSON.stringify(action === 'distribute' ? { distribution_reference: reference } : {}),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.message || 'That did not work.');
      await fetchPayouts();
    } catch (e: any) {
      setError(e.message);
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
      <p style={{ color: '#6B7280', fontSize: 14, marginTop: -8 }}>
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
            }}
          >
            <option value="weekly">Weekly &middot; Subscription Plan</option>
            <option value="monthly">Monthly &middot; Commission Model</option>
          </select>
        </div>

        <div className={styles.field}>
          <label htmlFor="cycle-start">
            {cycleType === 'monthly' ? 'Month' : 'Week starting (Monday)'}
          </label>
          <input
            id="cycle-start"
            type={cycleType === 'monthly' ? 'month' : 'date'}
            value={cycleType === 'monthly' ? cycleStart.slice(0, 7) : cycleStart}
            onChange={(e) =>
              setCycleStart(
                startOfCycle(
                  cycleType,
                  new Date(cycleType === 'monthly' ? `${e.target.value}-01` : e.target.value)
                )
              )
            }
          />
        </div>

        <div className={styles.field}>
          <label htmlFor="status">Status</label>
          <select id="status" value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)}>
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
        <p style={{ color: '#6B7280', fontSize: 13, marginTop: -8 }}>
          {cycleLabel} · {cycleStart} → {cycleEnd}
        </p>
      )}

      {error && <p style={{ color: '#DC2626' }}>{error}</p>}

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
            <div className={styles.summaryLabel}>Commission deducted</div>
            <div className={styles.summaryValue} style={{ color: '#DC2626' }}>
              {money(totals.commission_deducted)}
            </div>
          </div>
          <div className={styles.summaryTile}>
            <div className={styles.summaryLabel}>Still to distribute</div>
            <div className={styles.summaryValue}>{money(totals.net_to_distribute)}</div>
          </div>
          <div className={styles.summaryTile}>
            <div className={styles.summaryLabel}>Distributed</div>
            <div className={styles.summaryValue} style={{ color: '#15803D' }}>
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
          for this cycle yet. Press{' '}
          <strong>{cycleType === 'monthly' ? 'Calculate this month' : 'Calculate this week'}</strong>{' '}
          to build them from completed appointments.
        </div>
      ) : (
        <table className={styles.table}>
          <thead>
            <tr>
              <th>Salon</th>
              <th>Billing</th>
              <th>Appts</th>
              <th>Billed</th>
              <th>Advances held</th>
              <th>Commission</th>
              <th>Adjustments</th>
              <th>Net payable</th>
              <th>Status</th>
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
                      <small style={{ color: '#6B7280' }}>ref {p.distribution_reference}</small>
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
                <td className={p.commission_deducted > 0 ? styles.deduction : undefined}>
                  {p.commission_deducted > 0 ? `− ${money(p.commission_deducted)}` : '—'}
                  {p.commission_percentage > 0 && (
                    <>
                      <br />
                      <small style={{ color: '#6B7280' }}>at {p.commission_percentage}%</small>
                    </>
                  )}
                </td>
                <td>
                  {p.refund_adjustment > 0 && (
                    <div className={styles.deduction}>− {money(p.refund_adjustment)} refunds</div>
                  )}
                  {p.wallet_redeemed_amount > 0 && (
                    <div style={{ color: '#15803D' }}>
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
                        onClick={() => act(p, 'distribute')}
                      >
                        Distribute
                      </button>
                    )}
                    {p.status === 'distributed' && (
                      <small style={{ color: '#6B7280' }}>
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
    </div>
  );
}
