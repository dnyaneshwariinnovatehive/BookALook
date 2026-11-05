'use client';

import Link from 'next/link';
import {
  Area, Bar, CartesianGrid, Cell, ComposedChart, Legend as RLegend, Line, Pie, PieChart,
  ResponsiveContainer, Tooltip, XAxis, YAxis,
} from 'recharts';
import styles from './reports.module.css';
import {
  ChartBox, Empty, Fact, Grid, Legend, Metric, MetricGrid, Panel, TabSkeleton, compactINR, deltaOf, inr, num, pct, pointsOf,
  useChartPalette, useTooltipStyle, type SectionBase, type TabProps,
} from './parts';

export interface Kpis {
  gmv: number;
  bookings: number;
  completed: number;
  cancelled: number;
  no_show: number;
  upcoming: number;
  walk_in: number;
  abandoned_checkouts: number;
  completion_rate: number;
  cancellation_rate: number;
  no_show_rate: number;
  avg_ticket: number;
  customers: number;
  new_customers: number;
  returning_customers: number;
  trading_salons: number;
  online_collected: number;
  at_salon_collected: number;
  online_share: number;
  refunds: number;
  commission: number;
  plan_payments: number;
  earnings: number;
  take_rate: number;
  paid_to_salons: number;
  reviews: number;
  avg_rating: number | null;
}

interface OverviewData extends SectionBase {
  kpis: { current: Kpis; previous: Kpis };
  trend: { date: string; label: string; gmv: number; bookings: number; completed: number; online_collected: number; commission: number; plans: number; earnings: number }[];
  status_mix: { key: string; label: string; value: number }[];
  source_mix: { key: string; label: string; value: number }[];
  highlights: {
    best_bucket: { label: string; gmv: number } | null;
    top_city: { name: string; gmv: number } | null;
    top_salon: { id: string; name: string; gmv: number } | null;
    top_service: { name: string; bookings: number } | null;
  };
}

