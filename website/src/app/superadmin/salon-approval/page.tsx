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

export default function SalonApprovalQueue() {
  const [salons, setSalons] = useState<Salon[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    async function fetchSalons() {
      try {
        const res = await fetch('http://localhost:8000/api/superadmin/salons/pending');
        if (!res.ok) throw new Error('Failed to fetch salons');
        const json = await res.json();
        if (json.success) {
          setSalons(json.data);
        } else {
          throw new Error(json.message || 'Error loading salons');
        }
      } catch (err: any) {
        setError(err.message);
      } finally {
        setLoading(false);
      }
    }

    fetchSalons();
  }, []);

  return (
    <div className={styles.container}>
      <div className={styles.header}>
        <h1 className={styles.title}>Salon Approval Queue</h1>
        <p className={styles.subtitle}>Review and approve or reject newly submitted salons.</p>
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
                <td colSpan={5} className={styles.emptyState}>Loading...</td>
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
  );
}
