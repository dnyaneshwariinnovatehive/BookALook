'use client';

import {
  Bar, BarChart, CartesianGrid, Cell, Legend as RLegend, Pie, PieChart, ResponsiveContainer, Tooltip, XAxis, YAxis,
} from 'recharts';
import styles from './reports.module.css';
import type { Kpis } from './OverviewTab';
import {
  BarList, ChartBox, Empty, Grid, Legend, Metric, MetricGrid, Panel, TabSkeleton,
  deltaOf, inr, num, pct, pointsOf, useChartPalette, useTooltipStyle, type SectionBase, type TabProps,
} from './parts';

interface BookingsData extends SectionBase {
  kpis: Kpis;
  previous: Kpis;
  trend: { date: string; label: string; completed: number; cancelled: number; no_show: number; upcoming: number }[];
  funnel: { key: string; label: string; value: number }[];
  outcomes: { key: string; label: string; value: number }[];
  cancelled_by: { label: string; count: number }[];
  cancellation_reasons: { reason: string; count: number }[];
  lead_time: { label: string; count: number }[];
  heatmap: { hours: number[]; rows: { day: string; cells: { hour: number; count: number }[] }[]; max: number };
  by_weekday: { day: string; bookings: number; completed: number; gmv: number; per_day: number }[];
  by_hour: { hour: number; label: string; bookings: number }[];
  other: { rescheduled: number; booked_for_others: number; with_first_time_offer: number; avg_per_day: number };
}

