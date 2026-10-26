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
  /** The cycle has not ended: figures are a preview and cannot be approved yet. */
  in_progress?: boolean;
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
  const [inProgress, setInProgress] = useState(false);
  const [notice, setNotice] = useState('');
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
      setInProgress(Boolean(data.cycle_in_progress));
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
    setNotice('');
    try {
      const res = await fetch('/api/proxy/superadmin/payouts/generate', {
        method: 'POST',
        headers: authHeaders(),
        body: JSON.stringify({ cycle_type: cycleType, cycle_start: cycleStart }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.message || 'Could not calculate the cycle.');
      setNotice(data.message || 'Cycle calculated.');
      // The new cycle can be shorter than the page we were on.
      if (page === 1) await fetchPayouts();
      else setPage(1);
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
      title: `Calculate ${selectedCycleLabel()}?`,
      body: 'This rebuilds the open payouts for this cycle from the bookings dated inside it, plus any booking completed late after its own cycle was already approved. Earlier weeks that were never calculated get their own payouts. Approved and distributed payouts are never changed, and nothing is paid out by this.',
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
    return (
      <span className={`${styles.status} ${cls}`}>
        <span className={styles.dot} aria-hidden />
        {status.charAt(0).toUpperCase() + status.slice(1)}
      </span>
    );
  };

  const sortProps = (key: string) => ({
    active: sort?.key === key,
    dir: sort?.key === key ? sort.dir : null,
    onClick: () => onSortColumn(key),
  });

  const switchCycle = (next: CycleType) => {
    if (next === cycleType) return;
    setCycleType(next);
    // The same date sits in a different cycle depending on the rhythm, so the
    // anchor moves with it.
    setCycleStart(startOfCycle(next, new Date(cycleStart)));
    setPage(1);
  };

  const fmtDate = (iso: string) =>
    new Date(iso).toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' });

  const needsAction = payouts.filter(
    (p) => p.status !== 'distributed' && (p.status === 'pending' || p.payment_submission?.status === 'pending'),
  ).length;

  const kpis = totals
    ? [
        { label: 'Salons in cycle', value: String(totals.salons), hint: needsAction ? `${needsAction} need action on this page` : 'Nothing waiting on this page', tone: 'neutral' },
        { label: 'Billed on app bookings', value: money(totals.appointment_revenue), hint: 'Commission base; walk-ins excluded', tone: 'neutral' },
        { label: 'Advances held', value: money(totals.advances_held), hint: 'Collected online by BookALook', tone: 'info' },
        { label: 'Commission earned', value: money(totals.commission_deducted), hint: cycleType === 'monthly' ? 'On app bookings' : 'Not charged on plans', tone: 'success' },
        { label: 'Still to settle', value: money(totals.net_to_distribute), hint: 'Pending + approved', tone: 'warning' },
        { label: 'Settled', value: money(totals.distributed), hint: 'Distributed or collected', tone: 'success' },
      ]
    : [];

  return (
    <div className={styles.container}>
      <header className={styles.pageHeader}>
        <div>
          <h1 className={styles.title}>Payouts &amp; distribution</h1>
          <p className={styles.subtitle}>
            {cycleType === 'monthly'
              ? 'Commission Model salons, settled on the 1st for the month just finished. Settling extends the salon’s access into the next month.'
              : 'Subscription Plan salons, settled weekly. They have already paid for access, so this hands back the advances BookALook collected for them.'}
          </p>
        </div>
        <button className={styles.primaryAction} onClick={confirmGenerate} disabled={busyId === 'generate'}>
          {busyId === 'generate' ? 'Calculating…' : cycleType === 'monthly' ? 'Calculate selected month' : 'Calculate selected week'}
        </button>
      </header>

      <div className={styles.filterBar}>
        <div className={styles.segmented} role="tablist" aria-label="Settlement run">
          {(['weekly', 'monthly'] as CycleType[]).map((c) => (
            <button
              key={c}
              role="tab"
              aria-selected={cycleType === c}
              className={`${styles.segment} ${cycleType === c ? styles.segmentActive : ''}`}
              onClick={() => switchCycle(c)}
            >
              {c === 'weekly' ? 'Weekly · Subscription' : 'Monthly · Commission'}
            </button>
          ))}
        </div>

        <div className={styles.field}>
          <label htmlFor="cycle-start">{cycleType === 'monthly' ? 'Month' : 'Week'}</label>
          <select id="cycle-start" value={cycleStart} onChange={(e) => { setCycleStart(e.target.value); setPage(1); }}>
            {getCycleOptions(cycleType).map((opt) => (
              <option key={opt.value} value={opt.value}>{opt.label}</option>
            ))}
          </select>
        </div>

        <div className={styles.chips} role="group" aria-label="Status">
          {[
            { v: '', l: 'All' },
            { v: 'pending', l: 'Pending' },
            { v: 'approved', l: 'Approved' },
            { v: 'distributed', l: 'Distributed' },
          ].map((s) => (
            <button
              key={s.v || 'all'}
              className={`${styles.chip} ${statusFilter === s.v ? styles.chipActive : ''}`}
              aria-pressed={statusFilter === s.v}
              onClick={() => { setStatusFilter(s.v); setPage(1); }}
            >
              {s.l}
            </button>
          ))}
        </div>

        {cycleEnd && (
          <span className={styles.period}>
            {fmtDate(cycleStart)} – {fmtDate(cycleEnd)}
          </span>
        )}
      </div>

      {error && <div className={styles.errorBanner} role="alert">{error}</div>}
      {notice && !error && <div className={styles.noticeBanner} role="status">{notice}</div>}
      {inProgress && (
        <div className={styles.previewBanner} role="note">
          <strong>In progress.</strong> This {cycleType === 'monthly' ? 'month' : 'week'} has not ended, so these figures are a
          preview of the bookings so far. Payouts can be approved and paid once it is over.
        </div>
      )}

      {totals && (
        <div className={styles.summaryGrid}>
          {kpis.map((k) => (
            <div key={k.label} className={`${styles.summaryTile} ${styles[`tone_${k.tone}`]}`}>
              <div className={styles.summaryLabel}>{k.label}</div>
              <div className={styles.summaryValue}>{k.value}</div>
              <div className={styles.summaryHint}>{k.hint}</div>
            </div>
          ))}
        </div>
      )}

      <section className={styles.tableCard}>
        <div className={styles.tableHead}>
          <div>
            <h2 className={styles.tableTitle}>Salon settlements</h2>
            <p className={styles.tableSub}>{cycleLabel || selectedCycleLabel()} · {meta.total} payout{meta.total === 1 ? '' : 's'}</p>
          </div>
        </div>

        {isLoading ? (
          <div className={styles.skeletonList}>
            {[0, 1, 2, 3].map((i) => <div key={i} className={styles.skeletonRow} />)}
          </div>
        ) : payouts.length === 0 ? (
          <div className={styles.empty}>
            <div className={styles.emptyTitle}>No payouts for this cycle yet</div>
            <p>
              {cycleType === 'monthly' ? 'Commission Model' : 'Subscription Plan'} payouts appear here once the cycle has
              bookings. Press “{cycleType === 'monthly' ? 'Calculate selected month' : 'Calculate selected week'}” to build them.
            </p>
          </div>
        ) : (
          <div className={styles.tableScroll}>
            <table className={styles.table}>
              <thead>
                <tr>
                  <SortHeader label="Salon" {...sortProps('salon')} />
                  <SortHeader label="Appts" align="right" {...sortProps('appointments_count')} />
                  <SortHeader label="Billed" align="right" {...sortProps('appointment_revenue')} />
                  <SortHeader label="Advances held" align="right" {...sortProps('gross_amount')} />
                  <SortHeader label="Commission" align="right" {...sortProps('commission_deducted')} />
                  <th className={styles.num}>Adjustments</th>
                  <SortHeader label="Net" align="right" {...sortProps('net_amount')} />
                  <SortHeader label="Status" {...sortProps('status')} />
                  <th className={styles.actionsCol}>Actions</th>
                </tr>
              </thead>
              <tbody>
                {payouts.map((p) => {
                  const owes = p.direction === 'salon_owes';
                  const open = p.status !== 'distributed';
                  const paymentPending = open && p.payment_submission?.status === 'pending';
                  const paymentDeclined = open && p.payment_submission?.status === 'rejected';
                  const preview = open && Boolean(p.in_progress);
                  return (
                    <tr key={p.id} className={paymentPending ? styles.rowAttention : undefined}>
                      <td>
                        <div className={styles.salonName}>{p.salon_name ?? '—'}</div>
                        <div className={styles.salonMeta}>
                          <span className={`${styles.pill} ${p.billing_type === 'commission' ? styles.pillCommission : styles.pillSubscription}`}>
                            {p.billing_label}
                          </span>
                          {/* The statement is what the owner is handed when the money
                              moves; SuperAdmin answers their queries weeks later, so
                              the number stays one click away. */}
                          {p.settlement_invoice && (
                            <a className={styles.statementLink} href={p.settlement_invoice.url} target="_blank" rel="noreferrer">
                              {p.settlement_invoice.number}
                            </a>
                          )}
                        </div>
                      </td>
                      <td className={styles.num}>{p.appointments_count}</td>
                      <td className={styles.num}>{money(p.appointment_revenue)}</td>
                      <td className={styles.num}>{money(p.gross_amount)}</td>
                      <td className={styles.num}>
                        {p.commission_deducted > 0 ? (
                          <>
                            <span className={styles.earned}>{money(p.commission_deducted)}</span>
                            <div className={styles.cellSub}>at {p.commission_percentage}%</div>
                          </>
                        ) : (
                          <span className={styles.muted}>—</span>
                        )}
                      </td>
                      <td className={styles.num}>
                        {p.refund_adjustment > 0 && <div className={styles.deduction}>− {money(p.refund_adjustment)}<span className={styles.cellSub}> refunds</span></div>}
                        {p.wallet_redeemed_amount > 0 && <div className={styles.earned}>+ {money(p.wallet_redeemed_amount)}<span className={styles.cellSub}> coins</span></div>}
                        {p.refund_adjustment === 0 && p.wallet_redeemed_amount === 0 && <span className={styles.muted}>—</span>}
                      </td>
                      <td className={styles.num}>
                        {owes ? (
                          <span title="Commission exceeded the advances held; the salon pays this by QR.">
                            <span className={styles.owes}>{money(p.amount_due ?? Math.abs(p.net_amount))}</span>
                            <div className={styles.cellSub}>salon owes</div>
                          </span>
                        ) : (
                          <span className={styles.net}>{money(p.net_amount)}</span>
                        )}
                      </td>
                      <td>
                        {statusPill(p.status)}
                        {preview && <div className={styles.flagMuted}>Preview · cycle running</div>}
                        {paymentPending && <div className={styles.flagWarn}>Payment to verify</div>}
                        {paymentDeclined && <div className={styles.flagMuted}>Last payment declined</div>}
                      </td>
                      <td className={styles.actionsCol}>
                        <div className={styles.rowActions}>
                          {p.status === 'pending' && (
                            <button
                              className={styles.btnGhost}
                              disabled={busyId === p.id || preview}
                              title={preview ? 'Available once the cycle has ended' : undefined}
                              onClick={() => confirmApprove(p)}
                            >
                              Approve
                            </button>
                          )}
                          {paymentPending && (
                            <button className={styles.btnPrimary} disabled={busyId === p.id} onClick={() => { setReviewTarget(p); setRejectReason(''); }}>
                              Review payment
                            </button>
                          )}
                          {open && !paymentPending && (
                            <button
                              className={styles.btnSuccess}
                              disabled={busyId === p.id || preview}
                              title={preview ? 'Available once the cycle has ended' : undefined}
                              onClick={() => confirmDistribute(p)}
                            >
                              {owes ? 'Mark collected' : 'Distribute'}
                            </button>
                          )}
                          {!open && (
                            <>
                              <span className={styles.doneMeta}>
                                {p.distributed_at ? fmtDate(p.distributed_at) : 'Done'}
                                {p.distribution_reference && <span className={styles.cellSub}>Ref {p.distribution_reference}</span>}
                              </span>
                              {p.settlement_invoice && (
                                <a className={styles.btnGhost} href={p.settlement_invoice.url} target="_blank" rel="noreferrer">
                                  Statement
                                </a>
                              )}
                            </>
                          )}
                        </div>
                      </td>
                    </tr>
                  );
                })}
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
      </section>

      {distributeTarget && (
        <div className={styles.modalOverlay} onClick={() => setDistributeTarget(null)}>
          <div className={styles.modalContent} onClick={(e) => e.stopPropagation()} role="dialog" aria-modal="true">
            <h2 className={styles.modalTitle}>
              {distributeTarget.direction === 'salon_owes' ? 'Record payment received' : 'Distribute payout'}
            </h2>
            <div className={styles.modalAmount}>
              <span>{distributeTarget.salon_name}</span>
              <strong>
                {money(distributeTarget.direction === 'salon_owes'
                  ? (distributeTarget.amount_due ?? Math.abs(distributeTarget.net_amount))
                  : distributeTarget.net_amount)}
              </strong>
            </div>
            <p className={styles.modalText}>
              {distributeTarget.direction === 'salon_owes'
                ? `Their ${money(distributeTarget.commission_deducted)} commission was more than the ${money(distributeTarget.gross_amount)} of advances BookALook held, so they pay the difference. Confirm you have received it.`
                : `${money(distributeTarget.commission_deducted)} commission is earned in this cycle.`}
              {distributeTarget.cycle_type === 'monthly' ? ' Settling also extends their access into the next month.' : ''}
            </p>
            <p className={styles.modalWarn}>This cannot be undone.</p>
            <div className={styles.formGroup}>
              <label htmlFor="ref">
                {distributeTarget.direction === 'salon_owes' ? 'UPI / bank reference of the payment received (required)' : 'Payment reference (optional)'}
              </label>
              <input
                id="ref"
                type="text"
                placeholder="e.g. NEFT / UTR number"
                value={distributeReference}
                onChange={(e) => setDistributeReference(e.target.value)}
              />
            </div>
            <div className={styles.modalActions}>
              <button className={styles.btnGhost} onClick={() => setDistributeTarget(null)}>Cancel</button>
              <button
                className={styles.btnSuccessSolid}
                onClick={() => act(distributeTarget, 'distribute', distributeReference)}
                disabled={busyId === distributeTarget.id || (distributeTarget.direction === 'salon_owes' && !distributeReference.trim())}
              >
                {busyId === distributeTarget.id
                  ? 'Confirming…'
                  : distributeTarget.direction === 'salon_owes' ? 'Mark collected' : 'Confirm distribution'}
              </button>
            </div>
          </div>
        </div>
      )}

      {reviewTarget && reviewTarget.payment_submission && (
        <div className={styles.modalOverlay} onClick={() => setReviewTarget(null)}>
          <div className={`${styles.modalContent} ${styles.modalWide}`} onClick={(e) => e.stopPropagation()} role="dialog" aria-modal="true">
            <h2 className={styles.modalTitle}>Verify payment</h2>
            <div className={styles.modalAmount}>
              <span>{reviewTarget.salon_name} · {reviewTarget.cycle_label}</span>
              <strong>{money(reviewTarget.payment_submission.amount)}</strong>
            </div>
            <p className={styles.modalText}>Check the screenshot against your bank statement before approving.</p>
            <a href={reviewTarget.payment_submission.screenshot_url} target="_blank" rel="noreferrer">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img className={styles.screenshot} src={reviewTarget.payment_submission.screenshot_url} alt="Payment screenshot" />
            </a>
            <dl className={styles.details}>
              <dt>UTR / reference</dt>
              <dd>{reviewTarget.payment_submission.transaction_id || '—'}</dd>
              {reviewTarget.payment_submission.note && (<><dt>Note</dt><dd>{reviewTarget.payment_submission.note}</dd></>)}
              {reviewTarget.payment_submission.submitted_at && (
                <><dt>Sent</dt><dd>{new Date(reviewTarget.payment_submission.submitted_at).toLocaleString('en-IN')}</dd></>
              )}
            </dl>
            <div className={styles.formGroup}>
              <label htmlFor="reject-reason">If declining, tell the salon why (they pay the full amount again)</label>
              <input
                id="reject-reason"
                type="text"
                placeholder="e.g. Received ₹500 of ₹800"
                value={rejectReason}
                onChange={(e) => setRejectReason(e.target.value)}
              />
            </div>
            <div className={styles.modalActions}>
              <button
                className={styles.btnDanger}
                onClick={() => reviewPayment('reject')}
                disabled={busyId === reviewTarget.id || rejectReason.trim().length < 3}
              >
                Decline
              </button>
              <button className={styles.btnSuccessSolid} onClick={() => reviewPayment('approve')} disabled={busyId === reviewTarget.id}>
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
