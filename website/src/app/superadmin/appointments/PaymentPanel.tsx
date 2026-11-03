'use client';

import { useCallback, useEffect, useState } from 'react';
import { Alert, Badge, Button, DescriptionList, formatINR, useConfirm, type Tone } from '@/components/admin/ui';
import styles from './payment.module.css';

/**
 * Money on one booking, for SuperAdmin.
 *
 * There is no online payment gateway: customers pay the salon, and the salon
 * (or SuperAdmin, here) records it. Refunds are returned by hand — by the salon
 * for money it took, by BookALook for payments taken online in the past — and
 * marked returned once they have been.
 */

interface Summary {
  total: number;
  advance_due: number;
  advance_paid: number;
  advance_outstanding: number;
  paid: number;
  refunded: number;
  outstanding: number;
  status: 'paid' | 'partially_paid' | 'unpaid' | 'not_required';
}

interface PaymentRow {
  id: string;
  amount: number;
  type: string;
  mode: string;
  status: string;
  source: 'online' | 'recorded';
  reference: string | null;
  note: string | null;
  paid_at: string | null;
}

interface RefundRow {
  id: string;
  amount: number;
  reason: string;
  status: string;
  returned_by: 'salon' | 'bookalook' | null;
  note: string | null;
  processed_at: string | null;
}

interface Ledger {
  summary: Summary;
  payments: PaymentRow[];
  refunds: RefundRow[];
  modes: string[];
  types: string[];
}

const STATUS: Record<Summary['status'], { label: string; tone: Tone }> = {
  paid: { label: 'Paid', tone: 'success' },
  partially_paid: { label: 'Partly paid', tone: 'warning' },
  unpaid: { label: 'Unpaid', tone: 'danger' },
  not_required: { label: 'Nothing to pay', tone: 'neutral' },
};

const nice = (s: string) => (s === 'upi' ? 'UPI' : s.replace(/_/g, ' ').replace(/^\w/, (c) => c.toUpperCase()));
const when = (v: string | null) =>
  v ? new Date(v).toLocaleString('en-IN', { day: '2-digit', month: 'short', hour: 'numeric', minute: '2-digit' }) : '—';

