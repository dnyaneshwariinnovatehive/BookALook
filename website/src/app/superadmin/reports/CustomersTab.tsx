'use client';

import {
  Area, AreaChart, Bar, BarChart, CartesianGrid, Legend as RLegend, ResponsiveContainer, Tooltip, XAxis, YAxis,
} from 'recharts';
import { type DataColumn } from '@/components/admin/ui';
import styles from './reports.module.css';
import {
  BarList, ChartBox, Empty, Grid, Metric, MetricGrid, Note, Panel, TabSkeleton, Table,
  deltaOf, fmtDate, inr, num, pct, pointsOf, useChartPalette, useTooltipStyle, type SectionBase, type TabProps,
} from './parts';

interface Summary {
  customers: number;
  new: number;
  returning: number;
  repeaters: number;
  repeat_rate: number;
  visits: number;
  visits_per_customer: number;
  spend_per_customer: number;
  walk_in_customers: number;
}

interface TopCustomer { id: string; name: string; phone: string | null; visits: number; spend: number; salons: number; last_visit: string }

interface CustomersData extends SectionBase {
  summary: { current: Summary; previous: Summary };
  trend: { date: string; label: string; new: number; returning: number }[];
  frequency: { label: string; customers: number }[];
  spend_bands: { label: string; customers: number }[];
  multi_salon_customers: number;
  top: TopCustomer[];
  cohorts: { cohort: string; label: string; size: number; retention: { offset: number; customers: number; rate: number }[] }[];
  gender: { gender: string; visits: number; gmv: number }[];
  signups: { total: number; booked: number; conversion: number; trend: { date: string; label: string; signups: number }[] };
}

const topColumns: DataColumn<TopCustomer>[] = [
  {
    key: 'name',
    header: 'Customer',
    render: (r) => (
      <div>
        <span className={styles.cellMain}>{r.name}</span>
        {r.phone && <span className={styles.cellSub}>{r.phone}</span>}
      </div>
    ),
    sortValue: (r) => r.name,
    csvValue: (r) => r.name,
  },
  { key: 'visits', header: 'Visits', align: 'right', render: (r) => num(r.visits), sortValue: (r) => r.visits },
  { key: 'spend', header: 'Spend', align: 'right', render: (r) => <b>{inr(r.spend)}</b>, sortValue: (r) => r.spend },
  { key: 'avg', header: 'Avg bill', align: 'right', render: (r) => inr(r.visits ? r.spend / r.visits : 0), sortValue: (r) => (r.visits ? r.spend / r.visits : 0) },
  { key: 'salons', header: 'Salons', align: 'right', render: (r) => num(r.salons), sortValue: (r) => r.salons },
  { key: 'last', header: 'Last visit', align: 'right', render: (r) => fmtDate(r.last_visit), sortValue: (r) => r.last_visit },
];

