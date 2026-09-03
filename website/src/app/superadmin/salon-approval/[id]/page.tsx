'use client';

import { useEffect, useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import Link from 'next/link';
import styles from './page.module.css';

interface Salon {
  id: string;
  name: string;
  slug: string;
  created_at: string;
  address: string;
  pincode: string;
  gender_focus: string;
  description: string;
  city?: { name: string };
  admin?: { name: string; phone: string; email: string };
}

export default function SalonReviewPage() {
  const params = useParams();
  const router = useRouter();
  const { id } = params;
  
  const [salon, setSalon] = useState<Salon | null>(null);
  const [loading, setLoading] = useState(true);
  const [actionLoading, setActionLoading] = useState(false);
  const [error, setError] = useState('');
  
  const [showRejectModal, setShowRejectModal] = useState(false);
  const [rejectReason, setRejectReason] = useState('');

  useEffect(() => {
    async function fetchSalon() {
      try {
        const res = await fetch(`http://localhost:8000/api/superadmin/salons/pending/${id}`);
        if (!res.ok) throw new Error('Failed to fetch salon details');
        const json = await res.json();
        if (json.success) {
          setSalon(json.data);
        } else {
          throw new Error(json.message);
        }
      } catch (err: any) {
        setError(err.message);
      } finally {
        setLoading(false);
      }
    }
    if (id) fetchSalon();
  }, [id]);

  const handleApprove = async () => {
    if (!confirm('Are you sure you want to approve this salon?')) return;
    setActionLoading(true);
    try {
      const res = await fetch(`http://localhost:8000/api/superadmin/salons/${id}/approve`, {
        method: 'POST',
      });
      const json = await res.json();
      if (json.success) {
        alert(json.message);
        router.push('/superadmin/salon-approval');
      } else {
        alert(json.message || 'Approval failed');
      }
    } catch (err) {
      alert('Network error while approving');
    } finally {
      setActionLoading(false);
    }
  };

  const handleReject = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!rejectReason.trim()) return;
    setActionLoading(true);
    
    try {
      const res = await fetch(`http://localhost:8000/api/superadmin/salons/${id}/reject`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ rejection_reason: rejectReason })
      });
      const json = await res.json();
      if (json.success) {
        alert(json.message);
        router.push('/superadmin/salon-approval');
      } else {
        alert(json.message || 'Rejection failed');
      }
    } catch (err) {
      alert('Network error while rejecting');
    } finally {
      setActionLoading(false);
      setShowRejectModal(false);
    }
  };

  if (loading) return <div className={styles.container}>Loading...</div>;
  if (error || !salon) return <div className={styles.container} style={{color: 'red'}}>Error: {error || 'Salon not found'}</div>;

  return (
    <div className={styles.container}>
      <Link href="/superadmin/salon-approval" className={styles.backLink}>
        ← Back to Queue
      </Link>

      <div className={styles.card}>
        <div className={styles.header}>
          <div>
            <h1 className={styles.title}>{salon.name}</h1>
            <p className={styles.subtitle}>Submitted on {new Date(salon.created_at).toLocaleString()}</p>
          </div>
          <span className={styles.badge}>Pending Approval</span>
        </div>

        <div className={styles.grid}>
          <div>
            <h2 className={styles.sectionTitle}>Salon Information</h2>
            
            <div className={styles.infoGroup}>
              <span className={styles.label}>Slug</span>
              <div className={styles.value}>{salon.slug}</div>
            </div>
            
            <div className={styles.infoGroup}>
              <span className={styles.label}>City</span>
              <div className={styles.value}>{salon.city?.name || 'N/A'}</div>
            </div>

            <div className={styles.infoGroup}>
              <span className={styles.label}>Address</span>
              <div className={styles.value}>{salon.address}</div>
            </div>

            <div className={styles.infoGroup}>
              <span className={styles.label}>Pincode</span>
              <div className={styles.value}>{salon.pincode}</div>
            </div>

            <div className={styles.infoGroup}>
              <span className={styles.label}>Gender Focus</span>
              <div className={styles.value}>{salon.gender_focus || 'N/A'}</div>
            </div>

            {salon.description && (
              <div className={styles.infoGroup}>
                <span className={styles.label}>Description</span>
                <div className={styles.descValue}>{salon.description}</div>
              </div>
            )}
          </div>

          <div>
            <h2 className={styles.sectionTitle}>Owner / Admin Information</h2>
            
            {salon.admin ? (
              <>
                <div className={styles.infoGroup}>
                  <span className={styles.label}>Full Name</span>
                  <div className={styles.value}>{salon.admin.name}</div>
                </div>
                
                <div className={styles.infoGroup}>
                  <span className={styles.label}>Phone</span>
                  <div className={styles.value}>{salon.admin.phone}</div>
                </div>

                <div className={styles.infoGroup}>
                  <span className={styles.label}>Email</span>
                  <div className={styles.value}>{salon.admin.email || 'N/A'}</div>
                </div>
              </>
            ) : (
              <p style={{ color: '#64748b' }}>No admin information found.</p>
            )}
          </div>
        </div>

        <div className={styles.actions}>
          <button 
            className={styles.approveBtn} 
            onClick={handleApprove}
            disabled={actionLoading}
          >
            {actionLoading ? 'Processing...' : 'Approve Salon'}
          </button>
          
          <button 
            className={styles.rejectBtn}
            onClick={() => setShowRejectModal(true)}
            disabled={actionLoading}
          >
            Reject Salon
          </button>
        </div>
      </div>

      {showRejectModal && (
        <div className={styles.modalOverlay}>
          <div className={styles.modal}>
            <h3 className={styles.modalTitle}>Reject Salon</h3>
            <form onSubmit={handleReject}>
              <label className={styles.label} style={{ marginBottom: '0.5rem' }}>Reason for Rejection *</label>
              <textarea 
                className={styles.textarea} 
                rows={4}
                required
                placeholder="Tell the owner why their salon was rejected..."
                value={rejectReason}
                onChange={(e) => setRejectReason(e.target.value)}
              />
              <div className={styles.modalActions}>
                <button 
                  type="button" 
                  className={styles.cancelBtn}
                  onClick={() => setShowRejectModal(false)}
                >
                  Cancel
                </button>
                <button type="submit" className={styles.rejectBtn} disabled={actionLoading}>
                  {actionLoading ? 'Submitting...' : 'Submit Rejection'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
