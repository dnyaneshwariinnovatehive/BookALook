'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { Pagination, SortHeader, useConfirm } from '@/components/admin/ui';
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
  /** pay_salon: BookALook pays the salon. salon_owes: commission exceeded the
   *  advances held, so the salon pays the difference offline. */
  direction?: 'pay_salon' | 'salon_owes';
  amount_due?: number;
  /** Frozen because the salon has paid against it. */
  locked?: boolean;
  /** The latest screenshot the salon sent for what it owes. */
  payment_submission?: PaymentSubmission | null;
  status: string;
  distributed_at: string | null;
  distribution_reference: string | null;
  /** The statement issued for this cycle, present only once the money moved. */
  settlement_invoice: { number: string; url: string; issued_at: string } | null;
}

interface PaymentSubmission {
  id: string;
  amount: number;
  status: 'pending' | 'approved' | 'rejected';
  screenshot_url: string;
  transaction_id: string | null;
  note: string | null;
  rejection_reason: string | null;
  submitted_at: string | null;
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
  const [reviewTarget, setReviewTarget] = useState<Payout | null>(null);
  const [rejectReason, setRejectReason] = useState('');
  const [confirm, confirmDialog] = useConfirm();

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

  // Recalculation is never automatic. It used to fire from a useEffect whenever
  // the cycle type or start date changed, so simply opening a different month
  // in the dropdown rewrote every salon's settlement figures with no preview
  // and no way to see what had changed. It is now only ever run by pressing
  // "Calculate", and that press asks first.

  /** Human name of the cycle currently selected, without waiting on the API. */
  const selectedCycleLabel = () => {
    const match = getCycleOptions(cycleType).find(o => o.value === cycleStart);
    if (match) return match.label;
    return cycleType === 'monthly' ? 'that month' : 'that week';
  };

  const confirmGenerate = async () => {
    const ok = await confirm({
      title: `Rebuild the ${selectedCycleLabel()} cycle?`,
      body: 'This recalculates the open payouts for this cycle from every booking not yet settled — including late completions and no-show advances. Approved and distributed payouts are never changed. Nothing is paid out by this.',
      confirmLabel: 'Recalculate cycle',
    });
    if (!ok) return;
    await generate();
  };

  const confirmApprove = async (payout: Payout) => {
    const owes = payout.direction === 'salon_owes';
    const ok = await confirm({
      title: owes
        ? `Approve: ${payout.salon_name ?? 'this salon'} owes ${money(payout.amount_due ?? Math.abs(payout.net_amount))}?`
        : `Approve ${money(payout.net_amount)} for ${payout.salon_name ?? 'this salon'}?`,
      body: 'Approving freezes these figures — anything that changes afterwards goes into the next payout — and releases it to be settled.',
      confirmLabel: 'Approve payout',
    });
    if (!ok) return;
    await act(payout, 'approve');
  };

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

