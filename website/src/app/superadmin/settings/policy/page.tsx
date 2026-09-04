'use client';

import { useState, useEffect } from 'react';
import styles from './page.module.css';

export default function PlatformPolicyPage() {
  const [warningDays, setWarningDays] = useState('3');
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);

  useEffect(() => {
    fetchData();
  }, []);

  const fetchData = async () => {
    try {
      const res = await fetch('/api/superadmin/settings/policy');
      const data = await res.json();
      if (data.success) {
        setWarningDays(data.settings.subscription_expiry_warning_days?.toString() || '3');
      }
    } catch (e) {
      console.error(e);
    } finally {
      setIsLoading(false);
    }
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsSaving(true);
    try {
      const res = await fetch('/api/superadmin/settings/policy', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          subscription_expiry_warning_days: parseInt(warningDays, 10)
        })
      });
      if (res.ok) {
        alert('Settings saved successfully');
      } else {
        alert('Failed to save settings');
      }
    } catch (e) {
      console.error(e);
    } finally {
      setIsSaving(false);
    }
  };

  if (isLoading) return <div>Loading...</div>;

  return (
    <div className={styles.container}>
      <h1 className={styles.title}>Platform Policy Settings</h1>
      
      <div className={styles.card}>
        <form onSubmit={handleSave}>
          <div className={styles.formGroup}>
            <label>Subscription Expiry Warning Window (Days)</label>
            <input 
              type="number" 
              min="1"
              max="30"
              value={warningDays}
              onChange={(e) => setWarningDays(e.target.value)}
              required
            />
            <p style={{ marginTop: '8px', fontSize: '14px', color: 'var(--text-body)' }}>
              Number of days before a salon's subscription expires to show the warning banner in the Partner App.
            </p>
          </div>
          
          <button type="submit" className={styles.button} disabled={isSaving}>
            {isSaving ? 'Saving...' : 'Save Settings'}
          </button>
        </form>
      </div>
    </div>
  );
}
