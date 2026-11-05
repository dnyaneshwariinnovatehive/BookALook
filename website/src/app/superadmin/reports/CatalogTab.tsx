'use client';

import { Cell, Pie, PieChart, ResponsiveContainer, Tooltip } from 'recharts';
import { type DataColumn } from '@/components/admin/ui';
import styles from './reports.module.css';
import {
  BarList, Empty, Grid, Growth, Legend, Metric, MetricGrid, Panel, TabSkeleton, Table,
  compactINR, inr, num, pct, useChartPalette, useTooltipStyle, type SectionBase, type TabProps,
} from './parts';

interface CategoryRow { name: string; lines: number; completed: number; revenue: number; avg_price: number; share: number }

interface ServiceRow {
  id: string;
  name: string;
  category: string;
  lines: number;
  completed: number;
  revenue: number;
  previous_revenue: number;
  growth: number | null;
  avg_price: number;
  discount: number;
  salons: number;
  avg_minutes: number | null;
  revenue_per_hour: number | null;
}

interface ComboRow { id: string; name: string; salon: string; bookings: number; completed: number; revenue: number; discount: number }

interface OfferRow {
  id: string | null;
  name: string;
  discount_label: string;
  redemptions: number;
  committed: number;
  reserved: number;
  released: number;
  discount_given: number;
  gmv: number;
  return_on_discount: number | null;
}

interface CatalogData extends SectionBase {
  categories: CategoryRow[];
  services: ServiceRow[];
  combos: ComboRow[];
  combo_share: { bookings: number; with_combo: number; rate: number };
  offers: OfferRow[];
  offer_totals: { redemptions: number; committed: number; discount_given: number; gmv: number };
  additions: { count: number; revenue: number; top: { name: string; count: number; revenue: number }[] };
}

const serviceColumns: DataColumn<ServiceRow>[] = [
  {
    key: 'name',
    header: 'Service',
    render: (r) => (
      <div>
        <span className={styles.cellMain}>{r.name}</span>
        <span className={styles.cellSub}>{r.category}</span>
      </div>
    ),
    sortValue: (r) => r.name,
    csvValue: (r) => r.name,
  },
  { key: 'category', header: 'Category', render: (r) => r.category, sortValue: (r) => r.category },
  { key: 'lines', header: 'Booked', align: 'right', render: (r) => num(r.lines), sortValue: (r) => r.lines },
  { key: 'completed', header: 'Done', align: 'right', render: (r) => num(r.completed), sortValue: (r) => r.completed },
  { key: 'revenue', header: 'Revenue', align: 'right', render: (r) => <b>{inr(r.revenue)}</b>, sortValue: (r) => r.revenue },
  { key: 'growth', header: 'vs prev.', align: 'right', render: (r) => <Growth value={r.growth} />, sortValue: (r) => r.growth },
  { key: 'avg_price', header: 'Avg price', align: 'right', render: (r) => inr(r.avg_price), sortValue: (r) => r.avg_price },
  { key: 'discount', header: 'Discounts', align: 'right', render: (r) => (r.discount ? inr(r.discount) : '—'), sortValue: (r) => r.discount },
  { key: 'avg_minutes', header: 'Avg mins', align: 'right', render: (r) => (r.avg_minutes ?? '—'), sortValue: (r) => r.avg_minutes },
  { key: 'revenue_per_hour', header: '₹ / chair-hour', align: 'right', render: (r) => (r.revenue_per_hour ? inr(r.revenue_per_hour) : '—'), sortValue: (r) => r.revenue_per_hour },
  { key: 'salons', header: 'Salons', align: 'right', render: (r) => num(r.salons), sortValue: (r) => r.salons },
];

const categoryColumns: DataColumn<CategoryRow>[] = [
  { key: 'name', header: 'Category', render: (r) => <span className={styles.cellMain}>{r.name}</span>, sortValue: (r) => r.name },
  { key: 'lines', header: 'Booked', align: 'right', render: (r) => num(r.lines), sortValue: (r) => r.lines },
  { key: 'completed', header: 'Done', align: 'right', render: (r) => num(r.completed), sortValue: (r) => r.completed },
  { key: 'revenue', header: 'Revenue', align: 'right', render: (r) => <b>{inr(r.revenue)}</b>, sortValue: (r) => r.revenue },
  { key: 'avg_price', header: 'Avg price', align: 'right', render: (r) => inr(r.avg_price), sortValue: (r) => r.avg_price },
  { key: 'share', header: 'Share', align: 'right', render: (r) => pct(r.share), sortValue: (r) => r.share },
];