export default function CustomersTab({ data: raw }: TabProps) {
  const palette = useChartPalette();
  const tip = useTooltipStyle(palette);
  const data = raw as CustomersData | null;
  if (!data) return <TabSkeleton />;

  const c = data.summary.current;
  const p = data.summary.previous;
  const maxCohort = data.cohorts.reduce((m, x) => Math.max(m, x.retention.length), 0);

  return (
    <>
      <MetricGrid cols={5}>
        <Metric label="Customers served" icon="users" value={num(c.customers)} delta={deltaOf(c.customers, p.customers)} hint="With a completed visit" />
        <Metric label="New customers" icon="userPlus" tone="teal" value={num(c.new)} delta={deltaOf(c.new, p.new)} hint="First visit ever, in this scope" />
        <Metric label="Returning customers" icon="repeat" tone="blue" value={num(c.returning)} delta={deltaOf(c.returning, p.returning)} hint="Had visited before" />
        <Metric label="Came back in range" icon="history" tone="amber" value={pct(c.repeat_rate)} delta={pointsOf(c.repeat_rate, p.repeat_rate)} points hint={`${num(c.repeaters)} with 2+ visits`} />
        <Metric label="Spend per customer" icon="rupee" value={inr(c.spend_per_customer)} delta={deltaOf(c.spend_per_customer, p.spend_per_customer)} hint={`${c.visits_per_customer} visits each`} />
        <Metric label="App sign-ups" icon="smartphone" tone="teal" value={num(data.signups.total)} hint={`${pct(data.signups.conversion)} have booked`} />
        <Metric label="Visits by app customers" icon="calendar" tone="blue" value={num(c.visits)} delta={deltaOf(c.visits, p.visits)} />
        <Metric label="Walk-in customers" icon="walkIn" tone="amber" value={num(c.walk_in_customers)} delta={deltaOf(c.walk_in_customers, p.walk_in_customers)} hint="Distinct phone numbers" />
        <Metric label="Use 2+ salons" icon="store" value={num(data.multi_salon_customers)} hint={c.customers ? `${pct((data.multi_salon_customers / c.customers) * 100)} of customers` : undefined} />
        <Metric label="Sign-ups who booked" icon="checkCircle" tone="teal" value={num(data.signups.booked)} hint="Any booking, ever" />
      </MetricGrid>

      <Grid cols={3}>
        <Panel
          span={2}
          title="New and returning customers"
          subtitle="Distinct customers with a completed visit in each period"
          csv={{ name: 'new-vs-returning', headers: ['Period', 'New', 'Returning'], rows: data.trend.map((t) => [t.label, t.new, t.returning]) }}
        >
          {data.trend.some((t) => t.new || t.returning) ? (
            <ChartBox height={280}>
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={data.trend} margin={{ top: 8, right: 6, left: 0, bottom: 0 }}>
                  <CartesianGrid strokeDasharray="4 4" vertical={false} stroke={palette.grid} />
                  <XAxis dataKey="label" axisLine={false} tickLine={false} tick={{ fontSize: 11, fill: palette.axis }} minTickGap={24} />
                  <YAxis axisLine={false} tickLine={false} tick={{ fontSize: 11, fill: palette.axis }} allowDecimals={false} width={32} />
                  <Tooltip contentStyle={tip} cursor={{ fill: palette.track }} />
                  <RLegend iconType="circle" wrapperStyle={{ fontSize: 12 }} />
                  <Bar dataKey="returning" name="Returning" stackId="c" fill={palette.c5} maxBarSize={26} />
                  <Bar dataKey="new" name="New" stackId="c" fill={palette.c2} radius={[5, 5, 0, 0]} maxBarSize={26} />
                </BarChart>
              </ResponsiveContainer>
            </ChartBox>
          ) : (
            <Empty icon="users" />
          )}
        </Panel>

        <Panel title="Visits per customer" subtitle="How often each customer came in range">
          <BarList items={data.frequency.map((f) => ({ key: f.label, label: f.label, value: f.customers }))} color={palette.c1} emptyHint="No customers in range." />
          <p className={styles.miniTitle} style={{ marginTop: 18 }}>Spend per customer</p>
          <BarList items={data.spend_bands.map((f) => ({ key: f.label, label: f.label, value: f.customers }))} color={palette.c2} />
        </Panel>

        <Panel
          span={2}
          title="Cohort retention"
          subtitle="Customers grouped by the month of their first visit, and the share who visited again in each month after"
          csv={{
            name: 'cohort-retention',
            headers: ['Cohort', 'Customers', ...Array.from({ length: maxCohort }, (_, i) => `Month ${i}`)],
            rows: data.cohorts.map((x) => [x.label, x.size, ...x.retention.map((r) => r.rate)]),
          }}
        >
          {data.cohorts.some((x) => x.size > 0) ? (
            <div style={{ overflowX: 'auto' }}>
              <table className={styles.cohort}>
                <thead>
                  <tr>
                    <th>First visit</th>
                    <th>Customers</th>
                    {Array.from({ length: maxCohort }, (_, i) => <th key={i}>{i === 0 ? 'Month 0' : `+${i}`}</th>)}
                  </tr>
                </thead>
                <tbody>
                  {data.cohorts.map((x) => (
                    <tr key={x.cohort}>
                      <td>{x.label}</td>
                      <td className={styles.size}>{num(x.size)}</td>
                      {Array.from({ length: maxCohort }, (_, i) => {
                        const r = x.retention[i];
                        if (!r) return <td key={i} />;
                        const share = x.size ? r.rate / 100 : 0;
                        return (
                          <td
                            key={i}
                            title={`${num(r.customers)} of ${num(x.size)}`}
                            style={{
                              background: x.size ? `color-mix(in srgb, ${palette.c1} ${Math.round(8 + share * 82)}%, transparent)` : 'var(--surface-2)',
                              color: share > 0.5 ? '#fff' : 'var(--text-body)',
                            }}
                          >
                            {x.size ? pct(r.rate, 0) : '—'}
                          </td>
                        );
                      })}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : (
            <Empty icon="history" hint="No first visits in the last six months of this range." />
          )}
          <div style={{ marginTop: 12 }}>
            <Note>Six cohorts ending with the month of the range&apos;s last day. Month 0 is the first-visit month itself.</Note>
          </div>
        </Panel>

        <Panel title="Who visits" subtitle="Completed visits by the guest's gender">
          <BarList items={data.gender.map((g) => ({ key: g.gender, label: g.gender, value: g.visits, sub: `${inr(g.gmv)} GMV` }))} color={palette.c5} emptyHint="No visits in range." />
        </Panel>

        <Panel span={2} padded={false} title="Top customers" subtitle="By spend on completed visits in range. Phone numbers are masked.">
          <Table columns={topColumns} rows={data.top} rowKey={(r) => r.id} exportName="top-customers" initialSort={{ key: 'spend', dir: 'desc' }} perPage={10} empty="No customers in range" />
        </Panel>

        <Panel title="App sign-ups" subtitle={`${num(data.signups.total)} new accounts · ${pct(data.signups.conversion)} booked`}>
          {data.signups.trend.some((t) => t.signups) ? (
            <ChartBox height={220}>
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={data.signups.trend} margin={{ top: 8, right: 6, left: 0, bottom: 0 }}>
                  <CartesianGrid strokeDasharray="4 4" vertical={false} stroke={palette.grid} />
                  <XAxis dataKey="label" axisLine={false} tickLine={false} tick={{ fontSize: 11, fill: palette.axis }} minTickGap={24} />
                  <YAxis axisLine={false} tickLine={false} tick={{ fontSize: 11, fill: palette.axis }} allowDecimals={false} width={28} />
                  <Tooltip contentStyle={tip} />
                  <Area type="monotone" dataKey="signups" name="Sign-ups" stroke={palette.c2} fill={palette.c2} fillOpacity={0.15} strokeWidth={2} />
                </AreaChart>
              </ResponsiveContainer>
            </ChartBox>
          ) : (
            <Empty icon="userPlus" title="No sign-ups in range" />
          )}
        </Panel>
      </Grid>
    </>
  );
}
