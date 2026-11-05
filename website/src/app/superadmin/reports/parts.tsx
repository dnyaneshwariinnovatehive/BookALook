'use client';

import { useEffect, useRef, useState, type ReactNode } from 'react';
import Icon, { type IconName } from '@/components/admin/Icon';
import {
  Button, DataTable, downloadCSV, localISODate, useTableState, type DataColumn, type SortState,
} from '@/components/admin/ui';
import { useChartPalette, type ChartPalette } from '@/lib/theme';
import styles from './reports.module.css';

/* Shared pieces for the analytics tabs: formatting, the section fetch, metric
   tiles with period-over-period deltas, cards, bar lists and tables. */

// ------------------------------------------------------------------ format

export const inr = (n: number | null | undefined, decimals = 0) => {
  const v = Number(n) || 0;
  const abs = Math.abs(v).toLocaleString('en-IN', { minimumFractionDigits: decimals, maximumFractionDigits: decimals });
  return (v < 0 ? '−₹' : '₹') + abs;
};

export const compactINR = (n: number) => {
  const v = Number(n) || 0;
  const a = Math.abs(v);
  const sign = v < 0 ? '−' : '';
  if (a >= 1e7) return `${sign}₹${(a / 1e7).toFixed(1).replace(/\.0$/, '')}Cr`;
  if (a >= 1e5) return `${sign}₹${(a / 1e5).toFixed(1).replace(/\.0$/, '')}L`;
  if (a >= 1e3) return `${sign}₹${(a / 1e3).toFixed(a >= 1e4 ? 0 : 1).replace(/\.0$/, '')}k`;
  return `${sign}₹${Math.round(a)}`;
};

export const num = (n: number | null | undefined) => Math.round(Number(n) || 0).toLocaleString('en-IN');

/** "1 refund", "3 refunds". */
export const plural = (n: number, noun: string) => `${num(n)} ${noun}${Math.round(n) === 1 ? '' : 's'}`;

export const pct = (n: number | null | undefined, digits = 1) =>
  n === null || n === undefined ? '—' : `${Number(n).toFixed(digits).replace(/\.0$/, '')}%`;

export const fmtDate = (iso: string) => {
  const [y, m, d] = iso.slice(0, 10).split('-').map(Number);
  return new Date(y, m - 1, d).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' });
};

export type Delta = { pct: number; dir: 'up' | 'down' | 'flat' } | null;

/** Change against the previous period; null when there is nothing to compare. */
export const deltaOf = (curr: number, prev: number): Delta => {
  if (!prev) return curr ? null : { pct: 0, dir: 'flat' };
  const p = ((curr - prev) / Math.abs(prev)) * 100;
  const r = Math.round(p * 10) / 10;
  return { pct: Math.abs(r), dir: r > 0 ? 'up' : r < 0 ? 'down' : 'flat' };
};

/** For rates: the change in percentage points. */
export const pointsOf = (curr: number, prev: number): Delta => {
  const d = Math.round((curr - prev) * 10) / 10;
  return { pct: Math.abs(d), dir: d > 0 ? 'up' : d < 0 ? 'down' : 'flat' };
};

// ------------------------------------------------------------------ scope

export interface Scope {
  from: string;
  to: string;
  granularity: 'daily' | 'weekly' | 'monthly';
  cityId: string;
  subAreaId: string;
}

export interface RangeMeta {
  from: string;
  to: string;
  previous_from: string;
  previous_to: string;
  days: number;
  granularity: string;
}

export interface SectionBase {
  success: boolean;
  generated_at: string;
  range: RangeMeta;
  filters: { city_id: string | null; city: string | null; sub_area_id: string | null; sub_area: string | null };
}

export interface TabProps {
  data: Record<string, unknown> | null;
  loading: boolean;
  scope: Scope;
}

/** Skeleton row of panels while a tab loads for the first time. */
export function TabSkeleton() {
  return (
    <>
      <div className={`${styles.metricGrid} ${styles.cols4}`}>
        {[0, 1, 2, 3].map((i) => (
          <div key={i} className={styles.metric}>
            <span className={`${styles.skeleton} ${styles.skeletonValue}`} />
          </div>
        ))}
      </div>
      <div className={`${styles.grid} ${styles.grid2}`}>
        {[0, 1].map((i) => (
          <div key={i} className={styles.panel}>
            <div className={styles.panelBody}><span className={`${styles.skeleton} ${styles.skeletonBlock}`} /></div>
          </div>
        ))}
      </div>
    </>
  );
}

export const scopeQuery = (s: Scope) => {
  const q = new URLSearchParams({ from: s.from, to: s.to, granularity: s.granularity });
  if (s.cityId) q.set('city_id', s.cityId);
  if (s.subAreaId) q.set('sub_area_id', s.subAreaId);
  return q.toString();
};

