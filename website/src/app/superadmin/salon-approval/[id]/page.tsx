'use client';

import { useEffect, useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import Link from 'next/link';
import { useConfirm } from '@/components/admin/ui';
import styles from './page.module.css';

interface SalonMedia {
  id: string;
  file_url?: string;
  file_path?: string;
  url?: string;
  thumbnail_url?: string;
  media_type?: string;
  file_type?: string;
  is_cover: boolean | number;
  alt_text?: string | null;
}

function getMediaUrl(media?: SalonMedia | null): string {
  if (!media) return '';
  return media.file_url || media.file_path || media.url || media.thumbnail_url || '';
}

interface WorkingHour {
  id?: string;
  day_of_week: number;
  open_time?: string;
  close_time?: string;
  is_closed?: boolean | number;
}

interface SalonService {
  id: string;
  price: number;
  estimated_duration_minutes?: number;
  template?: {
    id: string;
    name: string;
    category?: {
      id: string;
      name: string;
    };
  };
}

interface PreferredPlan {
  id: string;
  name: string;
  price: number;
  duration_days: number;
  description?: string;
}

interface Salon {
  id: string;
  name: string;
  slug: string;
  status: string;
  created_at: string;
  resubmitted_at?: string | null;
  correction_requested_at?: string | null;
  correction_notes?: string | null;
  address: string;
  pincode: string;
  latitude?: number | null;
  longitude?: number | null;
  gender_focus?: string;
  description?: string;
  cover_photo_url?: string | null;
  preferred_plan_id?: string | null;
  preferred_plan?: PreferredPlan | null;
  preferred_commercial_model?: 'subscription' | 'commission' | null;
  requested_commission_percentage?: number | string | null;
  commission_percentage?: number | string | null;
  commission_opt_in?: boolean | number;
  city?: { id: string; name: string };
  sub_area?: { id: string; name: string };
  admin?: { id: string; name: string; phone: string; email: string };
  assigned_collaborator?: { id: string; name: string; phone?: string; email?: string } | null;
  media?: SalonMedia[];
  working_hours?: WorkingHour[];
  services?: SalonService[];
}

const DAYS_OF_WEEK = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

function resolveImageUrl(url?: string | null): string {
  if (!url) return '';
  const trimmed = url.trim();
  if (!trimmed) return '';

  const backendBase = (process.env.NEXT_PUBLIC_BACKEND_URL || 'https://api.bookalook.in').replace(/\/$/, '');

  // If already absolute URL
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    // In production or when accessed via HTTPS, upgrade http://api.bookalook.in or http://bookalook.in to https://
    if (trimmed.startsWith('http://api.bookalook.in') || trimmed.startsWith('http://bookalook.in')) {
      return trimmed.replace('http://', 'https://');
    }

    // If the image was saved with localhost/127.0.0.1 domain, rewrite the host to backendBase in non-local environments
    if (typeof window !== 'undefined' && window.location.hostname !== 'localhost' && window.location.hostname !== '127.0.0.1') {
      if (trimmed.includes('localhost') || trimmed.includes('127.0.0.1')) {
        const match = trimmed.match(/https?:\/\/[^\/]+(\/.*)$/);
        if (match && match[1]) {
          return `${backendBase}${match[1]}`;
        }
      }
    }

    return trimmed;
  }

  const cleanPath = trimmed.startsWith('/') ? trimmed : `/${trimmed}`;
  return `${backendBase}${cleanPath}`;
}