const comboColumns: DataColumn<ComboRow>[] = [
  { key: 'name', header: 'Combo', render: (r) => <span className={styles.cellMain}>{r.name}</span>, sortValue: (r) => r.name },
  { key: 'salon', header: 'Salon', render: (r) => r.salon, sortValue: (r) => r.salon },
  { key: 'bookings', header: 'Bookings', align: 'right', render: (r) => num(r.bookings), sortValue: (r) => r.bookings },
  { key: 'completed', header: 'Done', align: 'right', render: (r) => num(r.completed), sortValue: (r) => r.completed },
  { key: 'revenue', header: 'Revenue', align: 'right', render: (r) => <b>{inr(r.revenue)}</b>, sortValue: (r) => r.revenue },
  { key: 'discount', header: 'Saved by customers', align: 'right', render: (r) => inr(r.discount), sortValue: (r) => r.discount },
];

const offerColumns: DataColumn<OfferRow>[] = [
  {
    key: 'name',
    header: 'Offer',
    render: (r) => (
      <div>
        <span className={styles.cellMain}>{r.name}</span>
        <span className={styles.cellSub}>{r.discount_label}</span>
      </div>
    ),
    sortValue: (r) => r.name,
    csvValue: (r) => r.name,
  },
  { key: 'redemptions', header: 'Claimed', align: 'right', render: (r) => num(r.redemptions), sortValue: (r) => r.redemptions },
  { key: 'committed', header: 'Used', align: 'right', render: (r) => num(r.committed), sortValue: (r) => r.committed },
  { key: 'reserved', header: 'Held', align: 'right', render: (r) => num(r.reserved), sortValue: (r) => r.reserved },
  { key: 'released', header: 'Released', align: 'right', render: (r) => num(r.released), sortValue: (r) => r.released },
  { key: 'discount_given', header: 'Discount given', align: 'right', render: (r) => inr(r.discount_given), sortValue: (r) => r.discount_given },
  { key: 'gmv', header: 'GMV from offer visits', align: 'right', render: (r) => <b>{inr(r.gmv)}</b>, sortValue: (r) => r.gmv },
  { key: 'roi', header: 'GMV per ₹1 off', align: 'right', render: (r) => (r.return_on_discount === null ? '—' : `₹${r.return_on_discount}`), sortValue: (r) => r.return_on_discount },
];

