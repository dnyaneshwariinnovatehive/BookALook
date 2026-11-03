'use client';

import { useCallback, useEffect, useState, type ReactNode } from 'react';
import { Alert, Badge, DescriptionList, Drawer, StatCard, formatINR } from '@/components/admin/ui';
import styles from './page.module.css';

/* Shared pieces of the payouts desk: where to send money, what a payout is
   made of, who did what, a salon's history, the cross-cycle inbox and the
   overview strip. All read-only; actions stay on the page. */

export interface DeskPayout {
  id: string;
  salon_id: string;
  salon_name: string | null;
  cycle_type: 'weekly' | 'monthly';
  cycle_label: string;
  billing_label: string;
  appointments_count: number;
  appointment_revenue: number;
  gross_amount: number;
  commission_percentage: number;
  commission_deducted: number;
  refund_adjustment: number;
  wallet_redeemed_amount: number;
  dues_adjustment?: number;
  net_amount: number;
  direction?: 'pay_salon' | 'salon_owes';
  amount_due?: number;
  status: string;
  in_progress?: boolean;
  approved_at?: string | null;
  distributed_at: string | null;
  distribution_reference: string | null;
  payment_submission?: { id: string; amount: number; status: string; transaction_id: string | null; screenshot_url: string; submitted_at: string | null } | null;
  settlement_invoice: { number: string; url: string; issued_at: string } | null;
  waiting_days?: number | null;
}

interface Bank {
  account_holder_name: string | null;
  bank_name: string | null;
  ifsc: string | null;
  upi_id: string | null;
  account_number_masked: string | null;
  account_number: string | null;
  has_required: boolean;
  has_any: boolean;
}

const fmtDate = (v: string | null | undefined) =>
  v ? new Date(v).toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' }) : '—';
