'use client';

import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
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

export default function SalonApprovalQueue() {
  const [salons, setSalons] = useState<Salon[]>([]);
  const [enquiries, setEnquiries] = useState<Enquiry[]>([]);
  const [collaborators, setCollaborators] = useState<Collaborator[]>([]);
  
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  // Assign collaborator states
  const [selectedCollaborator, setSelectedCollaborator] = useState<Record<string, string>>({});
  const [assigningId, setAssigningId] = useState<string | null>(null);
  const [justAssignedIds, setJustAssignedIds] = useState<string[]>([]);

  // Pagination and search for enquiries
  const [searchEnquiries, setSearchEnquiries] = useState('');
  const [enquiriesPage, setEnquiriesPage] = useState(1);
  const ENQUIRIES_PER_PAGE = 10;

  // Pagination and search for salons
  const [searchSalons, setSearchSalons] = useState('');
  const [salonsPage, setSalonsPage] = useState(1);
  const SALONS_PER_PAGE = 10;

  useEffect(() => {
    async function fetchData() {
      try {
        const [salonsRes, enquiriesRes, collabRes] = await Promise.all([
          fetch(`${process.env.NEXT_PUBLIC_BACKEND_URL}/api/superadmin/salons/pending`),
          fetch(`${process.env.NEXT_PUBLIC_BACKEND_URL}/api/superadmin/enquiries`),
          fetch(`${process.env.NEXT_PUBLIC_BACKEND_URL}/api/superadmin/collaborators`)
        ]);

        if (!salonsRes.ok || !enquiriesRes.ok || !collabRes.ok) {
          throw new Error('Failed to fetch data');
        }

        const salonsJson = await salonsRes.json();
        const enquiriesJson = await enquiriesRes.json();
        const collabJson = await collabRes.json();

        setSalons(salonsJson.data || []);
        setEnquiries(enquiriesJson.data || []);
        setCollaborators(collabJson.data || []);
      } catch (err: any) {
        setError(err.message);
      } finally {
        setLoading(false);
      }
    }

    fetchData();
  }, []);

  const handleAssign = async (enquiryId: string) => {
    const collId = selectedCollaborator[enquiryId];
    if (!collId) {
      alert('Please select a collaborator first.');
      return;
    }

    if (!window.confirm('Are you sure you want to assign this collaborator?')) {
      return;
    }

    setAssigningId(enquiryId);
    try {
      const res = await fetch(`${process.env.NEXT_PUBLIC_BACKEND_URL}/api/superadmin/enquiries/${enquiryId}/assign`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ collaborator_id: collId })
      });

      const json = await res.json();
      if (res.ok) {
        // Update local state
        setEnquiries(prev => prev.map(enq => enq.id === enquiryId ? json.data : enq));
        
        // Trigger animation
        setJustAssignedIds(prev => [...prev, enquiryId]);
        setTimeout(() => {
          setJustAssignedIds(prev => prev.filter(id => id !== enquiryId));
        }, 2000);
      } else {
        throw new Error(json.message || 'Failed to assign collaborator');
      }
    } catch (err: any) {
      alert(err.message);
    } finally {
      setAssigningId(null);
    }
  };

  // Filter & paginate enquiries
  const filteredEnquiries = useMemo(() => {
    if (!searchEnquiries) return enquiries;
    const lower = searchEnquiries.toLowerCase();
    return enquiries.filter(e => 
      e.salon_name?.toLowerCase().includes(lower) || 
      e.owner_name?.toLowerCase().includes(lower) ||
      e.city?.toLowerCase().includes(lower)
    );
  }, [enquiries, searchEnquiries]);
  
  const paginatedEnquiries = useMemo(() => {
    const start = (enquiriesPage - 1) * ENQUIRIES_PER_PAGE;
    return filteredEnquiries.slice(start, start + ENQUIRIES_PER_PAGE);
  }, [filteredEnquiries, enquiriesPage]);
  const enquiriesTotalPages = Math.ceil(filteredEnquiries.length / ENQUIRIES_PER_PAGE);

  // Filter & paginate salons
  const filteredSalons = useMemo(() => {
    if (!searchSalons) return salons;
    const lower = searchSalons.toLowerCase();
    return salons.filter(s => 
      s.name?.toLowerCase().includes(lower) || 
      s.admin?.name?.toLowerCase().includes(lower) ||
      s.city?.name?.toLowerCase().includes(lower)
    );
  }, [salons, searchSalons]);

  const paginatedSalons = useMemo(() => {
    const start = (salonsPage - 1) * SALONS_PER_PAGE;
    return filteredSalons.slice(start, start + SALONS_PER_PAGE);
  }, [filteredSalons, salonsPage]);
  const salonsTotalPages = Math.ceil(filteredSalons.length / SALONS_PER_PAGE);


  return (
    <div className={styles.container}>
      <div className={styles.header}>
        <h1 className={styles.title}>Salon Approval Queue</h1>
        <p className={styles.subtitle}>Review new salon enquiries and approve pending onboarding salons.</p>
      </div>

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
          />
        </div>
        <div className={styles.tableContainer}>
          <table className={styles.table}>
            <thead>
              <tr>
                <th className={styles.th}>Salon / Owner</th>
                <th className={styles.th}>Area</th>
                <th className={styles.th}>Phone</th>
                <th className={styles.th}>Status</th>
                <th className={styles.th}>Submitted At</th>
                <th className={styles.th} style={{ textAlign: 'right' }}>Action</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                <tr><td colSpan={6} className={styles.emptyState}>Loading enquiries...</td></tr>
              ) : error ? (
                <tr><td colSpan={6} className={styles.emptyState} style={{ color: 'red' }}>{error}</td></tr>
              ) : filteredEnquiries.length === 0 ? (
                <tr><td colSpan={6} className={styles.emptyState}>No enquiries found.</td></tr>
              ) : (
                paginatedEnquiries.map((enq) => (
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
                      <span style={{ 
                        padding: '4px 8px', 
                        borderRadius: '12px', 
                        fontSize: '0.8rem',
                        backgroundColor: enq.status === 'new' ? '#fff3cd' : '#d1e7dd',
                        color: enq.status === 'new' ? '#856404' : '#0f5132'
                      }}>
                        {enq.status.toUpperCase()}
                      </span>
                    </td>
                    <td className={styles.td}>{new Date(enq.created_at).toLocaleString()}</td>
                    <td className={styles.td} style={{ textAlign: 'right' }}>
                      {enq.status === 'new' ? (
                        <div style={{ display: 'flex', gap: '8px', justifyContent: 'flex-end', alignItems: 'center' }}>
                          <CollaboratorPicker
                            enquiry={enq}
                            collaborators={collaborators}
                            value={selectedCollaborator[enq.id] || ''}
                            onChange={(id) => setSelectedCollaborator(prev => ({ ...prev, [enq.id]: id }))}
                          />
                          <button 
                            onClick={() => handleAssign(enq.id)}
                            disabled={assigningId === enq.id}
                            style={{ 
                              padding: '6px 12px', 
                              backgroundColor: 'var(--accent-color)', 
                              color: 'white', 
                              border: 'none', 
                              borderRadius: '4px', 
                              cursor: assigningId === enq.id ? 'not-allowed' : 'pointer',
                              opacity: assigningId === enq.id ? 0.7 : 1
                            }}
                          >
                            {assigningId === enq.id ? 'Assigning...' : 'Assign'}
                          </button>
                        </div>
                      ) : (
                        <div style={{ fontSize: '0.9rem', color: 'var(--color-success)', fontWeight: 500 }}>
                          ✓ Assigned to {enq.assigned_collaborator?.name || 'Unknown'}
                        </div>
                      )}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
          
          {enquiriesTotalPages > 1 && (
            <div className={styles.pagination}>
              <span>Showing page {enquiriesPage} of {enquiriesTotalPages}</span>
              <div className={styles.pageControls}>
                <button 
                  className={styles.pageButton} 
                  disabled={enquiriesPage === 1}
                  onClick={() => setEnquiriesPage(p => Math.max(1, p - 1))}
                >
                  Previous
                </button>
                <button 
                  className={styles.pageButton} 
                  disabled={enquiriesPage === enquiriesTotalPages}
                  onClick={() => setEnquiriesPage(p => Math.min(enquiriesTotalPages, p + 1))}
                >
                  Next
                </button>
              </div>
            </div>
          )}
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
          />
        </div>
        <div className={styles.tableContainer}>
          <table className={styles.table}>
            <thead>
              <tr>
                <th className={styles.th}>Salon Name</th>
                <th className={styles.th}>City</th>
                <th className={styles.th}>Owner/Admin</th>
                <th className={styles.th}>Submitted At</th>
                <th className={styles.th} style={{ textAlign: 'right' }}>Action</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                <tr>
                  <td colSpan={5} className={styles.emptyState}>Loading salons...</td>
                </tr>
              ) : error ? (
                <tr>
                  <td colSpan={5} className={styles.emptyState} style={{ color: 'red' }}>{error}</td>
                </tr>
              ) : filteredSalons.length === 0 ? (
                <tr>
                  <td colSpan={5} className={styles.emptyState}>No salons found.</td>
                </tr>
              ) : (
                paginatedSalons.map((salon) => (
                  <tr key={salon.id} className={styles.tr}>
                    <td className={`${styles.td} ${styles.salonName}`}>{salon.name}</td>
                    <td className={styles.td}>{salon.city?.name || 'N/A'}</td>
                    <td className={styles.td}>{salon.admin?.name || 'N/A'}</td>
                    <td className={styles.td}>{new Date(salon.created_at).toLocaleString()}</td>
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

          {salonsTotalPages > 1 && (
            <div className={styles.pagination}>
              <span>Showing page {salonsPage} of {salonsTotalPages}</span>
              <div className={styles.pageControls}>
                <button 
                  className={styles.pageButton} 
                  disabled={salonsPage === 1}
                  onClick={() => setSalonsPage(p => Math.max(1, p - 1))}
                >
                  Previous
                </button>
                <button 
                  className={styles.pageButton} 
                  disabled={salonsPage === salonsTotalPages}
                  onClick={() => setSalonsPage(p => Math.min(salonsTotalPages, p + 1))}
                >
                  Next
                </button>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
