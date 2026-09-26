/**
 * Theme handling for the admin surfaces.
 *
 * The preference lives in localStorage under `theme` ("light" | "dark";
 * absent means follow the OS). Dark is only ever applied on the admin and
 * login routes — the public landing page is a fixed light brand design.
 *
 * THEME_SCRIPT runs inline in <head> before first paint, so a reload never
 * flashes the wrong theme. Hooks live in ./theme (client-only).
 */

export type ThemePreference = 'light' | 'dark';

export const THEME_STORAGE_KEY = 'theme';

export const isThemedPath = (path: string) => path.startsWith('/superadmin') || path === '/login';

export const THEME_SCRIPT = `(function(){try{var p=location.pathname;var s=p.indexOf('/superadmin')===0||p==='/login';var t=localStorage.getItem('${THEME_STORAGE_KEY}');var d=s&&(t==='dark'||(t!=='light'&&matchMedia('(prefers-color-scheme: dark)').matches));var r=document.documentElement;r.classList.toggle('dark',!!d);if(s&&localStorage.getItem('sa_sidebar')==='collapsed')r.setAttribute('data-sidebar-collapsed','')}catch(e){}})()`;
