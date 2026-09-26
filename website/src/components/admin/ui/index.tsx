'use client';

import {
  useCallback, useEffect, useId, useMemo, useRef, useState,
  type ButtonHTMLAttributes, type ReactNode,
} from 'react';
import { createPortal } from 'react-dom';
import Icon, { type IconName } from '../Icon';
import s from './ui.module.css';

/**
 * Admin UI kit. Pages compose these instead of re-styling the same pieces,
 * so every screen shares one look in both themes.
 */

export { s as ui };

export type Tone = 'accent' | 'success' | 'warning' | 'danger' | 'info' | 'neutral';

const toneClass: Record<Tone, string> = {
  accent: s.toneAccent,
  success: s.toneSuccess,
  warning: s.toneWarning,
  danger: s.toneDanger,
  info: s.toneInfo,
  neutral: s.toneNeutral,
};

export const cx = (...parts: (string | false | null | undefined)[]) => parts.filter(Boolean).join(' ');

/* ------------------------------------------------------------ layout */

export function PageHeader({ eyebrow, title, subtitle, actions }: {
  eyebrow?: ReactNode;
  title: ReactNode;
  subtitle?: ReactNode;
  actions?: ReactNode;
}) {
  return (
    <header className={s.pageHeader}>
      <div className={s.pageHeaderText}>
        {eyebrow && <div className={s.eyebrow}>{eyebrow}</div>}
        <h1 className={s.pageTitle}>{title}</h1>
        {subtitle && <p className={s.pageSubtitle}>{subtitle}</p>}
      </div>
      {actions && <div className={s.pageActions}>{actions}</div>}
    </header>
  );
}

export function Card({ title, subtitle, actions, children, padded, className }: {
  title?: ReactNode;
  subtitle?: ReactNode;
  actions?: ReactNode;
  children?: ReactNode;
  /** Pad the body (for non-table content). */
  padded?: boolean;
  className?: string;
}) {
  return (
    <section className={cx(s.card, className)}>
      {(title || actions) && (
        <div className={s.cardHeader}>
          <div>
            {title && <h2 className={s.cardTitle}>{title}</h2>}
            {subtitle && <p className={s.cardSubtitle}>{subtitle}</p>}
          </div>
          {actions}
        </div>
      )}
      {padded ? <div className={s.cardBody}>{children}</div> : children}
    </section>
  );
}

export function StatCard({ label, value, sub, icon, tone = 'accent', loading }: {
  label: string;
  value: ReactNode;
  sub?: ReactNode;
  icon?: IconName;
  tone?: Tone;
  loading?: boolean;
}) {
  return (
    <div className={s.stat}>
      <div className={s.statTop}>
        <span className={s.statLabel}>{label}</span>
        {icon && <span className={cx(s.statIcon, toneClass[tone])}><Icon name={icon} size={18} /></span>}
      </div>
      {loading ? <Skeleton width="55%" height={30} /> : <div className={s.statValue}>{value}</div>}
      {sub && <div className={s.statSub}>{loading ? <Skeleton width="70%" height={12} /> : sub}</div>}
    </div>
  );
}

/* ------------------------------------------------------------ atoms */

export function Badge({ tone = 'neutral', children, dot = true, pulse }: {
  tone?: Tone;
  children: ReactNode;
  dot?: boolean;
  pulse?: boolean;
}) {
  return (
    <span className={cx(s.badge, toneClass[tone], pulse && s.badgePulse)}>
      {dot && <span className={s.badgeDot} />}
      {children}
    </span>
  );
}

export type ButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: 'primary' | 'secondary' | 'soft' | 'ghost' | 'danger' | 'dangerSoft';
  size?: 'sm' | 'md';
  icon?: IconName;
  loading?: boolean;
};

const variantClass = {
  primary: s.btnPrimary,
  secondary: s.btnSecondary,
  soft: s.btnSoft,
  ghost: s.btnGhost,
  danger: s.btnDanger,
  dangerSoft: s.btnDangerSoft,
};

