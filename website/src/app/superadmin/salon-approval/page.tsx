'use client';

import { useEffect, useState } from 'react';
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
}

interface Collaborator {
  id: string;
  name: string;
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
          fetch('http://localhost:8000/api/superadmin/salons/pending'),
          fetch('http://localhost:8000/api/superadmin/enquiries'),
          fetch('http://localhost:8000/api/superadmin/collaborators')
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
      const res = await fetch(`http://localhost:8000/api/superadmin/enquiries/${enquiryId}/assign`, {
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
                <th className={styles.th}>City</th>
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
                    <td className={styles.td}>{enq.city || 'N/A'}</td>
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
                          <select 
                            value={selectedCollaborator[enq.id] || ''}
                            onChange={(e) => setSelectedCollaborator(prev => ({ ...prev, [enq.id]: e.target.value }))}
                            style={{ padding: '6px', borderRadius: '4px', border: '1px solid #ddd' }}
                          >
                            <option value="">Select Collaborator</option>
                            {collaborators.map(c => (
                              <option key={c.id} value={c.id}>{c.name}</option>
                            ))}
                          </select>
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
