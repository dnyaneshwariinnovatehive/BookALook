'use client';

import { Bar, BarChart, CartesianGrid, Legend as RLegend, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import { type DataColumn } from '@/components/admin/ui';
import styles from './reports.module.css';
import {
  BarList, ChartBox, Empty, Grid, Growth, Metric, MetricGrid, Note, Panel, TabSkeleton, Table,
  compactINR, inr, num, pct, plural, useChartPalette, useTooltipStyle, type SectionBase, type TabProps,
} from './parts';

interface PlaceRow {
  name: string;
  id: string | null;
  city_id: string | null;
  city: string;
  salons: number;
  bookings: number;
  completed: number;
  cancelled: number;
  no_show: number;
  gmv: number;
  previous_gmv: number;
  growth: number | null;
  avg_ticket: number;
  cancellation_rate: number;
  no_show_rate: number;
  customers: number;
  online_collected: number;
  customers_living: number;
  customers_per_salon: number | null;
  gmv_per_salon: number;
  share: number;
}

interface PlacesData extends SectionBase {
  cities: PlaceRow[];
  areas: PlaceRow[];
  coverage: { salons_with_area: number; salons_active: number };
}

const columns = (kind: 'city' | 'area', onPick?: (id: string) => void): DataColumn<PlaceRow>[] => [
  {
    key: 'name',
    header: kind === 'city' ? 'City' : 'Area',
    render: (r) => (
      <div>
        {kind === 'city' && onPick && r.city_id ? (
          <button type="button" className={styles.link} style={{ background: 'none', border: 0, padding: 0, cursor: 'pointer', font: 'inherit' }} onClick={() => onPick(r.city_id!)} title="Narrow the whole report to this city">
            {r.name}
          </button>
        ) : (
          <span className={styles.cellMain}>{r.name}</span>
        )}
      </div>
    ),
    sortValue: (r) => r.name,
    csvValue: (r) => r.name,
  },
  ...(kind === 'area' ? [{ key: 'city', header: 'City', render: (r: PlaceRow) => r.city, sortValue: (r: PlaceRow) => r.city }] : []),
  { key: 'salons', header: 'Salons', align: 'right', render: (r) => num(r.salons), sortValue: (r) => r.salons },
  { key: 'bookings', header: 'Bookings', align: 'right', render: (r) => num(r.bookings), sortValue: (r) => r.bookings },
  { key: 'completed', header: 'Completed', align: 'right', render: (r) => num(r.completed), sortValue: (r) => r.completed },
  { key: 'gmv', header: 'GMV', align: 'right', render: (r) => <b>{inr(r.gmv)}</b>, sortValue: (r) => r.gmv },
  { key: 'growth', header: 'vs prev.', align: 'right', render: (r) => <Growth value={r.growth} />, sortValue: (r) => r.growth },
  { key: 'share', header: 'Share', align: 'right', render: (r) => pct(r.share), sortValue: (r) => r.share },
  { key: 'avg_ticket', header: 'Avg bill', align: 'right', render: (r) => inr(r.avg_ticket), sortValue: (r) => r.avg_ticket },
  { key: 'gmv_per_salon', header: 'GMV / salon', align: 'right', render: (r) => inr(r.gmv_per_salon), sortValue: (r) => r.gmv_per_salon },
  { key: 'cancellation_rate', header: 'Cancel %', align: 'right', render: (r) => pct(r.cancellation_rate), sortValue: (r) => r.cancellation_rate },
  { key: 'no_show_rate', header: 'No-show %', align: 'right', render: (r) => pct(r.no_show_rate), sortValue: (r) => r.no_show_rate },
  { key: 'customers', header: 'Customers', align: 'right', render: (r) => num(r.customers), sortValue: (r) => r.customers },
  { key: 'online_collected', header: 'Online', align: 'right', render: (r) => inr(r.online_collected), sortValue: (r) => r.online_collected },
  { key: 'customers_living', header: 'Live here', align: 'right', render: (r) => num(r.customers_living), sortValue: (r) => r.customers_living },
  { key: 'customers_per_salon', header: 'Cust. / salon', align: 'right', render: (r) => (r.customers_per_salon === null ? '—' : num(r.customers_per_salon)), sortValue: (r) => r.customers_per_salon },
];

export default function PlacesTab({ data: raw, onPickCity }: TabProps & { onPickCity: (id: string) => void }) {
  const palette = useChartPalette();
  const tip = useTooltipStyle(palette);
  const data = raw as PlacesData | null;
  if (!data) return <TabSkeleton />;

  const top = data.cities[0];
  const areasWithSalons = data.areas.filter((a) => a.id && a.salons > 0);
  const underserved = data.areas
    .filter((a) => a.id && a.customers_living > 0)
    .sort((a, b) => (b.customers_per_salon ?? Infinity) - (a.customers_per_salon ?? Infinity))
    .slice(0, 8);
  const chartCities = data.cities.slice(0, 10);
  const chartAreas = data.areas.filter((a) => a.gmv > 0 || a.previous_gmv > 0).slice(0, 12);

  return (
    <>
      <MetricGrid cols={4}>
        <Metric label="Cities trading" icon="pin" value={num(data.cities.filter((c) => c.completed > 0).length)} hint={`${num(data.cities.length)} with salons or customers`} />
        <Metric label="Areas with salons" icon="pin" tone="teal" value={num(areasWithSalons.length)} hint={`${num(data.areas.filter((a) => a.completed > 0).length)} trading in range`} />
        <Metric label="Leading city" icon="sparkle" tone="amber" value={top?.name ?? '—'} hint={top ? `${pct(top.share)} of GMV · ${inr(top.gmv)}` : undefined} />
        <Metric
          label="Salons with an area set"
          icon="store"
          tone="blue"
          value={`${num(data.coverage.salons_with_area)} / ${num(data.coverage.salons_active)}`}
          hint={data.coverage.salons_active ? `${pct((data.coverage.salons_with_area / data.coverage.salons_active) * 100, 0)} — area figures cover these` : undefined}
        />
      </MetricGrid>

      <Grid cols={2}>
        <Panel title="GMV by city" subtitle="This range against the one before">
          {chartCities.length ? (
            <ChartBox height={Math.max(200, chartCities.length * 42)}>
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={chartCities} layout="vertical" margin={{ top: 4, right: 16, left: 4, bottom: 4 }}>
                  <CartesianGrid strokeDasharray="3 3" horizontal={false} stroke={palette.grid} />
                  <XAxis type="number" tick={{ fontSize: 11, fill: palette.axis }} tickLine={false} axisLine={false} tickFormatter={(v) => compactINR(Number(v))} />
                  <YAxis type="category" dataKey="name" tick={{ fontSize: 12, fill: palette.axis }} tickLine={false} axisLine={false} width={96} />
                  <Tooltip contentStyle={tip} formatter={(v, name) => [inr(Number(v)), String(name)]} cursor={{ fill: palette.track }} />
                  <RLegend iconType="circle" wrapperStyle={{ fontSize: 12 }} />
                  <Bar dataKey="gmv" name="This range" fill={palette.c1} radius={[0, 5, 5, 0]} maxBarSize={16} />
                  <Bar dataKey="previous_gmv" name="Previous" fill={palette.muted} radius={[0, 5, 5, 0]} maxBarSize={16} />
                </BarChart>
              </ResponsiveContainer>
            </ChartBox>
          ) : (
            <Empty icon="pin" />
          )}
        </Panel>

        <Panel title="GMV by area" subtitle="Top areas this range against the one before">
          {chartAreas.length ? (
            <ChartBox height={Math.max(200, chartAreas.length * 36)}>
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={chartAreas.map((a) => ({ ...a, label: `${a.name} · ${a.city}` }))} layout="vertical" margin={{ top: 4, right: 16, left: 4, bottom: 4 }}>
                  <CartesianGrid strokeDasharray="3 3" horizontal={false} stroke={palette.grid} />
                  <XAxis type="number" tick={{ fontSize: 11, fill: palette.axis }} tickLine={false} axisLine={false} tickFormatter={(v) => compactINR(Number(v))} />
                  <YAxis type="category" dataKey="label" tick={{ fontSize: 11, fill: palette.axis }} tickLine={false} axisLine={false} width={150} />
                  <Tooltip contentStyle={tip} formatter={(v, name) => [inr(Number(v)), String(name)]} cursor={{ fill: palette.track }} />
                  <Bar dataKey="gmv" name="This range" fill={palette.c2} radius={[0, 5, 5, 0]} maxBarSize={14} />
                  <Bar dataKey="previous_gmv" name="Previous" fill={palette.muted} radius={[0, 5, 5, 0]} maxBarSize={14} />
                </BarChart>
              </ResponsiveContainer>
            </ChartBox>
          ) : (
            <Empty icon="pin" hint="No area-level trading yet — set an area on salons to see this." />
          )}
        </Panel>

        <Panel span={2} padded={false} title="Cities" subtitle="Click a city to narrow the whole report to it">
          <Table columns={columns('city', onPickCity)} rows={data.cities} rowKey={(r) => r.city_id ?? r.name} exportName="cities" initialSort={{ key: 'gmv', dir: 'desc' }} />
        </Panel>

        <Panel span={2} padded={false} title="Areas" subtitle="Every area with salons, bookings or customers living there. “No area set” collects salons without one.">
          <Table columns={columns('area')} rows={data.areas} rowKey={(r) => `${r.city_id}-${r.id ?? 'none'}`} exportName="areas" initialSort={{ key: 'gmv', dir: 'desc' }} perPage={20} />
        </Panel>

        <Panel title="Demand against supply" subtitle="Customers living in an area for every salon there — high numbers are room to recruit salons">
          <BarList
            items={underserved.map((a) => ({
              key: `${a.city_id}-${a.id}`,
              label: `${a.name} · ${a.city}`,
              value: a.customers_per_salon ?? a.customers_living,
              sub: a.salons ? `${plural(a.customers_living, 'customer')} · ${plural(a.salons, 'salon')}` : `${plural(a.customers_living, 'customer')} · no salon yet`,
              color: a.salons ? palette.c5 : palette.c4,
            }))}
            format={(n) => num(n)}
            emptyHint="Customers have not set an area yet."
          />
        </Panel>

        <Panel title="Reliability by area" subtitle="Cancellation and no-show rates where there were at least 10 bookings">
          <BarList
            items={data.areas
              .filter((a) => a.bookings >= 10)
              .sort((a, b) => b.cancellation_rate + b.no_show_rate - (a.cancellation_rate + a.no_show_rate))
              .slice(0, 8)
              .map((a) => ({
                key: `${a.city_id}-${a.id ?? 'none'}`,
                label: `${a.name} · ${a.city}`,
                value: a.cancellation_rate + a.no_show_rate,
                sub: `${pct(a.cancellation_rate)} cancelled · ${pct(a.no_show_rate)} no-show · ${plural(a.bookings, 'booking')}`,
              }))}
            format={(n) => pct(n)}
            color={palette.c3}
            emptyHint="Not enough bookings per area yet."
          />
          <div style={{ marginTop: 12 }}>
            <Note>Areas come from the salon&apos;s address. Customers&apos; areas come from their profile.</Note>
          </div>
        </Panel>
      </Grid>
    </>
  );
}
