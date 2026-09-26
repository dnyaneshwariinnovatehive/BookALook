'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import Icon, { type IconName } from './Icon';
import { navGroups } from '@/app/superadmin/nav';
import styles from './CommandPalette.module.css';

interface Command {
  id: string;
  label: string;
  group: string;
  icon: IconName;
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

/** Ctrl/⌘ + K jump-to-anything for the 18 admin sections. Mount it only
 *  while open, so each opening starts with a fresh query. */
export default function CommandPalette({ open, onClose, isDark, onToggleTheme, onSignOut }: Props) {
  const router = useRouter();
  const [query, setQuery] = useState('');
  const [active, setActive] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);
  const listRef = useRef<HTMLDivElement>(null);

  const commands = useMemo<Command[]>(() => {
    const pages = navGroups.flatMap((g) =>
      g.items.map((item) => ({
        id: item.path,
        label: item.name,
        group: g.label,
        icon: item.icon,
        keywords: `${item.name} ${g.label} ${item.keywords ?? ''}`.toLowerCase(),
        run: () => router.push(item.path),
      })),
    );
    return [
      ...pages,
      {
        id: 'theme',
        label: isDark ? 'Switch to light mode' : 'Switch to dark mode',
        group: 'Actions',
        icon: isDark ? 'sun' : 'moon',
        keywords: 'theme dark light appearance',
        run: onToggleTheme,
      },
      { id: 'signout', label: 'Sign out', group: 'Actions', icon: 'logout', keywords: 'logout exit', run: onSignOut },
    ];
  }, [router, isDark, onToggleTheme, onSignOut]);

  const results = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return commands;
    const terms = q.split(/\s+/);
    return commands.filter((c) => terms.every((t) => c.keywords.includes(t)));
  }, [commands, query]);

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
    } else if (e.key === 'Enter') {
      e.preventDefault();
      execute(results[active]);
    } else if (e.key === 'Escape') {
      e.preventDefault();
      onClose();
    }
  };

  let lastGroup = '';

  return (
    <div className={styles.overlay} onMouseDown={onClose}>
      <div
        className={styles.panel}
        role="dialog"
        aria-modal="true"
        aria-label="Command menu"
        onMouseDown={(e) => e.stopPropagation()}
        onKeyDown={onKeyDown}
      >
        <div className={styles.inputRow}>
          <Icon name="search" size={18} className={styles.inputIcon} />
          <input
            ref={inputRef}
            autoFocus
            className={styles.input}
            placeholder="Search pages and actions…"
            value={query}
            onChange={(e) => {
              setQuery(e.target.value);
              setActive(0);
            }}
            role="combobox"
            aria-expanded="true"
            aria-controls="command-results"
            aria-activedescendant={results[active] ? `cmd-${results[active].id}` : undefined}
          />
          <kbd className={styles.kbd}>Esc</kbd>
        </div>

        <div className={styles.results} id="command-results" role="listbox" ref={listRef}>
          {results.length === 0 ? (
            <div className={styles.empty}>No matches for “{query}”</div>
          ) : (
            results.map((cmd, i) => {
              const header = cmd.group !== lastGroup ? cmd.group : null;
              lastGroup = cmd.group;
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
                    <span className={styles.itemLabel}>{cmd.label}</span>
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
          <span><kbd className={styles.kbd}>Ctrl</kbd><kbd className={styles.kbd}>K</kbd> toggle</span>
        </div>
      </div>
    </div>
  );
}
