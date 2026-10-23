'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
import Link from 'next/link';
import Icon from '@/components/admin/Icon';
import { Pagination, SortHeader, useConfirm, useDebounced, type SortDir } from '@/components/admin/ui';
import styles from './page.module.css';

interface City {
  id: string;
  name: string;
  state?: string;
}

interface SubArea {
  id: string;
  name: string;
}

interface Salon {
  id: string;
  name: string;
  status?: string;
  created_at: string;
  resubmitted_at?: string;
  city?: { id?: string; name: string };
  sub_area?: { id?: string; name: string };
  subArea?: { id?: string; name: string };
  admin?: { id?: string; name: string; phone?: string; email?: string };
  assigned_collaborator?: { id: string; name: string } | null;
  assignedCollaborator?: { id: string; name: string } | null;
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
  photo_url?: string | null;
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
  const [cities, setCities] = useState<City[]>([]);

  const [error, setError] = useState('');

  // Assign collaborator states
  const [selectedCollaborator, setSelectedCollaborator] = useState<Record<string, string>>({});
  const [assigningId, setAssigningId] = useState<string | null>(null);
  const [justAssignedIds, setJustAssignedIds] = useState<string[]>([]);

  // Enquiries state & filters
  const [searchEnquiries, setSearchEnquiries] = useState('');
  const [enquiriesCityId, setEnquiriesCityId] = useState('');
  const [enquiriesSubAreaId, setEnquiriesSubAreaId] = useState('');
  const [enquiriesSubAreas, setEnquiriesSubAreas] = useState<SubArea[]>([]);
  const [enquiriesStatus, setEnquiriesStatus] = useState('');
  const [enquiriesCollaboratorId, setEnquiriesCollaboratorId] = useState('');
  const [enquiriesPage, setEnquiriesPage] = useState(1);
  const [enquiriesPerPage, setEnquiriesPerPage] = useState(20);
  const [enquiriesSort, setEnquiriesSort] = useState<{ key: string; dir: SortDir } | null>(null);
  const [enquiriesMeta, setEnquiriesMeta] = useState<PageMeta>(EMPTY_META);

  // Salons state & filters
  const [searchSalons, setSearchSalons] = useState('');
  const [salonsCityId, setSalonsCityId] = useState('');
  const [salonsSubAreaId, setSalonsSubAreaId] = useState('');
  const [salonsSubAreas, setSalonsSubAreas] = useState<SubArea[]>([]);
  const [salonsStatus, setSalonsStatus] = useState('');
  const [salonsCollaboratorId, setSalonsCollaboratorId] = useState('');
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

  // Loading derived from query keys
  const enquiriesKey = [
    debouncedEnquiries,
    enquiriesCityId,
    enquiriesSubAreaId,
    enquiriesStatus,
    enquiriesCollaboratorId,
    enquiriesPage,
    enquiriesPerPage,
    enquiriesSort?.key ?? '',
    enquiriesSort?.dir ?? '',
  ].join('|');
  const [enquiriesLoadedKey, setEnquiriesLoadedKey] = useState<string | null>(null);
  const loading = enquiriesLoadedKey !== enquiriesKey;

  const salonsKey = [
    debouncedSalons,
    salonsCityId,
    salonsSubAreaId,
    salonsStatus,
    salonsCollaboratorId,
    salonsPage,
    salonsPerPage,
    salonsSort?.key ?? '',
    salonsSort?.dir ?? '',
  ].join('|');
  const [salonsLoadedKey, setSalonsLoadedKey] = useState<string | null>(null);
  const salonsLoading = salonsLoadedKey !== salonsKey;

