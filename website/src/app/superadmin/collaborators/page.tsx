'use client';

import { useEffect, useState } from 'react';
import styles from '../salon-approval/page.module.css';
import ui from './page.module.css';

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
    fetch(`${process.env.NEXT_PUBLIC_BACKEND_URL}/api/cities`, { headers: { Accept: 'application/json' } })
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
    fetch(`${process.env.NEXT_PUBLIC_BACKEND_URL}/api/cities/${formData.city_id}/sub-areas`, {
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
      const res = await fetch(`${process.env.NEXT_PUBLIC_BACKEND_URL}/api/superadmin/collaborators/stats`);
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
      const res = await fetch(`${process.env.NEXT_PUBLIC_BACKEND_URL}/api/superadmin/collaborators`, {
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
      <div className={ui.card}>
        <h2 className={ui.cardTitle}>Add new collaborator</h2>
        <p className={ui.cardDesc}>Collaborators are matched to salon enquiries from the area they cover.</p>

        {submitStatus === 'success' && (
          <div className={`${ui.alert} ${ui.alertSuccess}`} role="status">Collaborator created successfully.</div>
        )}

        {submitStatus === 'error' && (
          <div className={`${ui.alert} ${ui.alertError}`} role="alert">{submitError}</div>
        )}

        <form onSubmit={handleSubmit} className={ui.form}>
          <label className={ui.field}>
            <span className={ui.label}>Name<span className={ui.required}>*</span></span>
            <input className={ui.input} type="text" name="name" required value={formData.name} onChange={handleInputChange} placeholder="Full name" />
          </label>

          <label className={ui.field}>
            <span className={ui.label}>Phone number<span className={ui.required}>*</span></span>
            <input className={ui.input} type="tel" name="phone" required value={formData.phone} onChange={handleInputChange} placeholder="10-digit mobile" />
          </label>

          <label className={ui.field}>
            <span className={ui.label}>Email address</span>
            <input className={ui.input} type="email" name="email" value={formData.email} onChange={handleInputChange} placeholder="name@example.com" />
          </label>

          <label className={ui.field}>
            <span className={ui.label}>City<span className={ui.required}>*</span></span>
            <select className={ui.input} name="city_id" required value={formData.city_id} onChange={handleInputChange}>
              <option value="">Select city</option>
              {cities.map((c) => (
                <option key={c.id} value={c.id}>{c.name}, {c.state}</option>
              ))}
            </select>
          </label>

          <label className={ui.field}>
            <span className={ui.label}>Area<span className={ui.required}>*</span></span>
            <select
              className={ui.input}
              name="sub_area_id"
              required
              disabled={!formData.city_id || loadingAreas}
              value={formData.sub_area_id}
              onChange={handleInputChange}
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
            <span className={ui.hint}>Enquiries from this area are offered to them first.</span>
          </label>

          <div className={ui.actions}>
            <button type="submit" className={ui.submit} disabled={submitStatus === 'submitting'}>
              {submitStatus === 'submitting' ? 'Creating…' : 'Create collaborator'}
            </button>
          </div>
        </form>
      </div>

      {/* Collaborators List */}
      <div>
        <h2 className={ui.sectionTitle}>All collaborators</h2>
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
                <tr><td colSpan={5} className={`${styles.emptyState} ${ui.errorText}`}>{error}</td></tr>
              ) : collaborators.length === 0 ? (
                <tr><td colSpan={5} className={styles.emptyState}>No collaborators found.</td></tr>
              ) : (
                collaborators.map((collab) => (
                  <tr key={collab.id} className={styles.tr}>
                    <td className={`${styles.td} ${styles.salonName}`}>{collab.name}</td>
                    <td className={styles.td}>{collab.phone || 'N/A'}</td>
                    <td className={styles.td}>{collab.email || 'N/A'}</td>
                    <td className={styles.td}>{new Date(collab.created_at).toLocaleDateString()}</td>
                    <td className={styles.td} style={{ textAlign: 'right' }}>
                      <span className={`${ui.countPill} ${collab.onboarded_salons_count > 0 ? ui.countPillActive : ''}`}>
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
