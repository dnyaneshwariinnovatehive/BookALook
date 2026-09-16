'use client';

import { useCallback, useEffect, useState } from 'react';
import styles from './page.module.css';

interface Change {
  field: string;
  from: string | number | null;
  to: string | number | null;
}

interface Entry {
  id: string;
  action: string;
  action_label: string;
  category: string;
  severity: 'normal' | 'high' | 'critical';
  actor_name: string;
  actor_role: string | null;
  entity_type: string;
  entity_label: string | null;
  field_name: string | null;
  changes: Change[];
  reason: string | null;
  metadata: Record<string, unknown> | null;
  ip_address: string | null;
  created_at: string;
  occurred_on: string;
  occurred_at: string;
}

interface Actor {
  id: string;
  name: string;
  role: string;
}

interface Summary {
  total: number;
  last_7_days: number;
  critical_last_7_days: number;
  active_actors_last_7_days: number;
}

const RANGES = [
  { key: '1', label: 'Today' },
  { key: '7', label: 'Last 7 days' },
  { key: '30', label: 'Last 30 days' },
  { key: '', label: 'All time' },
];

/**
 * An audit log is read for precision, so the timestamp is always absolute.
 * Entries are grouped under a full date heading and each row carries its exact
 * clock time — "2 hours ago" is useless the day after you read it.
 */
function formatDayHeading(isoDate: string) {
  const date = new Date(`${isoDate}T00:00:00`);
  const today = new Date();
  today.setHours(0, 0, 0, 0);

  const diffDays = Math.round((today.getTime() - date.getTime()) / 86_400_000);
  const full = date.toLocaleDateString('en-IN', {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
    year: 'numeric',
  });

  if (diffDays === 0) return `Today · ${full}`;
  if (diffDays === 1) return `Yesterday · ${full}`;
  return full;
}

