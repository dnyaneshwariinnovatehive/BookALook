'use client';

import Link from 'next/link';
import { type DataColumn } from '@/components/admin/ui';
import styles from './reports.module.css';
import {
  BarList, Grid, Growth, Metric, MetricGrid, Note, Panel, Pill, TabSkeleton, Table,
  inr, num, pct, plural, useChartPalette, type SectionBase, type TabProps,
} from './parts';

interface SalonRow {
  id: string;
  name: string;
  city: string;
  area: string | null;
  status: string;
  billing: string;
  bookings: number;
  completed: number;
  cancelled: number;
  no_show: number;
  upcoming: number;
  walk_in: number;
  completion_rate: number;
  cancellation_rate: number;
  no_show_rate: number;
  gmv: number;
  previous_gmv: number;
  growth: number | null;
  avg_ticket: number;
  online_collected: number;
  commission: number;
  customers: number;
  repeat_customers: number;
  repeat_rate: number;
  reviews: number;
  avg_rating: number | null;
  rating_all_time: number | null;
  team: number;
  utilisation: number | null;
}

interface ProviderRow {
  id: string;
  name: string;
  specialization: string | null;
  salon_id: string;
  salon: string;
  services: number;
  revenue: number;
  booked_minutes: number;
  capacity_minutes: number;
  leave_days: number;
  utilisation: number | null;
}

interface SalonsData extends SectionBase {
  salons: SalonRow[];
  providers: ProviderRow[];
  summary: {
    active: number;
    trading: number;
    dormant: number;
    new_in_range: number;
    commission_model: number;
    subscription_plan: number;
    pending_approval: number;
  };
}

const hours = (m: number) => `${num(m / 60)} h`;

const salonColumns: DataColumn<SalonRow>[] = [
  {
    key: 'name',
    header: 'Salon',
    render: (r) => (
      <div>
        <Link className={styles.link} href={`/superadmin/salons/${r.id}`}>{r.name}</Link>
        <span className={styles.cellSub}>{r.area ? `${r.area} · ${r.city}` : r.city}</span>
      </div>
    ),
    sortValue: (r) => r.name,
    csvValue: (r) => r.name,
  },
  { key: 'city', header: 'City', render: (r) => r.city, sortValue: (r) => r.city },
  { key: 'area', header: 'Area', render: (r) => r.area ?? '—', sortValue: (r) => r.area ?? '' },
  {
    key: 'billing',
    header: 'Model',
    render: (r) => <Pill tone={r.billing === 'Commission Model' ? 'accent' : 'neutral'}>{r.billing === 'Commission Model' ? 'Commission' : 'Plan'}</Pill>,
    sortValue: (r) => r.billing,
  },
  { key: 'status', header: 'Status', render: (r) => <Pill tone={r.status === 'active' ? 'good' : 'warn'}>{r.status.replace(/_/g, ' ')}</Pill>, sortValue: (r) => r.status },
  { key: 'bookings', header: 'Bookings', align: 'right', render: (r) => num(r.bookings), sortValue: (r) => r.bookings },
  { key: 'completed', header: 'Done', align: 'right', render: (r) => num(r.completed), sortValue: (r) => r.completed },
  { key: 'gmv', header: 'GMV', align: 'right', render: (r) => <b>{inr(r.gmv)}</b>, sortValue: (r) => r.gmv },
  { key: 'growth', header: 'vs prev.', align: 'right', render: (r) => <Growth value={r.growth} />, sortValue: (r) => r.growth },
  { key: 'avg_ticket', header: 'Avg bill', align: 'right', render: (r) => inr(r.avg_ticket), sortValue: (r) => r.avg_ticket },
  { key: 'online_collected', header: 'Online', align: 'right', render: (r) => inr(r.online_collected), sortValue: (r) => r.online_collected },
  { key: 'commission', header: 'Commission', align: 'right', render: (r) => (r.commission ? inr(r.commission) : '—'), sortValue: (r) => r.commission },
  { key: 'completion_rate', header: 'Completion', align: 'right', render: (r) => pct(r.completion_rate), sortValue: (r) => r.completion_rate },
  { key: 'cancellation_rate', header: 'Cancel %', align: 'right', render: (r) => pct(r.cancellation_rate), sortValue: (r) => r.cancellation_rate },
  { key: 'no_show_rate', header: 'No-show %', align: 'right', render: (r) => pct(r.no_show_rate), sortValue: (r) => r.no_show_rate },
  { key: 'customers', header: 'Customers', align: 'right', render: (r) => num(r.customers), sortValue: (r) => r.customers },
  { key: 'repeat_rate', header: 'Repeat %', align: 'right', render: (r) => pct(r.repeat_rate), sortValue: (r) => r.repeat_rate },
  {
    key: 'rating',
    header: 'Rating',
    align: 'right',
    render: (r) => (r.avg_rating ?? r.rating_all_time ? `${(r.avg_rating ?? r.rating_all_time)!.toFixed(1)} ★` : '—'),
    sortValue: (r) => r.avg_rating ?? r.rating_all_time,
  },
  { key: 'reviews', header: 'Reviews', align: 'right', render: (r) => num(r.reviews), sortValue: (r) => r.reviews },
  { key: 'team', header: 'Team', align: 'right', render: (r) => num(r.team), sortValue: (r) => r.team },
  { key: 'utilisation', header: 'Utilisation', align: 'right', render: (r) => pct(r.utilisation), sortValue: (r) => r.utilisation },
];