export default function PaymentPanel({ appointmentId, status, paymentOption, onChanged }: {
  appointmentId: string;
  status: string;
  paymentOption?: string;
  onChanged?: () => void;
}) {
  const [ledger, setLedger] = useState<Ledger | null>(null);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [busy, setBusy] = useState(false);
  const [amount, setAmount] = useState('');
  const [type, setType] = useState('advance');
  const [mode, setMode] = useState('cash');
  const [reference, setReference] = useState('');
  const [confirm, confirmDialog] = useConfirm();

  const canRecord = !['cancelled', 'no_show', 'pending_payment', 'rescheduled'].includes(status);

  const apply = useCallback((l: Ledger) => {
    setLedger(l);
    const due = l.summary.advance_outstanding > 0 ? l.summary.advance_outstanding : l.summary.outstanding;
    setType(l.summary.advance_outstanding > 0 ? 'advance' : 'balance');
    setAmount(due > 0 ? String(due) : '');
  }, []);

  const load = useCallback(async () => {
    try {
      const res = await fetch(`/api/proxy/superadmin/appointments/${appointmentId}/payments`, { cache: 'no-store' });
      const json = await res.json();
      if (!res.ok || !json.success) throw new Error(json.message || 'Could not load payments.');
      apply(json);
      setError('');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not load payments.');
    }
  }, [appointmentId, apply]);

  useEffect(() => {
    const t = setTimeout(load, 0);
    return () => clearTimeout(t);
  }, [load]);

  const post = async (path: string, body: object, done: string) => {
    setBusy(true);
    setError('');
    try {
      const res = await fetch(`/api/proxy/superadmin/appointments/${appointmentId}/${path}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });
      const json = await res.json();
      if (!res.ok || !json.success) {
        const first = json.errors ? Object.values(json.errors as Record<string, string[]>)[0]?.[0] : null;
        throw new Error(first || json.message || 'That did not work.');
      }
      apply(json);
      setNotice(done);
      setReference('');
      onChanged?.();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'That did not work.');
    } finally {
      setBusy(false);
    }
  };

  if (!ledger) {
    return error ? <Alert tone="error">{error}</Alert> : <p className={styles.muted}>Loading payments…</p>;
  }

  const s = ledger.summary;
  const st = STATUS[s.status];

  return (
    <div className={styles.panel}>
      {notice && <Alert tone="success" onClose={() => setNotice('')}>{notice}</Alert>}
      {error && <Alert tone="error" onClose={() => setError('')}>{error}</Alert>}

      <div className={styles.head}>
        <Badge tone={st.tone}>{st.label}</Badge>
        {s.advance_outstanding > 0 && (
          <span className={styles.due}>Advance of {formatINR(s.advance_outstanding)} not yet received</span>
        )}
      </div>

      <DescriptionList
        variant="clean"
        items={[
          ['Option', paymentOption?.replace(/_/g, ' ') || '—'],
          ['Total', formatINR(s.total, 2)],
          ['Advance asked for', formatINR(s.advance_due, 2)],
          ['Paid so far', formatINR(s.paid, 2)],
          ...(s.refunded > 0 ? [['Refunded', formatINR(s.refunded, 2)] as [string, string]] : []),
          ['Still to pay', formatINR(s.outstanding, 2)],
        ]}
      />

      <h4 className={styles.sub}>Payments</h4>
      {ledger.payments.length === 0 ? (
        <p className={styles.muted}>Nothing recorded yet.</p>
      ) : (
        <ul className={styles.list}>
          {ledger.payments.map((p) => (
            <li key={p.id}>
              <div>
                <b>{nice(p.type)} · {nice(p.mode)}</b>
                <span>
                  {p.source === 'online' ? 'Paid online' : 'Recorded'} · {when(p.paid_at)}
                  {p.reference ? ` · ${p.reference}` : ''}
                  {p.note ? ` · ${p.note}` : ''}
                </span>
              </div>
              <b>{formatINR(p.amount, 2)}</b>
            </li>
          ))}
        </ul>
      )}

      {ledger.refunds.length > 0 && (
        <>
          <h4 className={styles.sub}>Refunds</h4>
          <ul className={styles.list}>
            {ledger.refunds.map((r) => (
              <li key={r.id}>
                <div>
                  <b>
                    {formatINR(r.amount, 2)}{' '}
                    {r.status === 'processed'
                      ? <Badge tone="success">Returned</Badge>
                      : <Badge tone="warning">{r.returned_by === 'salon' ? 'Salon to return' : 'BookALook to return'}</Badge>}
                  </b>
                  <span>{r.reason}{r.processed_at ? ` · returned ${when(r.processed_at)}` : ''}</span>
                </div>
                {r.status !== 'processed' && (
                  <Button
                    size="sm"
                    disabled={busy}
                    onClick={async () => {
                      const ok = await confirm({
                        title: `Mark ${formatINR(r.amount, 2)} as returned?`,
                        body: 'Only once the money has actually gone back to the customer.',
                        confirmLabel: 'Mark returned',
                        tone: 'accent',
                      });
                      if (ok) post(`refunds/${r.id}/returned`, {}, 'Refund marked as returned.');
                    }}
                  >
                    Mark returned
                  </Button>
                )}
              </li>
            ))}
          </ul>
        </>
      )}

      {canRecord && s.outstanding > 0 && (
        <div className={styles.record}>
          <h4 className={styles.sub}>Record a payment</h4>
          <div className={styles.row}>
            <select className={styles.input} value={type} onChange={(e) => setType(e.target.value)} aria-label="What it is for">
              {ledger.types.map((t) => <option key={t} value={t}>{nice(t)}</option>)}
            </select>
            <select className={styles.input} value={mode} onChange={(e) => setMode(e.target.value)} aria-label="Paid by">
              {ledger.modes.map((m) => <option key={m} value={m}>{nice(m)}</option>)}
            </select>
            <input className={styles.input} type="number" min="0" step="0.01" value={amount}
              onChange={(e) => setAmount(e.target.value)} aria-label="Amount" placeholder="Amount" />
          </div>
          <div className={styles.row}>
            <input className={styles.input} value={reference} onChange={(e) => setReference(e.target.value)}
              placeholder="Reference (optional)" aria-label="Reference" />
            <Button
              variant="primary"
              disabled={busy || !(Number(amount) > 0)}
              onClick={() => post('payments', { amount: Number(amount), type, mode, reference: reference || undefined }, 'Payment recorded.')}
            >
              Record
            </Button>
          </div>
        </div>
      )}
      {confirmDialog}
    </div>
  );
}
