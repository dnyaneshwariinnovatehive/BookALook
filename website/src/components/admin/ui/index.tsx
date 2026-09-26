'use client';

import {
  useCallback, useEffect, useId, useRef, useState,
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

type ButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & {
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

export function SortHeader({ label, active, dir, onClick, align }: {
  label: string;
  active: boolean;
  dir: 'asc' | 'desc';
  onClick: () => void;
  align?: 'left' | 'right';
}) {
  return (
    <th className={align === 'right' ? s.alignRight : undefined} aria-sort={active ? (dir === 'asc' ? 'ascending' : 'descending') : 'none'}>
      <button type="button" className={cx(s.sortBtn, active && s.sortBtnActive)} onClick={onClick}>
        {label}
        <Icon name={active ? (dir === 'asc' ? 'arrowUp' : 'arrowDown') : 'sortBoth'} size={12} strokeWidth={2.2} className={s.sortArrow} />
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

export function Pagination({ page, lastPage, total, noun = 'results', onChange }: {
  page: number;
  lastPage: number;
  total?: number;
  noun?: string;
  onChange: (page: number) => void;
}) {
  if (lastPage <= 1) {
    return total !== undefined ? (
      <div className={s.pagination}><span>{total.toLocaleString('en-IN')} {noun}</span></div>
    ) : null;
  }
  const pages: (number | 'gap')[] = [];
  for (let p = 1; p <= lastPage; p++) {
    if (p === 1 || p === lastPage || Math.abs(p - page) <= 1) pages.push(p);
    else if (pages[pages.length - 1] !== 'gap') pages.push('gap');
  }
  return (
    <nav className={s.pagination} aria-label="Pagination">
      <span>
        Page {page} of {lastPage}
        {total !== undefined && ` · ${total.toLocaleString('en-IN')} ${noun}`}
      </span>
      <div className={s.pageButtons}>
        <IconButton icon="chevronLeft" label="Previous page" disabled={page <= 1} onClick={() => onChange(page - 1)} />
        {pages.map((p, i) =>
          p === 'gap' ? (
            <span key={`g${i}`} className={s.pageGap}>…</span>
          ) : (
            <button
              key={p}
              type="button"
              className={cx(s.pageNum, p === page && s.pageNumActive)}
              aria-current={p === page ? 'page' : undefined}
              onClick={() => onChange(p)}
            >
              {p}
            </button>
          ),
        )}
        <IconButton icon="chevronRight" label="Next page" disabled={page >= lastPage} onClick={() => onChange(page + 1)} />
      </div>
    </nav>
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

interface ConfirmOptions {
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