  // Checking the salon's screenshot of paying what it owed.
  const reviewPayment = async (decision: 'approve' | 'reject') => {
    const payout = reviewTarget;
    const submission = payout?.payment_submission;
    if (!payout || !submission) return;
    if (decision === 'reject' && rejectReason.trim().length < 3) {
      setError('Say why the payment is being declined. The salon sees this.');
      return;
    }

    setBusyId(payout.id);
    setError('');
    try {
      const res = await fetch(`/api/proxy/superadmin/payouts/${payout.id}/payments/${submission.id}/${decision}`, {
        method: 'POST',
        headers: authHeaders(),
        body: JSON.stringify(decision === 'reject' ? { reason: rejectReason.trim() } : {}),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.message || 'That did not work.');
      setReviewTarget(null);
      setRejectReason('');
      await fetchPayouts();
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

        <button className={styles.button} onClick={confirmGenerate} disabled={busyId === 'generate'}>
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
        <div className={styles.tableScroll}>
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
                  {/* The statement is the document the owner is given when the
                      money lands, so it is surfaced here too — SuperAdmin is
                      who answers when an owner queries the commission figure
                      weeks later, and hunting for the number then is how a
                      dispute goes unresolved. */}
                  {p.settlement_invoice && (
                    <>
                      <br />
                      <a
                        className={styles.statementLink}
                        href={p.settlement_invoice.url}
                        target="_blank"
                        rel="noreferrer"
                      >
                        {p.settlement_invoice.number}
                      </a>
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
                <td className={styles.net}>
                  {p.direction === 'salon_owes' ? (
                    <span style={{ color: 'var(--color-danger)' }} title="Commission exceeded the advances held; the salon pays this by QR.">
                      Salon owes {money(p.amount_due ?? Math.abs(p.net_amount))}
                      {p.payment_submission?.status === 'pending' && p.status !== 'distributed' && (
                        <small style={{ display: 'block', color: 'var(--color-warning, #b45309)' }}>Payment to verify</small>
                      )}
                      {p.payment_submission?.status === 'rejected' && p.status !== 'distributed' && (
                        <small style={{ display: 'block', color: 'var(--text-body)' }}>Last payment declined</small>
                      )}
                    </span>
                  ) : (
                    money(p.net_amount)
                  )}
                </td>
                <td>{statusPill(p.status)}</td>
                <td style={{ textAlign: 'right' }}>
                  <div className={styles.rowActions} style={{ justifyContent: 'flex-end' }}>
                    {p.status === 'pending' && (
                      <button
                        className={styles.smallButton}
                        disabled={busyId === p.id}
                        onClick={() => confirmApprove(p)}
                      >
                        Approve
                      </button>
                    )}
                    {p.status !== 'distributed' && p.payment_submission?.status === 'pending' && (
                      <button
                        className={`${styles.smallButton} ${styles.payButton}`}
                        disabled={busyId === p.id}
                        onClick={() => { setReviewTarget(p); setRejectReason(''); }}
                      >
                        Review payment
                      </button>
                    )}
                    {p.status !== 'distributed' && p.payment_submission?.status !== 'pending' && (
                      <button
                        className={`${styles.smallButton} ${styles.payButton}`}
                        disabled={busyId === p.id}
                        onClick={() => confirmDistribute(p)}
                      >
                        {p.direction === 'salon_owes' ? 'Mark collected' : 'Distribute'}
                      </button>
                    )}
                    {p.status === 'distributed' && (
                      <>
                        <small style={{ color: 'var(--text-body)', display: 'block' }}>
                          {p.distributed_at ? new Date(p.distributed_at).toLocaleDateString() : 'done'}
                        </small>
                        {p.settlement_invoice && (
                          <a
                            className={styles.smallButton}
                            href={p.settlement_invoice.url}
                            target="_blank"
                            rel="noreferrer"
                            style={{ marginTop: 6 }}
                          >
                            Statement
                          </a>
                        )}
                      </>
                    )}
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        </div>
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
            <h2 style={{ fontSize: '1.25rem', fontWeight: 600, marginBottom: '16px' }}>
              {distributeTarget.direction === 'salon_owes' ? 'Record payment received' : 'Distribute Payout'}
            </h2>
            <p style={{ color: 'var(--text-strong)', fontSize: '0.95rem', marginBottom: '16px', lineHeight: 1.5 }}>
              {distributeTarget.direction === 'salon_owes' ? (
                <>
                  Confirm you have received <strong>{money(distributeTarget.amount_due ?? Math.abs(distributeTarget.net_amount))}</strong> from <strong>{distributeTarget.salon_name}</strong>.<br/><br/>
                  Their {money(distributeTarget.commission_deducted)} commission was more than the {money(distributeTarget.gross_amount)} of advances BookALook held, so they pay the difference.
                </>
              ) : (
                <>
                  Distribute <strong>{money(distributeTarget.net_amount)}</strong> to <strong>{distributeTarget.salon_name}</strong>?<br/><br/>
                  {money(distributeTarget.commission_deducted)} commission is earned in this cycle.
                </>
              )}
              {distributeTarget.cycle_type === 'monthly' ? ' Settling also extends their access into the next month.' : ''}<br/><br/>
              <em>This cannot be undone.</em>
            </p>
            <div className={styles.formGroup}>
              <label htmlFor="ref">
                {distributeTarget.direction === 'salon_owes' ? 'UPI / bank reference of the payment received (required)' : 'Payment Reference (optional)'}
              </label>
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
                disabled={busyId === distributeTarget.id || (distributeTarget.direction === 'salon_owes' && !distributeReference.trim())}
                style={{ padding: '8px 16px', borderRadius: '8px', border: 'none', background: 'var(--color-danger-solid)', color: 'white', cursor: 'pointer', fontWeight: 500 }}
              >
                {busyId === distributeTarget.id
                  ? 'Confirming...'
                  : distributeTarget.direction === 'salon_owes' ? 'Mark collected' : 'Confirm Distribution'}
              </button>
            </div>
          </div>
        </div>
      )}

      {reviewTarget && reviewTarget.payment_submission && (
        <div className={styles.modalOverlay} onClick={() => setReviewTarget(null)}>
          <div className={styles.modalContent} onClick={e => e.stopPropagation()} style={{ maxWidth: '520px' }}>
            <h2 style={{ fontSize: '1.25rem', fontWeight: 600, marginBottom: '12px' }}>Verify payment</h2>
            <p style={{ color: 'var(--text-strong)', fontSize: '0.95rem', marginBottom: '12px', lineHeight: 1.5 }}>
              <strong>{reviewTarget.salon_name}</strong> says it paid{' '}
              <strong>{money(reviewTarget.payment_submission.amount)}</strong> for {reviewTarget.cycle_label}.
              Check the screenshot against your bank before approving.
            </p>
            <a href={reviewTarget.payment_submission.screenshot_url} target="_blank" rel="noreferrer">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={reviewTarget.payment_submission.screenshot_url}
                alt="Payment screenshot"
                style={{ width: '100%', maxHeight: 360, objectFit: 'contain', borderRadius: 8, border: '1px solid var(--border-strong)', background: 'var(--surface-color)' }}
              />
            </a>
            <div style={{ fontSize: '0.9rem', color: 'var(--text-body)', margin: '12px 0', lineHeight: 1.6 }}>
              <div>UTR / reference: <strong>{reviewTarget.payment_submission.transaction_id || '—'}</strong></div>
              {reviewTarget.payment_submission.note && <div>Note: {reviewTarget.payment_submission.note}</div>}
              {reviewTarget.payment_submission.submitted_at && (
                <div>Sent {new Date(reviewTarget.payment_submission.submitted_at).toLocaleString()}</div>
              )}
            </div>
            <div className={styles.formGroup}>
              <label htmlFor="reject-reason">If declining, tell the salon why (they pay the full amount again)</label>
              <input
                id="reject-reason"
                type="text"
                placeholder="e.g. Received ₹500 of ₹800"
                value={rejectReason}
                onChange={e => setRejectReason(e.target.value)}
                style={{ padding: '10px 14px', borderRadius: '8px', border: '1px solid var(--border-strong)', background: 'var(--surface-color)', color: 'var(--text-heading)', width: '100%', fontSize: '0.95rem' }}
              />
            </div>
            <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '12px', marginTop: '20px' }}>
              <button
                onClick={() => reviewPayment('reject')}
                disabled={busyId === reviewTarget.id || rejectReason.trim().length < 3}
                style={{ padding: '8px 16px', borderRadius: '8px', border: '1px solid var(--border-strong)', background: 'var(--surface-color)', color: 'var(--color-danger)', cursor: 'pointer', fontWeight: 500 }}
              >
                Decline
              </button>
              <button
                onClick={() => reviewPayment('approve')}
                disabled={busyId === reviewTarget.id}
                style={{ padding: '8px 16px', borderRadius: '8px', border: 'none', background: 'var(--color-success-solid, #16a34a)', color: 'white', cursor: 'pointer', fontWeight: 500 }}
              >
                {busyId === reviewTarget.id ? 'Saving…' : 'Approve & mark paid'}
              </button>
            </div>
          </div>
        </div>
      )}

      {confirmDialog}
    </div>
  );
}