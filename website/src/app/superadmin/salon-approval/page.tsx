'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
import Link from 'next/link';
import { Pagination, SortHeader, useConfirm, useDebounced, type SortDir } from '@/components/admin/ui';
import styles from './page.module.css';

interface Salon {
  id: string;
  name: string;
  created_at: string;
  city?: { name: string };
  admin?: { name: string };
}

interface Enquiry {
  id: string;
  salon_name: string;
  owner_name: string;
  city: string;
  phone: string;
  status: string;
  created_at: string;
  assigned_collaborator_id?: string;
  assigned_collaborator?: { name: string };
  city_id?: string | null;
  sub_area_id?: string | null;
  city_name?: string | null;
  sub_area_name?: string | null;
  location_label?: string | null;
}

interface Collaborator {
  id: string;
  name: string;
  city_id?: string | null;
  sub_area_id?: string | null;
  city_name?: string | null;
  sub_area_name?: string | null;
  location_label?: string | null;
  has_location?: boolean;
}

interface PageMeta {
  current_page: number;
  last_page: number;
  per_page: number;
  total: number;
}

const EMPTY_META: PageMeta = { current_page: 1, last_page: 1, per_page: 20, total: 0 };

/**
 * How close a collaborator is to an enquiry.
 */
type Proximity = 'same-area' | 'same-city' | 'elsewhere' | 'unknown';

function proximityOf(collaborator: Collaborator, enquiry: Enquiry): Proximity {
  if (!collaborator.city_id) return 'unknown';
  if (!enquiry.city_id) return 'unknown';
  if (collaborator.city_id !== enquiry.city_id) return 'elsewhere';
  if (
    enquiry.sub_area_id &&
    collaborator.sub_area_id &&
    collaborator.sub_area_id === enquiry.sub_area_id
  ) {
    return 'same-area';
  }
  return 'same-city';
}

const PROXIMITY_RANK: Record<Proximity, number> = {
  'same-area': 0,
  'same-city': 1,
  elsewhere: 2,
  unknown: 3,
};

const PROXIMITY_LABEL: Record<Proximity, string> = {
  'same-area': 'Same area',
  'same-city': 'Same city',
  elsewhere: '',
  unknown: 'No area set',
};

function CollaboratorPicker({
  enquiry,
  collaborators,
  value,
  onChange,
}: {
  enquiry: Enquiry;
  collaborators: Collaborator[];
  value: string;
  onChange: (id: string) => void;
}) {
  const ranked = useMemo(() => rankFor(enquiry, collaborators), [enquiry, collaborators]);

  const groups: { key: Proximity; heading: string }[] = [
    { key: 'same-area', heading: `In ${enquiry.sub_area_name ?? 'the same area'}` },
    { key: 'same-city', heading: `Elsewhere in ${enquiry.city_name ?? 'this city'}` },
    { key: 'elsewhere', heading: 'Other cities' },
    { key: 'unknown', heading: 'No area set' },
  ];

  const best = ranked[0];
  const hasLocalMatch = best && (best.proximity === 'same-area' || best.proximity === 'same-city');

  return (
    <div className={styles.pickerWrap}>
      <select
        className={`${styles.picker} ${hasLocalMatch && !value ? styles.pickerSuggested : ''}`}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        aria-label={`Collaborator for ${enquiry.salon_name}`}
      >
        <option value="">Select collaborator</option>
        {groups.map(({ key, heading }) => {
          const inGroup = ranked.filter((r) => r.proximity === key);
          if (inGroup.length === 0) return null;

          return (
            <optgroup key={key} label={heading}>
              {inGroup.map(({ collaborator }) => (
                <option key={collaborator.id} value={collaborator.id}>
                  {collaborator.name}
                  {collaborator.location_label ? ` — ${collaborator.location_label}` : ''}
                </option>
              ))}
            </optgroup>
          );
        })}
      </select>

      {hasLocalMatch && !value && (
        <button
          type="button"
          className={styles.suggestion}
          onClick={() => onChange(best.collaborator.id)}
          title={`${best.collaborator.name} works in ${best.collaborator.location_label}`}
        >
          <span
            className={
              best.proximity === 'same-area' ? styles.matchStrong : styles.matchWeak
            }
          >
            {PROXIMITY_LABEL[best.proximity]}
          </span>
          {best.collaborator.name}
        </button>
      )}
    </div>
  );
}