const cache = new Map<string, unknown>();

/**
 * Fetch one analytics section for a scope. Results are cached per scope for
 * the session so flipping between tabs is instant; `refreshKey` forces a
 * reload.
 */
export function useSection<T>(section: string, scope: Scope, refreshKey: number) {
  const key = `${section}?${scopeQuery(scope)}`;
  const [state, setState] = useState<{ key: string; data: T | null; error: string; loading: boolean }>(() => ({
    key, data: (cache.get(key) as T) ?? null, error: '', loading: !cache.has(key),
  }));
  const seq = useRef(0);
  const lastRefresh = useRef(refreshKey);

  useEffect(() => {
    const id = ++seq.current;
    const forced = lastRefresh.current !== refreshKey;
    lastRefresh.current = refreshKey;
    const run = async () => {
      const cached = cache.get(key) as T | undefined;
      if (cached && !forced) {
        setState({ key, data: cached, error: '', loading: false });
        return;
      }
      setState((s) => ({ key, data: s.key.split('?')[0] === section ? s.data : (cached ?? null), error: '', loading: true }));
      try {
        const res = await fetch(`/api/proxy/superadmin/reports/analytics/${section}?${key.split('?')[1]}`, { cache: 'no-store' });
        if (res.status === 401) throw new Error('Your session has ended. Sign in again to see reports.');
        const json = await res.json();
        if (id !== seq.current) return;
        if (!res.ok || !json.success) throw new Error(json.message || 'Could not load this report.');
        cache.set(key, json);
        setState({ key, data: json as T, error: '', loading: false });
      } catch (e) {
        if (id === seq.current) {
          setState((s) => ({ ...s, error: e instanceof Error ? e.message : 'Could not load this report.', loading: false }));
        }
      }
    };
    const timer = setTimeout(run, 0);
    return () => clearTimeout(timer);
  }, [key, section, refreshKey]);

  // While a new scope loads, the last figures stay on screen (dimmed by the
  // page) rather than the layout collapsing to skeletons.
  const sameSection = state.key.split('?')[0] === section;
  return {
    data: sameSection ? state.data : ((cache.get(key) as T) ?? null),
    error: sameSection ? state.error : '',
    loading: state.loading || state.key !== key,
  };
}

// ------------------------------------------------------------------ pieces

export function useTooltipStyle(palette: ChartPalette) {
  return {
    background: 'var(--surface-color)',
    borderRadius: 12,
    border: `1px solid ${palette.grid}`,
    boxShadow: '0 8px 24px rgba(0,0,0,0.12)',
    fontSize: 12,
    color: 'var(--text-heading)',
  };
}

export { useChartPalette };

export function DeltaChip({ delta, invert, points }: { delta: Delta; invert?: boolean; points?: boolean }) {
  if (!delta) return <span className={`${styles.delta} ${styles.deltaFlat}`}>new</span>;
  const good = delta.dir === 'flat' ? null : (delta.dir === 'up') !== !!invert;
  return (
    <span className={`${styles.delta} ${good === null ? styles.deltaFlat : good ? styles.deltaGood : styles.deltaBad}`}>
      {delta.dir !== 'flat' && <Icon name={delta.dir === 'up' ? 'trendUp' : 'trendDown'} size={12} strokeWidth={2.2} />}
      {delta.pct}{points ? ' pts' : '%'}
    </span>
  );
}

const TONES = {
  violet: styles.toneViolet,
  teal: styles.toneTeal,
  amber: styles.toneAmber,
  blue: styles.toneBlue,
  rose: styles.toneRose,
} as const;

/** A metric tile: value, change against the previous period, and a hint. */
export function Metric({
  label, value, delta, invert, points, hint, icon, tone = 'violet', loading, title,
}: {
  label: string;
  value: ReactNode;
  delta?: Delta;
  invert?: boolean;
  points?: boolean;
  hint?: ReactNode;
  icon?: IconName;
  tone?: keyof typeof TONES;
  loading?: boolean;
  title?: string;
}) {
  return (
    <div className={styles.metric} title={title}>
      <div className={styles.metricTop}>
        <span className={styles.metricLabel}>{label}</span>
        {icon && <span className={`${styles.metricIcon} ${TONES[tone]}`}><Icon name={icon} size={16} /></span>}
      </div>
      {loading ? <span className={`${styles.skeleton} ${styles.skeletonValue}`} /> : <div className={styles.metricValue}>{value}</div>}
      <div className={styles.metricFoot}>
        {!loading && delta !== undefined && <DeltaChip delta={delta} invert={invert} points={points} />}
        {hint && <span className={styles.metricHint}>{hint}</span>}
      </div>
    </div>
  );
}