export default function BookingsTab({ data: raw }: TabProps) {
  const palette = useChartPalette();
  const tip = useTooltipStyle(palette);
  const data = raw as BookingsData | null;
  if (!data) return <TabSkeleton />;

  const k = data.kpis;
  const p = data.previous;
  const outcomeColors: Record<string, string> = { completed: palette.c2, upcoming: palette.c1, cancelled: palette.c3, no_show: palette.c4, abandoned: palette.muted };
  const outcomes = data.outcomes.map((o) => ({ ...o, color: outcomeColors[o.key] ?? palette.c5 })).filter((o) => o.value > 0);
  const outcomeTotal = outcomes.reduce((s, o) => s + o.value, 0);
  const funnelTop = Math.max(1, data.funnel[0]?.value ?? 1);
  const peakHour = [...data.by_hour].sort((a, b) => b.bookings - a.bookings)[0];
  const peakDay = [...data.by_weekday].sort((a, b) => b.per_day - a.per_day)[0];

  return (
    <>
      <MetricGrid cols={6}>
        <Metric label="Bookings" icon="calendar" value={num(k.bookings)} delta={deltaOf(k.bookings, p.bookings)} hint={`${num(data.other.avg_per_day)} a day`} />
        <Metric label="Completion rate" icon="checkCircle" tone="teal" value={pct(k.completion_rate)} delta={pointsOf(k.completion_rate, p.completion_rate)} points hint="Of bookings already due" />
        <Metric label="Cancellation rate" icon="close" tone="amber" value={pct(k.cancellation_rate)} delta={pointsOf(k.cancellation_rate, p.cancellation_rate)} invert points hint={`${num(k.cancelled)} cancelled`} />
        <Metric label="No-show rate" icon="userX" tone="rose" value={pct(k.no_show_rate)} delta={pointsOf(k.no_show_rate, p.no_show_rate)} invert points hint={`${num(k.no_show)} no-shows`} />
        <Metric label="Checkouts abandoned" icon="alert" tone="amber" value={num(k.abandoned_checkouts)} delta={deltaOf(k.abandoned_checkouts, p.abandoned_checkouts)} invert hint="Payment hold ran out" />
        <Metric label="Walk-ins" icon="walkIn" tone="blue" value={num(k.walk_in)} delta={deltaOf(k.walk_in, p.walk_in)} hint={k.bookings ? `${pct((k.walk_in / k.bookings) * 100)} of bookings` : undefined} />
      </MetricGrid>

      <Grid cols={3}>
        <Panel
          span={2}
          title="Outcomes over time"
          subtitle="Every booking by what became of it, dated by the visit"
          csv={{ name: 'booking-outcomes', headers: ['Period', 'Completed', 'Upcoming', 'Cancelled', 'No-show'], rows: data.trend.map((t) => [t.label, t.completed, t.upcoming, t.cancelled, t.no_show]) }}
        >
          {data.trend.some((t) => t.completed || t.cancelled || t.no_show || t.upcoming) ? (
            <ChartBox height={300}>
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={data.trend} margin={{ top: 8, right: 6, left: 0, bottom: 0 }}>
                  <CartesianGrid strokeDasharray="4 4" vertical={false} stroke={palette.grid} />
                  <XAxis dataKey="label" axisLine={false} tickLine={false} tick={{ fontSize: 11, fill: palette.axis }} minTickGap={24} />
                  <YAxis axisLine={false} tickLine={false} tick={{ fontSize: 11, fill: palette.axis }} allowDecimals={false} width={36} />
                  <Tooltip contentStyle={tip} cursor={{ fill: palette.track }} />
                  <RLegend iconType="circle" wrapperStyle={{ fontSize: 12 }} />
                  <Bar dataKey="completed" name="Completed" stackId="o" fill={palette.c2} maxBarSize={26} />
                  <Bar dataKey="upcoming" name="Upcoming" stackId="o" fill={palette.c1} maxBarSize={26} />
                  <Bar dataKey="cancelled" name="Cancelled" stackId="o" fill={palette.c3} maxBarSize={26} />
                  <Bar dataKey="no_show" name="No-show" stackId="o" fill={palette.c4} radius={[5, 5, 0, 0]} maxBarSize={26} />
                </BarChart>
              </ResponsiveContainer>
            </ChartBox>
          ) : (
            <Empty icon="calendar" />
          )}
        </Panel>

        <Panel title="Where bookings end up" subtitle={`${num(outcomeTotal)} including abandoned checkouts`}>
          {outcomeTotal > 0 ? (
            <>
              <div className={styles.donutWrap}>
                <ResponsiveContainer width="100%" height="100%">
                  <PieChart>
                    <Pie data={outcomes} dataKey="value" nameKey="label" innerRadius="64%" outerRadius="92%" paddingAngle={2} stroke="none">
                      {outcomes.map((o) => <Cell key={o.key} fill={o.color} />)}
                    </Pie>
                    <Tooltip contentStyle={tip} formatter={(v, name) => [num(Number(v)), String(name)]} />
                  </PieChart>
                </ResponsiveContainer>
                <div className={styles.donutCenter}><b>{num(outcomeTotal)}</b><span>bookings</span></div>
              </div>
              <Legend items={outcomes.map((o) => ({ key: o.key, label: o.label, value: o.value, color: o.color }))} total={outcomeTotal} />
            </>
          ) : (
            <Empty icon="calendar" />
          )}
        </Panel>

        <Panel title="App booking funnel" subtitle="From starting checkout to a completed visit (walk-ins excluded)">
          <div className={styles.funnel}>
            {data.funnel.map((f, i) => {
              const prev = i > 0 ? data.funnel[i - 1].value : f.value;
              return (
                <div key={f.key} className={styles.funnelStep}>
                  <span className={styles.funnelLabel}>{f.label}</span>
                  <div className={styles.funnelBar}>
                    <span style={{ width: `${Math.max(6, (f.value / funnelTop) * 100)}%`, background: [palette.c5, palette.c1, palette.c3, palette.c2][i % 4] }}>{num(f.value)}</span>
                  </div>
                  <span className={styles.funnelRate}>
                    {pct((f.value / funnelTop) * 100, 0)}
                    {i > 0 && <small>{prev ? pct((f.value / prev) * 100, 0) : '—'} of step</small>}
                  </span>
                </div>
              );
            })}
          </div>
        </Panel>

        <Panel
          span={2}
          title="Peak times"
          subtitle={`Bookings by weekday and start hour${peakHour && peakHour.bookings ? ` · busiest hour ${peakHour.label}` : ''}${peakDay && peakDay.per_day ? ` · busiest day ${peakDay.day}` : ''}`}
          csv={{ name: 'peak-times', headers: ['Day', ...data.heatmap.hours.map((h) => `${String(h).padStart(2, '0')}:00`)], rows: data.heatmap.rows.map((r) => [r.day, ...r.cells.map((c) => c.count)]) }}
        >
          <Heatmap data={data.heatmap} color={palette.c1} />
        </Panel>

        <Panel
          title="By weekday"
          subtitle="Average bookings on each weekday in range"
          csv={{ name: 'bookings-by-weekday', headers: ['Day', 'Bookings', 'Completed', 'GMV', 'Average per day'], rows: data.by_weekday.map((d) => [d.day, d.bookings, d.completed, d.gmv, d.per_day]) }}
        >
          <ChartBox height={240}>
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={data.by_weekday} margin={{ top: 8, right: 6, left: 0, bottom: 0 }}>
                <CartesianGrid strokeDasharray="4 4" vertical={false} stroke={palette.grid} />
                <XAxis dataKey="day" axisLine={false} tickLine={false} tick={{ fontSize: 11, fill: palette.axis }} />
                <YAxis axisLine={false} tickLine={false} tick={{ fontSize: 11, fill: palette.axis }} width={32} />
                <Tooltip
                  contentStyle={tip}
                  cursor={{ fill: palette.track }}
                  formatter={(v, name, item) => {
                    const row = (item as { payload?: { gmv: number; bookings: number } }).payload;
                    return [`${Number(v)} a day · ${num(row?.bookings)} total · ${inr(row?.gmv)}`, String(name)];
                  }}
                />
                <Bar dataKey="per_day" name="Bookings a day" fill={palette.c1} radius={[5, 5, 0, 0]} maxBarSize={34} />
              </BarChart>
            </ResponsiveContainer>
          </ChartBox>
        </Panel>

        <Panel title="How far ahead people book" subtitle="Days between booking and the visit (app bookings)">
          <BarList items={data.lead_time.map((l) => ({ key: l.label, label: l.label, value: l.count }))} color={palette.c5} />
        </Panel>

        <Panel title="Who cancels" subtitle={`${num(k.cancelled)} cancellations`}>
          <BarList items={data.cancelled_by.map((c) => ({ key: c.label, label: c.label, value: c.count }))} color={palette.c3} emptyHint="No cancellations in this range." />
          <p className={styles.miniTitle} style={{ marginTop: 18 }}>Top reasons</p>
          <BarList items={data.cancellation_reasons.map((r) => ({ key: r.reason, label: r.reason, value: r.count }))} color={palette.c4} emptyHint="No reasons recorded." />
        </Panel>

        <Panel title="Other signals" subtitle="Changes and special bookings">
          <BarList
            items={[
              { key: 'resched', label: 'Rescheduled bookings', value: data.other.rescheduled },
              { key: 'others', label: 'Booked for someone else', value: data.other.booked_for_others },
              { key: 'offer', label: 'Used a first-time offer', value: data.other.with_first_time_offer },
            ]}
            max={Math.max(1, k.bookings)}
            color={palette.c2}
          />
        </Panel>
      </Grid>
    </>
  );
}