const fmtDateTime = (v: string | null | undefined) =>
  v ? new Date(v).toLocaleString('en-IN', { day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' }) : '—';

async function getJson(url: string) {
  const res = await fetch(url, { cache: 'no-store' });
  const json = await res.json();
  if (!res.ok || json.success === false) throw new Error(json.message || 'Could not load.');
  return json;
}

function Copy({ value }: { value: string | null }) {
  const [done, setDone] = useState(false);
  if (!value) return <span className={styles.muted}>—</span>;
  return (
    <span className={styles.copyRow}>
      <code>{value}</code>
      <button
        type="button"
        className={styles.copyBtn}
        onClick={() => { navigator.clipboard?.writeText(value); setDone(true); setTimeout(() => setDone(false), 1500); }}
      >
        {done ? 'Copied' : 'Copy'}
      </button>
    </span>
  );
}

/** Where the money goes: the salon's bank and UPI, with a logged reveal. */
export function BankBlock({ salonId, initial }: { salonId: string; initial?: Bank | null }) {
  const [bank, setBank] = useState<Bank | null>(initial ?? null);
  const [error, setError] = useState('');
  const [revealing, setRevealing] = useState(false);

  useEffect(() => {
    if (initial) return;
    let live = true;
    getJson(`/api/proxy/superadmin/salons/${salonId}/bank-details`)
      .then((j) => live && setBank(j.bank_details))
      .catch((e) => live && setError(e.message));
    return () => { live = false; };
  }, [salonId, initial]);

  const reveal = async () => {
    setRevealing(true);
    try {
      const j = await getJson(`/api/proxy/superadmin/salons/${salonId}/bank-details?reveal=1`);
      setBank(j.bank_details);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not reveal.');
    } finally {
      setRevealing(false);
    }
  };

  if (error) return <Alert tone="error">{error}</Alert>;
  if (!bank) return <p className={styles.muted}>Loading bank details…</p>;
  if (!bank.has_any) {
    return <Alert tone="warning">This salon has not added bank or UPI details yet. Ask the owner to add them in the Partner App (Settings → Bank details).</Alert>;
  }

  return (
    <div className={styles.bankBlock}>
      {!bank.has_required && <Alert tone="warning">Bank details are incomplete — check before paying.</Alert>}
      <DescriptionList
        variant="clean"
        items={[
          ['Account holder', bank.account_holder_name || '—'],
          ['Bank', bank.bank_name || '—'],
          [
            'Account no.',
            bank.account_number ? (
              <Copy value={bank.account_number} />
            ) : (
              <span className={styles.copyRow}>
                <code>{bank.account_number_masked || '—'}</code>
                {bank.account_number_masked && (
                  <button type="button" className={styles.copyBtn} onClick={reveal} disabled={revealing}>
                    {revealing ? '…' : 'Reveal'}
                  </button>
                )}
              </span>
            ),
          ],
          ['IFSC', <Copy key="ifsc" value={bank.ifsc} />],
          ['UPI ID', <Copy key="upi" value={bank.upi_id} />],
        ]}
      />
      <p className={styles.fineprint}>Revealing the full account number is recorded in the audit log.</p>
    </div>
  );
}

interface Item {
  id: string;
  kind: string;
  date: string | null;
  time: string | null;
  customer_name: string | null;
  source: string | null;
  appointment_status: string | null;
  advance_held: number;
  commission_base: number;
  commission_rate: number;
  commission: number;
  refund: number;
  net: number;
}

interface HistoryRow { action: string; label: string; by: string | null; at: string | null; reference: string | null; note: string | null }

/** Everything behind one payout: the lines, the bank, payments and who did what. */
export function PayoutDetailDrawer({ payoutId, onClose }: { payoutId: string | null; onClose: () => void }) {
  const [data, setData] = useState<{
    payout: DeskPayout;
    items: Item[];
    bank_details: Bank | null;
    payment_submissions: NonNullable<DeskPayout['payment_submission']>[];
    history: HistoryRow[];
  } | null>(null);
  const [error, setError] = useState('');

  useEffect(() => {
    if (!payoutId) return;
    let live = true;
    const t = setTimeout(() => {
      setData(null);
      setError('');
      getJson(`/api/proxy/superadmin/payouts/${payoutId}`)
        .then((j) => live && setData(j))
        .catch((e) => live && setError(e.message));
    }, 0);
    return () => { live = false; clearTimeout(t); };
  }, [payoutId]);

  const p = data?.payout;
  const owes = p?.direction === 'salon_owes';

  return (
    <Drawer
      open={Boolean(payoutId)}
      onClose={onClose}
      title={p ? `${p.salon_name ?? 'Salon'} · ${p.cycle_label}` : 'Payout'}
      description={p ? `${p.billing_label} · ${p.status.charAt(0).toUpperCase() + p.status.slice(1)}` : undefined}
    >
      {error && <Alert tone="error">{error}</Alert>}
      {!data && !error && <p className={styles.muted}>Loading…</p>}
      {data && p && (
        <div className={styles.drawerBody}>
          <section>
            <h3 className={styles.drawerH}>{owes ? 'Salon owes BookALook' : 'BookALook pays the salon'}</h3>
            <div className={styles.drawerAmount}>{formatINR(owes ? (p.amount_due ?? Math.abs(p.net_amount)) : p.net_amount, 2)}</div>
            <DescriptionList
              variant="clean"
              items={[
                ['Billed on app bookings', formatINR(p.appointment_revenue, 2)],
                ['Advances BookALook held', formatINR(p.gross_amount, 2)],
                ['Commission', p.commission_deducted > 0 ? `− ${formatINR(p.commission_deducted, 2)} at ${p.commission_percentage}%` : '—'],
                ...(p.refund_adjustment > 0 ? [['Refunds', `− ${formatINR(p.refund_adjustment, 2)}`] as [string, string]] : []),
                ...(p.wallet_redeemed_amount > 0 ? [['Coins', `+ ${formatINR(p.wallet_redeemed_amount, 2)}`] as [string, string]] : []),
                ...((p.dues_adjustment ?? 0) !== 0 ? [['Overdue commission', formatINR(p.dues_adjustment ?? 0, 2)] as [string, string]] : []),
                ['Net', <strong key="net">{formatINR(p.net_amount, 2)}</strong>],
              ]}
            />
          </section>

          <section>
            <h3 className={styles.drawerH}>Bookings in this payout ({data.items.length})</h3>
            {data.items.length === 0 ? (
              <p className={styles.muted}>No lines.</p>
            ) : (
              <div className={styles.tableScroll}>
                <table className={styles.miniTable}>
                  <thead>
                    <tr><th>Date</th><th>Customer</th><th className={styles.num}>Advance held</th><th className={styles.num}>Commission</th><th className={styles.num}>Net</th></tr>
                  </thead>
                  <tbody>
                    {data.items.map((i) => (
                      <tr key={i.id}>
                        <td>{i.date ? fmtDate(i.date) : '—'}{i.time && <div className={styles.cellSub}>{i.time}</div>}</td>
                        <td>
                          {i.kind === 'refund' ? 'Refund' : (i.customer_name ?? '—')}
                          <div className={styles.cellSub}>{[i.source === 'walk_in' ? 'Walk-in' : i.source === 'online' ? 'App' : i.source, i.appointment_status].filter(Boolean).join(' · ')}</div>
                        </td>
                        <td className={styles.num}>{formatINR(i.advance_held, 2)}</td>
                        <td className={styles.num}>{i.commission > 0 ? formatINR(i.commission, 2) : '—'}{i.refund > 0 && <div className={styles.deduction}>− {formatINR(i.refund, 2)} refund</div>}</td>
                        <td className={styles.num}>{formatINR(i.net, 2)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </section>

          {!owes && (
            <section>
              <h3 className={styles.drawerH}>Where to send the money</h3>
              <BankBlock salonId={p.salon_id} initial={data.bank_details} />
            </section>
          )}

          {data.payment_submissions.length > 0 && (
            <section>
              <h3 className={styles.drawerH}>Payments the salon sent</h3>
              <ul className={styles.timeline}>
                {data.payment_submissions.map((s) => (
                  <li key={s.id}>
                    <strong>{formatINR(s.amount, 2)}</strong>{' '}
                    <Badge tone={s.status === 'approved' ? 'success' : s.status === 'rejected' ? 'danger' : 'warning'}>{s.status}</Badge>
                    <div className={styles.cellSub}>
                      {fmtDateTime(s.submitted_at)}{s.transaction_id ? ` · UTR ${s.transaction_id}` : ''} ·{' '}
                      <a href={s.screenshot_url} target="_blank" rel="noreferrer">Screenshot</a>
                    </div>
                  </li>
                ))}
              </ul>
            </section>
          )}

          <section>
            <h3 className={styles.drawerH}>History</h3>
            {data.history.length === 0 ? (
              <p className={styles.muted}>Not approved or paid yet. Recalculated automatically every day at 04:00 until approved.</p>
            ) : (
              <ul className={styles.timeline}>
                {data.history.map((h, idx) => (
                  <li key={idx}>
                    <strong>{h.label}</strong> by {h.by ?? 'system'}
                    <div className={styles.cellSub}>{fmtDateTime(h.at)}{h.reference ? ` · Ref ${h.reference}` : ''}{h.note ? ` · ${h.note}` : ''}</div>
                  </li>
                ))}
              </ul>
            )}
          </section>

          {p.settlement_invoice && (
            <a className={styles.btnGhost} href={p.settlement_invoice.url} target="_blank" rel="noreferrer">
              Statement {p.settlement_invoice.number}
            </a>
          )}
        </div>
      )}
    </Drawer>
  );
}

/** One salon's payouts over time. */
export function SalonHistoryDrawer({ salon, onClose, onOpenPayout }: {
  salon: { id: string; name: string | null } | null;
  onClose: () => void;
  onOpenPayout: (id: string) => void;
}) {
  const [data, setData] = useState<{
    billing_label: string;
    commission_percentage: number | null;
    totals: { received_lifetime: number; pending_lifetime: number; commission_deducted_lifetime: number; count: number };
    payouts: DeskPayout[];
  } | null>(null);
  const [error, setError] = useState('');

  useEffect(() => {
    if (!salon) return;
    let live = true;
    const t = setTimeout(() => {
      setData(null);
      setError('');
      getJson(`/api/proxy/superadmin/salons/${salon.id}/payouts`)
        .then((j) => live && setData(j))
        .catch((e) => live && setError(e.message));
    }, 0);
    return () => { live = false; clearTimeout(t); };
  }, [salon]);

  return (
    <Drawer open={Boolean(salon)} onClose={onClose} title={salon?.name ?? 'Salon'} description={data ? `${data.billing_label}${data.commission_percentage ? ` · ${data.commission_percentage}% commission` : ''}` : undefined}>
      {error && <Alert tone="error">{error}</Alert>}
      {!data && !error && <p className={styles.muted}>Loading…</p>}
      {data && (
        <div className={styles.drawerBody}>
          <DescriptionList
            variant="clean"
            items={[
              ['Payouts', String(data.totals.count)],
              ['Settled (lifetime)', formatINR(data.totals.received_lifetime, 2)],
              ['Still open', formatINR(data.totals.pending_lifetime, 2)],
              ['Commission (lifetime)', formatINR(data.totals.commission_deducted_lifetime, 2)],
            ]}
          />
          <div className={styles.tableScroll}>
            <table className={styles.miniTable}>
              <thead><tr><th>Cycle</th><th className={styles.num}>Net</th><th>Status</th><th /></tr></thead>
              <tbody>
                {data.payouts.map((p) => (
                  <tr key={p.id}>
                    <td>{p.cycle_label}<div className={styles.cellSub}>{p.billing_label}</div></td>
                    <td className={styles.num}>
                      {p.direction === 'salon_owes' ? <span className={styles.owes}>owes {formatINR(p.amount_due ?? Math.abs(p.net_amount), 2)}</span> : formatINR(p.net_amount, 2)}
                    </td>
                    <td><Badge tone={p.status === 'distributed' ? 'success' : p.status === 'approved' ? 'info' : 'warning'}>{p.status}</Badge></td>
                    <td><button type="button" className={styles.linkBtn} onClick={() => onOpenPayout(p.id)}>Details</button></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </Drawer>
  );
}

interface InboxData {
  counts: { to_approve: number; to_pay: number; to_verify: number; salons_owe: number };
  to_approve: DeskPayout[];
  to_pay: DeskPayout[];
  to_verify: DeskPayout[];
  salons_owe: DeskPayout[];
}

/** Everything waiting on SuperAdmin, across all cycles. */
export function NeedsActionInbox({ refreshKey, onCount, onApprove, onPay, onReview, onDetails, onSalon }: {
  refreshKey: number;
  onCount: (n: number) => void;
  onApprove: (p: DeskPayout) => void;
  onPay: (p: DeskPayout) => void;
  onReview: (p: DeskPayout) => void;
  onDetails: (id: string) => void;
  onSalon: (p: DeskPayout) => void;
}) {
  const [data, setData] = useState<InboxData | null>(null);
  const [error, setError] = useState('');

  const load = useCallback(async () => {
    try {
      const j = await getJson('/api/proxy/superadmin/payouts/inbox');
      setData(j);
      setError('');
      onCount(j.counts.to_approve + j.counts.to_pay + j.counts.to_verify + j.counts.salons_owe);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not load.');
    }
  }, [onCount]);

  useEffect(() => {
    const t = setTimeout(load, 0);
    return () => clearTimeout(t);
  }, [load, refreshKey]);

  if (error) return <Alert tone="error">{error}</Alert>;
  if (!data) return <div className={styles.skeletonList}>{[0, 1, 2].map((i) => <div key={i} className={styles.skeletonRow} />)}</div>;

  const total = data.counts.to_approve + data.counts.to_pay + data.counts.to_verify + data.counts.salons_owe;
  if (total === 0) {
    return (
      <div className={styles.empty}>
        <div className={styles.emptyTitle}>All caught up</div>
        <p>Nothing to approve, pay, verify or chase in any cycle.</p>
      </div>
    );
  }

  const section = (title: string, hint: string, rows: DeskPayout[], action: (p: DeskPayout) => ReactNode, waitLabel: string) =>
    rows.length > 0 && (
      <section className={styles.tableCard}>
        <div className={styles.tableHead}>
          <div>
            <h2 className={styles.tableTitle}>{title} <span className={styles.countPill}>{rows.length}</span></h2>
            <p className={styles.tableSub}>{hint}</p>
          </div>
        </div>
        <div className={styles.tableScroll}>
          <table className={styles.table}>
            <thead><tr><th>Salon</th><th>Cycle</th><th className={styles.num}>Amount</th><th>{waitLabel}</th><th className={styles.actionsCol}>Actions</th></tr></thead>
            <tbody>
              {rows.map((p) => {
                const owes = p.direction === 'salon_owes';
                const late = (p.waiting_days ?? 0) >= 7;
                return (
                  <tr key={`${title}-${p.id}`}>
                    <td>
                      <button type="button" className={styles.salonLink} onClick={() => onSalon(p)}>{p.salon_name ?? '—'}</button>
                      <div className={styles.cellSub}>{p.billing_label}</div>
                    </td>
                    <td>{p.cycle_label}</td>
                    <td className={styles.num}>
                      {owes ? <span className={styles.owes}>{formatINR(p.amount_due ?? Math.abs(p.net_amount), 2)}<div className={styles.cellSub}>salon owes</div></span> : <span className={styles.net}>{formatINR(p.net_amount, 2)}</span>}
                    </td>
                    <td>
                      {p.waiting_days == null ? '—' : (
                        <span className={late ? styles.lateText : undefined}>{p.waiting_days === 0 ? 'Today' : `${p.waiting_days} day${p.waiting_days === 1 ? '' : 's'}`}</span>
                      )}
                    </td>
                    <td className={styles.actionsCol}>
                      <div className={styles.rowActions}>
                        {action(p)}
                        <button type="button" className={styles.btnGhost} onClick={() => onDetails(p.id)}>Details</button>
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </section>
    );

  return (
    <div className={styles.inbox}>
      {section('Payment screenshots to verify', 'Salons say they have paid. Check against your bank statement.', data.to_verify,
        (p) => <button type="button" className={styles.btnPrimary} onClick={() => onReview(p)}>Review payment</button>, 'Waiting')}
      {section('Approved — ready to pay', 'Figures are frozen. Send the money and record the reference.', data.to_pay,
        (p) => <button type="button" className={styles.btnSuccess} onClick={() => onPay(p)}>Pay</button>, 'Approved')}
      {section('To approve', 'Cycles that have ended. Check the figures, then approve.', data.to_approve,
        (p) => <button type="button" className={styles.btnGhost} onClick={() => onApprove(p)}>Approve</button>, 'Waiting')}
      {section('Salons that owe BookALook', 'Commission was more than the advances held, and no payment has been sent yet.', data.salons_owe,
        (p) => <button type="button" className={styles.btnSuccess} onClick={() => onPay(p)}>Mark collected</button>, 'Overdue')}
    </div>
  );
}

/** Both settlement rhythms at a glance. */
export function PayoutsOverview({ refreshKey }: { refreshKey: number }) {
  const [o, setO] = useState<{
    month_label: string; to_pay_salons: number; to_pay_count: number; salons_owe: number; salons_owe_count: number;
    paid_this_month: number; collected_this_month: number; commission_this_month: number;
  } | null>(null);

  useEffect(() => {
    let live = true;
    getJson('/api/proxy/superadmin/payouts/overview').then((j) => live && setO(j)).catch(() => {});
    return () => { live = false; };
  }, [refreshKey]);

  return (
    <div className={styles.overviewGrid}>
      <StatCard label="To pay salons" value={o ? formatINR(o.to_pay_salons) : '…'} sub={o ? `${o.to_pay_count} payout${o.to_pay_count === 1 ? '' : 's'}, cycles ended` : undefined} tone="warning" loading={!o} />
      <StatCard label="Salons owe BookALook" value={o ? formatINR(o.salons_owe) : '…'} sub={o ? `${o.salons_owe_count} salon payout${o.salons_owe_count === 1 ? '' : 's'}` : undefined} tone="danger" loading={!o} />
      <StatCard label={`Paid out · ${o?.month_label ?? 'this month'}`} value={o ? formatINR(o.paid_this_month) : '…'} sub={o ? `Collected ${formatINR(o.collected_this_month)}` : undefined} tone="info" loading={!o} />
      <StatCard label={`Commission · ${o?.month_label ?? 'this month'}`} value={o ? formatINR(o.commission_this_month) : '…'} sub="Weekly + monthly cycles" tone="success" loading={!o} />
    </div>
  );
}

export function useRefreshKey() {
  const [key, setKey] = useState(0);
  return [key, () => setKey((k) => k + 1)] as const;
}