  // Load collaborators on mount
  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const res = await fetch('/api/proxy/superadmin/collaborators');
        if (!res.ok) return;
        const json = await res.json();
        if (!cancelled) setCollaborators(json.data || []);
      } catch {
        // Picker falls back to "Select collaborator"
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  // Load cities on mount
  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const res = await fetch('/api/cities');
        if (!res.ok) return;
        const data = await res.json();
        if (!cancelled && Array.isArray(data)) {
          setCities(data);
        }
      } catch {
        // City filter dropdown fallback
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  // Load sub-areas for enquiries when enquiriesCityId changes
  useEffect(() => {
    if (!enquiriesCityId) {
      setEnquiriesSubAreas([]);
      setEnquiriesSubAreaId('');
      return;
    }
    let cancelled = false;
    (async () => {
      try {
        const res = await fetch(`/api/cities/${enquiriesCityId}/sub-areas`);
        if (!res.ok) return;
        const data = await res.json();
        if (!cancelled && Array.isArray(data?.sub_areas)) {
          setEnquiriesSubAreas(data.sub_areas);
        }
      } catch {
        setEnquiriesSubAreas([]);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [enquiriesCityId]);

  // Load sub-areas for salons when salonsCityId changes
  useEffect(() => {
    if (!salonsCityId) {
      setSalonsSubAreas([]);
      setSalonsSubAreaId('');
      return;
    }
    let cancelled = false;
    (async () => {
      try {
        const res = await fetch(`/api/cities/${salonsCityId}/sub-areas`);
        if (!res.ok) return;
        const data = await res.json();
        if (!cancelled && Array.isArray(data?.sub_areas)) {
          setSalonsSubAreas(data.sub_areas);
        }
      } catch {
        setSalonsSubAreas([]);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [salonsCityId]);

  // Fetch enquiries with all active filters
  useEffect(() => {
    const seq = ++enquiriesSeq.current;
    (async () => {
      try {
        const params = new URLSearchParams({
          page: String(enquiriesPage),
          per_page: String(enquiriesPerPage),
        });
        if (debouncedEnquiries) params.set('search', debouncedEnquiries);
        if (enquiriesCityId) params.set('city_id', enquiriesCityId);
        if (enquiriesSubAreaId) params.set('sub_area_id', enquiriesSubAreaId);
        if (enquiriesStatus) params.set('status', enquiriesStatus);
        if (enquiriesCollaboratorId) params.set('collaborator_id', enquiriesCollaboratorId);
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
      enquiriesSeq.current += 1;
    };
  }, [
    debouncedEnquiries,
    enquiriesCityId,
    enquiriesSubAreaId,
    enquiriesStatus,
    enquiriesCollaboratorId,
    enquiriesPage,
    enquiriesPerPage,
    enquiriesSort,
    enquiriesKey,
  ]);

  // Fetch pending salons with all active filters
  useEffect(() => {
    const seq = ++salonsSeq.current;
    (async () => {
      try {
        const params = new URLSearchParams({
          page: String(salonsPage),
          per_page: String(salonsPerPage),
        });
        if (debouncedSalons) params.set('search', debouncedSalons);
        if (salonsCityId) params.set('city_id', salonsCityId);
        if (salonsSubAreaId) params.set('sub_area_id', salonsSubAreaId);
        if (salonsStatus) params.set('status', salonsStatus);
        if (salonsCollaboratorId) params.set('collaborator_id', salonsCollaboratorId);
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
  }, [
    debouncedSalons,
    salonsCityId,
    salonsSubAreaId,
    salonsStatus,
    salonsCollaboratorId,
    salonsPage,
    salonsPerPage,
    salonsSort,
    salonsKey,
  ]);

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

  const hasEnquiriesFilters = Boolean(
    searchEnquiries || enquiriesCityId || enquiriesSubAreaId || enquiriesStatus || enquiriesCollaboratorId
  );
  const clearEnquiriesFilters = () => {
    setSearchEnquiries('');
    setEnquiriesCityId('');
    setEnquiriesSubAreaId('');
    setEnquiriesStatus('');
    setEnquiriesCollaboratorId('');
    setEnquiriesPage(1);
  };

  const hasSalonsFilters = Boolean(
    searchSalons || salonsCityId || salonsSubAreaId || salonsStatus || salonsCollaboratorId
  );
  const clearSalonsFilters = () => {
    setSearchSalons('');
    setSalonsCityId('');
    setSalonsSubAreaId('');
    setSalonsStatus('');
    setSalonsCollaboratorId('');
    setSalonsPage(1);
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
        <div className={styles.sectionHeader}>
          <h2 className={styles.sectionTitle}>
            New Salon Enquiries
            {enquiriesMeta.total > 0 && (
              <span className={styles.sectionCount}>{enquiriesMeta.total}</span>
            )}
          </h2>
        </div>

        {/* Filter Bar */}
        <div className={styles.filterBar}>
          <div className={styles.searchWrap}>
            <Icon name="search" size={15} className={styles.searchIcon} />
            <input
              type="text"
              className={styles.searchInput}
              placeholder="Search enquiries by salon, owner, phone..."
              value={searchEnquiries}
              onChange={(e) => { setSearchEnquiries(e.target.value); setEnquiriesPage(1); }}
              aria-label="Search enquiries"
            />
            {searchEnquiries && (
              <button
                type="button"
                className={styles.clearSearchBtn}
                onClick={() => { setSearchEnquiries(''); setEnquiriesPage(1); }}
                title="Clear search"
                aria-label="Clear search"
              >
                &times;
              </button>
            )}
          </div>

          <select
            className={`${styles.filterSelect} ${enquiriesCityId ? styles.filterActive : ''}`}
            value={enquiriesCityId}
            onChange={(e) => {
              setEnquiriesCityId(e.target.value);
              setEnquiriesSubAreaId('');
              setEnquiriesPage(1);
            }}
            aria-label="Filter enquiries by city"
          >
            <option value="">All Cities</option>
            {cities.map((c) => (
              <option key={c.id} value={c.id}>{c.name}</option>
            ))}
          </select>

          <select
            className={`${styles.filterSelect} ${enquiriesSubAreaId ? styles.filterActive : ''}`}
            value={enquiriesSubAreaId}
            disabled={!enquiriesCityId || enquiriesSubAreas.length === 0}
            onChange={(e) => {
              setEnquiriesSubAreaId(e.target.value);
              setEnquiriesPage(1);
            }}
            aria-label="Filter enquiries by sub-area"
          >
            <option value="">
              {!enquiriesCityId
                ? 'Select City First'
                : enquiriesSubAreas.length === 0
                ? 'No Sub-Areas'
                : 'All Sub-Areas'}
            </option>
            {enquiriesSubAreas.map((sa) => (
              <option key={sa.id} value={sa.id}>{sa.name}</option>
            ))}
          </select>

          <select
            className={`${styles.filterSelect} ${enquiriesStatus ? styles.filterActive : ''}`}
            value={enquiriesStatus}
            onChange={(e) => {
              setEnquiriesStatus(e.target.value);
              setEnquiriesPage(1);
            }}
            aria-label="Filter enquiries by status"
          >
            <option value="">All Statuses</option>
            <option value="new">New</option>
            <option value="assigned">Assigned</option>
            <option value="onboarded">Onboarded</option>
            <option value="rejected">Rejected</option>
          </select>

          <select
            className={`${styles.filterSelect} ${enquiriesCollaboratorId ? styles.filterActive : ''}`}
            value={enquiriesCollaboratorId}
            onChange={(e) => {
              setEnquiriesCollaboratorId(e.target.value);
              setEnquiriesPage(1);
            }}
            aria-label="Filter enquiries by collaborator"
          >
            <option value="">All Collaborators</option>
            <option value="unassigned">Only Unassigned</option>
            {collaborators.map((c) => (
              <option key={c.id} value={c.id}>{c.name}</option>
            ))}
          </select>

          {hasEnquiriesFilters && (
            <button
              type="button"
              className={styles.clearFiltersBtn}
              onClick={clearEnquiriesFilters}
              title="Reset all enquiry filters"
            >
              Reset Filters
            </button>
          )}
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
                <tr><td colSpan={6} className={styles.emptyState} style={{ color: 'var(--color-danger)' }}>{error}</td></tr>
              ) : enquiries.length === 0 ? (
                <tr>
                  <td colSpan={6} className={styles.emptyState}>
                    {hasEnquiriesFilters ? 'No enquiries match your active filters.' : 'No enquiries found.'}
                  </td>
                </tr>
              ) : (
                enquiries.map((enq) => (
                  <tr key={enq.id} className={`${styles.tr} ${justAssignedIds.includes(enq.id) ? styles.rowSuccess : ''}`}>
                    <td className={styles.td}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem' }}>
                        {enq.photo_url ? (
                          <img
                            src={enq.photo_url}
                            alt=""
                            style={{ width: '38px', height: '38px', borderRadius: '6px', objectFit: 'cover', border: '1px solid var(--border-color)' }}
                          />
                        ) : null}
                        <div>
                          <div className={styles.salonName}>{enq.salon_name}</div>
                          <div style={{ fontSize: '0.85rem', color: 'var(--text-body)' }}>{enq.owner_name}</div>
                        </div>
                      </div>
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
        <div className={styles.sectionHeader}>
          <h2 className={styles.sectionTitle}>
            Pending Onboarding (Salon Approval Queue)
            {salonsMeta.total > 0 && (
              <span className={styles.sectionCount}>{salonsMeta.total}</span>
            )}
          </h2>
        </div>

        {/* Filter Bar */}
        <div className={styles.filterBar}>
          <div className={styles.searchWrap}>
            <Icon name="search" size={15} className={styles.searchIcon} />
            <input
              type="text"
              className={styles.searchInput}
              placeholder="Search salons by name, city, owner, sub-area..."
              value={searchSalons}
              onChange={(e) => { setSearchSalons(e.target.value); setSalonsPage(1); }}
              aria-label="Search pending salons"
            />
            {searchSalons && (
              <button
                type="button"
                className={styles.clearSearchBtn}
                onClick={() => { setSearchSalons(''); setSalonsPage(1); }}
                title="Clear search"
                aria-label="Clear search"
              >
                &times;
              </button>
            )}
          </div>

          <select
            className={`${styles.filterSelect} ${salonsCityId ? styles.filterActive : ''}`}
            value={salonsCityId}
            onChange={(e) => {
              setSalonsCityId(e.target.value);
              setSalonsSubAreaId('');
              setSalonsPage(1);
            }}
            aria-label="Filter salons by city"
          >
            <option value="">All Cities</option>
            {cities.map((c) => (
              <option key={c.id} value={c.id}>{c.name}</option>
            ))}
          </select>

          <select
            className={`${styles.filterSelect} ${salonsSubAreaId ? styles.filterActive : ''}`}
            value={salonsSubAreaId}
            disabled={!salonsCityId || salonsSubAreas.length === 0}
            onChange={(e) => {
              setSalonsSubAreaId(e.target.value);
              setSalonsPage(1);
            }}
            aria-label="Filter salons by sub-area"
          >
            <option value="">
              {!salonsCityId
                ? 'Select City First'
                : salonsSubAreas.length === 0
                ? 'No Sub-Areas'
                : 'All Sub-Areas'}
            </option>
            {salonsSubAreas.map((sa) => (
              <option key={sa.id} value={sa.id}>{sa.name}</option>
            ))}
          </select>

          <select
            className={`${styles.filterSelect} ${salonsStatus ? styles.filterActive : ''}`}
            value={salonsStatus}
            onChange={(e) => {
              setSalonsStatus(e.target.value);
              setSalonsPage(1);
            }}
            aria-label="Filter salons by status"
          >
            <option value="">All Pending Statuses</option>
            <option value="pending_approval">Pending Approval</option>
            <option value="needs_correction">Needs Correction</option>
          </select>

          <select
            className={`${styles.filterSelect} ${salonsCollaboratorId ? styles.filterActive : ''}`}
            value={salonsCollaboratorId}
            onChange={(e) => {
              setSalonsCollaboratorId(e.target.value);
              setSalonsPage(1);
            }}
            aria-label="Filter salons by collaborator"
          >
            <option value="">All Collaborators</option>
            <option value="unassigned">Only Unassigned</option>
            {collaborators.map((c) => (
              <option key={c.id} value={c.id}>{c.name}</option>
            ))}
          </select>

          {hasSalonsFilters && (
            <button
              type="button"
              className={styles.clearFiltersBtn}
              onClick={clearSalonsFilters}
              title="Reset all salon filters"
            >
              Reset Filters
            </button>
          )}
        </div>

        <div className={styles.tableContainer}>
          <table className={styles.table}>
            <thead>
              <tr>
                <SortHeader label="Salon Name" {...sortProps('name', salonsSort)} onClick={() => onSortSalons('name')} />
                <SortHeader label="Area" {...sortProps('city', salonsSort)} onClick={() => onSortSalons('city')} />
                <th className={styles.th}>Owner / Admin</th>
                <th className={styles.th}>Assigned Collaborator</th>
                <SortHeader label="Status" {...sortProps('status', salonsSort)} onClick={() => onSortSalons('status')} />
                <SortHeader label="Submitted At" {...sortProps('created_at', salonsSort)} onClick={() => onSortSalons('created_at')} />
                <th className={styles.th} style={{ textAlign: 'right' }}>Action</th>
              </tr>
            </thead>
            <tbody>
              {salonsLoading && salons.length === 0 ? (
                <tr><td colSpan={7} className={styles.emptyState}>Loading salons...</td></tr>
              ) : salons.length === 0 ? (
                <tr>
                  <td colSpan={7} className={styles.emptyState}>
                    {hasSalonsFilters ? 'No pending salons match your active filters.' : 'No pending salons.'}
                  </td>
                </tr>
              ) : (
                salons.map((salon) => (
                  <tr key={salon.id} className={styles.tr}>
                    <td className={`${styles.td} ${styles.salonName}`}>
                      <div style={{ fontWeight: 600, color: 'var(--text-heading)' }}>{salon.name}</div>
                    </td>
                    <td className={styles.td}>
                      {(salon.sub_area?.name || salon.subArea?.name) ? (
                        <>
                          <div className={styles.areaName}>{salon.sub_area?.name || salon.subArea?.name}</div>
                          <div className={styles.areaCity}>{salon.city?.name || 'N/A'}</div>
                        </>
                      ) : (
                        <div className={styles.areaCity}>{salon.city?.name || 'N/A'}</div>
                      )}
                    </td>
                    <td className={styles.td}>
                      <div style={{ fontWeight: 500, color: 'var(--text-heading)' }}>{salon.admin?.name || '—'}</div>
                      {salon.admin?.phone && (
                        <div style={{ fontSize: '0.82rem', color: 'var(--text-muted)' }}>{salon.admin.phone}</div>
                      )}
                    </td>
                    <td className={styles.td}>
                      {(salon.assigned_collaborator?.name || salon.assignedCollaborator?.name) ? (
                        <span className={styles.assignedBadge}>
                          👤 {salon.assigned_collaborator?.name || salon.assignedCollaborator?.name}
                        </span>
                      ) : (
                        <span className={styles.unassignedBadge}>
                          Unassigned
                        </span>
                      )}
                    </td>
                    <td className={styles.td}>
                      <span className={styles.statusPill} data-status={salon.status}>
                        {salon.status === 'needs_correction'
                          ? 'NEEDS CORRECTION'
                          : (salon.status || 'PENDING').toUpperCase().replace(/_/g, ' ')}
                      </span>
                    </td>
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