function rankFor(enquiry: Enquiry, collaborators: Collaborator[]) {
  return [...collaborators]
    .map((c) => ({ collaborator: c, proximity: proximityOf(c, enquiry) }))
    .sort((a, b) => {
      const byDistance = PROXIMITY_RANK[a.proximity] - PROXIMITY_RANK[b.proximity];
      return byDistance !== 0
        ? byDistance
        : a.collaborator.name.localeCompare(b.collaborator.name);
    });
}

const formatDateTime = (value: string) => {
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? '—' : d.toLocaleString('en-IN');
};

export default function SalonApprovalQueue() {
  const [salons, setSalons] = useState<Salon[]>([]);
  const [enquiries, setEnquiries] = useState<Enquiry[]>([]);
  const [collaborators, setCollaborators] = useState<Collaborator[]>([]);

  const [error, setError] = useState('');

  // Assign collaborator states
  const [selectedCollaborator, setSelectedCollaborator] = useState<Record<string, string>>({});
  const [assigningId, setAssigningId] = useState<string | null>(null);
  const [justAssignedIds, setJustAssignedIds] = useState<string[]>([]);

  // Both lists are server-paginated now, so each keeps its own page and sort.
  const [searchEnquiries, setSearchEnquiries] = useState('');
  const [enquiriesPage, setEnquiriesPage] = useState(1);
  const [enquiriesPerPage, setEnquiriesPerPage] = useState(20);
  const [enquiriesSort, setEnquiriesSort] = useState<{ key: string; dir: SortDir } | null>(null);
  const [enquiriesMeta, setEnquiriesMeta] = useState<PageMeta>(EMPTY_META);

  const [searchSalons, setSearchSalons] = useState('');
  const [salonsPage, setSalonsPage] = useState(1);
  const [salonsPerPage, setSalonsPerPage] = useState(20);
  const [salonsSort, setSalonsSort] = useState<{ key: string; dir: SortDir } | null>(null);
  const [salonsMeta, setSalonsMeta] = useState<PageMeta>(EMPTY_META);

  const [assignError, setAssignError] = useState('');

  const debouncedEnquiries = useDebounced(searchEnquiries, 400);
  const debouncedSalons = useDebounced(searchSalons, 400);
  const [confirm, confirmDialog] = useConfirm();

  // Filtering and paging can land out of order; only the newest request renders.
  const enquiriesSeq = useRef(0);
  const salonsSeq = useRef(0);

  // Loading is derived from "have we rendered the current query yet?" so nothing
  // needs a synchronous setState inside the effect body.
  const enquiriesKey = [
    debouncedEnquiries,
    enquiriesPage,
    enquiriesPerPage,
    enquiriesSort?.key ?? '',
    enquiriesSort?.dir ?? '',
  ].join('|');
  const [enquiriesLoadedKey, setEnquiriesLoadedKey] = useState<string | null>(null);
  const loading = enquiriesLoadedKey !== enquiriesKey;

  const salonsKey = [
    debouncedSalons,
    salonsPage,
    salonsPerPage,
    salonsSort?.key ?? '',
    salonsSort?.dir ?? '',
  ].join('|');
  const [salonsLoadedKey, setSalonsLoadedKey] = useState<string | null>(null);
  const salonsLoading = salonsLoadedKey !== salonsKey;

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const res = await fetch('/api/proxy/superadmin/collaborators');
        if (!res.ok) return;
        const json = await res.json();
        if (!cancelled) setCollaborators(json.data || []);
      } catch {
        // The picker falls back to "Select collaborator"; not worth an alert.
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    const seq = ++enquiriesSeq.current;
    (async () => {
      try {
        const params = new URLSearchParams({
          page: String(enquiriesPage),
          per_page: String(enquiriesPerPage),
        });
        if (debouncedEnquiries) params.set('search', debouncedEnquiries);
        if (enquiriesSort) {
          params.set('column', enquiriesSort.key);
          params.set('direction', enquiriesSort.dir);
        }

        const res = await fetch(`/api/proxy/superadmin/enquiries?${params}`, { cache: 'no-store' });
        const json = await res.json();
        if (seq !== enquiriesSeq.current) return;
        if (!res.ok || !json.success) throw new Error(json.message || 'Could not load enquiries');

        setEnquiries(json.data || []);
        if (json.meta) setEnquiriesMeta(json.meta);
        setError('');
      } catch (e) {
        if (seq !== enquiriesSeq.current) return;
        setError(e instanceof Error ? e.message : 'Could not load enquiries');
      } finally {
        if (seq === enquiriesSeq.current) setEnquiriesLoadedKey(enquiriesKey);
      }
    })();

    return () => {
      // Marks this run stale so its result is discarded.
      enquiriesSeq.current += 1;
    };
  }, [debouncedEnquiries, enquiriesPage, enquiriesPerPage, enquiriesSort, enquiriesKey]);

  useEffect(() => {
    const seq = ++salonsSeq.current;
    (async () => {
      try {
        const params = new URLSearchParams({
          page: String(salonsPage),
          per_page: String(salonsPerPage),
        });
        if (debouncedSalons) params.set('search', debouncedSalons);
        if (salonsSort) {
          params.set('column', salonsSort.key);
          params.set('direction', salonsSort.dir);
        }

        const res = await fetch(`/api/proxy/superadmin/salons/pending?${params}`, { cache: 'no-store' });
        const json = await res.json();
        if (seq !== salonsSeq.current) return;
        if (!res.ok || !json.success) throw new Error(json.message || 'Could not load pending salons');

        setSalons(json.data || []);
        if (json.meta) setSalonsMeta(json.meta);
      } catch {
        // Left empty; the table's empty state covers it.
      } finally {
        if (seq === salonsSeq.current) setSalonsLoadedKey(salonsKey);
      }
    })();

    return () => {
      salonsSeq.current += 1;
    };
  }, [debouncedSalons, salonsPage, salonsPerPage, salonsSort, salonsKey]);

  /** asc -> desc -> unsorted, and always back to page 1. */
  const onSortEnquiries = (key: string) => {
    setEnquiriesSort((prev) => {
      if (prev?.key !== key) return { key, dir: 'asc' };
      if (prev.dir === 'asc') return { key, dir: 'desc' };
      return null;
    });
    setEnquiriesPage(1);
  };

  const onSortSalons = (key: string) => {
    setSalonsSort((prev) => {
      if (prev?.key !== key) return { key, dir: 'asc' };
      if (prev.dir === 'asc') return { key, dir: 'desc' };
      return null;
    });
    setSalonsPage(1);
  };

  const handleAssign = async (enquiryId: string) => {
    const collId = selectedCollaborator[enquiryId];
    const enquiry = enquiries.find((e) => e.id === enquiryId);
    if (!collId) {
      setAssignError('Pick a collaborator first.');
      return;
    }

    const collaborator = collaborators.find((c) => c.id === collId);
    const ok = await confirm({
      title: 'Assign this enquiry?',
      body: `${enquiry?.salon_name ?? 'This salon'} will be routed to ${collaborator?.name ?? 'the selected collaborator'}.`,
      confirmLabel: 'Assign',
      tone: 'accent',
    });
    if (!ok) return;

    setAssigningId(enquiryId);
    setAssignError('');
    try {
      const res = await fetch(`/api/proxy/superadmin/enquiries/${enquiryId}/assign`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ collaborator_id: collId }),
      });

      const json = await res.json();
      if (!res.ok || !json.success) throw new Error(json.message || 'Failed to assign collaborator');

      setEnquiries((prev) => prev.map((enq) => (enq.id === enquiryId ? { ...enq, ...json.data } : enq)));
      setJustAssignedIds((prev) => [...prev, enquiryId]);
      setTimeout(() => {
        setJustAssignedIds((prev) => prev.filter((id) => id !== enquiryId));
      }, 2000);
    } catch (e) {
      setAssignError(e instanceof Error ? e.message : 'Failed to assign collaborator');
    } finally {
      setAssigningId(null);
    }
  };

  const sortProps = (key: string, sort: { key: string; dir: SortDir } | null) => ({
    active: sort?.key === key,
    dir: sort?.key === key ? sort.dir : null,
  });

  return (
    <div className={styles.container}>
      {confirmDialog}
      <div className={styles.header}>
        <h1 className={styles.title}>Salon Approval Queue</h1>
        <p className={styles.subtitle}>Review new salon enquiries and approve pending onboarding salons.</p>
      </div>

      {assignError && (
        <div className={styles.errorBanner} role="alert">{assignError}</div>
      )}

      {/* New Enquiries Section */}
      <div style={{ marginBottom: '4rem' }}>
        <div className={styles.controlsRow}>
          <h2 className={styles.title} style={{ fontSize: '1.5rem', marginBottom: 0 }}>New Salon Enquiries</h2>
          <input
            type="text"
            className={styles.searchInput}
            placeholder="Search enquiries by name or city..."
            value={searchEnquiries}
            onChange={(e) => { setSearchEnquiries(e.target.value); setEnquiriesPage(1); }}
            aria-label="Search enquiries"
          />
        </div>
        <div className={styles.tableContainer}>
          <table className={styles.table}>
            <thead>
              <tr>
                <SortHeader label="Salon / Owner" {...sortProps('salon_name', enquiriesSort)} onClick={() => onSortEnquiries('salon_name')} />
                <SortHeader label="Area" {...sortProps('city', enquiriesSort)} onClick={() => onSortEnquiries('city')} />
                <th className={styles.th}>Phone</th>
                <SortHeader label="Status" {...sortProps('status', enquiriesSort)} onClick={() => onSortEnquiries('status')} />
                <SortHeader label="Submitted At" {...sortProps('created_at', enquiriesSort)} onClick={() => onSortEnquiries('created_at')} />
                <th className={styles.th} style={{ textAlign: 'right' }}>Action</th>
              </tr>
            </thead>
            <tbody>
              {loading && enquiries.length === 0 ? (
                <tr><td colSpan={6} className={styles.emptyState}>Loading enquiries...</td></tr>
              ) : error ? (
                <tr><td colSpan={6} className={styles.emptyState} style={{ color: 'red' }}>{error}</td></tr>
              ) : enquiries.length === 0 ? (
                <tr><td colSpan={6} className={styles.emptyState}>No enquiries found.</td></tr>
              ) : (
                enquiries.map((enq) => (
                  <tr key={enq.id} className={`${styles.tr} ${justAssignedIds.includes(enq.id) ? styles.rowSuccess : ''}`}>
                    <td className={styles.td}>
                      <div className={styles.salonName}>{enq.salon_name}</div>
                      <div style={{ fontSize: '0.85rem', color: 'var(--text-body)' }}>{enq.owner_name}</div>
                    </td>
                    <td className={styles.td}>
                      {enq.sub_area_name ? (
                        <>
                          <div className={styles.areaName}>{enq.sub_area_name}</div>
                          <div className={styles.areaCity}>{enq.city_name}</div>
                        </>
                      ) : (
                        <div className={styles.areaCity}>{enq.city_name || enq.city || 'N/A'}</div>
                      )}
                    </td>
                    <td className={styles.td}>{enq.phone}</td>
                    <td className={styles.td}>
                      <span className={styles.statusPill} data-status={enq.status}>
                        {enq.status.toUpperCase()}
                      </span>
                    </td>
                    <td className={styles.td}>{formatDateTime(enq.created_at)}</td>
                    <td className={styles.td} style={{ textAlign: 'right' }}>
                      {enq.status === 'new' ? (
                        <div className={styles.actionRow}>
                          <CollaboratorPicker
                            enquiry={enq}
                            collaborators={collaborators}
                            value={selectedCollaborator[enq.id] || ''}
                            onChange={(id) => setSelectedCollaborator((prev) => ({ ...prev, [enq.id]: id }))}
                          />
                          <button
                            className={styles.assignButton}
                            onClick={() => handleAssign(enq.id)}
                            disabled={assigningId === enq.id}
                          >
                            {assigningId === enq.id ? 'Assigning...' : 'Assign'}
                          </button>
                        </div>
                      ) : (
                        <div className={styles.assignedFlag}>
                          ✓ Assigned to {enq.assigned_collaborator?.name || 'Unknown'}
                        </div>
                      )}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>

          <Pagination
            page={enquiriesMeta.current_page}
            lastPage={enquiriesMeta.last_page}
            total={enquiriesMeta.total}
            noun="enquiries"
            onChange={setEnquiriesPage}
            perPage={enquiriesPerPage}
            onPerPageChange={(n) => { setEnquiriesPerPage(n); setEnquiriesPage(1); }}
            disabled={loading}
          />
        </div>
      </div>

      {/* Existing Salon Approval Queue */}
      <div>
        <div className={styles.controlsRow}>
          <h2 className={styles.title} style={{ fontSize: '1.5rem', marginBottom: 0 }}>Pending Onboarding (Salon Approval Queue)</h2>
          <input
            type="text"
            className={styles.searchInput}
            placeholder="Search salons by name or city..."
            value={searchSalons}
            onChange={(e) => { setSearchSalons(e.target.value); setSalonsPage(1); }}
            aria-label="Search pending salons"
          />
        </div>
        <div className={styles.tableContainer}>
          <table className={styles.table}>
            <thead>
              <tr>
                <SortHeader label="Salon Name" {...sortProps('name', salonsSort)} onClick={() => onSortSalons('name')} />
                <SortHeader label="City" {...sortProps('city', salonsSort)} onClick={() => onSortSalons('city')} />
                <th className={styles.th}>Owner/Admin</th>
                <SortHeader label="Submitted At" {...sortProps('created_at', salonsSort)} onClick={() => onSortSalons('created_at')} />
                <th className={styles.th} style={{ textAlign: 'right' }}>Action</th>
              </tr>
            </thead>
            <tbody>
              {salonsLoading && salons.length === 0 ? (
                <tr><td colSpan={5} className={styles.emptyState}>Loading salons...</td></tr>
              ) : salons.length === 0 ? (
                <tr><td colSpan={5} className={styles.emptyState}>No pending salons.</td></tr>
              ) : (
                salons.map((salon) => (
                  <tr key={salon.id} className={styles.tr}>
                    <td className={`${styles.td} ${styles.salonName}`}>{salon.name}</td>
                    <td className={styles.td}>{salon.city?.name || 'N/A'}</td>
                    <td className={styles.td}>{salon.admin?.name || 'N/A'}</td>
                    <td className={styles.td}>{formatDateTime(salon.created_at)}</td>
                    <td className={styles.td} style={{ textAlign: 'right' }}>
                      <Link href={`/superadmin/salon-approval/${salon.id}`} className={styles.actionButton}>
                        Review
                      </Link>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>

          <Pagination
            page={salonsMeta.current_page}
            lastPage={salonsMeta.last_page}
            total={salonsMeta.total}
            noun="pending salons"
            onChange={setSalonsPage}
            perPage={salonsPerPage}
            onPerPageChange={(n) => { setSalonsPerPage(n); setSalonsPage(1); }}
            disabled={salonsLoading}
          />
        </div>
      </div>
    </div>
  );
}
