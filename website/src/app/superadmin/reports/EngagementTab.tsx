'use client';

import Link from 'next/link';
import {
  CartesianGrid, ComposedChart, Bar, Line, Legend as RLegend, ResponsiveContainer, Tooltip, XAxis, YAxis,
} from 'recharts';
import { type DataColumn } from '@/components/admin/ui';
import styles from './reports.module.css';
import {
  BarList, ChartBox, Empty, Fact, Facts, Grid, Metric, MetricGrid, Panel, TabSkeleton, Table,
  inr, num, pct, plural, useChartPalette, useTooltipStyle, type SectionBase, type TabProps,
} from './parts';

interface TemplateRow { name: string; campaigns: number; sent: number; delivered: number; read: number; read_rate: number }
interface WaRow { category: string; total: number; sent: number; delivered: number; read: number; failed: number; delivery_rate: number }
interface CoinRow { type: string; label: string; transactions: number; coins: number; value: number }

interface EngagementData extends SectionBase {
  reviews: {
    count: number;
    avg_rating: number | null;
    review_rate: number;
    distribution: { stars: number; count: number }[];
    trend: { date: string; label: string; reviews: number; avg_rating: number | null }[];
    lowest_rated: { id: string; name: string; reviews: number; avg_rating: number }[];
  };
  complaints: { count: number; by_status: Record<string, number>; avg_resolution_hours: number | null; per_1000_visits: number };
  campaigns: {
    count: number;
    salons: number;
    recipients: number;
    sent: number;
    delivered: number;
    read: number;
    failed: number;
    skipped: number;
    delivery_rate: number;
    read_rate: number;
    by_status: Record<string, number>;
    by_template: TemplateRow[];
    top_salons: { id: string; name: string; campaigns: number; sent: number }[];
  };
  whatsapp: { total: number; by_category: WaRow[]; trend: { date: string; label: string; messages: number }[] };
  coins: { by_type: CoinRow[]; balance: number; wallets: number };
  notifications: { count: number; read: number; read_rate: number };
}

const templateColumns: DataColumn<TemplateRow>[] = [
  { key: 'name', header: 'Template', render: (r) => <span className={styles.cellMain}>{r.name}</span>, sortValue: (r) => r.name },
  { key: 'campaigns', header: 'Campaigns', align: 'right', render: (r) => num(r.campaigns), sortValue: (r) => r.campaigns },
  { key: 'sent', header: 'Sent', align: 'right', render: (r) => num(r.sent), sortValue: (r) => r.sent },
  { key: 'delivered', header: 'Delivered', align: 'right', render: (r) => num(r.delivered), sortValue: (r) => r.delivered },
  { key: 'read', header: 'Read', align: 'right', render: (r) => num(r.read), sortValue: (r) => r.read },
  { key: 'read_rate', header: 'Read rate', align: 'right', render: (r) => pct(r.read_rate), sortValue: (r) => r.read_rate },
];

const waColumns: DataColumn<WaRow>[] = [
  { key: 'category', header: 'Kind', render: (r) => <span className={styles.cellMain}>{r.category}</span>, sortValue: (r) => r.category },
  { key: 'total', header: 'Messages', align: 'right', render: (r) => num(r.total), sortValue: (r) => r.total },
  { key: 'delivered', header: 'Delivered', align: 'right', render: (r) => num(r.delivered), sortValue: (r) => r.delivered },
  { key: 'read', header: 'Read', align: 'right', render: (r) => num(r.read), sortValue: (r) => r.read },
  { key: 'failed', header: 'Failed', align: 'right', render: (r) => num(r.failed), sortValue: (r) => r.failed },
  { key: 'delivery_rate', header: 'Delivery rate', align: 'right', render: (r) => pct(r.delivery_rate), sortValue: (r) => r.delivery_rate },
];

const coinColumns: DataColumn<CoinRow>[] = [
  { key: 'label', header: 'Movement', render: (r) => <span className={styles.cellMain}>{r.label}</span>, sortValue: (r) => r.label },
  { key: 'transactions', header: 'Entries', align: 'right', render: (r) => num(r.transactions), sortValue: (r) => r.transactions },
  { key: 'coins', header: 'Coins', align: 'right', render: (r) => num(r.coins), sortValue: (r) => r.coins },
  { key: 'value', header: 'Worth', align: 'right', render: (r) => inr(r.value), sortValue: (r) => r.value },
];

