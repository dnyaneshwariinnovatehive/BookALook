'use client';

import { useEffect, useState } from 'react';
import { useParams } from 'next/navigation';
import Link from 'next/link';
import StaffDetailsModal from './StaffDetailsModal';
import styles from './page.module.css';

interface Salon {
  id: string;
  name: string;
  slug: string;
  status: string;
  created_at: string;
  address: string;
  pincode: string;
  gender_focus: string;
  description: string;
  city?: { name: string };
  admin?: { name: string; phone: string; email: string };
  assigned_collaborator_id?: string | null;
  assigned_collaborator?: { id: string; name: string; email: string } | null;
  providers?: { id: string; user?: { name: string; phone: string; email: string }; is_active: boolean }[];
  services?: { 
    id: string; 
    price: number; 
    estimated_duration_minutes?: number;
    template?: { 
      name: string; 
      estimated_duration_minutes: number;
      category?: { name: string } 
    }
  }[];
  combos?: { 
    id: string; 
    name: string; 
    is_active: boolean;
    services?: { pivot?: { combo_special_price: number | string } }[];
  }[];
}

interface Collaborator {
  id: string;
  name: string;
  email?: string;
}

export default function SalonDirectoryDetail() {
  const params = useParams();
  const { id } = params;

  const [salon, setSalon] = useState<Salon | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  // Onboarding collaborator. Salons that came in through an enquiry already
  // have one; salons registered from the partner app arrive with none, and the
  // directory is the only place they can be given one.
  const [collaborators, setCollaborators] = useState<Collaborator[]>([]);
  const [selectedCollaborator, setSelectedCollaborator] = useState('');
  const [assigning, setAssigning] = useState(false);
  const [assignNote, setAssignNote] = useState('');

  const [selectedStaffId, setSelectedStaffId] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState('Overview');

  useEffect(() => {
    async function fetchSalon() {
      try {
        const [salonRes, collabRes] = await Promise.all([
          fetch(`${process.env.NEXT_PUBLIC_BACKEND_URL}/api/superadmin/salons/${id}`),
          fetch(`${process.env.NEXT_PUBLIC_BACKEND_URL}/api/superadmin/collaborators`),
        ]);

        if (!salonRes.ok) throw new Error('Failed to fetch salon details');
        const json = await salonRes.json();
        if (json.success) {
          setSalon(json.data);
          setSelectedCollaborator(json.data.assigned_collaborator_id || '');
        } else {
          throw new Error(json.message);
        }

        // A missing collaborator list only costs the dropdown, not the page.
        if (collabRes.ok) {
          const collabJson = await collabRes.json();
          setCollaborators(collabJson.data || []);
        }
      } catch (err: any) {
        setError(err.message);
      } finally {
        setLoading(false);
      }
    }
    if (id) fetchSalon();
  }, [id]);

  const handleAssignCollaborator = async () => {
    setAssigning(true);
    setAssignNote('');

    try {
      const res = await fetch(
        `${process.env.NEXT_PUBLIC_BACKEND_URL}/api/superadmin/salons/${id}/assign-collaborator`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ collaborator_id: selectedCollaborator || null }),
        }
      );

      const json = await res.json();
      if (!res.ok || !json.success) {
        throw new Error(json.message || 'Failed to assign collaborator');
      }

      setSalon(prev => (prev ? { ...prev, ...json.data } : prev));
      setAssignNote(json.message);
    } catch (err: any) {
      setAssignNote(err.message);
    } finally {
      setAssigning(false);
    }
  };

  if (loading) return <div className={styles.container}>Loading...</div>;
  if (error || !salon) return <div className={styles.container} style={{color: 'red'}}>Error: {error || 'Salon not found'}</div>;

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
      <Link href="/superadmin/salons" className={styles.backLink}>
        ← Back to Directory
      </Link>

      <div className={styles.card}>
        <div className={styles.header}>
          <div>
            <h1 className={styles.title}>{salon.name}</h1>
            <p className={styles.subtitle}>Registered on {new Date(salon.created_at).toLocaleString()}</p>
          </div>
          <span className={`${styles.badge} ${getStatusBadgeClass(salon.status)}`}>
            {formatStatus(salon.status)}
          </span>
        </div>

        <div className={styles.pageTabs}>
          {['Overview', 'Collaborator', 'Staff', 'Catalog'].map(tab => (
            <button
              key={tab}
              className={`${styles.pageTab} ${activeTab === tab ? styles.pageTabActive : ''}`}
              onClick={() => setActiveTab(tab)}
            >
              {tab}
            </button>
          ))}
        </div>

        {activeTab === 'Overview' && (
          <div className={styles.grid}>
            <div>
              <h2 className={styles.sectionTitle}>Basic Information</h2>
              
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
              <h2 className={styles.sectionTitle}>Owner / Admin</h2>
              
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
                <p style={{ color: 'var(--text-body)' }}>No admin information found.</p>
              )}
            </div>
          </div>
        )}
      </div>

      {activeTab === 'Collaborator' && (
        <div className={styles.card}>
          <h2 className={styles.sectionTitle}>Onboarding Collaborator</h2>

          <div className={styles.infoGroup}>
            <span className={styles.label}>Currently Assigned</span>
            <div className={styles.value}>
              {salon.assigned_collaborator
                ? `${salon.assigned_collaborator.name}${
                    salon.assigned_collaborator.email ? ` — ${salon.assigned_collaborator.email}` : ''
                  }`
                : 'No collaborator assigned yet.'}
            </div>
          </div>

          <div className={styles.assignRow}>
            <select
              className={styles.assignSelect}
              value={selectedCollaborator}
              onChange={(e) => setSelectedCollaborator(e.target.value)}
              disabled={assigning}
            >
              <option value="">— No collaborator —</option>
              {collaborators.map((collaborator) => (
                <option key={collaborator.id} value={collaborator.id}>
                  {collaborator.name}
                </option>
              ))}
            </select>

            <button
              className={styles.assignButton}
              onClick={handleAssignCollaborator}
              disabled={assigning || selectedCollaborator === (salon.assigned_collaborator_id || '')}
            >
              {assigning ? 'Saving…' : 'Save Assignment'}
            </button>
          </div>

          {collaborators.length === 0 && (
            <p className={styles.assignNote}>
              No collaborators exist yet. Create one from the Collaborators page first.
            </p>
          )}

          {assignNote && <p className={styles.assignNote}>{assignNote}</p>}
        </div>
      )}

      {activeTab === 'Staff' && (
        <div className={styles.card}>
          <h2 className={styles.sectionTitle}>Staff Directory</h2>
          {salon.providers && salon.providers.length > 0 ? (
            <div className={styles.staffGrid}>
              {salon.providers.map(provider => (
                <div 
                  key={provider.id} 
                  className={`${styles.staffCard} ${styles.interactiveStaffCard}`}
                  onClick={() => setSelectedStaffId(provider.id)}
                >
                  <div className={styles.staffAvatar}>
                    {provider.user?.name.charAt(0).toUpperCase()}
                  </div>
                  <div className={styles.staffInfo} style={{ flex: 1 }}>
                    <h4>{provider.user?.name}</h4>
                    <p>{provider.user?.phone}</p>
                    <p>{provider.user?.email}</p>
                    <span className={`${styles.badge} ${provider.is_active ? styles.badgeActive : styles.badgeInactive}`}>
                      {provider.is_active ? 'Active' : 'Inactive'}
                    </span>
                  </div>
                  <div>
                    <button className={styles.viewInfoButton}>
                      View Info
                    </button>
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <p style={{ color: 'var(--text-body)' }}>No staff members registered.</p>
          )}
        </div>
      )}

      {activeTab === 'Catalog' && (
        <>
          <div className={styles.card}>
            <h2 className={styles.sectionTitle}>Services Offered</h2>
            {salon.services && salon.services.length > 0 ? (
              <div className={styles.servicesGrid}>
                {salon.services.map(service => (
                  <div key={service.id} className={styles.serviceItem}>
                    <div>
                      <div className={styles.serviceCategory}>
                        {service.template?.category?.name || 'Uncategorized'}
                      </div>
                      <div className={styles.serviceName}>
                        {service.template?.name || 'Custom Service'}
                      </div>
                    </div>
                    <div className={styles.serviceMeta}>
                      <span className={styles.serviceDuration}>
                        {service.estimated_duration_minutes || service.template?.estimated_duration_minutes || 0} mins
                      </span>
                      <span className={styles.servicePrice}>
                        ₹{service.price}
                      </span>
                    </div>
                  </div>
                ))}
              </div>
            ) : (
              <p style={{ color: 'var(--text-body)' }}>No services configured.</p>
            )}
          </div>

          <div className={styles.card}>
            <h2 className={styles.sectionTitle}>Combos</h2>
            {salon.combos && salon.combos.length > 0 ? (
              <div className={styles.combosGrid}>
                {salon.combos.map(combo => {
                  const totalPrice = combo.services?.reduce((sum, svc) => sum + Number(svc.pivot?.combo_special_price || 0), 0) || 0;
                  return (
                    <div key={combo.id} className={styles.comboItem}>
                      <div className={styles.comboName}>{combo.name}</div>
                      {combo.services && combo.services.length > 0 && (
                        <div style={{ fontSize: '0.85rem', color: 'var(--text-body)', marginTop: '-4px', marginBottom: '4px' }}>
                          {combo.services.length} services included
                        </div>
                      )}
                      <div className={styles.comboPrice}>₹{totalPrice}</div>
                      {!combo.is_active && <span className={`${styles.badge} ${styles.badgeInactive}`}>Inactive</span>}
                    </div>
                  );
                })}
              </div>
            ) : (
              <p style={{ color: 'var(--text-body)' }}>No combos configured.</p>
            )}
          </div>
        </>
      )}

      {selectedStaffId && typeof id === 'string' && (
        <StaffDetailsModal
          salonId={id}
          providerId={selectedStaffId}
          onClose={() => setSelectedStaffId(null)}
        />
      )}
    </div>
  );
}
