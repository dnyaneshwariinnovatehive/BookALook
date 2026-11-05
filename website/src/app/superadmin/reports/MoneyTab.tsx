'use client';

import {
  Bar, BarChart, CartesianGrid, Cell, ComposedChart, Legend as RLegend, Line, Pie, PieChart,
  ResponsiveContainer, Tooltip, XAxis, YAxis,
} from 'recharts';
import { type DataColumn } from '@/components/admin/ui';
import { CashBreakdown, type CashPosition } from '../PocketCard';
import styles from './reports.module.css';
import {
  BarList, ChartBox, Empty, Grid, Legend, Metric, MetricGrid, Note, Panel, Pill, TabSkeleton, Table,
  compactINR, deltaOf, inr, num, pct, plural, pointsOf, useChartPalette, useTooltipStyle, type SectionBase, type TabProps,
} from './parts';

interface Flows {
  online_collected: number;
  online_payments: number;
  online_advance: number;
  online_other: number;
  at_salon_collected: number;
  gateway_fee_estimate: number;
  refunds_processed: number;
  refunds_queued: number;
  refund_count: number;
  refund_rate: number;
  paid_to_salons: number;
  dues_collected: number;
  coins_against_commission: number;
  commission: number;
  plan_payments: number;
  earnings: number;
}

interface PayoutRow {
  status: string;
  billing: string;
  count: number;
  gross: number;
  commission: number;
  refunds: number;
  coins: number;
  to_salons: number;
  from_salons: number;
}

interface MoneyData extends SectionBase {
  cash_position: CashPosition;
  flows: { current: Flows; previous: Flows };
  trend: { date: string; label: string; online: number; at_salon: number; refunds: number; paid_to_salons: number; commission: number; plans: number }[];
  payment_types: { channel: string; type: string; mode: string; label: string; count: number; amount: number }[];
  payment_mix: { key: string; label: string; bookings: number; online: number; gmv: number }[];
  payment_options: Record<string, number>;
  refunds: {
    by_status: { status: string; count: number; amount: number }[];
    by_reason: { reason: string; count: number; amount: number }[];
    by_salon: { id: string; name: string; count: number; amount: number }[];
  };
  payouts: PayoutRow[];
  plans: { name: string; count: number; amount: number; coins: number }[];
}

const OPTION_LABELS: Record<string, string> = {
  advance_only: 'Advance only',
  full_optional: 'Full payment offered',
  full: 'Full payment',
  none: 'No online payment',
};

const payoutColumns: DataColumn<PayoutRow>[] = [
  { key: 'status', header: 'Status', render: (r) => <Pill tone={r.status === 'distributed' ? 'good' : r.status === 'approved' ? 'accent' : 'warn'}>{r.status}</Pill>, sortValue: (r) => r.status },
  { key: 'billing', header: 'Model', render: (r) => r.billing, sortValue: (r) => r.billing },
  { key: 'count', header: 'Payouts', align: 'right', render: (r) => num(r.count), sortValue: (r) => r.count },
  { key: 'gross', header: 'Advances held', align: 'right', render: (r) => inr(r.gross), sortValue: (r) => r.gross },
  { key: 'commission', header: 'Commission', align: 'right', render: (r) => inr(r.commission), sortValue: (r) => r.commission },
  { key: 'refunds', header: 'Refunds', align: 'right', render: (r) => inr(r.refunds), sortValue: (r) => r.refunds },
  { key: 'coins', header: 'Coins', align: 'right', render: (r) => inr(r.coins), sortValue: (r) => r.coins },
  { key: 'to_salons', header: 'To salons', align: 'right', render: (r) => <b>{inr(r.to_salons)}</b>, sortValue: (r) => r.to_salons },
  { key: 'from_salons', header: 'From salons', align: 'right', render: (r) => inr(r.from_salons), sortValue: (r) => r.from_salons },
];

