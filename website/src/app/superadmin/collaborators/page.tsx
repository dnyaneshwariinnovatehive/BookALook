'use client';

import { useEffect, useState } from 'react';
import styles from '../salon-approval/page.module.css';

interface CollaboratorStat {
  id: string;
  name: string;
  email: string;
  phone: string;
  created_at: string;
  onboarded_salons_count: number;
}

export default function CollaboratorManagement() {
  const [collaborators, setCollaborators] = useState<CollaboratorStat[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const [formData, setFormData] = useState({
    name: '',
    email: '',
    phone: '',
    city_id: '',
    sub_area_id: ''
  });

  // Where this collaborator works. Without it they can never be matched to an
  // enquiry, which is the whole reason for assigning one.
  const [cities, setCities] = useState<{ id: string; name: string; state: string }[]>([]);
  const [subAreas, setSubAreas] = useState<{ id: string; name: string }[]>([]);
  const [loadingAreas, setLoadingAreas] = useState(false);

  useEffect(() => {
    fetch('http://localhost:8000/api/cities', { headers: { Accept: 'application/json' } })
      .then((r) => r.json())
      .then((list) => Array.isArray(list) && setCities(list))
      .catch(() => setCities([]));
  }, []);

  useEffect(() => {
    if (!formData.city_id) {
      setSubAreas([]);
      return;
    }
    setLoadingAreas(true);
    fetch(`http://localhost:8000/api/cities/${formData.city_id}/sub-areas`, {
      headers: { Accept: 'application/json' },
    })
      .then((r) => r.json())
      .then((d) => setSubAreas(d?.sub_areas ?? []))
      .catch(() => setSubAreas([]))
      .finally(() => setLoadingAreas(false));
  }, [formData.city_id]);
  const [submitStatus, setSubmitStatus] = useState<'idle' | 'submitting' | 'success' | 'error'>('idle');
  const [submitError, setSubmitError] = useState('');

  const fetchCollaborators = async () => {
    try {
      const res = await fetch('http://localhost:8000/api/superadmin/collaborators/stats');
      if (!res.ok) throw new Error('Failed to fetch collaborators');
      const json = await res.json();
      setCollaborators(json.data || []);
    } catch (err: any) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchCollaborators();
  }, []);

  const handleInputChange = (
    e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>
  ) => {
    const { name, value } = e.target;
    setFormData(prev => ({
      ...prev,
      [name]: value,
      // An area from the old city would now be in the wrong one.
      ...(name === 'city_id' ? { sub_area_id: '' } : {}),
    }));
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitStatus('submitting');
    setSubmitError('');

    try {
      const res = await fetch('http://localhost:8000/api/superadmin/collaborators', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(formData)
      });

      const json = await res.json();
      if (res.ok) {
        setSubmitStatus('success');
        setFormData({ name: '', email: '', phone: '', city_id: '', sub_area_id: '' });
        fetchCollaborators(); // Refresh the list
      } else {
        const firstError = json?.errors ? Object.values(json.errors)[0] : null;
        throw new Error(
          Array.isArray(firstError)
            ? String(firstError[0])
            : json.message || 'Failed to create collaborator'
        );
      }
    } catch (err: any) {
      setSubmitStatus('error');
      setSubmitError(err.message);
    }
  };

  return (
    <div className={styles.container}>
      <div className={styles.header}>
        <h1 className={styles.title}>Collaborator Management</h1>
        <p className={styles.subtitle}>Create new onboarding collaborators and view their performance stats.</p>
      </div>

      {/* Create Form */}
      <div style={{ marginBottom: '3rem', padding: '2rem', background: 'white', borderRadius: '12px', boxShadow: '0 2px 4px rgba(0,0,0,0.05)' }}>
        <h2 style={{ fontSize: '1.25rem', marginBottom: '1.5rem' }}>Add New Collaborator</h2>
        
        {submitStatus === 'success' && (
          <div style={{ padding: '1rem', backgroundColor: '#e8f5e9', color: '#2e7d32', borderRadius: '8px', marginBottom: '1rem' }}>
            Collaborator created successfully!
          </div>
        )}
        
        {submitStatus === 'error' && (
          <div style={{ padding: '1rem', backgroundColor: '#ffebee', color: '#c62828', borderRadius: '8px', marginBottom: '1rem' }}>
            {submitError}
          </div>
        )}

        <form onSubmit={handleSubmit} style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '1rem' }}>
          <div>
            <label style={{ display: 'block', marginBottom: '0.5rem', fontWeight: 500 }}>Name *</label>
            <input 
              type="text" 
              name="name" 
              required 
              value={formData.name} 
              onChange={handleInputChange}
              style={{ width: '100%', padding: '0.75rem', border: '1px solid #ccc', borderRadius: '8px' }}
            />
          </div>

          <div>
            <label style={{ display: 'block', marginBottom: '0.5rem', fontWeight: 500 }}>Phone Number *</label>
            <input 
              type="tel" 
              name="phone" 
              required 
              value={formData.phone} 
              onChange={handleInputChange}
              style={{ width: '100%', padding: '0.75rem', border: '1px solid #ccc', borderRadius: '8px' }}
            />
          </div>

          <div>
            <label style={{ display: 'block', marginBottom: '0.5rem', fontWeight: 500 }}>Email Address</label>
            <input 
              type="email" 
              name="email" 
              value={formData.email} 
              onChange={handleInputChange}
              style={{ width: '100%', padding: '0.75rem', border: '1px solid #ccc', borderRadius: '8px' }}
            />
          </div>

          <div>
            <label style={{ display: 'block', marginBottom: '0.5rem', fontWeight: 500 }}>City *</label>
            <select
              name="city_id"
              required
              value={formData.city_id}
              onChange={handleInputChange}
              style={{ width: '100%', padding: '0.75rem', border: '1px solid #ccc', borderRadius: '8px', background: 'white' }}
            >
              <option value="">Select city</option>
              {cities.map((c) => (
                <option key={c.id} value={c.id}>{c.name}, {c.state}</option>
              ))}
            </select>
          </div>

          <div>
            <label style={{ display: 'block', marginBottom: '0.5rem', fontWeight: 500 }}>Area *</label>
            <select
              name="sub_area_id"
              required
              disabled={!formData.city_id || loadingAreas}
              value={formData.sub_area_id}
              onChange={handleInputChange}
              style={{ width: '100%', padding: '0.75rem', border: '1px solid #ccc', borderRadius: '8px', background: 'white' }}
            >
              <option value="">
                {!formData.city_id
                  ? 'Choose a city first'
                  : loadingAreas
                    ? 'Loading areas…'
                    : subAreas.length === 0
                      ? 'No areas listed for this city yet'
                      : 'Select area'}
              </option>
              {subAreas.map((a) => (
                <option key={a.id} value={a.id}>{a.name}</option>
              ))}
            </select>
            <p style={{ marginTop: '0.4rem', fontSize: '0.8rem', color: '#777' }}>
              Enquiries from this area are offered to them first.
            </p>
          </div>

          <div style={{ gridColumn: 'span 2', display: 'flex', justifyContent: 'flex-end', marginTop: '1rem' }}>
            <button 
              type="submit" 
              disabled={submitStatus === 'submitting'}
              style={{ 
                padding: '0.75rem 2rem', 
                backgroundColor: '#0070f3', 
                color: 'white', 
                border: 'none', 
                borderRadius: '8px', 
                fontWeight: 'bold',
                cursor: submitStatus === 'submitting' ? 'not-allowed' : 'pointer',
                opacity: submitStatus === 'submitting' ? 0.7 : 1
              }}
            >
              {submitStatus === 'submitting' ? 'Creating...' : 'Create Collaborator'}
            </button>
          </div>
        </form>
      </div>

      {/* Collaborators List */}
      <div>
        <h2 className={styles.title} style={{ fontSize: '1.5rem', marginBottom: '1rem' }}>All Collaborators</h2>
        <div className={styles.tableContainer}>
          <table className={styles.table}>
            <thead>
              <tr>
                <th className={styles.th}>Name</th>
                <th className={styles.th}>Phone</th>
                <th className={styles.th}>Email</th>
                <th className={styles.th}>Joined Date</th>
                <th className={styles.th} style={{ textAlign: 'right' }}>Salons Onboarded</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                <tr><td colSpan={5} className={styles.emptyState}>Loading collaborators...</td></tr>
              ) : error ? (
                <tr><td colSpan={5} className={styles.emptyState} style={{ color: 'red' }}>{error}</td></tr>
              ) : collaborators.length === 0 ? (
                <tr><td colSpan={5} className={styles.emptyState}>No collaborators found.</td></tr>
              ) : (
                collaborators.map((collab) => (
                  <tr key={collab.id} className={styles.tr}>
                    <td className={`${styles.td} ${styles.salonName}`}>{collab.name}</td>
                    <td className={styles.td}>{collab.phone || 'N/A'}</td>
                    <td className={styles.td}>{collab.email || 'N/A'}</td>
                    <td className={styles.td}>{new Date(collab.created_at).toLocaleDateString()}</td>
                    <td className={styles.td} style={{ textAlign: 'right', fontWeight: 'bold' }}>
                      <span style={{ 
                        padding: '4px 12px', 
                        borderRadius: '12px', 
                        backgroundColor: collab.onboarded_salons_count > 0 ? '#e0f2f1' : '#f5f5f5',
                        color: collab.onboarded_salons_count > 0 ? '#00796b' : '#666'
                      }}>
                        {collab.onboarded_salons_count}
                      </span>
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
