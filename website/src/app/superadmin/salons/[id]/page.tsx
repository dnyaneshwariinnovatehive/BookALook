'use client';

import { useEffect, useState } from 'react';
import { useParams } from 'next/navigation';
import Link from 'next/link';
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
  combos?: { id: string; name: string; total_price: number; is_active: boolean }[];
}

export default function SalonDirectoryDetail() {
  const params = useParams();
  const { id } = params;
  
  const [salon, setSalon] = useState<Salon | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    async function fetchSalon() {
      try {
        const res = await fetch(`http://localhost:8000/api/superadmin/salons/${id}`);
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
              <p style={{ color: '#64748b' }}>No admin information found.</p>
            )}
          </div>
        </div>
      </div>

      {/* Staff Directory */}
      <div className={styles.card} style={{ marginTop: '24px' }}>
        <h2 className={styles.sectionTitle}>Staff Directory</h2>
        {salon.providers && salon.providers.length > 0 ? (
          <div className={styles.staffGrid}>
            {salon.providers.map(provider => (
              <div key={provider.id} className={styles.staffCard}>
                <div className={styles.staffAvatar}>
                  {provider.user?.name.charAt(0).toUpperCase()}
                </div>
                <div className={styles.staffInfo}>
                  <h4>{provider.user?.name}</h4>
                  <p>{provider.user?.phone}</p>
                  <p>{provider.user?.email}</p>
                  <span className={`${styles.badge} ${provider.is_active ? styles.badgeActive : styles.badgeInactive}`}>
                    {provider.is_active ? 'Active' : 'Inactive'}
                  </span>
                </div>
              </div>
            ))}
          </div>
        ) : (
          <p style={{ color: '#64748b' }}>No staff members registered.</p>
        )}
      </div>

      {/* Services Offered */}
      <div className={styles.card} style={{ marginTop: '24px' }}>
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
          <p style={{ color: '#64748b' }}>No services configured.</p>
        )}
      </div>

      {/* Combos */}
      <div className={styles.card} style={{ marginTop: '24px' }}>
        <h2 className={styles.sectionTitle}>Combos</h2>
        {salon.combos && salon.combos.length > 0 ? (
          <div className={styles.combosGrid}>
            {salon.combos.map(combo => (
              <div key={combo.id} className={styles.comboItem}>
                <div className={styles.comboName}>{combo.name}</div>
                <div className={styles.comboPrice}>₹{combo.total_price}</div>
                {!combo.is_active && <span className={`${styles.badge} ${styles.badgeInactive}`}>Inactive</span>}
              </div>
            ))}
          </div>
        ) : (
          <p style={{ color: '#64748b' }}>No combos configured.</p>
        )}
      </div>
    </div>
  );
}