export function Button({ variant = 'secondary', size = 'md', icon, loading, children, className, disabled, type = 'button', ...rest }: ButtonProps) {
  return (
    <button
      type={type}
      className={cx(s.btn, variantClass[variant], size === 'sm' && s.btnSm, className)}
      disabled={disabled || loading}
      {...rest}
    >
      {loading ? <span className={s.spinner} aria-hidden="true" /> : icon && <Icon name={icon} size={size === 'sm' ? 14 : 16} />}
      {children}
    </button>
  );
}

export function IconButton({ icon, label, className, ...rest }: ButtonHTMLAttributes<HTMLButtonElement> & { icon: IconName; label: string }) {
  return (
    <button type="button" className={cx(s.iconBtn, className)} aria-label={label} title={label} {...rest}>
      <Icon name={icon} size={17} />
    </button>
  );
}

const AVATAR_TONES: Tone[] = ['accent', 'info', 'success', 'warning'];

export const initials = (name?: string | null) =>
  (name || '?').split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0]).join('').toUpperCase();

export function Avatar({ name, size = 36, tone }: { name?: string | null; size?: number; tone?: Tone }) {
  const hash = [...(name || '?')].reduce((h, c) => (h * 31 + c.charCodeAt(0)) >>> 0, 7);
  const t = tone ?? AVATAR_TONES[hash % AVATAR_TONES.length];
  return (
    <span
      className={cx(s.avatar, toneClass[t])}
      style={{ width: size, height: size, fontSize: Math.round(size * 0.36), borderRadius: Math.round(size * 0.32) }}
      aria-hidden="true"
    >
      {initials(name)}
    </span>
  );
}

export function Person({ name, sub, size }: { name: ReactNode; sub?: ReactNode; size?: number }) {
  return (
    <div className={s.personCell}>
      <Avatar name={typeof name === 'string' ? name : undefined} size={size} />
      <div className={s.personText}>
        <div className={cx(s.cellPrimary, s.ellipsis)}>{name}</div>
        {sub && <div className={cx(s.cellSub, s.ellipsis)}>{sub}</div>}
      </div>
    </div>
  );
}

export function Skeleton({ width = '100%', height = 14, radius }: { width?: number | string; height?: number | string; radius?: number }) {
  return <span className={s.skeleton} style={{ width, height, borderRadius: radius }} />;
}

export function EmptyState({ icon = 'search', title, hint, action }: {
  icon?: IconName;
  title: ReactNode;
  hint?: ReactNode;
  action?: ReactNode;
}) {
  return (
    <div className={s.empty}>
      <span className={s.emptyIcon}><Icon name={icon} size={22} /></span>
      <div className={s.emptyTitle}>{title}</div>
      {hint && <div className={s.emptyHint}>{hint}</div>}
      {action && <div className={s.emptyAction}>{action}</div>}
    </div>
  );
}

const alertClass = { success: s.alertSuccess, error: s.alertError, warning: s.alertWarning, info: s.alertInfo };
const alertIcon: Record<keyof typeof alertClass, IconName> = { success: 'checkCircle', error: 'alert', warning: 'alert', info: 'info' };

export function Alert({ tone = 'info', children, onClose }: {
  tone?: keyof typeof alertClass;
  children: ReactNode;
  onClose?: () => void;
}) {
  return (
    <div className={cx(s.alert, alertClass[tone])} role={tone === 'error' ? 'alert' : 'status'}>
      <Icon name={alertIcon[tone]} size={17} />
      <div className={s.alertBody}>{children}</div>
      {onClose && <IconButton icon="close" label="Dismiss" className={s.alertClose} onClick={onClose} />}
    </div>
  );
}

/* ------------------------------------------------------------ inputs */

export function Field({ label, hint, children, className }: {
  label: ReactNode;
  hint?: ReactNode;
  children: ReactNode;
  className?: string;
}) {
  return (
    <label className={cx(s.field, className)}>
      <span className={s.fieldLabel}>{label}</span>
      {children}
      {hint && <span className={s.fieldHint}>{hint}</span>}
    </label>
  );
}