export default function MoneyTab({ data: raw }: TabProps) {
  const palette = useChartPalette();
  const tip = useTooltipStyle(palette);
  const data = raw as MoneyData | null;
  if (!data) return <TabSkeleton />;

  const c = data.flows.current;
  const p = data.flows.previous;
  const hasTrend = data.trend.some((t) => t.online || t.at_salon || t.refunds || t.paid_to_salons || t.commission || t.plans);
  const mixColors: Record<string, string> = { advance: palette.c1, full: palette.c2, at_salon: palette.c5 };
  const mix = data.payment_mix.map((m) => ({ ...m, color: mixColors[m.key] ?? palette.c3 }));
  const mixTotal = mix.reduce((s, m) => s + m.bookings, 0);
  const refundTotal = c.refunds_processed + c.refunds_queued;

  return (
    <>
      <MetricGrid cols={5}>
        <Metric label="Collected online" icon="smartphone" value={inr(c.online_collected)} delta={deltaOf(c.online_collected, p.online_collected)} hint={`${num(c.online_payments)} payments`} />
        <Metric label="Taken at the salon" icon="walkIn" tone="blue" value={inr(c.at_salon_collected)} delta={deltaOf(c.at_salon_collected, p.at_salon_collected)} hint="Cash and UPI — the salon keeps it" />
        <Metric label="Refunds" icon="repeat" tone="rose" value={inr(refundTotal)} delta={deltaOf(refundTotal, p.refunds_processed + p.refunds_queued)} invert hint={`${pct(c.refund_rate)} of online · ${inr(c.refunds_queued)} still queued`} />
        <Metric label="Paid out to salons" icon="wallet" tone="teal" value={inr(c.paid_to_salons)} delta={deltaOf(c.paid_to_salons, p.paid_to_salons)} hint="Distributed in range" />
        <Metric label="Commission dues paid in" icon="percent" tone="amber" value={inr(c.dues_collected)} delta={deltaOf(c.dues_collected, p.dues_collected)} hint="Commission Model salons paying BookALook" />
        <Metric label="Commission earned" icon="percent" value={inr(c.commission)} delta={deltaOf(c.commission, p.commission)} hint="On visits in range, as calculated in payouts" />
        <Metric label="Plan payments" icon="crown" tone="teal" value={inr(c.plan_payments)} delta={deltaOf(c.plan_payments, p.plan_payments)} hint="Approved in range, after coins" />
        <Metric label="BookALook earnings" icon="sparkle" value={inr(c.earnings)} delta={deltaOf(c.earnings, p.earnings)} hint="Commission + plans" />
        <Metric label="Coins against commission" icon="coins" tone="amber" value={inr(c.coins_against_commission)} delta={deltaOf(c.coins_against_commission, p.coins_against_commission)} hint="Given back on settled payouts" />
        <Metric label="Razorpay fee (est.)" icon="receipt" tone="rose" value={inr(c.gateway_fee_estimate)} delta={deltaOf(c.gateway_fee_estimate, p.gateway_fee_estimate)} invert hint={`${pct(data.cash_position.fee_percent, 2)} of Razorpay collections`} />
      </MetricGrid>

      <Grid cols={3}>
        <Panel
          span={2}
          title="Money movement over time"
          subtitle="Online and at-salon collections (bars) with refunds and payouts (lines)"
          csv={{ name: 'money-movement', headers: ['Period', 'Collected online', 'Taken at salon', 'Refunds', 'Paid to salons', 'Commission', 'Plan payments'], rows: data.trend.map((t) => [t.label, t.online, t.at_salon, t.refunds, t.paid_to_salons, t.commission, t.plans]) }}
        >
          {hasTrend ? (
            <ChartBox height={320}>
              <ResponsiveContainer width="100%" height="100%">
                <ComposedChart data={data.trend} margin={{ top: 8, right: 6, left: 0, bottom: 0 }}>
                  <CartesianGrid strokeDasharray="4 4" vertical={false} stroke={palette.grid} />
                  <XAxis dataKey="label" axisLine={false} tickLine={false} tick={{ fontSize: 11, fill: palette.axis }} minTickGap={24} />
                  <YAxis axisLine={false} tickLine={false} tick={{ fontSize: 11, fill: palette.axis }} tickFormatter={(v) => compactINR(Number(v))} width={56} />
                  <Tooltip contentStyle={tip} formatter={(v, name) => [inr(Number(v)), String(name)]} cursor={{ fill: palette.track }} />
                  <RLegend iconType="circle" wrapperStyle={{ fontSize: 12 }} />
                  <Bar dataKey="online" name="Collected online" stackId="in" fill={palette.c1} maxBarSize={28} />
                  <Bar dataKey="at_salon" name="Taken at salon" stackId="in" fill={palette.c5} radius={[5, 5, 0, 0]} maxBarSize={28} />
                  <Line type="monotone" dataKey="paid_to_salons" name="Paid to salons" stroke={palette.c2} strokeWidth={2} dot={false} />
                  <Line type="monotone" dataKey="refunds" name="Refunds" stroke={palette.c4} strokeWidth={2} dot={false} strokeDasharray="5 4" />
                </ComposedChart>
              </ResponsiveContainer>
            </ChartBox>
          ) : (
            <Empty hint="No money moved in this range." />
          )}
        </Panel>

        <Panel title="Money in pocket — right now" subtitle="All time, whatever the range or city above">
          <CashBreakdown data={data.cash_position} />
        </Panel>

        <Panel title="How bookings were paid" subtitle="By what came in through the gateway">
          {mixTotal > 0 ? (
            <>
              <div className={styles.donutWrap}>
                <ResponsiveContainer width="100%" height="100%">
                  <PieChart>
                    <Pie data={mix} dataKey="bookings" nameKey="label" innerRadius="64%" outerRadius="92%" paddingAngle={2} stroke="none">
                      {mix.map((m) => <Cell key={m.key} fill={m.color} />)}
                    </Pie>
                    <Tooltip contentStyle={tip} formatter={(v, name) => [`${num(Number(v))} bookings`, String(name)]} />
                  </PieChart>
                </ResponsiveContainer>
                <div className={styles.donutCenter}><b>{num(mixTotal)}</b><span>bookings</span></div>
              </div>
              <Legend items={mix.map((m) => ({ key: m.key, label: m.label, value: m.bookings, color: m.color }))} total={mixTotal} />
              <div style={{ marginTop: 14 }}>
                <Note>
                  {Object.entries(data.payment_options).map(([k, n], i) => `${i ? ' · ' : 'Payment setting at booking: '}${OPTION_LABELS[k] ?? k} ${num(n)}`).join('')}
                </Note>
              </div>
            </>
          ) : (
            <Empty icon="receipt" />
          )}
        </Panel>

        <Panel
          title="Payment channels"
          subtitle="Every successful payment in range"
          csv={{ name: 'payment-channels', headers: ['Channel', 'Type', 'Mode', 'Payments', 'Amount'], rows: data.payment_types.map((t) => [t.channel, t.type, t.mode, t.count, t.amount]) }}
        >
          <BarList
            items={data.payment_types.map((t) => ({ key: `${t.channel}-${t.type}-${t.mode}`, label: t.label, value: t.amount, sub: plural(t.count, 'payment'), color: t.channel === 'online' ? palette.c1 : palette.c5 }))}
            format={inr}
            emptyHint="No payments in this range."
          />
        </Panel>

        <Panel
          title="What BookALook earned"
          subtitle="Commission on visits and plan payments, per period"
        >
          {data.trend.some((t) => t.commission || t.plans) ? (
            <ChartBox height={240}>
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={data.trend} margin={{ top: 8, right: 6, left: 0, bottom: 0 }}>
                  <CartesianGrid strokeDasharray="4 4" vertical={false} stroke={palette.grid} />
                  <XAxis dataKey="label" axisLine={false} tickLine={false} tick={{ fontSize: 11, fill: palette.axis }} minTickGap={24} />
                  <YAxis axisLine={false} tickLine={false} tick={{ fontSize: 11, fill: palette.axis }} tickFormatter={(v) => compactINR(Number(v))} width={52} />
                  <Tooltip contentStyle={tip} formatter={(v, name) => [inr(Number(v)), String(name)]} cursor={{ fill: palette.track }} />
                  <Bar dataKey="commission" name="Commission" stackId="e" fill={palette.c2} maxBarSize={26} />
                  <Bar dataKey="plans" name="Plan payments" stackId="e" fill={palette.c1} radius={[5, 5, 0, 0]} maxBarSize={26} />
                </BarChart>
              </ResponsiveContainer>
            </ChartBox>
          ) : (
            <Empty icon="crown" hint="No commission or plan payments in range." />
          )}
        </Panel>

        <Panel
          title="Plan payments by plan"
          subtitle="Approved in range"
          csv={{ name: 'plan-payments', headers: ['Plan', 'Payments', 'Cash', 'Coins used'], rows: data.plans.map((x) => [x.name, x.count, x.amount, x.coins]) }}
        >
          <BarList
            items={data.plans.map((x) => ({ key: x.name, label: x.name, value: x.amount, sub: `${plural(x.count, 'payment')}${x.coins ? ` · ${inr(x.coins)} in coins` : ''}` }))}
            format={inr}
            color={palette.c1}
            emptyHint="No plan payments approved in range."
          />
        </Panel>

        <Panel
          title="Refunds"
          subtitle={`${plural(c.refund_count, 'refund')} · ${pct(c.refund_rate)} of online money · rate ${pointsLabel(c.refund_rate, p.refund_rate)}`}
          csv={{ name: 'refunds-by-reason', headers: ['Reason', 'Refunds', 'Amount'], rows: data.refunds.by_reason.map((r) => [r.reason, r.count, r.amount]) }}
        >
          {data.refunds.by_status.length ? (
            <>
              <p className={styles.miniTitle}>By status</p>
              <BarList items={data.refunds.by_status.map((r) => ({ key: r.status, label: statusLabel(r.status), value: r.amount, sub: plural(r.count, 'refund'), color: r.status === 'processed' ? palette.c2 : r.status === 'failed' ? palette.c4 : palette.c3 }))} format={inr} />
              <p className={styles.miniTitle} style={{ marginTop: 16 }}>Top reasons</p>
              <BarList items={data.refunds.by_reason.map((r) => ({ key: r.reason, label: r.reason, value: r.amount, sub: plural(r.count, 'refund') }))} format={inr} color={palette.c4} />
            </>
          ) : (
            <Empty icon="repeat" title="No refunds in this range" />
          )}
        </Panel>

        <Panel
          title="Refunds by salon"
          subtitle="Where online money went back"
          csv={{ name: 'refunds-by-salon', headers: ['Salon', 'Refunds', 'Amount'], rows: data.refunds.by_salon.map((r) => [r.name, r.count, r.amount]) }}
        >
          <BarList items={data.refunds.by_salon.map((r) => ({ key: r.id, label: r.name, value: r.amount, sub: plural(r.count, 'refund') }))} format={inr} color={palette.c3} emptyHint="No refunds in this range." />
        </Panel>

        <Panel span={3} padded={false} title="Payouts for cycles that closed in range" subtitle="By where they stand and how the salon pays">
          <Table columns={payoutColumns} rows={data.payouts} rowKey={(r) => `${r.status}-${r.billing}`} exportName="payouts-by-status" empty="No payout cycles closed in this range" />
        </Panel>
      </Grid>
    </>
  );
}

const statusLabel = (s: string) => ({ processed: 'Sent back', pending: 'Pending', processing: 'Processing', failed: 'Failed', awaiting_manual: 'Awaiting manual payout' }[s] ?? s.replace(/_/g, ' '));

const pointsLabel = (curr: number, prev: number) => {
  const d = pointsOf(curr, prev);
  if (!d || d.dir === 'flat') return 'unchanged';
  return `${d.dir === 'up' ? 'up' : 'down'} ${d.pct} pts`;
};