export default function SalonReviewPage() {
  const params = useParams();
  const router = useRouter();
  const { id } = params;

  const [salon, setSalon] = useState<Salon | null>(null);
  const [loading, setLoading] = useState(true);
  const [actionLoading, setActionLoading] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');

  // Commercial model & commission management
  const [approvedCommission, setApprovedCommission] = useState<string>('');

  // Modals
  const [showRejectModal, setShowRejectModal] = useState(false);
  const [rejectReason, setRejectReason] = useState('');
  const [showCorrectionModal, setShowCorrectionModal] = useState(false);
  const [correctionNotes, setCorrectionNotes] = useState('');

  const [confirm, confirmDialog] = useConfirm();

  useEffect(() => {
    async function fetchSalon() {
      try {
        const res = await fetch(`/api/proxy/superadmin/salons/pending/${id}`, { cache: 'no-store' });
        if (!res.ok) throw new Error('Failed to fetch salon details');
        const json = await res.json();
        if (json.success) {
          const data: Salon = json.data;
          setSalon(data);
          // Pre-populate approved commission if already stored, or defaults to requested
          if (data.commission_percentage !== undefined && data.commission_percentage !== null) {
            setApprovedCommission(String(data.commission_percentage));
          } else if (data.requested_commission_percentage !== undefined && data.requested_commission_percentage !== null) {
            setApprovedCommission(String(data.requested_commission_percentage));
          }
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
    if (!salon) return;

    const isCommission = salon.preferred_commercial_model === 'commission';
    if (isCommission) {
      const parsedRate = parseFloat(approvedCommission);
      if (isNaN(parsedRate) || parsedRate < 0 || parsedRate > 100) {
        setNotice('Please enter a valid final approved commission rate between 0% and 100%.');
        return;
      }
    }

    const ok = await confirm({
      title: `Approve ${salon.name}?`,
      body: isCommission
        ? `This salon will go live with an approved commission rate of ${approvedCommission}%.`
        : 'This salon registration will be approved. The salon can now proceed to purchase/select their subscription plan.',
      confirmLabel: 'Approve Salon',
    });
    if (!ok) return;

    setActionLoading(true);
    setNotice('');

    try {
      const res = await fetch(`/api/proxy/superadmin/salons/${id}/approve`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          commercial_model: salon.preferred_commercial_model || 'subscription',
          commission_percentage: isCommission ? parseFloat(approvedCommission) : undefined,
        }),
      });
      const json = await res.json();
      if (json.success) {
        router.push('/superadmin/salon-approval');
      } else {
        setNotice(json.message || 'Approval failed');
      }
    } catch {
      setNotice('Network error while approving salon');
    } finally {
      setActionLoading(false);
    }
  };

  const handleRequestCorrections = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!correctionNotes.trim() || !salon) return;

    const ok = await confirm({
      title: `Return ${salon.name} for corrections?`,
      body: `The applicant will be requested to make the following corrections: "${correctionNotes.trim()}". The application will be reopened for edits.`,
      confirmLabel: 'Send for Corrections',
      tone: 'danger',
    });
    if (!ok) return;

    setActionLoading(true);
    setNotice('');

    try {
      const res = await fetch(`/api/proxy/superadmin/salons/${id}/request-corrections`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ correction_notes: correctionNotes.trim() }),
      });
      const json = await res.json();
      if (json.success) {
        setShowCorrectionModal(false);
        router.push('/superadmin/salon-approval');
      } else {
        setNotice(json.message || 'Failed to request corrections');
      }
    } catch {
      setNotice('Network error while sending corrections request');
    } finally {
      setActionLoading(false);
    }
  };

  const handleReject = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!rejectReason.trim() || !salon) return;

    const ok = await confirm({
      title: `Reject ${salon.name}?`,
      body: `The owner is told: "${rejectReason.trim()}". This closes the enquiry and the salon stays unpublished.`,
      confirmLabel: 'Reject Salon',
      tone: 'danger',
    });
    if (!ok) return;

    setActionLoading(true);
    setNotice('');

    try {
      const res = await fetch(`/api/proxy/superadmin/salons/${id}/reject`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ rejection_reason: rejectReason.trim() }),
      });
      const json = await res.json();
      if (json.success) {
        setShowRejectModal(false);
        router.push('/superadmin/salon-approval');
      } else {
        setNotice(json.message || 'Rejection failed');
      }
    } catch {
      setNotice('Network error while rejecting salon');
    } finally {
      setActionLoading(false);
    }
  };

  if (loading) return <div className={styles.container}>Loading registration review...</div>;
  if (error || !salon) return <div className={styles.container} style={{ color: 'red' }}>Error: {error || 'Salon not found'}</div>;

  // Media calculations
  const coverMedia = salon.media?.find((m) => Boolean(m.is_cover));
  const coverImageUrl = getMediaUrl(coverMedia) || salon.cover_photo_url;
  const isCommissionModel = salon.preferred_commercial_model === 'commission';

  return (
    <div className={styles.container}>
      <Link href="/superadmin/salon-approval" className={styles.backLink}>
        ← Back to Queue
      </Link>

      <div className={styles.card}>
        {/* Header */}
        <div className={styles.header}>
          <div>
            <h1 className={styles.title}>{salon.name}</h1>
            <p className={styles.subtitle}>
              Submitted on {new Date(salon.created_at).toLocaleString('en-IN')}
              {salon.resubmitted_at && ` • Resubmitted on ${new Date(salon.resubmitted_at).toLocaleString('en-IN')}`}
            </p>
          </div>
          <div>
            {salon.status === 'needs_correction' ? (
              <span className={styles.badgeCorrection}>Needs Correction</span>
            ) : salon.status === 'approved' ? (
              <span className={styles.badgeApproved}>Approved</span>
            ) : salon.status === 'rejected' ? (
              <span className={styles.badgeRejected}>Rejected</span>
            ) : (
              <span className={styles.badgePending}>Pending Approval</span>
            )}
          </div>
        </div>

        {/* Previous Correction Banner */}
        {salon.correction_notes && (
          <div className={styles.bannerCorrection}>
            <div className={styles.bannerCorrectionTitle}>
              Correction Instructions Sent {salon.correction_requested_at ? `(${new Date(salon.correction_requested_at).toLocaleDateString('en-IN')})` : ''}
            </div>
            <p className={styles.bannerCorrectionText}>{salon.correction_notes}</p>
          </div>
        )}

        {/* Photo Gallery & Mandatory Main Cover Photo */}
        <div className={styles.coverWrapper}>
          <h2 className={styles.sectionTitle}>Salon Photos & Main Cover Photo</h2>
          {coverImageUrl ? (
            <div className={styles.coverCard}>
              <img
                src={resolveImageUrl(coverImageUrl)}
                alt="Main Cover"
                className={styles.coverImg}
              />
              <span className={styles.coverTag}>★ Main Cover Photo</span>
            </div>
          ) : (
            <div className={styles.noCoverNotice}>
              No main cover photo selected (legacy registration).
            </div>
          )}

          {salon.media && salon.media.length > 0 && (
            <div>
              <span className={styles.label} style={{ marginBottom: '0.5rem' }}>All Uploaded Photos ({salon.media.length})</span>
              <div className={styles.galleryGrid}>
                {salon.media.map((media) => {
                  const mediaUrl = getMediaUrl(media);
                  const isCover = Boolean(media.is_cover);
                  return (
                    <div
                      key={media.id}
                      className={`${styles.galleryItem} ${isCover ? styles.galleryItemActive : ''}`}
                    >
                      <img
                        src={resolveImageUrl(mediaUrl)}
                        alt={media.alt_text || 'Salon Gallery Item'}
                        className={styles.galleryImg}
                        loading="lazy"
                        onError={(e) => {
                          if (media.thumbnail_url && e.currentTarget.src !== resolveImageUrl(media.thumbnail_url)) {
                            e.currentTarget.src = resolveImageUrl(media.thumbnail_url);
                          }
                        }}
                      />
                      {isCover && <span className={styles.thumbCoverTag}>Cover</span>}
                    </div>
                  );
                })}
              </div>
            </div>
          )}
        </div>

        {/* Commercial Preferences & Commission Review */}
        <div className={styles.fullSection}>
          <h2 className={styles.sectionTitle}>Commercial Preferences & Commission Terms</h2>
          <div className={styles.prefGrid}>
            <div className={styles.prefCard}>
              <div className={styles.prefTitle}>Commercial Model Preference</div>
              <div className={styles.prefValue}>
                {isCommissionModel ? 'Commission Model' : salon.preferred_commercial_model === 'subscription' ? 'Subscription Plan' : 'Not specified'}
              </div>
              <div className={styles.prefSub}>Chosen during initial registration</div>
            </div>

            <div className={styles.prefCard}>
              <div className={styles.prefTitle}>Preferred Subscription Plan</div>
              <div className={styles.prefValue}>
                {salon.preferred_plan ? salon.preferred_plan.name : 'Not sure yet'}
              </div>
              <div className={styles.prefSub}>
                {salon.preferred_plan
                  ? `₹${salon.preferred_plan.price} / ${salon.preferred_plan.duration_days} days (Informational preference only)`
                  : 'Salon did not choose a specific plan yet'}
              </div>
            </div>

            {isCommissionModel && (
              <div className={styles.prefCard}>
                <div className={styles.prefTitle}>Requested Commission Rate</div>
                <div className={styles.prefValue}>
                  {salon.requested_commission_percentage !== null && salon.requested_commission_percentage !== undefined
                    ? `${salon.requested_commission_percentage}%`
                    : 'Not specified'}
                </div>
                <div className={styles.prefSub}>Applicant requested percentage</div>
              </div>
            )}

            {isCommissionModel && (
              <div className={styles.prefCard} style={{ borderColor: 'var(--accent-color)' }}>
                <div className={styles.prefTitle} style={{ color: 'var(--accent-color)' }}>
                  Final Approved Commission % *
                </div>
                <input
                  type="number"
                  step="0.01"
                  min="0"
                  max="100"
                  required
                  className={styles.inputField}
                  placeholder="e.g. 15.00"
                  value={approvedCommission}
                  onChange={(e) => setApprovedCommission(e.target.value)}
                />
                <span className={styles.helpText}>
                  Authoritative rate set by SuperAdmin. Used for future bookings billing.
                </span>
              </div>
            )}
          </div>
        </div>

        {/* Core Details Grid */}
        <div className={styles.grid}>
          {/* Identity & Location */}
          <div>
            <h2 className={styles.sectionTitle}>Salon Identity & Location</h2>

            <div className={styles.infoGroup}>
              <span className={styles.label}>Slug</span>
              <div className={styles.value}>{salon.slug}</div>
            </div>

            <div className={styles.infoGroup}>
              <span className={styles.label}>City</span>
              <div className={styles.value}>{salon.city?.name || 'N/A'}</div>
            </div>

            <div className={styles.infoGroup}>
              <span className={styles.label}>Sub-Area / Locality</span>
              <div className={styles.value}>{salon.sub_area?.name || 'N/A'}</div>
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

            {salon.latitude && salon.longitude && (
              <div className={styles.infoGroup}>
                <span className={styles.label}>GPS Coordinates</span>
                <div className={styles.value}>
                  {salon.latitude}, {salon.longitude}{' '}
                  <a
                    href={`https://www.google.com/maps/search/?api=1&query=${salon.latitude},${salon.longitude}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    style={{ color: 'var(--accent-color)', marginLeft: 8 }}
                  >
                    View on Google Maps ↗
                  </a>
                </div>
              </div>
            )}

            {salon.description && (
              <div className={styles.infoGroup}>
                <span className={styles.label}>Description</span>
                <div className={styles.descValue}>{salon.description}</div>
              </div>
            )}
          </div>

          {/* Owner & Collaborator Attribution */}
          <div>
            <h2 className={styles.sectionTitle}>Owner & Collaborator Attribution</h2>

            <div className={styles.infoGroup}>
              <span className={styles.label}>Owner / Admin Name</span>
              <div className={styles.value}>{salon.admin?.name || 'N/A'}</div>
            </div>

            <div className={styles.infoGroup}>
              <span className={styles.label}>Owner Phone</span>
              <div className={styles.value}>{salon.admin?.phone || 'N/A'}</div>
            </div>

            <div className={styles.infoGroup}>
              <span className={styles.label}>Owner Email</span>
              <div className={styles.value}>{salon.admin?.email || 'N/A'}</div>
            </div>

            <div style={{ marginTop: '2rem' }}>
              <span className={styles.label}>Onboarding Collaborator</span>
              {salon.assigned_collaborator ? (
                <div className={styles.descValue}>
                  <strong>{salon.assigned_collaborator.name}</strong>
                  {salon.assigned_collaborator.phone && <div>Phone: {salon.assigned_collaborator.phone}</div>}
                  {salon.assigned_collaborator.email && <div>Email: {salon.assigned_collaborator.email}</div>}
                </div>
              ) : (
                <div className={styles.value}>Direct Salon Admin Registration (Self-onboarded)</div>
              )}
            </div>
          </div>
        </div>

        {/* Operating Hours */}
        {salon.working_hours && salon.working_hours.length > 0 && (
          <div className={styles.fullSection}>
            <h2 className={styles.sectionTitle}>Operating Hours</h2>
            <table className={styles.dataTable}>
              <thead>
                <tr>
                  <th>Day</th>
                  <th>Status</th>
                  <th>Hours</th>
                </tr>
              </thead>
              <tbody>
                {salon.working_hours.map((wh) => (
                  <tr key={wh.id || wh.day_of_week}>
                    <td>{DAYS_OF_WEEK[wh.day_of_week] || `Day ${wh.day_of_week}`}</td>
                    <td>
                      {wh.is_closed ? (
                        <span className={styles.closedTag}>Closed</span>
                      ) : (
                        <span className={styles.openTag}>Open</span>
                      )}
                    </td>
                    <td>
                      {wh.is_closed ? '—' : `${wh.open_time || '09:00'} - ${wh.close_time || '20:00'}`}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {/* Services & Pricing */}
        {salon.services && salon.services.length > 0 && (
          <div className={styles.fullSection}>
            <h2 className={styles.sectionTitle}>Services & Pricing ({salon.services.length})</h2>
            <table className={styles.dataTable}>
              <thead>
                <tr>
                  <th>Service</th>
                  <th>Category</th>
                  <th>Price</th>
                  <th>Duration</th>
                </tr>
              </thead>
              <tbody>
                {salon.services.map((svc) => (
                  <tr key={svc.id}>
                    <td>{svc.template?.name || 'Custom Service'}</td>
                    <td>{svc.template?.category?.name || 'General'}</td>
                    <td>₹{svc.price}</td>
                    <td>{svc.estimated_duration_minutes ? `${svc.estimated_duration_minutes} min` : '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {/* Notice Message */}
        {notice && (
          <p style={{ color: 'var(--color-danger)', marginTop: 16, fontWeight: 600 }}>{notice}</p>
        )}

        {/* Action Buttons */}
        <div className={styles.actions}>
          <button
            className={styles.approveBtn}
            onClick={handleApprove}
            disabled={actionLoading}
          >
            {actionLoading ? 'Processing...' : 'Approve Salon'}
          </button>

          <button
            className={styles.correctionBtn}
            onClick={() => {
              setNotice('');
              setShowCorrectionModal(true);
            }}
            disabled={actionLoading}
          >
            Return for Corrections
          </button>

          <button
            className={styles.rejectBtn}
            onClick={() => {
              setNotice('');
              setShowRejectModal(true);
            }}
            disabled={actionLoading}
          >
            Reject Salon
          </button>
        </div>
      </div>

      {/* Return for Corrections Modal */}
      {showCorrectionModal && (
        <div className={styles.modalOverlay}>
          <div className={styles.modal}>
            <h3 className={styles.modalTitle}>Return Application for Corrections</h3>
            <p style={{ color: 'var(--text-body)', fontSize: '0.9rem', marginBottom: '1rem' }}>
              The application will be reopened for the applicant to edit and resubmit. Please provide clear instructions on what needs to be corrected (e.g. photos, address, documentation).
            </p>
            <form onSubmit={handleRequestCorrections}>
              <label className={styles.label} style={{ marginBottom: '0.5rem' }}>
                Correction Instructions *
              </label>
              <textarea
                className={styles.textarea}
                rows={5}
                required
                placeholder="Describe the required changes clearly..."
                value={correctionNotes}
                onChange={(e) => setCorrectionNotes(e.target.value)}
              />
              <div className={styles.modalActions}>
                <button
                  type="button"
                  className={styles.cancelBtn}
                  onClick={() => setShowCorrectionModal(false)}
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  className={styles.correctionBtn}
                  disabled={actionLoading || !correctionNotes.trim()}
                >
                  {actionLoading ? 'Submitting...' : 'Send for Corrections'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Reject Modal */}
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
                <button
                  type="submit"
                  className={styles.rejectBtn}
                  disabled={actionLoading || !rejectReason.trim()}
                >
                  {actionLoading ? 'Submitting...' : 'Submit Rejection'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {confirmDialog}
    </div>
  );
}
