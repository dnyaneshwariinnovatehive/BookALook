'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { Pagination } from '@/components/admin/ui';
import styles from './page.module.css';

interface Complaint {
  id: string;
  subject: string;
  description: string;
  status: string;
  action_taken: string | null;
  resolution_note: string | null;
  salon_id: string;
  salon_name: string;
  salon_status: string | null;
  owner_name: string | null;
  owner_phone: string | null;
  customer_name: string;
  customer_phone: string | null;
  appointment_date: string | null;
  resolved_by: string | null;
  resolved_at: string | null;
  created_at: string;
  age_label: string;
}

interface SalonContext {
  rating: { average: number; count: number };
  complaints_total: number;
  complaints_outstanding: number;
  warnings_sent: number;
  review_for_this_visit: { rating: number; comment: string | null } | null;
}

type Action = 'warn' | 'suspend' | 'dismiss';

const STATUS_LABELS: Record<string, string> = {
  open: 'Open',
  under_review: 'Under review',
  resolved: 'Resolved',
  dismissed: 'Dismissed',
};

const ACTION_LABELS: Record<string, string> = {
  warning: 'Warning sent',
  suspended: 'Salon suspended',
  dismissed: 'No action',
};

export default function ComplaintsPage() {
  const [complaints, setComplaints] = useState<Complaint[]>([]);
  const [counts, setCounts] = useState({ outstanding: 0, open: 0, resolved: 0, dismissed: 0 });
  const [filter, setFilter] = useState<string>('outstanding');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [page, setPage] = useState(1);
  const [perPage, setPerPage] = useState(20);
  const [meta, setMeta] = useState({ current_page: 1, last_page: 1, total: 0 });

  // The complaint currently open for a decision, with the context needed to
  // make one.
  const [selected, setSelected] = useState<Complaint | null>(null);
  const [context, setContext] = useState<SalonContext | null>(null);
  const [action, setAction] = useState<Action>('warn');
  const [message, setMessage] = useState('');
  const [saving, setSaving] = useState(false);
  const [actionError, setActionError] = useState('');

  // Paging can land out of order; only the newest request may render.
  const requestId = useRef(0);

  const load = useCallback(async () => {
    const id = ++requestId.current;
    setLoading(true);
    try {
      const params = new URLSearchParams({ status: filter, page: String(page), per_page: String(perPage) });
      const res = await fetch(`/api/proxy/superadmin/complaints?${params}`, {
        cache: 'no-store',
      });
      const json = await res.json();
      if (id !== requestId.current) return;
      if (!json.success) throw new Error(json.message || 'Could not load complaints');
      setComplaints(json.data || []);
      setCounts(json.counts || counts);
      if (json.meta) setMeta(json.meta);
      setError('');
    } catch (e) {
      if (id !== requestId.current) return;
      setError(e instanceof Error ? e.message : 'Could not load complaints');
    } finally {
      if (id === requestId.current) setLoading(false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filter, page, perPage]);

  useEffect(() => {
    const timer = setTimeout(load, 0);
    return () => clearTimeout(timer);
  }, [load]);

  const openComplaint = async (complaint: Complaint) => {
    setSelected(complaint);
    setContext(null);
    setMessage('');
    setActionError('');
    setAction(complaint.status === 'open' || complaint.status === 'under_review' ? 'warn' : 'dismiss');

    try {
      const res = await fetch(`/api/proxy/superadmin/complaints/${complaint.id}`, { cache: 'no-store' });
      const json = await res.json();
      if (json.success) setContext(json.salon_context);
    } catch {
      // The decision panel still works without context; it is supporting
      // information, not a prerequisite.
    }
  };

  const submitAction = async () => {
    if (!selected) return;

    if (action !== 'dismiss' && message.trim().length === 0) {
      setActionError(
        action === 'warn'
          ? 'Write the warning the owner will read.'
          : 'Give a reason — the owner is told why their salon went offline.'
      );
      return;
    }

    setSaving(true);
    setActionError('');

    const body =
      action === 'warn'
        ? { message: message.trim() }
        : action === 'suspend'
          ? { reason: message.trim() }
          : { note: message.trim() || null };

    try {
      const res = await fetch(`/api/proxy/superadmin/complaints/${selected.id}/${action}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });
      const json = await res.json();

      if (!res.ok || !json.success) throw new Error(json.message || 'Action failed');

      setSelected(null);
      await load();
    } catch (e) {
      setActionError(e instanceof Error ? e.message : 'Action failed');
    } finally {
      setSaving(false);
    }
  };

  const reinstate = async (complaint: Complaint) => {
    if (!confirm(`Put ${complaint.salon_name} back online?`)) return;

    try {
      const res = await fetch(`/api/proxy/superadmin/salons/${complaint.salon_id}/reinstate`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: '{}',
      });
      const json = await res.json();
      alert(json.message || 'Done');
      await load();
    } catch {
      alert('Could not reinstate the salon.');
    }
  };

  return (
    <div className={styles.container}>
      <div className={styles.header}>
        <div>
          <h1 className={styles.title}>Complaints</h1>
          <p className={styles.subtitle}>
            Reported by customers after a visit. A warning goes to the owner&apos;s
            app; a suspension takes the salon offline immediately.
          </p>
        </div>
      </div>

      <div className={styles.filters}>
        {[
          { key: 'outstanding', label: `Needs a decision (${counts.outstanding})` },
          { key: 'resolved', label: `Resolved (${counts.resolved})` },
          { key: 'dismissed', label: `Dismissed (${counts.dismissed})` },
          { key: '', label: 'All' },
        ].map((tab) => (
          <button
            key={tab.key}
            className={`${styles.filterChip} ${filter === tab.key ? styles.filterChipActive : ''}`}
            onClick={() => { setFilter(tab.key); setPage(1); }}
          >
            {tab.label}
          </button>
        ))}
      </div>

      {loading ? (
        <div className={styles.empty}>Loading…</div>
      ) : error ? (
        <div className={styles.empty} style={{ color: 'var(--color-danger)' }}>{error}</div>
      ) : complaints.length === 0 ? (
        <div className={styles.empty}>
          {filter === 'outstanding'
            ? 'Nothing waiting on you. Complaints appear here the moment a customer reports a visit.'
            : 'Nothing here.'}
        </div>
      ) : (
        <div className={styles.list}>
          {complaints.map((complaint) => (
            <div key={complaint.id} className={styles.card}>
              <div className={styles.cardHead}>
                <div>
                  <h3 className={styles.cardTitle}>{complaint.subject}</h3>
                  <p className={styles.cardMeta}>
                    <strong>{complaint.salon_name}</strong> · reported by {complaint.customer_name} ·{' '}
                    {complaint.age_label}
                  </p>
                </div>
                <span className={`${styles.badge} ${styles[`badge_${complaint.status}`] ?? ''}`}>
                  {STATUS_LABELS[complaint.status] ?? complaint.status}
                </span>
              </div>

              <p className={styles.description}>{complaint.description}</p>

              {complaint.action_taken && (
                <div className={styles.outcome}>
                  <strong>{ACTION_LABELS[complaint.action_taken] ?? complaint.action_taken}</strong>
                  {complaint.resolved_by ? ` by ${complaint.resolved_by}` : ''}
                  {complaint.resolution_note ? ` — “${complaint.resolution_note}”` : ''}
                </div>
              )}

              <div className={styles.cardFoot}>
                <span className={styles.contact}>
                  Owner: {complaint.owner_name ?? '—'}
                  {complaint.owner_phone ? ` · ${complaint.owner_phone}` : ''}
                </span>

                <div className={styles.actions}>
                  {complaint.salon_status === 'suspended' && (
                    <button className={styles.secondaryButton} onClick={() => reinstate(complaint)}>
                      Put back online
                    </button>
                  )}
                  {(complaint.status === 'open' || complaint.status === 'under_review') && (
                    <button className={styles.primaryButton} onClick={() => openComplaint(complaint)}>
                      Decide
                    </button>
                  )}
                </div>
              </div>
            </div>
          ))}
        </div>
      )}

      {meta.last_page > 0 && (
        <div className={styles.pager}>
          <Pagination
            page={meta.current_page}
            lastPage={meta.last_page}
            total={meta.total}
            noun={filter === 'outstanding' ? 'outstanding' : 'complaints'}
            onChange={setPage}
            perPage={perPage}
            onPerPageChange={(n) => { setPerPage(n); setPage(1); }}
            disabled={loading}
          />
        </div>
      )}

      {selected && (
        <div className={styles.overlay} onClick={() => !saving && setSelected(null)}>
          <div className={styles.modal} onClick={(e) => e.stopPropagation()}>
            <h2 className={styles.modalTitle}>{selected.subject}</h2>
            <p className={styles.modalSub}>
              {selected.salon_name} · reported by {selected.customer_name} · {selected.age_label}
            </p>

            <p className={styles.modalDescription}>{selected.description}</p>

            {context && (
              <div className={styles.context}>
                <p className={styles.contextTitle}>Before you decide</p>
                <ul className={styles.contextList}>
                  <li>
                    Rated <strong>{context.rating.average || '—'}</strong> from{' '}
                    {context.rating.count} {context.rating.count === 1 ? 'customer' : 'customers'}
                  </li>
                  <li>
                    <strong>{context.complaints_total}</strong> complaint
                    {context.complaints_total === 1 ? '' : 's'} in total,{' '}
                    <strong>{context.warnings_sent}</strong> warning
                    {context.warnings_sent === 1 ? '' : 's'} already sent
                  </li>
                  {context.review_for_this_visit && (
                    <li>
                      This customer publicly rated the same visit{' '}
                      <strong>{context.review_for_this_visit.rating}/5</strong>
                      {context.review_for_this_visit.comment
                        ? ` — “${context.review_for_this_visit.comment}”`
                        : ''}
                    </li>
                  )}
                </ul>
              </div>
            )}

            <div className={styles.choices}>
              {(
                [
                  ['warn', 'Send a warning', 'The owner reads it in their app. The salon keeps trading.'],
                  ['suspend', 'Suspend the salon', 'Offline immediately. Customers stop seeing it and the owner’s app locks.'],
                  ['dismiss', 'Dismiss', 'Close it with no action against the salon.'],
                ] as [Action, string, string][]
              ).map(([key, label, hint]) => (
                <label
                  key={key}
                  className={`${styles.choice} ${action === key ? styles.choiceActive : ''} ${
                    key === 'suspend' ? styles.choiceDanger : ''
                  }`}
                >
                  <input
                    type="radio"
                    name="action"
                    checked={action === key}
                    onChange={() => {
                      setAction(key);
                      setActionError('');
                    }}
                  />
                  <span>
                    <strong>{label}</strong>
                    <em>{hint}</em>
                  </span>
                </label>
              ))}
            </div>

            <label className={styles.fieldLabel}>
              {action === 'warn'
                ? 'The warning the owner will read'
                : action === 'suspend'
                  ? 'Why the salon is being suspended'
                  : 'Note (optional, internal)'}
            </label>
            <textarea
              className={styles.textarea}
              rows={4}
              value={message}
              onChange={(e) => setMessage(e.target.value)}
              placeholder={
                action === 'warn'
                  ? 'Stations must be cleaned between every customer.'
                  : action === 'suspend'
                    ? 'Repeated hygiene failures after a written warning.'
                    : 'Could not be substantiated.'
              }
            />

            {actionError && <p className={styles.actionError}>{actionError}</p>}

            <div className={styles.modalActions}>
              <button
                className={styles.secondaryButton}
                onClick={() => setSelected(null)}
                disabled={saving}
              >
                Cancel
              </button>
              <button
                className={action === 'suspend' ? styles.dangerButton : styles.primaryButton}
                onClick={submitAction}
                disabled={saving}
              >
                {saving
                  ? 'Saving…'
                  : action === 'warn'
                    ? 'Send warning'
                    : action === 'suspend'
                      ? 'Suspend salon'
                      : 'Dismiss complaint'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