export function SearchInput({ value, onChange, placeholder = 'Search…', className, ariaLabel }: {
  value: string;
  onChange: (v: string) => void;
  placeholder?: string;
  className?: string;
  ariaLabel?: string;
}) {
  return (
    <div className={cx(s.searchWrap, className)}>
      <Icon name="search" size={16} className={s.searchIcon} />
      <input
        type="search"
        className={s.control}
        value={value}
        placeholder={placeholder}
        aria-label={ariaLabel ?? placeholder}
        onChange={(e) => onChange(e.target.value)}
      />
      {value && <IconButton icon="close" label="Clear search" className={s.searchClear} onClick={() => onChange('')} />}
    </div>
  );
}

export function Segmented<T extends string>({ options, value, onChange, ariaLabel }: {
  options: { value: T; label: ReactNode; count?: number }[];
  value: T;
  onChange: (v: T) => void;
  ariaLabel: string;
}) {
  return (
    <div className={s.segmented} role="group" aria-label={ariaLabel}>
      {options.map((o) => (
        <button
          key={o.value}
          type="button"
          className={cx(s.segBtn, value === o.value && s.segBtnActive)}
          aria-pressed={value === o.value}
          onClick={() => onChange(o.value)}
        >
          {o.label}
          {o.count !== undefined && <span className={s.segCount}>{o.count}</span>}
        </button>
      ))}
    </div>
  );
}

export function Tabs<T extends string>({ tabs, value, onChange }: {
  tabs: { value: T; label: ReactNode }[];
  value: T;
  onChange: (v: T) => void;
}) {
  return (
    <div className={s.tabs} role="tablist">
      {tabs.map((t) => (
        <button
          key={t.value}
          type="button"
          role="tab"
          aria-selected={value === t.value}
          className={cx(s.tab, value === t.value && s.tabActive)}
          onClick={() => onChange(t.value)}
        >
          {t.label}
        </button>
      ))}
    </div>
  );
}

/* ------------------------------------------------------------ table bits */

export type SortDir = 'asc' | 'desc';
export type Align = 'left' | 'right' | 'center';

const alignClass: Record<Align, string | undefined> = {
  left: undefined,
  right: s.alignRight,
  center: s.alignCenter,
};

/**
 * Clickable column header. The whole cell is the hit area (professional tables
 * don't make users find a small arrow), while the inner button keeps the
 * keyboard and screen-reader contract via a real `aria-sort` on the `<th>`.
 */
export function SortHeader({ label, active, dir, onClick, align = 'left', title }: {
  label: ReactNode;
  active: boolean;
  /** Null is allowed: an unsorted column has no direction yet. */
  dir: SortDir | null;
  onClick: () => void;
  align?: Align;
  title?: string;
}) {
  return (
    <th
      scope="col"
      className={cx(s.sortHead, alignClass[align])}
      aria-sort={active && dir ? (dir === 'asc' ? 'ascending' : 'descending') : 'none'}
      onClick={onClick}
    >
      <button type="button" className={cx(s.sortBtn, alignClass[align], active && s.sortBtnActive)} title={title ?? (active && dir ? `Sorted ${dir === 'asc' ? 'ascending' : 'descending'}. Activate to reverse.` : 'Sort by this column')}>
        <span className={s.sortLabel}>{label}</span>
        <Icon name={active && dir ? (dir === 'asc' ? 'arrowUp' : 'arrowDown') : 'sortBoth'} size={12} strokeWidth={2.2} className={s.sortArrow} />
      </button>
    </th>
  );
}

/** Props that make a table row behave like a button for mouse and keyboard. */
export const clickableRow = (onActivate: () => void) => ({
  className: s.rowClickable,
  tabIndex: 0,
  onClick: onActivate,
  onKeyDown: (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      onActivate();
    }
  },
});

export const PAGE_SIZES = [10, 20, 50, 100] as const;

