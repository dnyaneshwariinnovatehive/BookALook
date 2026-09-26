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

export const applyThemeClass = (dark: boolean, animate = false) => {
  const root = document.documentElement;
  if (animate) {
    root.classList.add('theme-transition');
    window.setTimeout(() => root.classList.remove('theme-transition'), 320);
  }
  root.classList.toggle('dark', dark);
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
