'use client';

import { useCallback, useEffect, useMemo, useSyncExternalStore } from 'react';
import { THEME_STORAGE_KEY, isThemedPath, type ThemePreference } from './theme-script';

export type { ThemePreference } from './theme-script';

const readPreference = (): ThemePreference | null => {
  try {
    const v = localStorage.getItem(THEME_STORAGE_KEY);
    return v === 'dark' || v === 'light' ? v : null;
  } catch {
    return null;
  }
};

const systemPrefersDark = () =>
  typeof window !== 'undefined' && window.matchMedia('(prefers-color-scheme: dark)').matches;

export const resolveIsDark = (path: string) => {
  if (!isThemedPath(path)) return false;
  const pref = readPreference();
  return pref ? pref === 'dark' : systemPrefersDark();
};

/**
 * Present only while a swap is actually running. The glyph uses it to skip the
 * morph on hydration, where <html> already carries the right class before React
 * ever renders and the sun or moon would otherwise fly in on page load.
 */
const THEME_FLIP_ATTR = 'data-theme-flip';

/** Long enough for the slowest part of the swap: 700ms wipe, 635ms glyph. */
const FALLBACK_MS = 700;

const prefersReducedMotion = () =>
  typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

type Point = { x: number; y: number };

/**
 * The wipe grows out of the control that was pressed. Reading it from the
 * button itself is what makes the swap feel aimed rather than arbitrary, and
 * it keeps the origin correct when the button sits in a different place on
 * mobile than on desktop.
 */
const originFromControl = (): Point => {
  const centre = { x: window.innerWidth / 2, y: window.innerHeight / 2 };
  const el = document.querySelector<HTMLElement>('[data-theme-origin]');
  if (!el) return centre;
  const r = el.getBoundingClientRect();
  if (!r.width && !r.height) return centre;
  return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
};

const setWipeOrigin = ({ x, y }: Point) => {
  const root = document.documentElement;
  // Big enough to reach the furthest corner from that point, so the circle
  // always closes past the edge of the viewport.
  const r = Math.hypot(Math.max(x, window.innerWidth - x), Math.max(y, window.innerHeight - y));
  root.style.setProperty('--theme-wipe-x', `${x}px`);
  root.style.setProperty('--theme-wipe-y', `${y}px`);
  root.style.setProperty('--theme-wipe-r', `${r}px`);
};

const clearWipeOrigin = () => {
  const root = document.documentElement;
  root.style.removeProperty('--theme-wipe-x');
  root.style.removeProperty('--theme-wipe-y');
  root.style.removeProperty('--theme-wipe-r');
  root.removeAttribute(THEME_FLIP_ATTR);
};

/**
 * A swap in flight owns the root; a second click finishes the first one
 * immediately rather than queueing behind it, so hammering the button stays
 * responsive instead of lagging a frame per click.
 */
let inFlight: ViewTransition | null = null;

export const applyThemeClass = (dark: boolean, animate = false) => {
  const root = document.documentElement;
  const commit = () => {
    root.classList.toggle('dark', dark);
    root.setAttribute(THEME_FLIP_ATTR, '');
  };

  // Without the View Transition API the swap is a plain cross-fade, so the
  // flag would outlive the only animation that reads it.
  const canWipe = animate && typeof document.startViewTransition === 'function' && !prefersReducedMotion();

  if (!canWipe) {
    if (animate) {
      root.classList.add('theme-transition');
      window.setTimeout(() => root.classList.remove('theme-transition'), FALLBACK_MS);
      // The glyph has no wipe to sit inside, so it morphs on its own clock.
      root.setAttribute(THEME_FLIP_ATTR, '');
      window.setTimeout(() => root.removeAttribute(THEME_FLIP_ATTR), 640);
    }
    commit();
    return;
  }

  inFlight?.skipTransition();
  setWipeOrigin(originFromControl());

  const transition = document.startViewTransition(commit);
  inFlight = transition;
  const settle = () => {
    if (inFlight !== transition) return;
    inFlight = null;
    clearWipeOrigin();
  };
  transition.finished.then(settle, settle);
};

/**
 * <html> is the source of truth (the inline script sets it before paint), so
 * React subscribes to it rather than keeping a copy that could drift.
 */
const subscribeToRoot = (onChange: () => void) => {
  const obs = new MutationObserver(onChange);
  obs.observe(document.documentElement, { attributes: true, attributeFilter: ['class', 'data-sidebar-collapsed'] });
  return () => obs.disconnect();
};

const isDarkSnapshot = () => document.documentElement.classList.contains('dark');

export function useIsDark() {
  return useSyncExternalStore(subscribeToRoot, isDarkSnapshot, () => false);
}

/** True when <html> carries the given boolean attribute. */
export function useRootAttribute(name: string) {
  return useSyncExternalStore(
    subscribeToRoot,
    () => document.documentElement.hasAttribute(name),
    () => false,
  );
}

/** Current theme + a toggle. Use inside any themed route. */
export function useTheme() {
  const isDark = useIsDark();

  // Follow the OS while the user hasn't picked a theme explicitly.
  useEffect(() => {
    const mq = window.matchMedia('(prefers-color-scheme: dark)');
    const onChange = () => {
      if (!readPreference()) applyThemeClass(resolveIsDark(window.location.pathname), true);
    };
    mq.addEventListener('change', onChange);
    return () => mq.removeEventListener('change', onChange);
  }, []);

  // The origin of the wipe is read from the [data-theme-origin] control, so
  // this works identically whether it was clicked or run from the palette.
  const toggle = useCallback(() => {
    const next = !document.documentElement.classList.contains('dark');
    try {
      localStorage.setItem(THEME_STORAGE_KEY, next ? 'dark' : 'light');
    } catch {}
    applyThemeClass(next, true);
  }, []);

  return { isDark, toggle };
}

/**
 * Resolved chart colours for the active theme. Recharts takes colours as
 * props, so we read the CSS tokens and re-read them whenever `.dark` flips.
 */
const CHART_TOKENS = ['--chart-1', '--chart-2', '--chart-3', '--chart-4', '--chart-5', '--chart-grid', '--chart-axis', '--text-muted', '--surface-3'] as const;

export type ChartPalette = {
  c1: string; c2: string; c3: string; c4: string; c5: string;
  grid: string; axis: string; muted: string; track: string;
};

const LIGHT_FALLBACK: ChartPalette = {
  c1: '#9C54F2', c2: '#14B8A6', c3: '#F59E0B', c4: '#EF4444', c5: '#3B82F6',
  grid: '#ECE9F2', axis: '#8A849C', muted: '#8A849C', track: '#F2F0F7',
};

const readPalette = (): ChartPalette => {
  const cs = getComputedStyle(document.documentElement);
  const v = CHART_TOKENS.map((t) => cs.getPropertyValue(t).trim());
  if (!v[0]) return LIGHT_FALLBACK;
  return { c1: v[0], c2: v[1], c3: v[2], c4: v[3], c5: v[4], grid: v[5], axis: v[6], muted: v[7], track: v[8] };
};

export function useChartPalette(): ChartPalette {
  // During hydration this is the server snapshot (false), so the first client
  // render uses the same light palette the server rendered, then updates.
  const isDark = useIsDark();
  return useMemo(() => (isDark ? readPalette() : LIGHT_FALLBACK), [isDark]);
}