export function Pagination({ page, lastPage, total, noun = 'results', onChange, perPage, onPerPageChange, disabled = false, hideWhenSingle = true }: {
  page: number;
  lastPage: number;
  total?: number;
  noun?: string;
  onChange: (page: number) => void;
  /** Supply both to render a rows-per-page selector. */
  perPage?: number;
  onPerPageChange?: (perPage: number) => void;
  /** Greys the controls while a new page is in flight. */
  disabled?: boolean;
  hideWhenSingle?: boolean;
}) {
  // Bad totals happen (a filter that matches nothing mid-flight); don't render NaN.
  const safeLast = Math.max(1, Number.isFinite(lastPage) ? Math.floor(lastPage) : 1);
  const safePage = Math.min(safeLast, Math.max(1, Number.isFinite(page) ? Math.floor(page) : 1));

  const sizeControl =
    onPerPageChange && (
      <label className={s.pageSize}>
        <span className={s.pageSizeLabel}>Rows</span>
        <select
          className={s.pageSizeSelect}
          value={perPage ?? 20}
          disabled={disabled}
          onChange={(e) => onPerPageChange(Number(e.target.value))}
          aria-label={`Rows per page`}
        >
          {PAGE_SIZES.map((n) => (
            <option key={n} value={n}>{n}</option>
          ))}
        </select>
      </label>
    );

  if (safeLast <= 1) {
    if (hideWhenSingle && !onPerPageChange) return null;
    return (
      <div className={s.pagination}>
        <span>{total !== undefined ? `${total.toLocaleString('en-IN')} ${noun}` : ''}</span>
        {sizeControl}
      </div>
    );
  }

  const pages: (number | 'gap')[] = [];
  for (let p = 1; p <= safeLast; p++) {
    if (p === 1 || p === safeLast || Math.abs(p - safePage) <= 1) pages.push(p);
    else if (pages[pages.length - 1] !== 'gap') pages.push('gap');
  }

  return (
    <nav className={s.pagination} aria-label="Pagination">
      <span className={s.pageInfo}>
        {total !== undefined && (
          <>
            {total.toLocaleString('en-IN')} {noun}
            <span className={s.pageInfoSep}> · </span>
          </>
        )}
        Page {safePage.toLocaleString('en-IN')} of {safeLast.toLocaleString('en-IN')}
      </span>
      <div className={s.pageButtons}>
        {sizeControl}
        <IconButton icon="chevronLeft" label="Previous page" disabled={disabled || safePage <= 1} onClick={() => onChange(safePage - 1)} />
        {pages.map((p, i) =>
          p === 'gap' ? (
            <span key={`g${i}`} className={s.pageGap} aria-hidden="true">…</span>
          ) : (
            <button
              key={p}
              type="button"
              className={cx(s.pageNum, p === safePage && s.pageNumActive)}
              aria-current={p === safePage ? 'page' : undefined}
              disabled={disabled}
              onClick={() => onChange(p)}
            >
              {p.toLocaleString('en-IN')}
            </button>
          ),
        )}
        <IconButton icon="chevronRight" label="Next page" disabled={disabled || safePage >= safeLast} onClick={() => onChange(safePage + 1)} />
      </div>
    </nav>
  );
}

/* ------------------------------------------------------------ data table */

export type SortState = { key: string; dir: SortDir } | null;

export type DataColumn<T> = {
  key: string;
  header: ReactNode;
  render: (row: T) => ReactNode;
  /**
   * Omit to make the column static. Present = the column gets a sort control,
   * and the value drives ordering, so keep it cheap and total.
   */
  sortValue?: (row: T) => string | number | boolean | null | undefined;
  align?: Align;
  width?: number | string;
  className?: string;
  /** Value written to CSV. Falls back to `sortValue`, then to the sort-free cell text. */
  csvValue?: (row: T) => unknown;
};

// Natural order so "Item 9" lands after "Item 10", and accents ignored.
const collator = new Intl.Collator('en-IN', { numeric: true, sensitivity: 'base' });

const isBlank = (v: unknown) => v === null || v === undefined || v === '';

function compareValues(a: unknown, b: unknown): number {
  if (typeof a === 'number' && typeof b === 'number') return a - b;
  if (typeof a === 'boolean' && typeof b === 'boolean') return Number(a) - Number(b);
  return collator.compare(String(a), String(b));
}