export function MetricGrid({ children, cols = 4 }: { children: ReactNode; cols?: 3 | 4 | 5 | 6 }) {
  return <div className={`${styles.metricGrid} ${styles[`cols${cols}`]}`}>{children}</div>;
}

/** Card with a title row and optional CSV export of the rows behind it. */
export function Panel({
  title, subtitle, actions, children, csv, span, padded = true, className,
}: {
  title: ReactNode;
  subtitle?: ReactNode;
  actions?: ReactNode;
  children: ReactNode;
  csv?: { name: string; headers: string[]; rows: unknown[][] };
  span?: 1 | 2 | 3;
  padded?: boolean;
  className?: string;
}) {
  return (
    <section className={`${styles.panel} ${span ? styles[`span${span}`] : ''} ${className ?? ''}`}>
      <header className={styles.panelHead}>
        <div className={styles.panelHeadText}>
          <h2 className={styles.panelTitle}>{title}</h2>
          {subtitle && <p className={styles.panelSub}>{subtitle}</p>}
        </div>
        <div className={styles.panelActions}>
          {actions}
          {csv && csv.rows.length > 0 && (
            <button
              type="button"
              className={styles.csvBtn}
              onClick={() => downloadCSV(`${csv.name}-${localISODate()}.csv`, csv.headers, csv.rows.map(safeRow))}
              title="Download as CSV"
            >
              <Icon name="download" size={13} /> CSV
            </button>
          )}
        </div>
      </header>
      <div className={padded ? styles.panelBody : styles.panelBodyFlush}>{children}</div>
    </section>
  );
}

export function Grid({ children, cols = 2 }: { children: ReactNode; cols?: 2 | 3 }) {
  return <div className={`${styles.grid} ${cols === 3 ? styles.grid3 : styles.grid2}`}>{children}</div>;
}

export function Empty({ title = 'Nothing in this range', hint, icon = 'chart' }: { title?: string; hint?: string; icon?: IconName }) {
  return (
    <div className={styles.empty}>
      <span className={styles.emptyIcon}><Icon name={icon} size={18} /></span>
      <b>{title}</b>
      {hint && <span>{hint}</span>}
    </div>
  );
}

export function ChartBox({ height = 280, children }: { height?: number; children: ReactNode }) {
  return <div className={styles.chartBox} style={{ height }}>{children}</div>;
}

/** Horizontal bars with a label, value and optional caption. */
export function BarList({
  items, format = num, color, max, emptyHint,
}: {
  items: { key: string; label: ReactNode; value: number; sub?: ReactNode; color?: string }[];
  format?: (n: number) => string;
  color?: string;
  max?: number;
  emptyHint?: string;
}) {
  const palette = useChartPalette();
  const top = max ?? Math.max(1, ...items.map((i) => Math.abs(i.value)));
  if (items.length === 0) return <Empty hint={emptyHint} />;
  return (
    <ul className={styles.barList}>
      {items.map((i) => (
        <li key={i.key}>
          <div className={styles.barTop}>
            <span className={styles.barLabel}>{i.label}</span>
            <b>{format(i.value)}</b>
          </div>
          <div className={styles.barTrack}>
            <span style={{ width: `${Math.max(1.5, (Math.abs(i.value) / top) * 100)}%`, background: i.color ?? color ?? palette.c1 }} />
          </div>
          {i.sub && <div className={styles.barSub}>{i.sub}</div>}
        </li>
      ))}
    </ul>
  );
}

/** Legend rows for donut charts. */
export function Legend({ items, total, format = num }: {
  items: { key: string; label: string; value: number; color: string }[];
  total: number;
  format?: (n: number) => string;
}) {
  return (
    <ul className={styles.legend}>
      {items.map((i) => (
        <li key={i.key}>
          <span className={styles.swatch} style={{ background: i.color }} />
          <span className={styles.legendName}>{i.label}</span>
          <b>{format(i.value)}</b>
          <em>{total > 0 ? pct((i.value / total) * 100, 0) : '—'}</em>
        </li>
      ))}
    </ul>
  );
}

/** Sortable, paginated table with CSV export. */
export function Table<T>({
  columns, rows, rowKey, exportName, initialSort, perPage = 10, empty,
}: {
  columns: DataColumn<T>[];
  rows: T[];
  rowKey: (row: T) => string | number;
  exportName: string;
  initialSort?: SortState;
  perPage?: number;
  empty?: string;
}) {
  const t = useTableState({ rows, columns, initialSort: initialSort ?? null, initialPerPage: perPage });
  return (
    <div className={styles.tableShell}>
      <DataTable
        columns={columns}
        rows={t.pageRows}
        rowKey={rowKey}
        sort={t.sort}
        onSort={t.toggleSort}
        page={t.page}
        lastPage={t.lastPage}
        total={t.total}
        onPage={t.setPage}
        perPage={t.perPage}
        onPerPageChange={t.changePerPage}
        exportName={exportName}
        empty={{ title: empty ?? 'Nothing in this range' }}
      />
    </div>
  );
}

