'use client';

import { useMemo, useState } from 'react';
import Icon, { type IconName } from '@/components/admin/Icon';
import { localISODate } from '@/components/admin/ui';
import styles from './reports.module.css';
import { ErrorBox, exportSectionCSV, fmtDate, useSection, type Scope } from './parts';
import OverviewTab from './OverviewTab';
import MoneyTab from './MoneyTab';
import BookingsTab from './BookingsTab';
import PlacesTab from './PlacesTab';
import SalonsTab from './SalonsTab';
import CatalogTab from './CatalogTab';
import CustomersTab from './CustomersTab';
import EngagementTab from './EngagementTab';

/**
 * Platform Reporting — the owner's analytics across the whole marketplace.
 *
 * One scope (date range, city, area) drives every tab, and every figure is
 * compared with the same length of time just before it. Each tab loads its own
 * section from /superadmin/reports/analytics/{section}; every table and the
 * whole tab can be downloaded as CSV. Read-only: nothing here writes back.
 */

const TABS: { key: string; label: string; icon: IconName }[] = [
  { key: 'overview', label: 'Overview', icon: 'dashboard' },
  { key: 'money', label: 'Money', icon: 'rupee' },
  { key: 'bookings', label: 'Bookings', icon: 'calendar' },
  { key: 'places', label: 'Cities & areas', icon: 'pin' },
  { key: 'salons', label: 'Salons & teams', icon: 'store' },
  { key: 'catalog', label: 'Services', icon: 'catalog' },
  { key: 'customers', label: 'Customers', icon: 'users' },
  { key: 'engagement', label: 'Engagement', icon: 'star' },
];

const PRESETS = [
  { key: '7d', label: '7D' },
  { key: '30d', label: '30D' },
  { key: '90d', label: '90D' },
  { key: 'mtd', label: 'This month' },
  { key: 'last', label: 'Last month' },
  { key: 'ytd', label: 'This year' },
  { key: '12m', label: '12M' },
] as const;

const addDays = (iso: string, days: number) => {
  const d = new Date(iso + 'T00:00:00');
  d.setDate(d.getDate() + days);
  return localISODate(d);
};

const presetRange = (key: string): [string, string] => {
  const now = new Date();
  const today = localISODate(now);
  switch (key) {
    case '7d': return [addDays(today, -6), today];
    case '90d': return [addDays(today, -89), today];
    case 'mtd': return [localISODate(new Date(now.getFullYear(), now.getMonth(), 1)), today];
    case 'last': return [
      localISODate(new Date(now.getFullYear(), now.getMonth() - 1, 1)),
      localISODate(new Date(now.getFullYear(), now.getMonth(), 0)),
    ];
    case 'ytd': return [localISODate(new Date(now.getFullYear(), 0, 1)), today];
    case '12m': return [addDays(today, -364), today];
    default: return [addDays(today, -29), today];
  }
};

const autoGranularity = (from: string, to: string): Scope['granularity'] => {
  const days = Math.round((new Date(to + 'T00:00:00').getTime() - new Date(from + 'T00:00:00').getTime()) / 86400000) + 1;
  return days <= 31 ? 'daily' : days <= 120 ? 'weekly' : 'monthly';
};

interface Options {
  cities: { id: string; name: string; salons: number; areas: { id: string; name: string }[] }[];
}

const OPTIONS_SCOPE: Scope = { from: '', to: '', granularity: 'daily', cityId: '', subAreaId: '' };

