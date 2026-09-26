'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import styles from './page.module.css';

interface Salon {
  id: string;
  name: string;
  status: string;
  created_at: string;
  city?: { name: string };
  admin?: { name: string };
  assigned_collaborator?: { id: string; name: string } | null;
}

interface Collaborator {
  id: string;
  name: string;
}

interface Meta {
  current_page: number;
  last_page: number;
  total: number;
}

export default function SalonDirectory() {
  const [salons, setSalons] = useState<Salon[]>([]);
  const [meta, setMeta] = useState<Meta | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [collaborators, setCollaborators] = useState<Collaborator[]>([]);
  const [assigningId, setAssigningId] = useState<string | null>(null);
  const [justAssignedIds, setJustAssignedIds] = useState<string[]>([]);
  
  // Filters & Sort
  const [search, setSearch] = useState('');
  const [status, setStatus] = useState('');
  const [collaboratorId, setCollaboratorId] = useState('');
  const [sort, setSort] = useState('created_at_desc');
  const [page, setPage] = useState(1);

  // Debounced search
  const [debouncedSearch, setDebouncedSearch] = useState('');

  useEffect(() => {
    async function fetchCollabs() {
      try {
        const res = await fetch(`/api/proxy/superadmin/collaborators`);
        if (res.ok) {
          const json = await res.json();
          setCollaborators(json.data || []);
        }
      } catch (err) {
        console.error(err);
      }
    }
    fetchCollabs();
  }, []);

  useEffect(() => {
    const handler = setTimeout(() => setDebouncedSearch(search), 500);
    return () => clearTimeout(handler);
  }, [search]);

  useEffect(() => {
    async function fetchSalons() {
      setLoading(true);
      try {
        const queryParams = new URLSearchParams();
        if (debouncedSearch) queryParams.append('search', debouncedSearch);
        if (status) queryParams.append('status', status);
        if (collaboratorId) queryParams.append('collaborator_id', collaboratorId);
        if (sort) queryParams.append('sort', sort);
        queryParams.append('page', page.toString());

        const res = await fetch(`${process.env.NEXT_PUBLIC_BACKEND_URL}/api/superadmin/salons?${queryParams.toString()}`);
        if (!res.ok) throw new Error('Failed to fetch salons');
        
        const json = await res.json();
        if (json.success) {
          setSalons(json.data);
          setMeta(json.meta);
        } else {
          // fallback if controller returns old format (array)
          if (Array.isArray(json)) {
            setSalons(json);
            setMeta(null);
          } else {
            throw new Error(json.message || 'Error loading salons');
          }
        }
      } catch (err: any) {
        setError(err.message);
      } finally {
        setLoading(false);
      }
    }

    fetchSalons();
  }, [debouncedSearch, status, collaboratorId, sort, page]);

  const handleAssign = async (salonId: string, collId: string) => {
    if (!window.confirm('Are you sure you want to change the assigned collaborator?')) {
      // Revert the select locally since we didn't update state
      const el = document.getElementById(`select-coll-${salonId}`) as HTMLSelectElement;
      const salon = salons.find(s => s.id === salonId);
      if (el) el.value = salon?.assigned_collaborator?.id || '';
      return;
    }

    setAssigningId(salonId);
    try {
      const res = await fetch(`/api/proxy/superadmin/salons/${salonId}/assign-collaborator`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ collaborator_id: collId || null })
      });
      const json = await res.json();
      if (!res.ok || !json.success) throw new Error(json.message || 'Failed to assign');
      
      setSalons(prev => prev.map(s => s.id === salonId ? { ...s, assigned_collaborator: json.data?.assigned_collaborator || null } : s));
      
      // Trigger animation
      setJustAssignedIds(prev => [...prev, salonId]);
      setTimeout(() => {
        setJustAssignedIds(prev => prev.filter(id => id !== salonId));
      }, 2000);
    } catch (err: any) {
      alert(err.message);
      // Revert on error
      const el = document.getElementById(`select-coll-${salonId}`) as HTMLSelectElement;
      const salon = salons.find(s => s.id === salonId);
      if (el) el.value = salon?.assigned_collaborator?.id || '';
    } finally {
      setAssigningId(null);
    }
  };

  const getStatusBadgeClass = (status: string) => {
    switch(status) {
      case 'active': return styles.badgeActive;
      case 'pending_approval': return styles.badgePending;
      case 'rejected': return styles.badgeRejected;
      case 'suspended': return styles.badgeSuspended;
      default: return styles.badgeSuspended;
    }
  };

  const formatStatus = (status: string) => {
    return status.replace('_', ' ');
  };

  return (
    <div className={styles.container}>
      <div className={styles.header}>
        <div>
          <h1 className={styles.title}>Salon Directory</h1>
          <p className={styles.subtitle}>Master list of every salon on the platform.</p>
        </div>
      </div>

      <div className={styles.filters} style={{ display: 'flex', gap: '12px', flexWrap: 'wrap', marginBottom: '20px' }}>
        <input 
          type="text" 
          placeholder="Search by salon name or city..." 
          className={styles.searchInput}
          style={{ flexGrow: 1 }}
          value={search}
          onChange={(e) => { setSearch(e.target.value); setPage(1); }}
        />
        
        <select 
          className={styles.selectInput} 
          value={status} 
          onChange={(e) => { setStatus(e.target.value); setPage(1); }}
        >
          <option value="">All Statuses</option>
          <option value="active">Active</option>
          <option value="pending_approval">Pending Approval</option>
          <option value="suspended">Suspended</option>
          <option value="deactivated">Deactivated</option>
          <option value="rejected">Rejected</option>
        </select>

        <select 
          className={styles.selectInput} 
          value={collaboratorId} 
          onChange={(e) => { setCollaboratorId(e.target.value); setPage(1); }}
        >
          <option value="">All Collaborators</option>
          <option value="unassigned">Only Unassigned</option>
          {collaborators.map(c => (
            <option key={c.id} value={c.id}>{c.name}</option>
          ))}
        </select>

        <select 
          className={styles.selectInput} 
          value={sort} 
          onChange={(e) => { setSort(e.target.value); setPage(1); }}
        >
          <option value="created_at_desc">Newest First</option>
          <option value="created_at_asc">Oldest First</option>
          <option value="name_asc">Name (A-Z)</option>
          <option value="name_desc">Name (Z-A)</option>
        </select>
      </div>

      <div className={styles.tableContainer}>
        <table className={styles.table}>
          <thead>
            <tr>
              <th className={styles.th}>Salon Name</th>
              <th className={styles.th}>City</th>
              <th className={styles.th}>Owner/Admin</th>
              <th className={styles.th}>Collaborator</th>
              <th className={styles.th}>Status</th>
              <th className={styles.th} style={{ textAlign: 'right' }}>Action</th>
            </tr>
          </thead>
          <tbody>
            {loading && salons.length === 0 ? (
              <tr>
                <td colSpan={6} className={styles.emptyState}>Loading...</td>
              </tr>
            ) : error ? (
              <tr>
                <td colSpan={6} className={styles.emptyState} style={{ color: 'red' }}>{error}</td>
              </tr>
            ) : salons.length === 0 ? (
              <tr>
                <td colSpan={6} className={styles.emptyState}>No salons found matching your criteria.</td>
              </tr>
            ) : (
              salons.map((salon) => (
                <tr key={salon.id} className={`${styles.tr} ${justAssignedIds.includes(salon.id) ? styles.rowSuccess : ''}`}>
                  <td className={`${styles.td} ${styles.salonName}`}>{salon.name}</td>
                  <td className={styles.td}>{salon.city?.name || 'N/A'}</td>
                  <td className={styles.td}>{salon.admin?.name || 'N/A'}</td>
                  <td className={styles.td}>
                    <select
                      id={`select-coll-${salon.id}`}
                      className={styles.selectInput}
                      style={{ padding: '4px', fontSize: '0.85rem' }}
                      defaultValue={salon.assigned_collaborator?.id || ''}
                      onChange={(e) => handleAssign(salon.id, e.target.value)}
                      disabled={assigningId === salon.id}
                    >
                      <option value="">Unassigned</option>
                      {collaborators.map(c => (
                        <option key={c.id} value={c.id}>{c.name}</option>
                      ))}
                    </select>
                    {justAssignedIds.includes(salon.id) && (
                      <span style={{ marginLeft: '8px', color: 'var(--color-success)', fontSize: '0.8rem', fontWeight: 600 }}>✓ Saved</span>
                    )}
                  </td>
                  <td className={styles.td}>
                    <span className={`${styles.badge} ${getStatusBadgeClass(salon.status)}`}>
                      {formatStatus(salon.status)}
                    </span>
                  </td>
                  <td className={styles.td} style={{ textAlign: 'right' }}>
                    <Link href={`/superadmin/salons/${salon.id}`} className={styles.actionButton}>
                      View Profile
                    </Link>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
        
        {meta && meta.last_page > 1 && (
          <div className={styles.pagination}>
            <div className={styles.pageInfo}>
              Showing page {meta.current_page} of {meta.last_page} ({meta.total} total salons)
            </div>
            <div className={styles.pageControls}>
              <button 
                className={styles.pageButton} 
                disabled={meta.current_page === 1}
                onClick={() => setPage(p => Math.max(1, p - 1))}
              >
                Previous
              </button>
              <button 
                className={styles.pageButton} 
                disabled={meta.current_page === meta.last_page}
                onClick={() => setPage(p => Math.min(meta.last_page, p + 1))}
              >
                Next
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
