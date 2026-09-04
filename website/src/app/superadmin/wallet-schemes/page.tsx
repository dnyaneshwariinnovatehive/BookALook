'use client';

import { useState, useEffect } from 'react';
import styles from './page.module.css';

export default function WalletSchemesPage() {
  const [schemes, setSchemes] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);

  const [formData, setFormData] = useState({
    name: '',
    coin_value: '1',
    is_active: true,
    tiers: [{ milestone_type: 'appointment_completed', milestone_value: 1, reward_coins: 1 }]
  });

  useEffect(() => {
    fetchData();
  }, []);

  const fetchData = async () => {
    try {
      const res = await fetch('/api/superadmin/wallet-schemes');
      const data = await res.json();
      if (data.success) {
        setSchemes(data.schemes);
      }
    } catch (e) {
      console.error(e);
    } finally {
      setIsLoading(false);
    }
  };

  const openCreateModal = () => {
    setEditingId(null);
    setFormData({
      name: '',
      coin_value: '1',
      is_active: true,
      tiers: [{ milestone_type: 'appointment_completed', milestone_value: 1, reward_coins: 1 }]
    });
    setIsModalOpen(true);
  };

  const openEditModal = (scheme: any) => {
    setEditingId(scheme.id);
    setFormData({
      name: scheme.name,
      coin_value: scheme.coin_value.toString(),
      is_active: scheme.is_active,
      tiers: scheme.tiers.length ? scheme.tiers : [{ milestone_type: 'appointment_completed', milestone_value: 1, reward_coins: 1 }]
    });
    setIsModalOpen(true);
  };

  const addTier = () => {
    setFormData({
      ...formData,
      tiers: [...formData.tiers, { milestone_type: 'appointment_completed', milestone_value: 10, reward_coins: 10 }]
    });
  };

  const removeTier = (index: number) => {
    const newTiers = [...formData.tiers];
    newTiers.splice(index, 1);
    setFormData({ ...formData, tiers: newTiers });
  };

  const updateTier = (index: number, field: string, value: any) => {
    const newTiers = [...formData.tiers];
    newTiers[index] = { ...newTiers[index], [field]: value };
    setFormData({ ...formData, tiers: newTiers });
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      const url = editingId 
        ? `/api/superadmin/wallet-schemes/${editingId}`
        : `/api/superadmin/wallet-schemes`;
      const method = editingId ? 'PUT' : 'POST';

      const res = await fetch(url, {
        method,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(formData)
      });
      if (res.ok) {
        setIsModalOpen(false);
        fetchData();
        alert(`Scheme ${editingId ? 'updated' : 'created'} successfully`);
      }
    } catch (e) {
      console.error(e);
    }
  };

  if (isLoading) return <div>Loading...</div>;

  return (
    <div className={styles.container}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <h1 className={styles.title}>Wallet Scheme Management</h1>
        <button className={styles.button} onClick={openCreateModal}>+ Create Scheme</button>
      </div>
      
      <div className={styles.grid}>
        {schemes.map(scheme => (
          <div key={scheme.id} className={styles.card}>
            <h3>{scheme.name}</h3>
            <p><strong>Coin Value:</strong> ₹{scheme.coin_value}</p>
            <p><strong>Status:</strong> {scheme.is_active ? 'Active' : 'Inactive'}</p>
            <div style={{ marginTop: '16px' }}>
              <h4>Reward Tiers</h4>
              <ul style={{ paddingLeft: '20px', marginTop: '8px', color: 'var(--text-body)' }}>
                {scheme.tiers.map((t: any) => (
                  <li key={t.id}>{t.milestone_value} {t.milestone_type} = {t.reward_coins} Coins</li>
                ))}
              </ul>
            </div>
            
            <div style={{ display: 'flex', gap: '8px', marginTop: '24px' }}>
              <button className={styles.button} onClick={() => openEditModal(scheme)}>Edit</button>
            </div>
          </div>
        ))}
      </div>

      {isModalOpen && (
        <div className={styles.modalOverlay}>
          <div className={styles.modalContent}>
            <h3>{editingId ? 'Edit' : 'Create'} Wallet Scheme</h3>
            <form onSubmit={handleSave} style={{ marginTop: '24px' }}>
              <div className={styles.formGroup}>
                <label>Scheme Name</label>
                <input 
                  type="text" 
                  value={formData.name}
                  onChange={(e) => setFormData({...formData, name: e.target.value})}
                  required
                />
              </div>
              <div className={styles.formGroup}>
                <label>Value of 1 Coin (₹)</label>
                <input 
                  type="number" 
                  step="0.01"
                  min="0"
                  value={formData.coin_value}
                  onChange={(e) => setFormData({...formData, coin_value: e.target.value})}
                  required
                />
              </div>
              <div className={styles.formGroup}>
                <label>
                  <input 
                    type="checkbox" 
                    checked={formData.is_active}
                    onChange={(e) => setFormData({...formData, is_active: e.target.checked})}
                    style={{width: 'auto', marginRight: '8px'}}
                  />
                  Is Active
                </label>
              </div>

              <div style={{ marginTop: '24px', marginBottom: '16px' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '12px' }}>
                  <h4 style={{ margin: 0 }}>Reward Ladder (Tiers)</h4>
                  <button type="button" onClick={addTier} style={{ fontSize: '12px', padding: '4px 8px' }} className={styles.cancelButton}>+ Add Tier</button>
                </div>
                
                {formData.tiers.map((tier, index) => (
                  <div key={index} className={styles.tierRow}>
                    <div className={styles.formGroup} style={{ marginBottom: 0, flex: 2 }}>
                      <label style={{ fontSize: '12px' }}>Milestone Type</label>
                      <select 
                        value={tier.milestone_type} 
                        onChange={(e) => updateTier(index, 'milestone_type', e.target.value)}
                      >
                        <option value="appointment_completed">Appointments Completed</option>
                        <option value="revenue_reached">Revenue Reached</option>
                      </select>
                    </div>
                    <div className={styles.formGroup} style={{ marginBottom: 0, flex: 1 }}>
                      <label style={{ fontSize: '12px' }}>Value</label>
                      <input 
                        type="number" 
                        value={tier.milestone_value}
                        onChange={(e) => updateTier(index, 'milestone_value', parseInt(e.target.value) || 0)}
                        required
                      />
                    </div>
                    <div className={styles.formGroup} style={{ marginBottom: 0, flex: 1 }}>
                      <label style={{ fontSize: '12px' }}>Coins</label>
                      <input 
                        type="number" 
                        value={tier.reward_coins}
                        onChange={(e) => updateTier(index, 'reward_coins', parseInt(e.target.value) || 0)}
                        required
                      />
                    </div>
                    <button type="button" onClick={() => removeTier(index)} style={{ padding: '8px', backgroundColor: 'transparent', border: 'none', cursor: 'pointer', color: 'red' }}>✕</button>
                  </div>
                ))}
              </div>

              <div className={styles.formActions}>
                <button type="submit" className={styles.primaryButton}>Save Scheme</button>
                <button type="button" onClick={() => setIsModalOpen(false)} className={styles.cancelButton}>Cancel</button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