const providerColumns: DataColumn<ProviderRow>[] = [
  {
    key: 'name',
    header: 'Team member',
    render: (r) => (
      <div>
        <span className={styles.cellMain}>{r.name}</span>
        <span className={styles.cellSub}>{r.specialization || 'Stylist'}</span>
      </div>
    ),
    sortValue: (r) => r.name,
    csvValue: (r) => r.name,
  },
  { key: 'salon', header: 'Salon', render: (r) => <Link className={styles.link} href={`/superadmin/salons/${r.salon_id}`}>{r.salon}</Link>, sortValue: (r) => r.salon },
  { key: 'services', header: 'Services', align: 'right', render: (r) => num(r.services), sortValue: (r) => r.services },
  { key: 'revenue', header: 'Revenue', align: 'right', render: (r) => inr(r.revenue), sortValue: (r) => r.revenue },
  { key: 'booked', header: 'Booked', align: 'right', render: (r) => hours(r.booked_minutes), sortValue: (r) => r.booked_minutes },
  { key: 'capacity', header: 'Working', align: 'right', render: (r) => hours(r.capacity_minutes), sortValue: (r) => r.capacity_minutes },
  { key: 'leave', header: 'Leave days', align: 'right', render: (r) => num(r.leave_days), sortValue: (r) => r.leave_days },
  {
    key: 'utilisation',
    header: 'Utilisation',
    align: 'right',
    render: (r) => <Pill tone={r.utilisation === null ? 'neutral' : r.utilisation >= 60 ? 'good' : r.utilisation >= 30 ? 'warn' : 'bad'}>{pct(r.utilisation)}</Pill>,
    sortValue: (r) => r.utilisation,
  },
];