export default function ReportsPage() {
  const [tab, setTab] = useState('overview');
  const [preset, setPreset] = useState<string>('30d');
  const [range, setRange] = useState<[string, string]>(() => presetRange('30d'));
  const [granularity, setGranularity] = useState<Scope['granularity']>('daily');
  const [cityId, setCityId] = useState('');
  const [subAreaId, setSubAreaId] = useState('');
  const [refreshKey, setRefreshKey] = useState(0);

  const scope = useMemo<Scope>(
    () => ({ from: range[0], to: range[1], granularity, cityId, subAreaId }),
    [range, granularity, cityId, subAreaId],
  );

  const options = useSection<Options>('options', OPTIONS_SCOPE, 0);
  const section = useSection<Record<string, unknown>>(tab, scope, refreshKey);
  const cities = options.data?.cities ?? [];
  const city = cities.find((c) => c.id === cityId);
  const area = city?.areas.find((a) => a.id === subAreaId);

  const applyPreset = (key: string) => {
    const r = presetRange(key);
    setPreset(key);
    setRange(r);
    setGranularity(autoGranularity(r[0], r[1]));
  };

  const setFrom = (v: string) => {
    if (!v) return;
    setPreset('custom');
    const next: [string, string] = [v, v > range[1] ? v : range[1]];
    setRange(next);
    setGranularity(autoGranularity(next[0], next[1]));
  };

  const setTo = (v: string) => {
    if (!v) return;
    setPreset('custom');
    const next: [string, string] = [v < range[0] ? v : range[0], v];
    setRange(next);
    setGranularity(autoGranularity(next[0], next[1]));
  };

  const meta = section.data?.range as { previous_from: string; previous_to: string } | undefined;
  const active = TABS.find((t) => t.key === tab) ?? TABS[0];
  const props = { data: section.data, loading: section.loading, scope };

  return (
    <div className={styles.page}>
      <header className={styles.pageHeader}>
        <div>
          <p className={styles.eyebrow}>Platform reporting</p>
          <h1 className={styles.title}>Analytics</h1>
          <p className={styles.subtitle}>
            Every number across the marketplace for the range you pick, compared with the period just before it.
            Narrow it to a city or an area, and download any table as CSV.
          </p>
        </div>
        <div className={styles.headerActions}>
          <button
            type="button"
            className={styles.btn}
            onClick={() => setRefreshKey((n) => n + 1)}
            disabled={section.loading}
          >
            <Icon name="refresh" size={15} className={section.loading ? styles.spin : undefined} />
            {section.loading ? 'Loading' : 'Refresh'}
          </button>
          <button
            type="button"
            className={`${styles.btn} ${styles.btnPrimary}`}
            onClick={() => exportSectionCSV(active.label, section.data)}
            disabled={!section.data || section.loading}
            title={`Download everything on the ${active.label} tab as one CSV`}
          >
            <Icon name="download" size={15} />
            Export tab
          </button>
        </div>
      </header>

      <nav className={styles.tabs} role="tablist" aria-label="Report">
        {TABS.map((t) => (
          <button
            key={t.key}
            type="button"
            role="tab"
            aria-selected={tab === t.key}
            className={`${styles.tab} ${tab === t.key ? styles.tabActive : ''}`}
            onClick={() => setTab(t.key)}
          >
            <Icon name={t.icon} size={15} />
            {t.label}
          </button>
        ))}
      </nav>

      <div className={styles.filterBar}>
        <div className={styles.filterGroup}>
          <div className={styles.segmented} role="group" aria-label="Date range">
            {PRESETS.map((p) => (
              <button
                key={p.key}
                type="button"
                className={`${styles.segBtn} ${preset === p.key ? styles.segBtnActive : ''}`}
                aria-pressed={preset === p.key}
                onClick={() => applyPreset(p.key)}
              >
                {p.label}
              </button>
            ))}
          </div>
          <label className={styles.field}>
            <span className={styles.fieldLabel}>From</span>
            <input type="date" value={range[0]} max={range[1]} onChange={(e) => setFrom(e.target.value)} />
          </label>
          <label className={styles.field}>
            <span className={styles.fieldLabel}>To</span>
            <input type="date" value={range[1]} min={range[0]} onChange={(e) => setTo(e.target.value)} />
          </label>
        </div>
        <div className={styles.filterGroup}>
          <label className={styles.field}>
            <span className={styles.fieldLabel}>City</span>
            <select
              value={cityId}
              onChange={(e) => {
                setCityId(e.target.value);
                setSubAreaId('');
              }}
              aria-label="City"
            >
              <option value="">All cities</option>
              {cities.map((c) => (
                <option key={c.id} value={c.id}>{c.name} ({c.salons})</option>
              ))}
            </select>
          </label>
          <label className={styles.field}>
            <span className={styles.fieldLabel}>Area</span>
            <select
              value={subAreaId}
              onChange={(e) => setSubAreaId(e.target.value)}
              disabled={!city || city.areas.length === 0}
              aria-label="Area"
            >
              <option value="">{city ? (city.areas.length ? 'All areas' : 'No areas yet') : 'Pick a city'}</option>
              {city?.areas.map((a) => (
                <option key={a.id} value={a.id}>{a.name}</option>
              ))}
            </select>
          </label>
          <div className={styles.segmented} role="group" aria-label="Chart grouping">
            {(['daily', 'weekly', 'monthly'] as const).map((g) => (
              <button
                key={g}
                type="button"
                className={`${styles.segBtn} ${granularity === g ? styles.segBtnActive : ''}`}
                aria-pressed={granularity === g}
                onClick={() => setGranularity(g)}
              >
                {g === 'daily' ? 'Day' : g === 'weekly' ? 'Week' : 'Month'}
              </button>
            ))}
          </div>
        </div>
      </div>

      <div className={styles.filterGroup}>
        <span className={styles.compare}>
          <Icon name="history" size={14} />
          {fmtDate(range[0])} – {fmtDate(range[1])}
          {meta && <> · compared with <b>{fmtDate(meta.previous_from)} – {fmtDate(meta.previous_to)}</b></>}
        </span>
        {city && (
          <span className={styles.scopeChip}>
            <Icon name="pin" size={12} />
            {city.name}{area ? ` · ${area.name}` : ''}
            <button type="button" aria-label="Clear city filter" onClick={() => { setCityId(''); setSubAreaId(''); }}>
              <Icon name="close" size={12} />
            </button>
          </span>
        )}
      </div>

      {section.error && !section.data ? (
        <ErrorBox message={section.error} onRetry={() => setRefreshKey((n) => n + 1)} />
      ) : (
        <div className={`${styles.body} ${section.loading && section.data ? styles.bodyLoading : ''}`} aria-busy={section.loading}>
          {tab === 'overview' && <OverviewTab {...props} />}
          {tab === 'money' && <MoneyTab {...props} />}
          {tab === 'bookings' && <BookingsTab {...props} />}
          {tab === 'places' && <PlacesTab {...props} onPickCity={(id) => { setCityId(id); setSubAreaId(''); }} />}
          {tab === 'salons' && <SalonsTab {...props} />}
          {tab === 'catalog' && <CatalogTab {...props} />}
          {tab === 'customers' && <CustomersTab {...props} />}
          {tab === 'engagement' && <EngagementTab {...props} />}
        </div>
      )}
    </div>
  );
}