/** Blanks sink to the bottom whichever way the column is pointing. */
function compareForDir(a: unknown, b: unknown, dir: SortDir): number {
  const aBlank = isBlank(a);
  const bBlank = isBlank(b);
  if (aBlank && bBlank) return 0;
  if (aBlank) return 1;
  if (bBlank) return -1;
  const cmp = compareValues(a, b);
  return dir === 'asc' ? cmp : -cmp;
}

/**
 * Sort + pagination state for a table, in either mode.
 *
 * `client` — the whole collection is already in memory: sorting and slicing
 * happen here. Right for reference data (cities, banners, collaborators).
 *
 * `server` — `rows` is just the current page; `lastPage`/`total` come from the
 * API and the hook only owns the page/sort request. Right for anything that can
 * grow past a few hundred rows.
 *
 * Both modes expose the same fields, so a page can be upgraded later without
 * rewriting the table.
 */
export function useTableState<T>({
  rows,
  columns,
  mode = 'client',
  initialSort = null,
  initialPerPage = 20,
  total: serverTotal,
  lastPage: serverLastPage,
}: {
  rows: T[];
  columns: DataColumn<T>[];
  mode?: 'client' | 'server';
  initialSort?: SortState;
  initialPerPage?: number;
  total?: number;
  lastPage?: number;
}) {
  const [sort, setSort] = useState<SortState>(initialSort);
  const [perPage, setPerPage] = useState(initialPerPage);
  const [page, setPage] = useState(1);

  const sortCol = useMemo(
    () => (sort ? columns.find((c) => c.key === sort.key) : undefined),
    [columns, sort],
  );

  const sorted = useMemo(() => {
    if (mode !== 'client' || !sortCol?.sortValue) return rows;
    const get = sortCol.sortValue;
    // Copy first: sorting the prop array in place mutates caller state.
    return [...rows].sort((a, b) => compareForDir(get(a), get(b), sort!.dir));
  }, [rows, mode, sortCol, sort]);

  const clientTotal = sorted.length;
  const lastPage =
    mode === 'server'
      ? Math.max(1, Math.floor(serverLastPage ?? 1))
      : Math.max(1, Math.ceil(clientTotal / perPage));
  const total = mode === 'server' ? serverTotal : clientTotal;

  // Clamp so a filter that shrinks the set can't strand the user on page 9.
  const safePage = Math.min(Math.max(1, page), lastPage);
  const pageRows =
    mode === 'client' ? sorted.slice((safePage - 1) * perPage, safePage * perPage) : rows;

  /** asc -> desc -> unsorted, and always back to page 1. */
  const toggleSort = useCallback((key: string) => {
    setSort((prev) => {
      if (prev?.key !== key) return { key, dir: 'asc' };
      if (prev.dir === 'asc') return { key, dir: 'desc' };
      return null;
    });
    setPage(1);
  }, []);

  const changePerPage = useCallback((next: number) => {
    setPerPage(next);
    setPage(1);
  }, []);

  /** Drop back to the source ordering — e.g. when a curated sort chip wins. */
  const clearSort = useCallback(() => {
    setSort(null);
    setPage(1);
  }, []);

  return {
    mode,
    sort,
    toggleSort,
    clearSort,
    page: safePage,
    setPage,
    lastPage,
    total,
    perPage,
    changePerPage,
    pageRows,
    /** Every row in sort order — export this, not `pageRows`. */
    sortedRows: sorted,
  };
}

/**
 * The table shell every data screen should use: sortable headers, pagination,
 * skeleton rows while loading, an empty state, and optional CSV export.
 *
 * `<DataTable>` is presentational — pair it with `useTableState` for paging and
 * sorting state. Pagination only appears when `onPage` is passed.
 */