function Heatmap({ data, color }: { data: BookingsData['heatmap']; color: string }) {
  if (!data.max) return <Empty icon="clock" />;
  return (
    <>
      <div className={styles.heatmap} style={{ gridTemplateColumns: `44px repeat(${data.hours.length}, minmax(22px, 1fr))` }}>
        <span />
        {data.hours.map((h) => <span key={h} className={styles.heatHour}>{String(h).padStart(2, '0')}</span>)}
        {data.rows.map((r) => (
          <div key={r.day} className={styles.heatRow}>
            <span className={styles.heatLabel}>{r.day}</span>
            {r.cells.map((c) => {
              const share = c.count / data.max;
              return (
                <span
                  key={c.hour}
                  className={styles.heatCell}
                  title={`${r.day} ${String(c.hour).padStart(2, '0')}:00 — ${c.count} booking${c.count === 1 ? '' : 's'}`}
                  style={{
                    background: c.count ? `color-mix(in srgb, ${color} ${Math.round(12 + share * 88)}%, transparent)` : 'var(--surface-2)',
                    color: share > 0.55 ? '#fff' : 'var(--text-body)',
                  }}
                >
                  {c.count || ''}
                </span>
              );
            })}
          </div>
        ))}
      </div>
      <div className={styles.heatScale}>
        Fewer
        <span style={{ background: `linear-gradient(90deg, color-mix(in srgb, ${color} 12%, transparent), ${color})` }} />
        More · busiest slot {num(data.max)}
      </div>
    </>
  );
}