export function Pill({ children, tone = 'neutral' }: { children: ReactNode; tone?: 'neutral' | 'good' | 'bad' | 'accent' | 'warn' }) {
  return <span className={`${styles.pill} ${styles[`pill_${tone}`]}`}>{children}</span>;
}

export function Growth({ value, invert }: { value: number | null | undefined; invert?: boolean }) {
  if (value === null || value === undefined) return <span className={styles.muted}>—</span>;
  const good = value === 0 ? null : (value > 0) !== !!invert;
  return (
    <span className={good === null ? styles.muted : good ? styles.good : styles.bad}>
      {value > 0 ? '+' : ''}{pct(value)}
    </span>
  );
}

/** One line of a facts list: icon, label, value and a caption. */
export function Fact({ icon, label, value, sub }: { icon: IconName; label: ReactNode; value: ReactNode; sub?: ReactNode }) {
  return (
    <li>
      <span className={styles.factLabel}><Icon name={icon} size={14} />{label}</span>
      <span className={styles.factValue}>{value}{sub && <small>{sub}</small>}</span>
    </li>
  );
}

export function Facts({ children }: { children: ReactNode }) {
  return <ul className={styles.facts}>{children}</ul>;
}

export function Note({ children }: { children: ReactNode }) {
  return (
    <p className={styles.note}>
      <Icon name="info" size={13} />
      <span>{children}</span>
    </p>
  );
}

export function ErrorBox({ message, onRetry }: { message: string; onRetry?: () => void }) {
  return (
    <div className={styles.errorBox} role="alert">
      <span>{message}</span>
      {onRetry && <Button size="sm" variant="secondary" icon="refresh" onClick={onRetry}>Try again</Button>}
    </div>
  );
}

/** Stops a spreadsheet from treating a cell as a formula. */
const safeCell = (v: unknown) => {
  if (typeof v === 'string' && /^[=+\-@]/.test(v)) return `'${v}`;
  return v;
};
export const safeRow = (r: unknown[]) => r.map(safeCell);

/** Flatten a whole section payload into one CSV: one block per list. */
export function exportSectionCSV(section: string, data: Record<string, unknown> | null) {
  if (!data) return;
  const lines: unknown[][] = [];
  const range = data.range as RangeMeta | undefined;
  const filters = data.filters as SectionBase['filters'] | undefined;
  lines.push([`BookALook analytics — ${section}`]);
  if (range) lines.push(['Range', range.from, range.to, 'Compared with', range.previous_from, range.previous_to]);
  if (filters?.city) lines.push(['City', filters.city, 'Area', filters.sub_area ?? 'All']);
  lines.push([]);

  const scalarBlock = (title: string, obj: Record<string, unknown>) => {
    const entries = Object.entries(obj).filter(([, v]) => v === null || ['string', 'number', 'boolean'].includes(typeof v));
    if (!entries.length) return;
    lines.push([title]);
    entries.forEach(([k, v]) => lines.push([k, v as unknown]));
    lines.push([]);
  };
  const listBlock = (title: string, list: unknown[]) => {
    const rows = list.filter((r): r is Record<string, unknown> => !!r && typeof r === 'object' && !Array.isArray(r));
    if (!rows.length) return;
    const headers = Array.from(new Set(rows.flatMap((r) => Object.keys(r).filter((k) => typeof r[k] !== 'object' || r[k] === null))));
    lines.push([title]);
    lines.push(headers);
    rows.forEach((r) => lines.push(headers.map((h) => r[h] as unknown)));
    lines.push([]);
  };
  const walk = (prefix: string, value: unknown, depth: number) => {
    if (depth > 3 || value === null || value === undefined) return;
    if (Array.isArray(value)) {
      listBlock(prefix, value);
      return;
    }
    if (typeof value === 'object') {
      const obj = value as Record<string, unknown>;
      scalarBlock(prefix, obj);
      Object.entries(obj).forEach(([k, v]) => {
        if (v && typeof v === 'object') walk(`${prefix} › ${k}`, v, depth + 1);
      });
    }
  };
  Object.entries(data).forEach(([k, v]) => {
    if (['success', 'section', 'generated_at', 'range', 'filters'].includes(k)) return;
    walk(k, v, 0);
  });

  const csvRows = lines.map(safeRow);
  const width = Math.max(1, ...csvRows.map((r) => r.length));
  downloadCSV(`bookalook-${section}-${localISODate()}.csv`, Array.from({ length: width }, (_, i) => (i === 0 ? 'Section' : '')), csvRows);
}