export function DataTable<T>({
  columns,
  rows,
  rowKey,
  loading = false,
  error,
  sort,
  onSort,
  page,
  lastPage,
  total,
  onPage,
  perPage,
  onPerPageChange,
  noun = 'results',
  onRowClick,
  rowClassName,
  empty,
  toolbar,
  exportName,
  skeletonRows = 8,
  caption,
}: {
  columns: DataColumn<T>[];
  rows: T[];
  rowKey: (row: T) => string | number;
  loading?: boolean;
  error?: ReactNode;
  sort?: SortState;
  onSort?: (key: string) => void;
  page?: number;
  lastPage?: number;
  total?: number;
  onPage?: (page: number) => void;
  perPage?: number;
  onPerPageChange?: (n: number) => void;
  noun?: string;
  onRowClick?: (row: T) => void;
  /** Extra class on a row — e.g. to flash it after an inline edit. */
  rowClassName?: (row: T) => string | undefined;
  empty?: { title: ReactNode; hint?: ReactNode; action?: ReactNode };
  toolbar?: ReactNode;
  /** Filename stem for the CSV button, e.g. "salons" -> "salons-2026-01-05.csv". */
  exportName?: string;
  skeletonRows?: number;
  caption?: ReactNode;
}) {
  const exportable = exportName && columns.some((c) => c.sortValue || c.csvValue);

  const handleExport = () => {
    if (!exportName) return;
    const cols = columns.filter((c) => c.sortValue || c.csvValue);
    const cell = (col: DataColumn<T>, row: T) => {
      if (col.csvValue) return col.csvValue(row);
      if (col.sortValue) return col.sortValue(row);
      const node = col.render(row);
      return typeof node === 'string' || typeof node === 'number' ? node : '';
    };
    downloadCSV(
      `${exportName}-${localISODate()}.csv`,
      cols.map((c) => (typeof c.header === 'string' ? c.header : c.key)),
      rows.map((row) => cols.map((c) => cell(c, row))),
    );
  };

  const showEmpty = !loading && !error && rows.length === 0;

  return (
    <>
      {(toolbar || exportable) && (
        <div className={s.tableToolbar}>
          {toolbar && <div className={s.toolbarGrow}>{toolbar}</div>}
          {exportable && (
            <Button variant="secondary" size="sm" icon="download" onClick={handleExport}>
              Export CSV
            </Button>
          )}
        </div>
      )}

      {error && <div className={s.tableError}><Alert tone="error">{error}</Alert></div>}

      <div className={s.tableWrap}>
        <table className={s.table}>
          {caption && <caption className={s.srOnly}>{caption}</caption>}
          <thead>
            <tr>
              {columns.map((c) => {
                const align = c.align ?? 'left';
                const width = c.width ? { width: c.width } : undefined;
                if (c.sortValue && onSort) {
                  const active = sort?.key === c.key;
                  return (
                    <SortHeader
                      key={c.key}
                      label={c.header}
                      active={active}
                      dir={active ? sort!.dir : null}
                      onClick={() => onSort(c.key)}
                      align={align}
                    />
                  );
                }
                return (
                  <th key={c.key} scope="col" className={alignClass[align]} style={width}>
                    {c.header}
                  </th>
                );
              })}
            </tr>
          </thead>

          {loading ? (
            <tbody>
              {Array.from({ length: skeletonRows }, (_, i) => (
                <tr key={i} className={s.skeletonRow}>
                  {columns.map((c) => (
                    <td key={c.key} className={alignClass[c.align ?? 'left']}>
                      <Skeleton width={c.width ? '80%' : `${55 + ((i * 7 + c.key.length * 13) % 35)}%`} height={13} />
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          ) : showEmpty ? (
            <tbody>
              <tr>
                <td colSpan={columns.length} className={s.tableEmptyCell}>
                  <EmptyState
                    title={empty?.title ?? 'Nothing to show'}
                    hint={empty?.hint}
                    action={empty?.action}
                  />
                </td>
              </tr>
            </tbody>
          ) : (
            <tbody>
              {rows.map((row) => (
                <tr
                  key={rowKey(row)}
                  className={rowClassName?.(row)}
                  {...(onRowClick ? clickableRow(() => onRowClick(row)) : undefined)}
                >
                  {columns.map((c) => (
                    <td key={c.key} className={cx(alignClass[c.align ?? 'left'], c.className)} style={c.width ? { width: c.width } : undefined}>
                      {c.render(row)}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          )}
        </table>
      </div>

      {onPage && page !== undefined && lastPage !== undefined && (
        <Pagination
          page={page}
          lastPage={lastPage}
          total={total}
          noun={noun}
          onChange={onPage}
          perPage={perPage}
          onPerPageChange={onPerPageChange}
          disabled={loading}
        />
      )}
    </>
  );
}

export function DescriptionList({ items }: { items: [ReactNode, ReactNode][] }) {
  return (
    <dl className={s.dl}>
      {items.map(([k, v], i) => (
        <div key={i} style={{ display: 'contents' }}>
          <dt>{k}</dt>
          <dd>{v ?? '—'}</dd>
        </div>
      ))}
    </dl>
  );
}

/* ------------------------------------------------------------ overlays */

function useOverlay(open: boolean, onClose: () => void) {
  const panelRef = useRef<HTMLDivElement>(null);
  const onCloseRef = useRef(onClose);
  useEffect(() => {
    onCloseRef.current = onClose;
  });

  useEffect(() => {
    if (!open) return;
    const previous = document.activeElement as HTMLElement | null;
    const panel = panelRef.current;
    const first =
      panel?.querySelector<HTMLElement>('[data-autofocus]') ??
      panel?.querySelector<HTMLElement>('input, select, textarea, button:not([aria-label="Close"])');
    (first ?? panel)?.focus();

    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.stopPropagation();
        onCloseRef.current();
      } else if (e.key === 'Tab' && panel) {
        // keep focus inside the dialog
        const nodes = panel.querySelectorAll<HTMLElement>('a[href], button:not(:disabled), input:not(:disabled), select:not(:disabled), textarea:not(:disabled), [tabindex]:not([tabindex="-1"])');
        if (!nodes.length) return;
        const firstNode = nodes[0];
        const lastNode = nodes[nodes.length - 1];
        if (e.shiftKey && document.activeElement === firstNode) {
          e.preventDefault();
          lastNode.focus();
        } else if (!e.shiftKey && document.activeElement === lastNode) {
          e.preventDefault();
          firstNode.focus();
        }
      }
    };
    document.addEventListener('keydown', onKey);
    return () => {
      document.removeEventListener('keydown', onKey);
      previous?.focus?.();
    };
  }, [open]);

  return panelRef;
}

interface OverlayProps {
  open: boolean;
  onClose: () => void;
  title: ReactNode;
  description?: ReactNode;
  footer?: ReactNode;
  children?: ReactNode;
  /** Replaces the default title block (e.g. a profile header). */
  header?: ReactNode;
}

export function Modal({ open, onClose, title, description, footer, children, header, size = 'md' }: OverlayProps & { size?: 'sm' | 'md' | 'lg' }) {
  const panelRef = useOverlay(open, onClose);
  const titleId = useId();
  if (!open || typeof document === 'undefined') return null;
  return createPortal(
    <div className={cx(s.overlay, s.overlayCenter)} onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div
        ref={panelRef}
        className={cx(s.modal, size === 'sm' ? s.modalSm : size === 'lg' ? s.modalLg : s.modalMd)}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        tabIndex={-1}
      >
        <div className={s.overlayHead}>
          <div className={s.overlayHeadText}>
            {header}
            <h2 id={titleId} className={s.overlayTitle} style={header ? { display: 'none' } : undefined}>{title}</h2>
            {!header && description && <p className={s.overlayDesc}>{description}</p>}
          </div>
          <IconButton icon="close" label="Close" onClick={onClose} />
        </div>
        {children && <div className={s.overlayBody}>{children}</div>}
        {footer && <div className={s.overlayFoot}>{footer}</div>}
      </div>
    </div>,
    document.body,
  );
}

export function Drawer({ open, onClose, title, description, footer, children, header }: OverlayProps) {
  const panelRef = useOverlay(open, onClose);
  const titleId = useId();
  if (!open || typeof document === 'undefined') return null;
  return createPortal(
    <div className={cx(s.overlay, s.overlayRight)} onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <aside ref={panelRef} className={s.drawer} role="dialog" aria-modal="true" aria-labelledby={titleId} tabIndex={-1}>
        <div className={s.overlayHead}>
          <div className={s.overlayHeadText}>
            {header}
            <h2 id={titleId} className={s.overlayTitle} style={header ? { position: 'absolute', width: 1, height: 1, overflow: 'hidden', clip: 'rect(0 0 0 0)' } : undefined}>{title}</h2>
            {!header && description && <p className={s.overlayDesc}>{description}</p>}
          </div>
          <IconButton icon="close" label="Close" onClick={onClose} />
        </div>
        <div className={s.overlayBody}>{children}</div>
        {footer && <div className={s.overlayFoot}>{footer}</div>}
      </aside>
    </div>,
    document.body,
  );
}

export type ConfirmOptions = {
  title: string;
  body?: ReactNode;
  confirmLabel?: string;
  tone?: 'accent' | 'danger';
}

/**
 * Promise-based replacement for window.confirm with a styled dialog:
 *   const [confirm, confirmDialog] = useConfirm();
 *   if (!(await confirm({ title: 'Delete plan?' }))) return;
 * Render {confirmDialog} once in the page.
 */
export function useConfirm(): [(opts: ConfirmOptions) => Promise<boolean>, ReactNode] {
  const [state, setState] = useState<(ConfirmOptions & { resolve: (v: boolean) => void }) | null>(null);

  const confirm = useCallback(
    (opts: ConfirmOptions) => new Promise<boolean>((resolve) => setState({ ...opts, resolve })),
    [],
  );

  const settle = (value: boolean) => {
    state?.resolve(value);
    setState(null);
  };

  const dialog = (
    <Modal
      open={!!state}
      onClose={() => settle(false)}
      size="sm"
      title={state?.title ?? ''}
      header={
        state && (
          <>
            <span className={cx(s.confirmIcon, state.tone === 'danger' ? s.toneDanger : s.toneAccent)}>
              <Icon name={state.tone === 'danger' ? 'alert' : 'info'} size={20} />
            </span>
            <div className={s.overlayTitle}>{state.title}</div>
            {state.body && <div className={s.overlayDesc}>{state.body}</div>}
          </>
        )
      }
      footer={
        <>
          {/* Destructive prompts start on Cancel so a stray Enter can't delete anything. */}
          <Button variant="ghost" onClick={() => settle(false)} data-autofocus={state?.tone === 'danger' ? true : undefined}>Cancel</Button>
          <Button variant={state?.tone === 'danger' ? 'danger' : 'primary'} onClick={() => settle(true)} data-autofocus={state?.tone === 'danger' ? undefined : true}>
            {state?.confirmLabel ?? 'Confirm'}
          </Button>
        </>
      }
    />
  );

  return [confirm, dialog];
}

/* ------------------------------------------------------------ helpers */

/** Debounced copy of a value — for search boxes that hit the API. */
export function useDebounced<T>(value: T, delay = 350) {
  const [debounced, setDebounced] = useState(value);
  useEffect(() => {
    const t = setTimeout(() => setDebounced(value), delay);
    return () => clearTimeout(t);
  }, [value, delay]);
  return debounced;
}

/** Local-time YYYY-MM-DD (toISOString() is UTC and is a day off in IST before 05:30). */
export const localISODate = (d = new Date()) =>
  `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;

export const formatINR = (v: unknown, decimals = 0) => {
  if (v === null || v === undefined || v === '') return '—';
  const n = Number(v);
  if (Number.isNaN(n)) return '—';
  return '₹' + n.toLocaleString('en-IN', { minimumFractionDigits: decimals, maximumFractionDigits: decimals });
};

export function downloadCSV(filename: string, headers: string[], rows: unknown[][]) {
  const escape = (v: unknown) => {
    const str = String(v ?? '');
    return /[",\n]/.test(str) ? `"${str.replace(/"/g, '""')}"` : str;
  };
  const csv = '﻿' + [headers.map(escape).join(','), ...rows.map((r) => r.map(escape).join(','))].join('\n');
  const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8;' }));
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}
