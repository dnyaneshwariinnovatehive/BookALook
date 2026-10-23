'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { Pagination, useConfirm } from '@/components/admin/ui';
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

interface CustomerDetails {
  id: string;
  name: string;
  phone: string | null;
  email: string | null;
  created_at: string | null;
  total_platform_bookings: number;
  salon_visits_count: number;
  past_complaints_count: number;
}

interface SalonDetails {
  id: string;
  name: string;
  status: string | null;
  suspended_reason: string | null;
  contact_phone: string | null;
  contact_email: string | null;
  street_address: string | null;
  address: string | null;
  city_name: string;
  sub_area_name: string;
  pincode: string | null;
  gender_focus: string;
  commercial_model: string;
  commission_percentage: number | null;
  owner_name: string | null;
  owner_phone: string | null;
  owner_email: string | null;
  created_at: string | null;
}

interface AppointmentServiceLine {
  id: string;
  name: string;
  category: string;
  price: number;
  duration_minutes: number;
  serving_provider_name: string | null;
  line_status: string | null;
}

interface AppointmentServiceAddition {
  id: string;
  name: string;
  price: number;
  duration_minutes: number;
  provider_name: string | null;
  added_by_name: string | null;
  status: string;
  added_at: string | null;
}

interface AppointmentDetails {
  id: string;
  appointment_date: string | null;
  start_time: string | null;
  end_time: string | null;
  status: string;
  payment_status: string | null;
  payment_mode: string | null;
  booking_source: string | null;
  total_amount: number | null;
  advance_paid_amount: number | null;
  balance_amount: number | null;
  final_billed_amount: number | null;
  first_time_discount_amount: number | null;
  appointed_provider_name: string | null;
  appointed_provider_phone: string | null;
  serving_provider_name: string | null;
  serving_provider_phone: string | null;
  payment_collected_by: string | null;
  invoice_id: string | null;
  invoice_number: string | null;
  verification_method: string | null;
  checked_in_at: string | null;
  completed_at: string | null;
  cancelled_at: string | null;
  cancellation_reason: string | null;
  customer_notes: string | null;
  services: AppointmentServiceLine[];
  service_additions: AppointmentServiceAddition[];
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
  const [notice, setNotice] = useState('');
  const [confirm, confirmDialog] = useConfirm();

  // The complaint currently open for a decision, with the context needed to
  // make one.
  const [selected, setSelected] = useState<Complaint | null>(null);
  const [context, setContext] = useState<SalonContext | null>(null);
  const [customerDetails, setCustomerDetails] = useState<CustomerDetails | null>(null);
  const [salonDetails, setSalonDetails] = useState<SalonDetails | null>(null);
  const [appointmentDetails, setAppointmentDetails] = useState<AppointmentDetails | null>(null);
  const [modalTab, setModalTab] = useState<'decision' | 'appointment' | 'salon' | 'customer'>('decision');
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
    setCustomerDetails(null);
    setSalonDetails(null);
    setAppointmentDetails(null);
    setModalTab('decision');
    setMessage('');
    setActionError('');
    setAction(complaint.status === 'open' || complaint.status === 'under_review' ? 'warn' : 'dismiss');