export default function OverviewTab({ data: raw }: TabProps) {
  const palette = useChartPalette();
  const tip = useTooltipStyle(palette);
  const data = raw as OverviewData | null;
  if (!data) return <TabSkeleton />;

  const c = data.kpis.current;
  const p = data.kpis.previous;
  const statusColors: Record<string, string> = { completed: palette.c2, upcoming: palette.c1, cancelled: palette.c3, no_show: palette.c4 };
  const status = data.status_mix.map((s) => ({ ...s, color: statusColors[s.key] ?? palette.c5 }));
  const statusTotal = status.reduce((s, x) => s + x.value, 0);
  const hasTrend = data.trend.some((t) => t.gmv > 0 || t.bookings > 0);
  const h = data.highlights;

  return (
    <>
      <MetricGrid cols={6}>
        <Metric label="GMV (completed visits)" icon="rupee" value={inr(c.gmv)} delta={deltaOf(c.gmv, p.gmv)} hint={`vs ${compactINR(p.gmv)}`} title="What completed visits were billed, dated by the visit" />
        <Metric label="Bookings" icon="calendar" tone="blue" value={num(c.bookings)} delta={deltaOf(c.bookings, p.bookings)} hint={`${num(c.walk_in)} walk-ins`} />
        <Metric label="Completed visits" icon="checkCircle" tone="teal" value={num(c.completed)} delta={deltaOf(c.completed, p.completed)} hint={`${pct(c.completion_rate)} of those due`} />
        <Metric label="Average bill" icon="receipt" tone="amber" value={inr(c.avg_ticket)} delta={deltaOf(c.avg_ticket, p.avg_ticket)} hint="Per completed visit" />
        <Metric label="Customers served" icon="users" tone="blue" value={num(c.customers)} delta={deltaOf(c.customers, p.customers)} hint={`${num(c.new_customers)} new · ${num(c.returning_customers)} returning`} />
        <Metric label="Salons trading" icon="store" value={num(c.trading_salons)} delta={deltaOf(c.trading_salons, p.trading_salons)} hint="With a completed visit" />
        <Metric label="Collected online" icon="smartphone" tone="teal" value={inr(c.online_collected)} delta={deltaOf(c.online_collected, p.online_collected)} hint={`${pct(c.online_share)} of all money taken`} />
        <Metric label="BookALook earnings" icon="crown" value={inr(c.earnings)} delta={deltaOf(c.earnings, p.earnings)} hint={`Take rate ${pct(c.take_rate)} of GMV`} title="Commission on visits in range plus plan payments approved in range" />
        <Metric label="Paid out to salons" icon="wallet" tone="blue" value={inr(c.paid_to_salons)} delta={deltaOf(c.paid_to_salons, p.paid_to_salons)} hint="Payouts distributed" />
        <Metric label="Refunds" icon="repeat" tone="rose" value={inr(c.refunds)} delta={deltaOf(c.refunds, p.refunds)} invert hint="Of online payments" />
        <Metric label="Cancellation rate" icon="close" tone="amber" value={pct(c.cancellation_rate)} delta={pointsOf(c.cancellation_rate, p.cancellation_rate)} invert points hint={`${num(c.cancelled)} cancelled`} />
        <Metric label="No-show rate" icon="userX" tone="rose" value={pct(c.no_show_rate)} delta={pointsOf(c.no_show_rate, p.no_show_rate)} invert points hint={`${num(c.no_show)} no-shows`} />
      </MetricGrid>

      <Grid cols={3}>
        <Panel
          span={2}
          title="GMV and bookings"
          subtitle="Completed-visit value (area) against all bookings (line)"
          csv={{ name: 'gmv-and-bookings', headers: ['Period', 'GMV', 'Bookings', 'Completed', 'Collected online', 'Commission', 'Plan payments', 'Earnings'], rows: data.trend.map((t) => [t.label, t.gmv, t.bookings, t.completed, t.online_collected, t.commission, t.plans, t.earnings]) }}
        >
          {hasTrend ? (
            <ChartBox height={300}>
              <ResponsiveContainer width="100%" height="100%">
                <ComposedChart data={data.trend} margin={{ top: 8, right: 6, left: 0, bottom: 0 }}>
                  <defs>
                    <linearGradient id="ovGmv" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="0%" stopColor={palette.c1} stopOpacity={0.3} />
                      <stop offset="100%" stopColor={palette.c1} stopOpacity={0} />
                    </linearGradient>
                  </defs>
                  <CartesianGrid strokeDasharray="4 4" vertical={false} stroke={palette.grid} />
                  <XAxis dataKey="label" axisLine={false} tickLine={false} tick={{ fontSize: 11, fill: palette.axis }} minTickGap={24} />
                  <YAxis yAxisId="m" axisLine={false} tickLine={false} tick={{ fontSize: 11, fill: palette.axis }} tickFormatter={(v) => compactINR(Number(v))} width={56} />
                  <YAxis yAxisId="n" orientation="right" axisLine={false} tickLine={false} tick={{ fontSize: 11, fill: palette.axis }} width={32} allowDecimals={false} />
                  <Tooltip contentStyle={tip} formatter={(v, name) => [name === 'Bookings' ? num(Number(v)) : inr(Number(v)), String(name)]} />
                  <RLegend iconType="circle" wrapperStyle={{ fontSize: 12 }} />
                  <Area yAxisId="m" type="monotone" dataKey="gmv" name="GMV" stroke={palette.c1} strokeWidth={2.2} fill="url(#ovGmv)" />
                  <Line yAxisId="n" type="monotone" dataKey="bookings" name="Bookings" stroke={palette.c2} strokeWidth={2} dot={false} />
                </ComposedChart>
              </ResponsiveContainer>
            </ChartBox>
          ) : (
            <Empty hint="No bookings in this range — try a wider one." />
          )}
        </Panel>

        <Panel title="Booking outcomes" subtitle={`${num(statusTotal)} bookings in range`}>
          {statusTotal > 0 ? (
            <>
              <div className={styles.donutWrap}>
                <ResponsiveContainer width="100%" height="100%">
                  <PieChart>
                    <Pie data={status} dataKey="value" nameKey="label" innerRadius="64%" outerRadius="92%" paddingAngle={2} stroke="none">
                      {status.map((s) => <Cell key={s.key} fill={s.color} />)}
                    </Pie>
                    <Tooltip contentStyle={tip} formatter={(v, name) => [num(Number(v)), String(name)]} />
                  </PieChart>
                </ResponsiveContainer>
                <div className={styles.donutCenter}><b>{pct(c.completion_rate, 0)}</b><span>completed</span></div>
              </div>
              <Legend items={status.map((s) => ({ key: s.key, label: s.label, value: s.value, color: s.color }))} total={statusTotal} />
            </>
          ) : (
            <Empty icon="calendar" />
          )}
        </Panel>

        <Panel span={2} title="Money in and money earned" subtitle="Collected online against what BookALook earned (commission + plans)">
          {hasTrend ? (
            <ChartBox height={260}>
              <ResponsiveContainer width="100%" height="100%">
                <ComposedChart data={data.trend} margin={{ top: 8, right: 6, left: 0, bottom: 0 }}>
                  <CartesianGrid strokeDasharray="4 4" vertical={false} stroke={palette.grid} />
                  <XAxis dataKey="label" axisLine={false} tickLine={false} tick={{ fontSize: 11, fill: palette.axis }} minTickGap={24} />
                  <YAxis axisLine={false} tickLine={false} tick={{ fontSize: 11, fill: palette.axis }} tickFormatter={(v) => compactINR(Number(v))} width={56} />
                  <Tooltip contentStyle={tip} formatter={(v, name) => [inr(Number(v)), String(name)]} cursor={{ fill: palette.track }} />
                  <RLegend iconType="circle" wrapperStyle={{ fontSize: 12 }} />
                  <Bar dataKey="online_collected" name="Collected online" fill={palette.c5} radius={[5, 5, 0, 0]} maxBarSize={28} />
                  <Bar dataKey="commission" name="Commission" stackId="e" fill={palette.c2} maxBarSize={28} />
                  <Bar dataKey="plans" name="Plan payments" stackId="e" fill={palette.c1} radius={[5, 5, 0, 0]} maxBarSize={28} />
                </ComposedChart>
              </ResponsiveContainer>
            </ChartBox>
          ) : (
            <Empty />
          )}
        </Panel>

        <Panel title="Highlights" subtitle="What stood out in this range">
          <ul className={styles.facts}>
            <Fact icon="sparkle" label="Best period" value={h.best_bucket ? inr(h.best_bucket.gmv) : '—'} sub={h.best_bucket?.label} />
            <Fact icon="pin" label="Top city" value={h.top_city?.name ?? '—'} sub={h.top_city ? `${inr(h.top_city.gmv)} GMV` : undefined} />
            <Fact
              icon="store"
              label="Top salon"
              value={h.top_salon ? <Link className={styles.link} href={`/superadmin/salons/${h.top_salon.id}`}>{h.top_salon.name}</Link> : '—'}
              sub={h.top_salon ? `${inr(h.top_salon.gmv)} GMV` : undefined}
            />
            <Fact icon="catalog" label="Most booked service" value={h.top_service?.name ?? '—'} sub={h.top_service ? `${num(h.top_service.bookings)} bookings` : undefined} />
            {data.source_mix.map((s) => (
              <Fact key={s.key} icon={s.key === 'walk_in' ? 'walkIn' : 'smartphone'} label={s.label} value={num(s.value)} sub={c.bookings ? pct((s.value / c.bookings) * 100, 0) : undefined} />
            ))}
            <Fact icon="alert" label="Checkouts abandoned" value={num(c.abandoned_checkouts)} sub="Payment not finished" />
            <Fact icon="star" label="Average rating" value={c.avg_rating ? `${c.avg_rating.toFixed(2)} ★` : '—'} sub={`${num(c.reviews)} reviews`} />
          </ul>
        </Panel>
      </Grid>
    </>
  );
}