export default function SalonsTab({ data: raw }: TabProps) {
  const palette = useChartPalette();
  const data = raw as SalonsData | null;
  if (!data) return <TabSkeleton />;

  const s = data.summary;
  const trading = data.salons.filter((r) => r.completed > 0);
  const capacity = data.providers.reduce((a, p) => a + p.capacity_minutes, 0);
  const booked = data.providers.reduce((a, p) => a + p.booked_minutes, 0);
  const growers = data.salons.filter((r) => r.growth !== null && r.previous_gmv > 0).sort((a, b) => (b.growth ?? 0) - (a.growth ?? 0)).slice(0, 6);
  const unreliable = data.salons.filter((r) => r.bookings >= 10).sort((a, b) => b.no_show_rate + b.cancellation_rate - (a.no_show_rate + a.cancellation_rate)).slice(0, 6);
  const loyal = data.salons.filter((r) => r.customers >= 3).sort((a, b) => b.repeat_rate - a.repeat_rate).slice(0, 6);
  const dormant = data.salons.filter((r) => r.status === 'active' && r.bookings === 0);

  return (
    <>
      <MetricGrid cols={6}>
        <Metric label="Active salons" icon="store" value={num(s.active)} hint={`${num(s.pending_approval)} awaiting approval`} />
        <Metric label="Trading in range" icon="checkCircle" tone="teal" value={num(s.trading)} hint={s.active ? `${pct((s.trading / s.active) * 100, 0)} of active` : undefined} />
        <Metric label="No bookings in range" icon="alert" tone="rose" value={num(s.dormant)} hint="Active but quiet" />
        <Metric label="Approved in range" icon="userPlus" tone="blue" value={num(s.new_in_range)} hint="New salons" />
        <Metric label="Billing mix" icon="crown" tone="amber" value={`${num(s.subscription_plan)} / ${num(s.commission_model)}`} hint="Plan / Commission Model" />
        <Metric label="Team utilisation" icon="clock" value={capacity ? pct((booked / capacity) * 100) : '—'} hint={`${hours(booked)} booked of ${hours(capacity)}`} title="Booked service minutes against scheduled working minutes" />
      </MetricGrid>

      <Panel padded={false} title="Salon leaderboard" subtitle="Every active salon, and any that traded in range. Sort by any column; GMV is completed visits.">
        <Table columns={salonColumns} rows={data.salons} rowKey={(r) => r.id} exportName="salon-leaderboard" initialSort={{ key: 'gmv', dir: 'desc' }} perPage={20} />
      </Panel>

      <Grid cols={3}>
        <Panel title="Top by GMV" subtitle="Completed visits in range">
          <BarList
            items={trading.slice(0, 8).map((r) => ({ key: r.id, label: r.name, value: r.gmv, sub: `${plural(r.completed, 'visit')} · avg ${inr(r.avg_ticket)}` }))}
            format={inr}
            emptyHint="No completed visits in range."
          />
        </Panel>
        <Panel title="Fastest growing" subtitle="GMV against the previous period">
          <BarList
            items={growers.map((r) => ({ key: r.id, label: r.name, value: r.growth ?? 0, sub: `${inr(r.previous_gmv)} → ${inr(r.gmv)}`, color: (r.growth ?? 0) >= 0 ? palette.c2 : palette.c4 }))}
            format={(n) => `${n > 0 ? '+' : ''}${pct(n)}`}
            emptyHint="Needs a previous period to compare with."
          />
        </Panel>
        <Panel title="Most loyal customers" subtitle="Share of customers who came back in range (3+ customers)">
          <BarList
            items={loyal.map((r) => ({ key: r.id, label: r.name, value: r.repeat_rate, sub: `${num(r.repeat_customers)} of ${num(r.customers)} returned` }))}
            format={(n) => pct(n)}
            max={100}
            color={palette.c5}
            emptyHint="Not enough customers yet."
          />
        </Panel>
        <Panel title="Watch list" subtitle="Highest cancellation + no-show rate (10+ bookings)">
          <BarList
            items={unreliable.map((r) => ({ key: r.id, label: r.name, value: r.cancellation_rate + r.no_show_rate, sub: `${pct(r.cancellation_rate)} cancelled · ${pct(r.no_show_rate)} no-show` }))}
            format={(n) => pct(n)}
            color={palette.c3}
            emptyHint="No salon has 10+ bookings in range."
          />
        </Panel>
        <Panel title="Best rated in range" subtitle="Average stars from reviews written in range">
          <BarList
            items={data.salons.filter((r) => r.reviews > 0).sort((a, b) => (b.avg_rating ?? 0) - (a.avg_rating ?? 0)).slice(0, 6).map((r) => ({ key: r.id, label: r.name, value: r.avg_rating ?? 0, sub: plural(r.reviews, 'review') }))}
            format={(n) => `${n.toFixed(2)} ★`}
            max={5}
            color={palette.c3}
            emptyHint="No reviews in range."
          />
        </Panel>
        <Panel title="Quiet salons" subtitle="Active, but no bookings in range">
          <BarList
            items={dormant.slice(0, 8).map((r) => ({ key: r.id, label: r.name, value: r.rating_all_time ?? 0, sub: `${r.city} · ${r.billing}` }))}
            format={(n) => (n ? `${n.toFixed(1)} ★` : 'no rating')}
            max={5}
            color={palette.muted}
            emptyHint="Every active salon had bookings."
          />
        </Panel>
      </Grid>

      <Panel padded={false} title="Team utilisation" subtitle="Booked service time against scheduled working time, less approved full-day leave">
        <Table columns={providerColumns} rows={data.providers} rowKey={(r) => r.id} exportName="team-utilisation" initialSort={{ key: 'utilisation', dir: 'desc' }} perPage={10} />
        <div style={{ padding: '0 18px 16px' }}>
          <Note>Working time comes from each team member&apos;s weekly hours (or the salon&apos;s, when they follow it). Completed, upcoming and in-chair bookings count; cancelled ones do not.</Note>
        </div>
      </Panel>
    </>
  );
}
