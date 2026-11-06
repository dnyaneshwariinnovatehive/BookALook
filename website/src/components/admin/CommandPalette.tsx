'use client';

import { Fragment, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { usePathname, useRouter } from 'next/navigation';
import Icon, { type IconName } from './Icon';
import { normalizeSearch } from './ui';
import { navGroups, type NavSection } from '@/app/superadmin/nav';
import styles from './CommandPalette.module.css';

type Kind = 'here' | 'page' | 'section' | 'action';

interface Command {
  id: string;
  kind: Kind;
  label: string;
  /** Where it lives, shown under the label ("Platform Reporting › Money"). */
  trail?: string;
  icon: IconName;
  /** Normalised words it matches on, besides the label. */
  keywords: string;
  run: () => void;
}

interface Props {
  open: boolean;
  onClose: () => void;
  isDark: boolean;
  onToggleTheme: () => void;
  onSignOut: () => void;
}

const GROUP_LABEL: Record<Kind, string> = {
  here: 'On this page',
  page: 'Pages',
  section: 'Sections',
  action: 'Actions',
};

const SECTION_LIMIT = 12;
const HERE_LIMIT = 8;

/** Headings on the page behind the palette, so any card can be found by name. */
function readPageHeadings(): string[] {
  if (typeof document === 'undefined') return [];
  const seen = new Set<string>();
  const out: string[] = [];
  document
    .querySelectorAll<HTMLElement>('#main-content h1, #main-content h2, #main-content h3, #main-content [data-section]')
    .forEach((el) => {
      if (el.closest('[role="dialog"]')) return;
      const text = (el.dataset.section ?? el.textContent ?? '').replace(/\s+/g, ' ').trim();
      const key = normalizeSearch(text);
      if (text.length < 3 || text.length > 80 || seen.has(key)) return;
      seen.add(key);
      out.push(text);
    });
  return out;
}

function findHeading(heading: string): HTMLElement | null {
  const want = normalizeSearch(heading);
  const nodes = [...document.querySelectorAll<HTMLElement>('#main-content h1, #main-content h2, #main-content h3, #main-content [data-section]')]
    .filter((el) => !el.closest('[role="dialog"]'));
  const text = (el: HTMLElement) => normalizeSearch(el.dataset.section ?? el.textContent ?? '');
  return nodes.find((el) => text(el) === want) ?? nodes.find((el) => text(el).startsWith(want)) ?? null;
}

/**
 * Switch to the section's tab if it has one, then scroll its card into view
 * and ring it briefly. Polls for a few seconds because the page (or the tab)
 * may still be loading after navigation.
 */
function jumpTo(target: { tab?: string; heading: string }) {
  const deadline = Date.now() + 8000;
  const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  let tabDone = !target.tab;

  const tick = () => {
    if (!tabDone && target.tab) {
      const want = normalizeSearch(target.tab);
      const tab = [...document.querySelectorAll<HTMLElement>('#main-content [role="tab"]')]
        .find((t) => normalizeSearch(t.textContent).startsWith(want));
      if (tab) {
        if (tab.getAttribute('aria-selected') !== 'true') tab.click();
        tabDone = true;
        if (!target.heading) {
          tab.scrollIntoView({ block: 'nearest', behavior: reduce ? 'auto' : 'smooth' });
          return;
        }
      }
    }
    if (tabDone && target.heading) {
      const el = findHeading(target.heading);
      if (el) {
        const block = el.closest<HTMLElement>('section, [class*="card"], [class*="Card"], [class*="panel"]') ?? el;
        block.style.scrollMarginTop = '84px';
        block.scrollIntoView({ block: 'start', behavior: reduce ? 'auto' : 'smooth' });
        if (!reduce) {
          block.animate(
            [
              { boxShadow: '0 0 0 0 rgba(156, 84, 242, 0)' },
              { boxShadow: '0 0 0 4px rgba(156, 84, 242, 0.55)', offset: 0.25 },
              { boxShadow: '0 0 0 0 rgba(156, 84, 242, 0)' },
            ],
            { duration: 1800, easing: 'ease-out' },
          );
        }
        return;
      }
    }
    if (Date.now() < deadline) setTimeout(tick, 150);
  };
  setTimeout(tick, 60);
}

/** Higher is better: exact label, label start, a word start, anywhere, keywords only. */
function score(cmd: Command, words: string[]): number {
  const label = normalizeSearch(cmd.label);
  const all = `${label} ${cmd.keywords}`;
  if (!words.every((w) => all.includes(w))) return -1;
  const q = words.join(' ');
  if (label === q) return 100;
  if (label.startsWith(q)) return 80;
  if (label.split(/[\s›&/-]+/).some((part) => part.startsWith(words[0]))) return 60;
  if (words.every((w) => label.includes(w))) return 40;
  return 20;
}

/** Bold the parts of the label the query matched. */
function highlight(label: string, words: string[]): ReactNode {
  if (!words.length) return label;
  const norm = normalizeSearch(label);
  // Only highlight when normalising kept every character in place.
  if (norm.length !== label.length) return label;
  const marks = new Array(label.length).fill(false);
  for (const w of words) {
    let i = norm.indexOf(w);
    while (i !== -1) {
      for (let k = i; k < i + w.length; k++) marks[k] = true;
      i = norm.indexOf(w, i + w.length);
    }
  }
  const parts: ReactNode[] = [];
  let start = 0;
  for (let i = 1; i <= label.length; i++) {
    if (i === label.length || marks[i] !== marks[start]) {
      const chunk = label.slice(start, i);
      parts.push(marks[start] ? <mark key={start} className={styles.match}>{chunk}</mark> : <Fragment key={start}>{chunk}</Fragment>);
      start = i;
    }
  }
  return parts;
}

/** Ctrl/⌘ + K: jump to any page, any card or tab inside a page, or an action.
 *  Mount it only while open, so each opening starts fresh. */
export default function CommandPalette({ open, onClose, isDark, onToggleTheme, onSignOut }: Props) {
  const router = useRouter();
  const pathname = usePathname();
  const [query, setQuery] = useState('');
  const [active, setActive] = useState(0);
  const [headings] = useState(readPageHeadings);
  const inputRef = useRef<HTMLInputElement>(null);
  const listRef = useRef<HTMLDivElement>(null);

  const commands = useMemo<Command[]>(() => {
    const go = (path: string, target?: { tab?: string; heading: string }) => () => {
      if (pathname !== path) router.push(path);
      if (target) jumpTo(target);
    };

    const here: Command[] = headings.map((h, i) => ({
      id: `here-${i}`,
      kind: 'here',
      label: h,
      icon: 'arrowRight',
      keywords: '',
      run: () => jumpTo({ heading: h }),
    }));

    const pages: Command[] = [];
    const sections: Command[] = [];
    for (const g of navGroups) {
      for (const item of g.items) {
        pages.push({
          id: item.path,
          kind: 'page',
          label: item.name,
          trail: g.label,
          icon: item.icon,
          keywords: normalizeSearch(`${g.label} ${item.keywords ?? ''}`),
          run: go(item.path),
        });
        (item.sections ?? []).forEach((sec: NavSection, i) => {
          sections.push({
            id: `${item.path}#${i}`,
            kind: 'section',
            label: sec.name,
            trail: sec.tab && sec.heading !== '' ? `${item.name} › ${sec.tab}` : item.name,
            icon: item.icon,
            keywords: normalizeSearch(`${item.name} ${sec.tab ?? ''} ${sec.keywords ?? ''}`),
            run: go(item.path, { tab: sec.tab, heading: sec.heading ?? sec.name }),
          });
        });
      }
    }

    const actions: Command[] = [
      {
        id: 'theme',
        kind: 'action',
        label: isDark ? 'Switch to light mode' : 'Switch to dark mode',
        icon: isDark ? 'sun' : 'moon',
        keywords: 'theme dark light appearance',
        run: onToggleTheme,
      },
      { id: 'signout', kind: 'action', label: 'Sign out', icon: 'logout', keywords: 'logout exit', run: onSignOut },
    ];

    return [...here, ...pages, ...sections, ...actions];
  }, [router, pathname, headings, isDark, onToggleTheme, onSignOut]);

  const words = useMemo(() => normalizeSearch(query).split(' ').filter(Boolean), [query]);

  const results = useMemo(() => {
    if (!words.length) {
      // Nothing typed: what is on this page, then every page and the actions.
      return [
        ...commands.filter((c) => c.kind === 'here').slice(0, HERE_LIMIT),
        ...commands.filter((c) => c.kind === 'page' || c.kind === 'action'),
      ];
    }
    const order: Kind[] = ['here', 'page', 'section', 'action'];
    const limit: Partial<Record<Kind, number>> = { here: HERE_LIMIT, section: SECTION_LIMIT };
    const ranked = commands
      .map((c) => ({ c, s: score(c, words) }))
      .filter((r) => r.s >= 0);
    // Best match first inside each group; the group with the best match first.
    const best = (k: Kind) => Math.max(-1, ...ranked.filter((r) => r.c.kind === k).map((r) => r.s));
    const groups = order
      .filter((k) => best(k) >= 0)
      .sort((a, b) => best(b) - best(a) || order.indexOf(a) - order.indexOf(b));
    return groups.flatMap((k) =>
      ranked
        .filter((r) => r.c.kind === k)
        .sort((a, b) => b.s - a.s)
        .slice(0, limit[k] ?? Infinity)
        .map((r) => r.c),
    );
  }, [commands, words]);

  useEffect(() => {
    listRef.current?.querySelector<HTMLElement>(`[data-index="${active}"]`)?.scrollIntoView({ block: 'nearest' });
  }, [active]);

  if (!open) return null;

  const execute = (cmd: Command | undefined) => {
    if (!cmd) return;
    onClose();
    cmd.run();
  };

  const onKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      setActive((i) => (results.length ? (i + 1) % results.length : 0));
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      setActive((i) => (results.length ? (i - 1 + results.length) % results.length : 0));
    } else if (e.key === 'Home') {
      e.preventDefault();
      setActive(0);
    } else if (e.key === 'End') {
      e.preventDefault();
      setActive(Math.max(0, results.length - 1));
    } else if (e.key === 'Enter') {
      e.preventDefault();
      execute(results[active]);
    } else if (e.key === 'Escape') {
      e.preventDefault();
      if (query) {
        setQuery('');
        setActive(0);
      } else {
        onClose();
      }
    }
  };

  let lastKind: Kind | '' = '';

  return (
    <div className={styles.overlay} onMouseDown={onClose}>
      <div
        className={styles.panel}
        role="dialog"
        aria-modal="true"
        aria-label="Search pages, sections and actions"
        onMouseDown={(e) => e.stopPropagation()}
        onKeyDown={onKeyDown}
      >
        <div className={styles.inputRow}>
          <Icon name="search" size={18} className={styles.inputIcon} />
          <input
            ref={inputRef}
            autoFocus
            className={styles.input}
            placeholder="Search pages, sections and actions…"
            value={query}
            autoComplete="off"
            spellCheck={false}
            maxLength={80}
            onChange={(e) => {
              setQuery(e.target.value);
              setActive(0);
            }}
            role="combobox"
            aria-expanded="true"
            aria-controls="command-results"
            aria-activedescendant={results[active] ? `cmd-${results[active].id}` : undefined}
          />
          {query ? (
            <button
              type="button"
              className={styles.clear}
              onClick={() => {
                setQuery('');
                setActive(0);
                inputRef.current?.focus();
              }}
              aria-label="Clear search"
            >
              <Icon name="close" size={14} />
            </button>
          ) : (
            <kbd className={styles.kbd}>Esc</kbd>
          )}
        </div>

        <div className={styles.results} id="command-results" role="listbox" ref={listRef}>
          {results.length === 0 ? (
            <div className={styles.empty}>
              <b>No matches for “{query.trim()}”</b>
              <span>Try a page name like “payouts”, or a card like “peak times” or “money in pocket”.</span>
            </div>
          ) : (
            results.map((cmd, i) => {
              const header = cmd.kind !== lastKind ? GROUP_LABEL[cmd.kind] : null;
              lastKind = cmd.kind;
              return (
                <div key={cmd.id}>
                  {header && <div className={styles.groupLabel}>{header}</div>}
                  <button
                    id={`cmd-${cmd.id}`}
                    type="button"
                    role="option"
                    aria-selected={i === active}
                    data-index={i}
                    className={`${styles.item} ${i === active ? styles.itemActive : ''}`}
                    onMouseMove={() => setActive(i)}
                    onClick={() => execute(cmd)}
                  >
                    <span className={styles.itemIcon}><Icon name={cmd.icon} size={16} /></span>
                    <span className={styles.itemText}>
                      <span className={styles.itemLabel}>{highlight(cmd.label, words)}</span>
                      {cmd.trail && <span className={styles.itemTrail}>{cmd.trail}</span>}
                    </span>
                    {i === active && <Icon name="enter" size={14} className={styles.enterHint} />}
                  </button>
                </div>
              );
            })
          )}
        </div>

        <div className={styles.footer}>
          <span><kbd className={styles.kbd}>↑</kbd><kbd className={styles.kbd}>↓</kbd> navigate</span>
          <span><kbd className={styles.kbd}>↵</kbd> open</span>
          <span><kbd className={styles.kbd}>Esc</kbd> {query ? 'clear' : 'close'}</span>
          <span className={styles.footerRight}><kbd className={styles.kbd}>Ctrl</kbd><kbd className={styles.kbd}>K</kbd> toggle</span>
        </div>
      </div>
    </div>
  );
}