export default function CatalogTab({ data: raw }: TabProps) {
  const palette = useChartPalette();
  const tip = useTooltipStyle(palette);
  const data = raw as CatalogData | null;
  if (!data) return <TabSkeleton />;

  const colors = [palette.c1, palette.c2, palette.c5, palette.c3, palette.c4, palette.muted];
  const cats = data.categories.filter((c) => c.revenue > 0);
  const catTop = cats.slice(0, 5);
  const catRest = cats.slice(5).reduce((s, c) => s + c.revenue, 0);
  const donut = [...catTop.map((c, i) => ({ key: c.name, label: c.name, value: c.revenue, color: colors[i] })), ...(catRest > 0 ? [{ key: 'other', label: 'Other', value: catRest, color: colors[5] }] : [])];
  const catTotal = donut.reduce((s, d) => s + d.value, 0);
  const lines = data.categories.reduce((s, c) => s + c.lines, 0);
  const completedLines = data.categories.reduce((s, c) => s + c.completed, 0);
  const growers = data.services.filter((x) => x.previous_revenue > 0 && x.growth !== null).sort((a, b) => (b.growth ?? 0) - (a.growth ?? 0)).slice(0, 6);
  const earners = [...data.services].filter((x) => x.revenue_per_hour).sort((a, b) => (b.revenue_per_hour ?? 0) - (a.revenue_per_hour ?? 0)).slice(0, 6);

  return (
    <>
      <MetricGrid cols={6}>
        <Metric label="Services booked" icon="catalog" value={num(lines)} hint={`${num(completedLines)} done`} />
        <Metric label="Service revenue" icon="rupee" tone="teal" value={inr(catTotal)} hint="Completed lines at booked price" />
        <Metric label="Bookings with a combo" icon="sparkle" tone="amber" value={pct(data.combo_share.rate)} hint={`${num(data.combo_share.with_combo)} of ${num(data.combo_share.bookings)}`} />
        <Metric label="First-time offers used" icon="userPlus" tone="blue" value={num(data.offer_totals.committed)} hint={`${num(data.offer_totals.redemptions)} claimed`} />
        <Metric label="Offer discount given" icon="percent" tone="rose" value={inr(data.offer_totals.discount_given)} hint={`${inr(data.offer_totals.gmv)} GMV from those visits`} />
        <Metric label="Added at the counter" icon="plus" value={num(data.additions.count)} hint={`${inr(data.additions.revenue)} extra`} />
      </MetricGrid>

      <Grid cols={3}>
        <Panel title="Revenue by category" subtitle="Completed services">
          {catTotal > 0 ? (
            <>
              <div className={styles.donutWrap}>
                <ResponsiveContainer width="100%" height="100%">
                  <PieChart>
                    <Pie data={donut} dataKey="value" nameKey="label" innerRadius="64%" outerRadius="92%" paddingAngle={2} stroke="none">
                      {donut.map((d) => <Cell key={d.key} fill={d.color} />)}
                    </Pie>
                    <Tooltip contentStyle={tip} formatter={(v, name) => [inr(Number(v)), String(name)]} />
                  </PieChart>
                </ResponsiveContainer>
                <div className={styles.donutCenter}><b>{compactINR(catTotal)}</b><span>revenue</span></div>
              </div>
              <Legend items={donut} total={catTotal} format={(n) => compactINR(n)} />
            </>
          ) : (
            <Empty icon="catalog" />
          )}
        </Panel>

        <Panel span={2} padded={false} title="Categories" subtitle="Every category booked in range">
          <Table columns={categoryColumns} rows={data.categories} rowKey={(r) => r.name} exportName="categories" initialSort={{ key: 'revenue', dir: 'desc' }} perPage={10} />
        </Panel>

        <Panel title="Top services by revenue" subtitle="Completed in range">
          <BarList items={data.services.slice(0, 8).map((x) => ({ key: x.id, label: x.name, value: x.revenue, sub: `${num(x.completed)} done · avg ${inr(x.avg_price)}` }))} format={inr} emptyHint="No services booked." />
        </Panel>
        <Panel title="Fastest growing services" subtitle="Revenue against the previous period">
          <BarList
            items={growers.map((x) => ({ key: x.id, label: x.name, value: x.growth ?? 0, sub: `${inr(x.previous_revenue)} → ${inr(x.revenue)}`, color: (x.growth ?? 0) >= 0 ? palette.c2 : palette.c4 }))}
            format={(n) => `${n > 0 ? '+' : ''}${pct(n)}`}
            emptyHint="Needs a previous period to compare with."
          />
        </Panel>
        <Panel title="Best earners per chair-hour" subtitle="Average price for the time a service takes">
          <BarList items={earners.map((x) => ({ key: x.id, label: x.name, value: x.revenue_per_hour ?? 0, sub: `${inr(x.avg_price)} · ${x.avg_minutes} min` }))} format={inr} color={palette.c5} emptyHint="No timed services yet." />
        </Panel>

        <Panel span={3} padded={false} title="Services" subtitle="Grouped by the catalogue service they are built from">
          <Table columns={serviceColumns} rows={data.services} rowKey={(r) => r.id} exportName="services" initialSort={{ key: 'revenue', dir: 'desc' }} perPage={20} />
        </Panel>

        <Panel span={2} padded={false} title="Combos" subtitle="Bookings that included each combo">
          <Table columns={comboColumns} rows={data.combos} rowKey={(r) => r.id} exportName="combos" initialSort={{ key: 'revenue', dir: 'desc' }} empty="No combos booked in range" />
        </Panel>
        <Panel title="Added at the counter" subtitle="Services a salon added during the visit">
          <BarList items={data.additions.top.map((a) => ({ key: a.name, label: a.name, value: a.count, sub: inr(a.revenue) }))} color={palette.c2} emptyHint="Nothing added at the counter in range." />
        </Panel>

        <Panel span={3} padded={false} title="First-time offers" subtitle="Claimed in range — used, still held for an upcoming visit, or released">
          <Table columns={offerColumns} rows={data.offers} rowKey={(r) => r.id ?? r.name} exportName="first-time-offers" initialSort={{ key: 'redemptions', dir: 'desc' }} empty="No first-time offers claimed in range" />
        </Panel>
      </Grid>
    </>
  );
}