export default function AuditLogPage() {
  const [entries, setEntries] = useState<Entry[]>([]);
  const [actors, setActors] = useState<Actor[]>([]);
  const [categories, setCategories] = useState<string[]>([]);
  const [summary, setSummary] = useState<Summary | null>(null);

  const [range, setRange] = useState('7');
  const [category, setCategory] = useState('');
  const [severity, setSeverity] = useState('');
  const [actorId, setActorId] = useState('');
  const [search, setSearch] = useState('');
  const [debouncedSearch, setDebouncedSearch] = useState('');

  const [page, setPage] = useState(1);
  const [hasMore, setHasMore] = useState(false);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const [expanded, setExpanded] = useState<string | null>(null);

  useEffect(() => {
    const timer = setTimeout(() => setDebouncedSearch(search), 400);
    return () => clearTimeout(timer);
  }, [search]);

  const load = useCallback(
    async (targetPage: number, append: boolean) => {
      setLoading(true);
      try {
        const params = new URLSearchParams({ page: String(targetPage) });
        if (range) params.set('within_days', range);
        if (category) params.set('category', category);
        if (severity) params.set('severity', severity);
        if (actorId) params.set('actor_id', actorId);
        if (debouncedSearch.trim()) params.set('search', debouncedSearch.trim());

        const res = await fetch(`/api/proxy/superadmin/audit-log?${params}`, { cache: 'no-store' });
        const json = await res.json();
        if (!json.success) throw new Error(json.message || 'Could not load the audit log');

        setEntries((prev) => (append ? [...prev, ...json.data] : json.data));
        setActors(json.filters?.actors || []);
        setCategories(json.filters?.categories || []);
        setSummary(json.summary || null);
        setHasMore(json.meta?.has_more || false);
        setTotal(json.meta?.total || 0);
        setError('');
      } catch (e) {
        setError(e instanceof Error ? e.message : 'Could not load the audit log');
      } finally {
        setLoading(false);
      }
    },
    [range, category, severity, actorId, debouncedSearch]
  );

  useEffect(() => {
    setPage(1);
    load(1, false);
  }, [load]);

  const loadMore = () => {
    const next = page + 1;
    setPage(next);
    load(next, true);
  };

  // Entries arrive newest-first; grouping preserves that order within each day.
  const days = entries.reduce<Record<string, Entry[]>>((acc, entry) => {
    (acc[entry.occurred_on] ||= []).push(entry);
    return acc;
  }, {});

  return (
    <div className={styles.container}>
      <div className={styles.header}>
        <h1 className={styles.title}>Audit Log</h1>
        <p className={styles.subtitle}>
          Every sensitive action taken from this dashboard — who did it, what
          changed, and exactly when. Entries are written automatically and cannot
          be edited or deleted.
        </p>
      </div>

      {summary && (
        <div className={styles.statRow}>
          <div className={styles.stat}>
            <span className={styles.statValue}>{summary.last_7_days}</span>
            <span className={styles.statLabel}>Actions this week</span>
          </div>
          <div className={`${styles.stat} ${summary.critical_last_7_days > 0 ? styles.statAlert : ''}`}>
            <span className={styles.statValue}>{summary.critical_last_7_days}</span>
            <span className={styles.statLabel}>Critical this week</span>
          </div>
          <div className={styles.stat}>
            <span className={styles.statValue}>{summary.active_actors_last_7_days}</span>
            <span className={styles.statLabel}>People active</span>
          </div>
          <div className={styles.stat}>
            <span className={styles.statValue}>{summary.total}</span>
            <span className={styles.statLabel}>Entries on record</span>
          </div>
        </div>
      )}

      <div className={styles.filterBar}>
        <input
          className={styles.searchInput}
          placeholder="Search salon, reason, or person…"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />

        <select className={styles.select} value={range} onChange={(e) => setRange(e.target.value)}>
          {RANGES.map((r) => (
            <option key={r.key} value={r.key}>{r.label}</option>
          ))}
        </select>

        <select className={styles.select} value={category} onChange={(e) => setCategory(e.target.value)}>
          <option value="">All areas</option>
          {categories.map((c) => (
            <option key={c} value={c}>{c}</option>
          ))}
        </select>

        <select className={styles.select} value={severity} onChange={(e) => setSeverity(e.target.value)}>
          <option value="">Any importance</option>
          <option value="critical">Critical only</option>
          <option value="high">High and above</option>
          <option value="normal">Routine</option>
        </select>

        <select className={styles.select} value={actorId} onChange={(e) => setActorId(e.target.value)}>
          <option value="">Anyone</option>
          {actors.map((a) => (
            <option key={a.id} value={a.id}>{a.name}</option>
          ))}
        </select>
      </div>

      {loading && entries.length === 0 ? (
        <div className={styles.empty}>Loading…</div>
      ) : error ? (
        <div className={styles.empty} style={{ color: 'var(--color-danger)' }}>{error}</div>
      ) : entries.length === 0 ? (
        <div className={styles.empty}>
          Nothing recorded for these filters. The log fills itself as sensitive
          actions are taken — approvals, suspensions, rate changes, payouts and
          policy edits.
        </div>
      ) : (
        <>
          <p className={styles.resultCount}>
            {total} {total === 1 ? 'entry' : 'entries'}
          </p>

          {Object.entries(days).map(([day, dayEntries]) => (
            <section key={day} className={styles.day}>
              <h2 className={styles.dayHeading}>{formatDayHeading(day)}</h2>

              <div className={styles.entries}>
                {dayEntries.map((entry) => {
                  const isOpen = expanded === entry.id;
                  const hasDetail =
                    entry.changes.length > 0 || entry.reason || entry.metadata || entry.ip_address;

                  return (
                    <article
                      key={entry.id}
                      className={`${styles.entry} ${styles[`sev_${entry.severity}`]}`}
                    >
                      <time className={styles.time} dateTime={entry.created_at}>
                        {entry.occurred_at}
                      </time>

                      <div className={styles.body}>
                        <div className={styles.line}>
                          <strong className={styles.actor}>{entry.actor_name}</strong>
                          <span className={styles.actionLabel}>
                            {entry.action_label.toLowerCase()}
                          </span>
                          {entry.entity_label && (
                            <strong className={styles.subject}>{entry.entity_label}</strong>
                          )}
                          <span className={`${styles.chip} ${styles[`chip_${entry.severity}`]}`}>
                            {entry.category}
                          </span>
                        </div>

                        {entry.reason && (
                          <p className={styles.reason}>&ldquo;{entry.reason}&rdquo;</p>
                        )}

                        {entry.changes.length > 0 && (
                          <div className={styles.changes}>
                            {entry.changes.slice(0, isOpen ? undefined : 3).map((change) => (
                              <span key={change.field} className={styles.change}>
                                <span className={styles.changeField}>{change.field}</span>
                                <span className={styles.changeFrom}>{String(change.from ?? '—')}</span>
                                <span className={styles.arrow}>→</span>
                                <span className={styles.changeTo}>{String(change.to ?? '—')}</span>
                              </span>
                            ))}
                            {!isOpen && entry.changes.length > 3 && (
                              <span className={styles.moreCount}>
                                +{entry.changes.length - 3} more
                              </span>
                            )}
                          </div>
                        )}

                        {isOpen && (
                          <dl className={styles.detail}>
                            <dt>Exact time</dt>
                            <dd>{new Date(entry.created_at).toLocaleString('en-IN')}</dd>

                            <dt>Actor</dt>
                            <dd>
                              {entry.actor_name}
                              {entry.actor_role ? ` (${entry.actor_role})` : ''}
                            </dd>

                            <dt>Acted on</dt>
                            <dd>
                              {entry.entity_type}
                              {entry.entity_label ? ` — ${entry.entity_label}` : ''}
                            </dd>

                            {entry.ip_address && (
                              <>
                                <dt>From IP</dt>
                                <dd>{entry.ip_address}</dd>
                              </>
                            )}

                            {entry.metadata &&
                              Object.entries(entry.metadata).map(([key, value]) => (
                                <div key={key} className={styles.detailPair}>
                                  <dt>{key.replace(/_/g, ' ')}</dt>
                                  <dd>{String(value ?? '—')}</dd>
                                </div>
                              ))}
                          </dl>
                        )}

                        {hasDetail && (
                          <button
                            className={styles.toggle}
                            onClick={() => setExpanded(isOpen ? null : entry.id)}
                          >
                            {isOpen ? 'Hide details' : 'Details'}
                          </button>
                        )}
                      </div>
                    </article>
                  );
                })}
              </div>
            </section>
          ))}

          {hasMore && (
            <div className={styles.loadMoreWrap}>
              <button className={styles.loadMore} onClick={loadMore} disabled={loading}>
                {loading ? 'Loading…' : 'Load older entries'}
              </button>
            </div>
          )}
        </>
      )}
    </div>
  );
}