const STATUS_LABEL: Record<string, string> = { open: 'Open', in_progress: 'In progress', resolved: 'Resolved', closed: 'Closed', dismissed: 'Dismissed' };

export default function EngagementTab({ data: raw }: TabProps) {
  const palette = useChartPalette();
  const tip = useTooltipStyle(palette);
  const data = raw as EngagementData | null;
  if (!data) return <TabSkeleton />;

  const r = data.reviews;
  const cm = data.campaigns;
  const earned = data.coins.by_type.find((c) => c.type === 'earned');
  const spent = data.coins.by_type.find((c) => c.type === 'redeemed');
  const openComplaints = (data.complaints.by_status.open ?? 0) + (data.complaints.by_status.in_progress ?? 0);

  return (
    <>
      <MetricGrid cols={6}>
        <Metric label="Reviews" icon="star" value={num(r.count)} hint={`${pct(r.review_rate)} of completed visits`} />
        <Metric label="Average rating" icon="star" tone="amber" value={r.avg_rating ? `${r.avg_rating.toFixed(2)} ★` : '—'} hint="Reviews written in range" />
        <Metric label="Complaints" icon="alert" tone="rose" value={num(data.complaints.count)} hint={`${data.complaints.per_1000_visits} per 1,000 visits · ${num(openComplaints)} open`} />
        <Metric label="Campaigns sent" icon='message' tone="blue" value={num(cm.count)} hint={`${plural(cm.salons, 'salon')} · ${plural(cm.sent, "message")}`} />
        <Metric label="Campaign read rate" icon="checkCircle" tone="teal" value={pct(cm.read_rate)} hint={`${pct(cm.delivery_rate)} delivered`} />
        <Metric label="Coins earned / spent" icon="coins" tone="amber" value={`${num(earned?.coins)} / ${num(Math.abs(spent?.coins ?? 0))}`} hint={`${num(data.coins.balance)} held by ${plural(data.coins.wallets, 'salon')}`} />
      </MetricGrid>

      <Grid cols={3}>
        <Panel
          span={2}
          title="Reviews and rating over time"
          subtitle="Number of reviews (bars) and their average stars (line)"
          csv={{ name: 'reviews-over-time', headers: ['Period', 'Reviews', 'Average rating'], rows: r.trend.map((t) => [t.label, t.reviews, t.avg_rating ?? '']) }}
        >
          {r.trend.some((t) => t.reviews) ? (
            <ChartBox height={260}>
              <ResponsiveContainer width="100%" height="100%">
                <ComposedChart data={r.trend} margin={{ top: 8, right: 6, left: 0, bottom: 0 }}>
                  <CartesianGrid strokeDasharray="4 4" vertical={false} stroke={palette.grid} />
                  <XAxis dataKey="label" axisLine={false} tickLine={false} tick={{ fontSize: 11, fill: palette.axis }} minTickGap={24} />
                  <YAxis yAxisId="n" axisLine={false} tickLine={false} tick={{ fontSize: 11, fill: palette.axis }} allowDecimals={false} width={28} />
                  <YAxis yAxisId="r" orientation="right" domain={[1, 5]} axisLine={false} tickLine={false} tick={{ fontSize: 11, fill: palette.axis }} width={28} />
                  <Tooltip contentStyle={tip} cursor={{ fill: palette.track }} />
                  <RLegend iconType="circle" wrapperStyle={{ fontSize: 12 }} />
                  <Bar yAxisId="n" dataKey="reviews" name="Reviews" fill={palette.c5} radius={[5, 5, 0, 0]} maxBarSize={24} />
                  <Line yAxisId="r" type="monotone" dataKey="avg_rating" name="Average rating" stroke={palette.c3} strokeWidth={2} connectNulls dot={false} />
                </ComposedChart>
              </ResponsiveContainer>
            </ChartBox>
          ) : (
            <Empty icon="star" title="No reviews in this range" />
          )}
        </Panel>

        <Panel title="Rating spread" subtitle={`${num(r.count)} reviews in range`}>
          <BarList
            items={r.distribution.map((d) => ({ key: String(d.stars), label: `${'★'.repeat(d.stars)}${'☆'.repeat(5 - d.stars)}`, value: d.count, color: d.stars >= 4 ? palette.c2 : d.stars === 3 ? palette.c3 : palette.c4 }))}
            max={Math.max(1, ...r.distribution.map((d) => d.count))}
          />
        </Panel>

        <Panel title="Lowest rated salons" subtitle="Average from reviews in range (3+ reviews)">
          <BarList
            items={r.lowest_rated.map((s) => ({ key: s.id, label: <Link className={styles.link} href={`/superadmin/salons/${s.id}`}>{s.name}</Link>, value: s.avg_rating, sub: plural(s.reviews, 'review') }))}
            format={(n) => `${n.toFixed(2)} ★`}
            max={5}
            color={palette.c4}
            emptyHint="No salon has three reviews in range yet."
          />
        </Panel>

        <Panel title="Complaints" subtitle="Raised in range">
          {data.complaints.count ? (
            <Facts>
              {Object.entries(data.complaints.by_status).map(([k, n]) => (
                <Fact key={k} icon={k === 'resolved' || k === 'closed' ? 'checkCircle' : 'alert'} label={STATUS_LABEL[k] ?? k} value={num(n)} />
              ))}
              <Fact icon="clock" label="Average time to resolve" value={data.complaints.avg_resolution_hours === null ? '—' : `${data.complaints.avg_resolution_hours} h`} />
              <Fact icon="chart" label="Per 1,000 completed visits" value={data.complaints.per_1000_visits} />
            </Facts>
          ) : (
            <Empty icon="checkCircle" title="No complaints in this range" />
          )}
        </Panel>

        <Panel title="Campaign reach" subtitle="Salon WhatsApp campaigns started in range">
          {cm.count ? (
            <BarList
              items={[
                { key: 'rec', label: 'Audience', value: cm.recipients, color: palette.muted },
                { key: 'sent', label: 'Sent', value: cm.sent, color: palette.c5 },
                { key: 'del', label: 'Delivered', value: cm.delivered, color: palette.c1 },
                { key: 'read', label: 'Read', value: cm.read, color: palette.c2 },
                { key: 'fail', label: 'Failed', value: cm.failed, color: palette.c4 },
                { key: 'skip', label: 'Skipped (no consent etc.)', value: cm.skipped, color: palette.c3 },
              ]}
              max={Math.max(1, cm.recipients, cm.sent)}
            />
          ) : (
            <Empty icon="message" title="No campaigns in this range" />
          )}
        </Panel>

        <Panel span={2} padded={false} title="Campaigns by template" subtitle="Which messages salons send, and how many get read">
          <Table columns={templateColumns} rows={cm.by_template} rowKey={(x) => x.name} exportName="campaign-templates" initialSort={{ key: 'campaigns', dir: 'desc' }} empty="No campaigns in range" />
        </Panel>
        <Panel title="Most active marketers" subtitle="Salons by campaign messages sent">
          <BarList items={cm.top_salons.map((s) => ({ key: s.id, label: s.name, value: s.sent, sub: plural(s.campaigns, 'campaign') }))} color={palette.c5} emptyHint="No campaigns in range." />
        </Panel>

        <Panel span={2} padded={false} title="WhatsApp messages" subtitle={`${num(data.whatsapp.total)} messages in range, by kind`}>
          <Table columns={waColumns} rows={data.whatsapp.by_category} rowKey={(x) => x.category} exportName="whatsapp-messages" initialSort={{ key: 'total', dir: 'desc' }} empty="No WhatsApp messages in range" />
        </Panel>
        <Panel title="In-app notifications" subtitle="Created in range">
          <Facts>
            <Fact icon="bell" label="Sent" value={num(data.notifications.count)} />
            <Fact icon="checkCircle" label="Opened" value={num(data.notifications.read)} sub={pct(data.notifications.read_rate)} />
          </Facts>
        </Panel>

        <Panel span={3} padded={false} title="Reward coins" subtitle={`Salon coin movements in range · ${num(data.coins.balance)} coins currently held`}>
          <Table columns={coinColumns} rows={data.coins.by_type} rowKey={(x) => x.type} exportName="coin-movements" initialSort={{ key: 'coins', dir: 'desc' }} empty="No coin movements in range" />
        </Panel>
      </Grid>
    </>
  );
}
