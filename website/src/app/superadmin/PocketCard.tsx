'use client';

import { useEffect, useRef, useState } from 'react';
import Icon from '@/components/admin/Icon';
import { Drawer } from '@/components/admin/ui';
import styles from './dashboard.module.css';
import pocket from './pocket.module.css';

/* "Money in pocket": what BookALook holds now, less what it still owes out.
   The figure is all-time (a position, not a period), so it ignores the date
   range on the page. Shared by the dashboard and the reports Money tab. */

export interface CashLine {
  key: string;
  label: string;
  amount: number;
  count: number;
  hint: string;
}

export interface CashPosition {
  in_pocket: number;
  cash_held: number;
  still_owed: number;
  fee_percent: number;
  cash_in: CashLine[];
  cash_out: CashLine[];
  owed_out: CashLine[];
  not_counted: CashLine[];
  commission_kept: number;
}

const inr = (n: number | undefined) => {
  const v = Number(n) || 0;
  return (v < 0 ? '−₹' : '₹') + Math.abs(Math.round(v)).toLocaleString('en-IN');
};

export function useCashPosition(refreshKey = 0) {
  const [data, setData] = useState<CashPosition | null>(null);
  const [error, setError] = useState('');
  const seq = useRef(0);

  useEffect(() => {
    const id = ++seq.current;
    const run = async () => {
      try {
        const res = await fetch('/api/proxy/superadmin/reports/cash-position', { cache: 'no-store' });
        const json = await res.json();
        if (id !== seq.current) return;
        if (!res.ok || !json.success) throw new Error(json.message || 'Could not work out the cash position.');
        setData(json as CashPosition);
        setError('');
      } catch (e) {
        if (id === seq.current) setError(e instanceof Error ? e.message : 'Could not work out the cash position.');
      }
    };
    const timer = setTimeout(run, 0);
    return () => clearTimeout(timer);
  }, [refreshKey]);

  return { data, error };
}

/** The stat card. Opens the line-by-line breakdown on click. */
export function PocketCard({ refreshKey = 0 }: { refreshKey?: number }) {
  const { data, error } = useCashPosition(refreshKey);
  const [open, setOpen] = useState(false);
  const loading = !data && !error;

  const summary = data
    ? `${inr(data.cash_held)} cash held − ${inr(data.still_owed)} still owed to salons and customers`
    : '';

  return (
    <>
      <button
        type="button"
        className={`${styles.kpiCard} ${styles.clickableCard} ${pocket.card}`}
        onClick={() => setOpen(true)}
        disabled={!data}
        title={data ? `${summary}. Click for the full breakdown.` : undefined}
        aria-haspopup="dialog"
        data-section="Money in pocket"
      >
        <div className={styles.kpiHeader}>
          <span className={`${styles.kpiIcon} ${pocket.tone}`}><Icon name="wallet" size={20} /></span>
          <span className={pocket.how}><Icon name="info" size={13} /> How?</span>
        </div>
        <div className={styles.kpiLabel}>Money in pocket</div>
        {loading ? (
          <div className={`${styles.skeleton} ${styles.skeletonValue}`} />
        ) : (
          <div className={`${styles.kpiValue} ${data && data.in_pocket < 0 ? pocket.negative : ''}`}>
            {error ? '—' : inr(data?.in_pocket)}
          </div>
        )}
        <div className={styles.kpiTrend}>
          <span className={styles.trendSub}>
            {error ? error : data ? `${inr(data.cash_held)} held · ${inr(data.still_owed)} owed out` : 'All time, right now'}
          </span>
        </div>
      </button>

      <Drawer
        open={open}
        onClose={() => setOpen(false)}
        title="Money in pocket"
        description="What BookALook holds right now, and how much of it is its own once everything it owes has gone out. All time — the date range does not apply."
      >
        {data && <CashBreakdown data={data} />}
      </Drawer>
    </>
  );
}

/** The waterfall: cash in, cash out, = held, owed out, = in pocket. */
export function CashBreakdown({ data }: { data: CashPosition }) {
  return (
    <div className={pocket.breakdown}>
      <Group title="Money that came in" sign="+" lines={data.cash_in} />
      <Group title="Money that went out" sign="−" lines={data.cash_out} />
      <div className={pocket.subtotal}>
        <span>Cash held now</span>
        <b>{inr(data.cash_held)}</b>
      </div>
      <Group title="Still owed out — not BookALook's to keep" sign="−" lines={data.owed_out} />
      <div className={`${pocket.subtotal} ${pocket.total}`}>
        <span>Money in pocket</span>
        <b className={data.in_pocket < 0 ? pocket.negative : undefined}>{inr(data.in_pocket)}</b>
      </div>
      {data.commission_kept > 0 && (
        <p className={pocket.note}>
          Commission settled to date, after coins: <b>{inr(data.commission_kept)}</b>. It is already inside the figures
          above — payouts are paid net of it.
        </p>
      )}
      <Group title="Not counted until it arrives" lines={data.not_counted} muted />
      <p className={pocket.note}>
        Only money that passed through the payment gateway counts — what customers pay at the counter is the salon&apos;s
        from the start. Razorpay does not report its fee per payment, so it is estimated at {data.fee_percent}% of Razorpay
        collections.
      </p>
    </div>
  );
}

function Group({ title, sign, lines, muted }: { title: string; sign?: '+' | '−'; lines: CashLine[]; muted?: boolean }) {
  return (
    <section className={`${pocket.group} ${muted ? pocket.muted : ''}`}>
      <h3 className={pocket.groupTitle}>{title}</h3>
      <ul className={pocket.lines}>
        {lines.map((l) => (
          <li key={l.key}>
            <div className={pocket.lineText}>
              <span className={pocket.lineLabel}>{l.label}</span>
              <span className={pocket.lineHint}>
                {l.hint}
                {l.count > 0 && ` · ${l.count.toLocaleString('en-IN')}`}
              </span>
            </div>
            <b className={pocket.lineAmount}>
              {sign && l.amount !== 0 ? `${sign} ` : ''}
              {inr(l.amount)}
            </b>
          </li>
        ))}
      </ul>
    </section>
  );
}