    try {
      const res = await fetch(`/api/proxy/superadmin/complaints/${complaint.id}`, { cache: 'no-store' });
      const json = await res.json();
      if (json.success) {
        setContext(json.salon_context);
        if (json.customer_details) setCustomerDetails(json.customer_details);
        if (json.salon_details) setSalonDetails(json.salon_details);
        if (json.appointment_details) setAppointmentDetails(json.appointment_details);
      }
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
    const ok = await confirm({
      title: `Put ${complaint.salon_name} back online?`,
      body: complaint.action_taken
        ? `It comes down off the platform immediately and the owner can take bookings again. The ${ACTION_LABELS[complaint.action_taken]?.toLowerCase() ?? complaint.action_taken} on this complaint stays on the record.`
        : 'It comes down off the platform immediately and the owner can take bookings again.',
      confirmLabel: 'Put back online',
    });
    if (!ok) return;

    try {
      const res = await fetch(`/api/proxy/superadmin/salons/${complaint.salon_id}/reinstate`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: '{}',
      });
      const json = await res.json();
      if (!res.ok) throw new Error(json.message || 'Could not reinstate the salon.');
      setNotice(`${complaint.salon_name} is back online.`);
      await load();
    } catch (e) {
      setNotice(e instanceof Error ? e.message : 'Could not reinstate the salon.');
    }
  };

  return (
    <div className={styles.container}>
      {notice && (
        <p role="status" style={{ color: 'var(--text-body)', marginBottom: '1rem' }}>
          {notice}
        </p>
      )}

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
            {/* Modal Header */}
            <div className={styles.modalHead}>
              <div>
                <div style={{ display: 'flex', alignItems: 'center', gap: '0.6rem', marginBottom: '0.25rem', flexWrap: 'wrap' }}>
                  <h2 className={styles.modalTitle} style={{ margin: 0 }}>{selected.subject}</h2>
                  <span className={`${styles.badge} ${styles[`badge_${selected.status}`] ?? ''}`}>
                    {STATUS_LABELS[selected.status] ?? selected.status}
                  </span>
                </div>
                <p className={styles.modalSub} style={{ margin: 0 }}>
                  Reported by <strong>{selected.customer_name}</strong> · <strong>{selected.salon_name}</strong> · {selected.age_label}
                </p>
              </div>
              <button className={styles.closeBtn} onClick={() => !saving && setSelected(null)} title="Close">
                ✕
              </button>
            </div>

            {/* Quick Glance Chips */}
            <div className={styles.quickGlance}>
              <span className={styles.glanceChip}>
                👤 <span>Customer: <strong>{customerDetails?.name || selected.customer_name}</strong> {customerDetails?.phone ? `(${customerDetails.phone})` : ''}</span>
              </span>
              <span className={styles.glanceChip}>
                ✂️ <span>Salon: <strong>{salonDetails?.name || selected.salon_name}</strong> ({salonDetails?.city_name || '—'})</span>
              </span>
              <span className={styles.glanceChip}>
                📅 <span>Visit: <strong>{appointmentDetails?.appointment_date || selected.appointment_date || 'No Date'}</strong> {appointmentDetails?.start_time ? `at ${appointmentDetails.start_time}` : ''}</span>
              </span>
              {appointmentDetails?.total_amount != null && (
                <span className={styles.glanceChip}>
                  💰 <span>Bill: <strong>₹{appointmentDetails.total_amount}</strong> ({appointmentDetails.payment_status || 'unpaid'})</span>
                </span>
              )}
              {context?.rating && (
                <span className={styles.glanceChip}>
                  ⭐ <span>Rating: <strong>{context.rating.average || '—'}/5</strong> ({context.rating.count} reviews)</span>
                </span>
              )}
            </div>

            {/* Customer Complaint Statement */}
            <div className={styles.modalDescription}>
              <div style={{ fontSize: '0.725rem', fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.04em', color: 'var(--text-muted)', marginBottom: '0.35rem' }}>
                Customer Complaint Statement
              </div>
              <div style={{ color: 'var(--text-heading)', fontWeight: 500 }}>{selected.description}</div>
            </div>

            {/* Public Review on Same Visit */}
            {context?.review_for_this_visit && (
              <div className={styles.reviewBox}>
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '0.25rem' }}>
                  <span className={styles.reviewStars}>
                    ★ {context.review_for_this_visit.rating} / 5
                  </span>
                  <span style={{ fontSize: '0.75rem', color: '#b45309', fontWeight: 600 }}>
                    Public review for this visit
                  </span>
                </div>
                {context.review_for_this_visit.comment && (
                  <p style={{ margin: 0, fontSize: '0.85rem', color: 'var(--text-heading)', fontStyle: 'italic' }}>
                    “{context.review_for_this_visit.comment}”
                  </p>
                )}
              </div>
            )}

            {/* Modal Tabs */}
            <div className={styles.modalTabs}>
              <button
                type="button"
                className={`${styles.modalTabBtn} ${modalTab === 'decision' ? styles.modalTabBtnActive : ''}`}
                onClick={() => setModalTab('decision')}
              >
                ⚖️ Take Decision
              </button>
              <button
                type="button"
                className={`${styles.modalTabBtn} ${modalTab === 'appointment' ? styles.modalTabBtnActive : ''}`}
                onClick={() => setModalTab('appointment')}
              >
                📅 Appointment Details {appointmentDetails ? `(${appointmentDetails.services.length} services)` : ''}
              </button>
              <button
                type="button"
                className={`${styles.modalTabBtn} ${modalTab === 'salon' ? styles.modalTabBtnActive : ''}`}
                onClick={() => setModalTab('salon')}
              >
                ✂️ Salon Information
              </button>
              <button
                type="button"
                className={`${styles.modalTabBtn} ${modalTab === 'customer' ? styles.modalTabBtnActive : ''}`}
                onClick={() => setModalTab('customer')}
              >
                👤 Customer Profile
              </button>
            </div>

            {/* TAB: DECISION */}
            {modalTab === 'decision' && (
              <div>
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
              </div>
            )}

            {/* TAB: APPOINTMENT DETAILS */}
            {modalTab === 'appointment' && (
              <div>
                {!appointmentDetails ? (
                  <div className={styles.empty} style={{ padding: '2rem 1rem' }}>
                    No appointment record was attached to this complaint.
                  </div>
                ) : (
                  <div>
                    {/* Financial Summary */}
                    <div className={styles.metricStrip}>
                      <div className={styles.metricCard}>
                        <div className={styles.metricLabel}>Total Amount</div>
                        <div className={styles.metricVal}>₹{appointmentDetails.total_amount ?? 0}</div>
                      </div>
                      <div className={styles.metricCard}>
                        <div className={styles.metricLabel}>Advance Paid</div>
                        <div className={styles.metricVal} style={{ color: 'var(--color-success)' }}>
                          ₹{appointmentDetails.advance_paid_amount ?? 0}
                        </div>
                      </div>
                      <div className={styles.metricCard}>
                        <div className={styles.metricLabel}>Balance Due</div>
                        <div className={styles.metricVal} style={{ color: (appointmentDetails.balance_amount ?? 0) > 0 ? 'var(--color-warning)' : 'var(--text-heading)' }}>
                          ₹{appointmentDetails.balance_amount ?? 0}
                        </div>
                      </div>
                      <div className={styles.metricCard}>
                        <div className={styles.metricLabel}>Final Billed</div>
                        <div className={styles.metricVal}>₹{appointmentDetails.final_billed_amount ?? appointmentDetails.total_amount ?? 0}</div>
                      </div>
                    </div>

                    <div className={styles.infoGrid}>
                      <div className={styles.infoCard}>
                        <div className={styles.infoCardTitle}>📅 Visit & Timing</div>
                        <div className={styles.kvRow}>
                          <span className={styles.kvKey}>Appointment Date</span>
                          <span className={styles.kvVal}>{appointmentDetails.appointment_date || '—'}</span>
                        </div>
                        <div className={styles.kvRow}>
                          <span className={styles.kvKey}>Slot Time</span>
                          <span className={styles.kvVal}>
                            {appointmentDetails.start_time || '—'} {appointmentDetails.end_time ? `– ${appointmentDetails.end_time}` : ''}
                          </span>
                        </div>
                        <div className={styles.kvRow}>
                          <span className={styles.kvKey}>Booking Status</span>
                          <span className={styles.kvVal}>
                            <span className={styles.statusTag} style={{ background: 'rgba(156, 84, 242, 0.12)', color: 'var(--accent-text)' }}>
                              {appointmentDetails.status}
                            </span>
                          </span>
                        </div>
                        <div className={styles.kvRow}>
                          <span className={styles.kvKey}>Payment Status</span>
                          <span className={styles.kvVal}>
                            <span className={styles.statusTag} style={{ background: appointmentDetails.payment_status === 'paid' ? 'rgba(34, 197, 94, 0.15)' : 'rgba(239, 108, 0, 0.15)', color: appointmentDetails.payment_status === 'paid' ? 'var(--color-success)' : 'var(--color-warning)' }}>
                              {appointmentDetails.payment_status || 'unpaid'}
                            </span>
                          </span>
                        </div>
                        <div className={styles.kvRow}>
                          <span className={styles.kvKey}>Payment Mode</span>
                          <span className={styles.kvVal}>{appointmentDetails.payment_mode || '—'}</span>
                        </div>
                        <div className={styles.kvRow}>
                          <span className={styles.kvKey}>Booking Source</span>
                          <span className={styles.kvVal}>{appointmentDetails.booking_source || 'app'}</span>
                        </div>
                        {appointmentDetails.invoice_number && (
                          <div className={styles.kvRow}>
                            <span className={styles.kvKey}>Invoice #</span>
                            <span className={styles.kvVal}>{appointmentDetails.invoice_number}</span>
                          </div>
                        )}
                      </div>

                      <div className={styles.infoCard}>
                        <div className={styles.infoCardTitle}>👥 Staff & Verification</div>
                        <div className={styles.kvRow}>
                          <span className={styles.kvKey}>Appointed Staff</span>
                          <span className={styles.kvVal}>
                            {appointmentDetails.appointed_provider_name || '—'}
                            {appointmentDetails.appointed_provider_phone ? ` (${appointmentDetails.appointed_provider_phone})` : ''}
                          </span>
                        </div>
                        <div className={styles.kvRow}>
                          <span className={styles.kvKey}>Serving Staff</span>
                          <span className={styles.kvVal}>
                            {appointmentDetails.serving_provider_name || appointmentDetails.appointed_provider_name || '—'}
                            {appointmentDetails.serving_provider_phone ? ` (${appointmentDetails.serving_provider_phone})` : ''}
                          </span>
                        </div>
                        <div className={styles.kvRow}>
                          <span className={styles.kvKey}>Check-In Method</span>
                          <span className={styles.kvVal}>{appointmentDetails.verification_method || '—'}</span>
                        </div>
                        <div className={styles.kvRow}>
                          <span className={styles.kvKey}>Checked-in At</span>
                          <span className={styles.kvVal}>{appointmentDetails.checked_in_at || '—'}</span>
                        </div>
                        <div className={styles.kvRow}>
                          <span className={styles.kvKey}>Completed At</span>
                          <span className={styles.kvVal}>{appointmentDetails.completed_at || '—'}</span>
                        </div>
                        {appointmentDetails.cancelled_at && (
                          <div className={styles.kvRow}>
                            <span className={styles.kvKey}>Cancelled At</span>
                            <span className={styles.kvVal} style={{ color: 'var(--color-danger)' }}>
                              {appointmentDetails.cancelled_at} {appointmentDetails.cancellation_reason ? `(${appointmentDetails.cancellation_reason})` : ''}
                            </span>
                          </div>
                        )}
                        {appointmentDetails.customer_notes && (
                          <div className={styles.kvRow}>
                            <span className={styles.kvKey}>Customer Notes</span>
                            <span className={styles.kvVal}>{appointmentDetails.customer_notes}</span>
                          </div>
                        )}
                      </div>
                    </div>

                    {/* Booked Services Table */}
                    <div style={{ marginTop: '0.75rem' }}>
                      <div style={{ fontSize: '0.85rem', fontWeight: 700, color: 'var(--text-heading)', marginBottom: '0.5rem' }}>
                        Booked Services ({appointmentDetails.services.length})
                      </div>
                      <div className={styles.tableWrapper}>
                        <table className={styles.servicesTable}>
                          <thead>
                            <tr>
                              <th>Service Name</th>
                              <th>Category</th>
                              <th>Duration</th>
                              <th>Price</th>
                              <th>Serving Staff</th>
                              <th>Status</th>
                            </tr>
                          </thead>
                          <tbody>
                            {appointmentDetails.services.map((svc) => (
                              <tr key={svc.id}>
                                <td><strong>{svc.name}</strong></td>
                                <td>{svc.category}</td>
                                <td>{svc.duration_minutes}m</td>
                                <td>₹{svc.price}</td>
                                <td>{svc.serving_provider_name || '—'}</td>
                                <td>
                                  <span className={styles.statusTag} style={{ background: 'rgba(34, 197, 94, 0.12)', color: 'var(--color-success)' }}>
                                    {svc.line_status || 'booked'}
                                  </span>
                                </td>
                              </tr>
                            ))}
                          </tbody>
                        </table>
                      </div>
                    </div>

                    {/* In-Salon Additions if any */}
                    {appointmentDetails.service_additions && appointmentDetails.service_additions.length > 0 && (
                      <div style={{ marginTop: '0.75rem' }}>
                        <div style={{ fontSize: '0.85rem', fontWeight: 700, color: 'var(--text-heading)', marginBottom: '0.5rem' }}>
                          In-Salon Service Additions ({appointmentDetails.service_additions.length})
                        </div>
                        <div className={styles.tableWrapper}>
                          <table className={styles.servicesTable}>
                            <thead>
                              <tr>
                                <th>Addition</th>
                                <th>Price</th>
                                <th>Staff</th>
                                <th>Added By</th>
                                <th>Status</th>
                              </tr>
                            </thead>
                            <tbody>
                              {appointmentDetails.service_additions.map((add) => (
                                <tr key={add.id}>
                                  <td><strong>{add.name}</strong></td>
                                  <td>₹{add.price}</td>
                                  <td>{add.provider_name || '—'}</td>
                                  <td>{add.added_by_name || '—'}</td>
                                  <td>
                                    <span className={styles.statusTag} style={{ background: 'rgba(21, 101, 192, 0.12)', color: 'var(--color-info)' }}>
                                      {add.status}
                                    </span>
                                  </td>
                                </tr>
                              ))}
                            </tbody>
                          </table>
                        </div>
                      </div>
                    )}
                  </div>
                )}
              </div>
            )}

            {/* TAB: SALON INFORMATION */}
            {modalTab === 'salon' && (
              <div className={styles.infoGrid}>
                <div className={styles.infoCard}>
                  <div className={styles.infoCardTitle}>✂️ Salon Profile & Address</div>
                  <div className={styles.kvRow}>
                    <span className={styles.kvKey}>Salon Name</span>
                    <span className={styles.kvVal}>{salonDetails?.name || selected.salon_name}</span>
                  </div>
                  <div className={styles.kvRow}>
                    <span className={styles.kvKey}>Status</span>
                    <span className={styles.kvVal}>
                      <span className={`${styles.badge} ${styles[`badge_${salonDetails?.status ?? selected.salon_status}`] ?? ''}`}>
                        {salonDetails?.status ?? selected.salon_status ?? 'Active'}
                      </span>
                    </span>
                  </div>
                  <div className={styles.kvRow}>
                    <span className={styles.kvKey}>Gender Focus</span>
                    <span className={styles.kvVal}>{salonDetails?.gender_focus || 'Unisex'}</span>
                  </div>
                  <div className={styles.kvRow}>
                    <span className={styles.kvKey}>Salon Phone</span>
                    <span className={styles.kvVal}>{salonDetails?.contact_phone || selected.owner_phone || '—'}</span>
                  </div>
                  <div className={styles.kvRow}>
                    <span className={styles.kvKey}>Salon Email</span>
                    <span className={styles.kvVal}>{salonDetails?.contact_email || '—'}</span>
                  </div>
                  <div className={styles.kvRow}>
                    <span className={styles.kvKey}>Street Address</span>
                    <span className={styles.kvVal}>{salonDetails?.street_address || salonDetails?.address || '—'}</span>
                  </div>
                  <div className={styles.kvRow}>
                    <span className={styles.kvKey}>Area & City</span>
                    <span className={styles.kvVal}>{salonDetails?.sub_area_name ? `${salonDetails.sub_area_name}, ` : ''}{salonDetails?.city_name || '—'}</span>
                  </div>
                  <div className={styles.kvRow}>
                    <span className={styles.kvKey}>Pincode</span>
                    <span className={styles.kvVal}>{salonDetails?.pincode || '—'}</span>
                  </div>
                  <div className={styles.kvRow}>
                    <span className={styles.kvKey}>Onboarded On</span>
                    <span className={styles.kvVal}>{salonDetails?.created_at || '—'}</span>
                  </div>
                </div>

                <div className={styles.infoCard}>
                  <div className={styles.infoCardTitle}>👑 Ownership & Commercials</div>
                  <div className={styles.kvRow}>
                    <span className={styles.kvKey}>Owner Name</span>
                    <span className={styles.kvVal}>{salonDetails?.owner_name || selected.owner_name || '—'}</span>
                  </div>
                  <div className={styles.kvRow}>
                    <span className={styles.kvKey}>Owner Phone</span>
                    <span className={styles.kvVal}>{salonDetails?.owner_phone || selected.owner_phone || '—'}</span>
                  </div>
                  <div className={styles.kvRow}>
                    <span className={styles.kvKey}>Owner Email</span>
                    <span className={styles.kvVal}>{salonDetails?.owner_email || '—'}</span>
                  </div>
                  <div className={styles.kvRow}>
                    <span className={styles.kvKey}>Commercial Model</span>
                    <span className={styles.kvVal}>
                      {salonDetails?.commercial_model === 'commission'
                        ? `Commission (${salonDetails.commission_percentage ?? 0}%)`
                        : 'Subscription Plan'}
                    </span>
                  </div>
                  <div className={styles.kvRow}>
                    <span className={styles.kvKey}>Public Rating</span>
                    <span className={styles.kvVal}>
                      ⭐ {context?.rating.average || '—'} / 5 ({context?.rating.count || 0} reviews)
                    </span>
                  </div>
                  <div className={styles.kvRow}>
                    <span className={styles.kvKey}>Total Complaints</span>
                    <span className={styles.kvVal} style={{ color: (context?.complaints_total ?? 0) > 1 ? 'var(--color-danger)' : 'var(--text-heading)' }}>
                      {context?.complaints_total ?? 0}
                    </span>
                  </div>
                  <div className={styles.kvRow}>
                    <span className={styles.kvKey}>Warnings Sent</span>
                    <span className={styles.kvVal} style={{ color: (context?.warnings_sent ?? 0) > 0 ? 'var(--color-warning)' : 'var(--text-heading)' }}>
                      {context?.warnings_sent ?? 0}
                    </span>
                  </div>
                </div>
              </div>
            )}

            {/* TAB: CUSTOMER PROFILE */}
            {modalTab === 'customer' && (
              <div className={styles.infoGrid}>
                <div className={styles.infoCard}>
                  <div className={styles.infoCardTitle}>👤 Customer Details</div>
                  <div className={styles.kvRow}>
                    <span className={styles.kvKey}>Full Name</span>
                    <span className={styles.kvVal}>{customerDetails?.name || selected.customer_name}</span>
                  </div>
                  <div className={styles.kvRow}>
                    <span className={styles.kvKey}>Phone Number</span>
                    <span className={styles.kvVal}>{customerDetails?.phone || selected.customer_phone || '—'}</span>
                  </div>
                  <div className={styles.kvRow}>
                    <span className={styles.kvKey}>Email Address</span>
                    <span className={styles.kvVal}>{customerDetails?.email || '—'}</span>
                  </div>
                  <div className={styles.kvRow}>
                    <span className={styles.kvKey}>Registered Since</span>
                    <span className={styles.kvVal}>{customerDetails?.created_at || '—'}</span>
                  </div>
                </div>

                <div className={styles.infoCard}>
                  <div className={styles.infoCardTitle}>📊 Platform Activity & Trust</div>
                  <div className={styles.kvRow}>
                    <span className={styles.kvKey}>Total Platform Bookings</span>
                    <span className={styles.kvVal}>{customerDetails?.total_platform_bookings ?? '—'}</span>
                  </div>
                  <div className={styles.kvRow}>
                    <span className={styles.kvKey}>Visits to This Salon</span>
                    <span className={styles.kvVal}>{customerDetails?.salon_visits_count ?? '—'}</span>
                  </div>
                  <div className={styles.kvRow}>
                    <span className={styles.kvKey}>Past Complaints Filed</span>
                    <span className={styles.kvVal} style={{ color: (customerDetails?.past_complaints_count ?? 0) > 0 ? 'var(--color-warning)' : 'var(--text-heading)' }}>
                      {customerDetails?.past_complaints_count ?? 0}
                    </span>
                  </div>
                </div>
              </div>
            )}

            {/* Modal Actions */}
            <div className={styles.modalActions}>
              <button
                className={styles.secondaryButton}
                onClick={() => setSelected(null)}
                disabled={saving}
              >
                Close
              </button>
              {modalTab !== 'decision' ? (
                <button
                  className={styles.primaryButton}
                  onClick={() => setModalTab('decision')}
                >
                  Proceed to Decision →
                </button>
              ) : (
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
              )}
            </div>
          </div>
        </div>
      )}

      {confirmDialog}
    </div>
  );
}
