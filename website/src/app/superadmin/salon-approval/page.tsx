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
 *
 * Whoever already works in the same locality is almost always the right answer,
 * so they are lifted to the top of the list and labelled rather than left for
 * SuperAdmin to spot by reading twenty names.
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

/**
 * Picks who goes to this enquiry, with the local people first.
 *
 * Grouped rather than merely sorted: a flat list still asks SuperAdmin to work
 * out which names are nearby. Optgroup headings say it outright, and the
 * best match is preselected so the common case is one click.
 */
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

/** Nearest first, then alphabetically inside each band. */
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

  // Dropdown states for each enquiry row
  const [selectedCollaborator, setSelectedCollaborator] = useState<Record<string, string>>({});
  const [assigningId, setAssigningId] = useState<string | null>(null);

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
        alert('Collaborator assigned successfully!');
      } else {
        throw new Error(json.message || 'Failed to assign collaborator');
      }
    } catch (err: any) {
      alert(err.message);
    } finally {
      setAssigningId(null);
    }
  };

  return (
    <div className={styles.container}>
      <div className={styles.header}>
        <h1 className={styles.title}>SuperAdmin Dashboard</h1>
        <p className={styles.subtitle}>Review new salon enquiries and approve pending onboarding salons.</p>
      </div>

      {/* New Enquiries Section */}
      <div style={{ marginBottom: '4rem' }}>
        <h2 className={styles.title} style={{ fontSize: '1.5rem', marginBottom: '1rem' }}>New Salon Enquiries</h2>
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
              ) : enquiries.length === 0 ? (
                <tr><td colSpan={6} className={styles.emptyState}>No enquiries received.</td></tr>
              ) : (
                enquiries.map((enq) => (
                  <tr key={enq.id} className={styles.tr}>
                    <td className={styles.td}>
                      <div className={styles.salonName}>{enq.salon_name}</div>
                      <div style={{ fontSize: '0.85rem', color: '#666' }}>{enq.owner_name}</div>
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
                              backgroundColor: '#0070f3', 
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
                        <div style={{ fontSize: '0.9rem', color: '#555' }}>
                          Assigned to: <strong>{enq.assigned_collaborator?.name || 'Unknown'}</strong>
                        </div>
                      )}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* Existing Salon Approval Queue */}
      <div>
        <h2 className={styles.title} style={{ fontSize: '1.5rem', marginBottom: '1rem' }}>Pending Onboarding (Salon Approval Queue)</h2>
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
              ) : salons.length === 0 ? (
                <tr>
                  <td colSpan={5} className={styles.emptyState}>No salons pending approval.</td>
                </tr>
              ) : (
                salons.map((salon) => (
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
        </div>
      </div>
    </div>
  );
}
