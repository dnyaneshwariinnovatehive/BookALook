'use client';

import { useState, useEffect } from 'react';
import styles from './page.module.css';

interface Tier {
  appointments_from: number;
  appointments_to: number | null;
  coins_awarded: number;
  label?: string;
}

interface Scheme {
  id: string;
  name: string;
  description: string | null;
  award_mode: string;
  is_active: boolean;
  starts_on: string | null;
  ends_on: string | null;
  tiers: Tier[];
}

const emptyLadder = (): Tier[] => [
  { appointments_from: 1, appointments_to: 250, coins_awarded: 1 },
  { appointments_from: 251, appointments_to: null, coins_awarded: 2 },
];

export default function WalletSchemesPage() {
  const [schemes, setSchemes] = useState<Scheme[]>([]);
  const [coinValue, setCoinValue] = useState<number>(0);
  const [coinValueInput, setCoinValueInput] = useState('');
  const [inForceId, setInForceId] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [error, setError] = useState('');
  const [savingCoinValue, setSavingCoinValue] = useState(false);

  const [formData, setFormData] = useState({
    name: '',
    description: '',
    award_mode: 'per_appointment',
    is_active: true,
    starts_on: '',
    ends_on: '',
    tiers: emptyLadder(),
  });

  useEffect(() => {
    fetchData();
  }, []);

  const authHeaders = (): Record<string, string> => {
    const token = localStorage.getItem('sa_token');
    return {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    };
  };

  const fetchData = async () => {
    try {
      const res = await fetch('/api/proxy/superadmin/wallet-schemes', { headers: authHeaders() });
      const data = await res.json();
      if (data.success) {
        setSchemes(data.schemes);
        setCoinValue(data.coin_value_inr ?? 0);
        setCoinValueInput(String(data.coin_value_inr ?? 0));
        setInForceId(data.scheme_in_force_id ?? null);
      }
    } catch (e) {
      console.error(e);
    } finally {
      setIsLoading(false);
    }
  };

  const saveCoinValue = async () => {
    setSavingCoinValue(true);
    setError('');
    try {
      const res = await fetch('/api/proxy/superadmin/settings/policy', {
        method: 'PUT',
        headers: authHeaders(),
        body: JSON.stringify({ coin_value_inr: Number(coinValueInput) }),
      });
      if (!res.ok) throw new Error('Could not save the coin value.');
      setCoinValue(Number(coinValueInput));
    } catch (e: any) {
      setError(e.message);
    } finally {
      setSavingCoinValue(false);
    }
  };

  const openCreateModal = () => {
    setEditingId(null);
    setError('');
    setFormData({
      name: '',
      description: '',
      award_mode: 'per_appointment',
      is_active: true,
      starts_on: '',
      ends_on: '',
      tiers: emptyLadder(),
    });
    setIsModalOpen(true);
  };

  const openEditModal = (scheme: Scheme) => {
    setEditingId(scheme.id);
    setError('');
    setFormData({
      name: scheme.name,
      description: scheme.description ?? '',
      award_mode: scheme.award_mode,
      is_active: scheme.is_active,
      starts_on: scheme.starts_on ?? '',
      ends_on: scheme.ends_on ?? '',
      tiers: scheme.tiers.length ? scheme.tiers : emptyLadder(),
    });
    setIsModalOpen(true);
  };

  /* Rungs must run back to back, so adding one starts where the last ended. */
  const addTier = () => {
    const tiers = [...formData.tiers];
    const last = tiers[tiers.length - 1];
    const from = (last?.appointments_to ?? last?.appointments_from ?? 0) + 1;

    // Only the final rung may be open-ended; close the old one first.
    if (last && last.appointments_to === null) {
      last.appointments_to = last.appointments_from + 99;
    }

    tiers.push({
      appointments_from: last ? (last.appointments_to ?? 0) + 1 : from,
      appointments_to: null,
      coins_awarded: (last?.coins_awarded ?? 0) + 1,
    });
    setFormData({ ...formData, tiers });
  };

  const removeTier = (index: number) => {
    if (formData.tiers.length === 1) return;
    const tiers = formData.tiers.filter((_, i) => i !== index);
    // The remaining last rung runs forever.
    tiers[tiers.length - 1].appointments_to = null;
    setFormData({ ...formData, tiers });
  };

  const updateTier = (index: number, field: keyof Tier, raw: string) => {
    const tiers = [...formData.tiers];
    const value = raw === '' ? null : Number(raw);

    if (field === 'appointments_to') {
      tiers[index].appointments_to = value;
      // Keep the next rung starting immediately after this one.
      if (value !== null && tiers[index + 1]) {
        tiers[index + 1].appointments_from = value + 1;
      }
    } else if (field === 'coins_awarded') {
      tiers[index].coins_awarded = value ?? 0;
    } else if (field === 'appointments_from') {
      tiers[index].appointments_from = value ?? 1;
    }

    setFormData({ ...formData, tiers });
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');

    const payload = {
      name: formData.name,
      description: formData.description || null,
      award_mode: formData.award_mode,
      is_active: formData.is_active,
      starts_on: formData.starts_on || null,
      ends_on: formData.ends_on || null,
      tiers: formData.tiers.map((t) => ({
        appointments_from: Number(t.appointments_from),
        appointments_to: t.appointments_to === null ? null : Number(t.appointments_to),
        coins_awarded: Number(t.coins_awarded),
      })),
    };

    const url = editingId
      ? `/api/proxy/superadmin/wallet-schemes/${editingId}`
      : '/api/proxy/superadmin/wallet-schemes';

    try {
      const res = await fetch(url, {
        method: editingId ? 'PUT' : 'POST',
        headers: authHeaders(),
        body: JSON.stringify(payload),
      });

      const data = await res.json();

      if (!res.ok) {
        throw new Error(
          data.message ||
            (data.errors
              ? Object.values(data.errors).flat().join('\n')
              : 'Could not save the scheme.')
        );
      }

      setIsModalOpen(false);
      fetchData();
    } catch (e: any) {
      setError(e.message);
    }
  };

  const handleDelete = async (scheme: Scheme) => {
    if (!confirm(`Retire "${scheme.name}"?`)) return;

    const res = await fetch(`/api/proxy/superadmin/wallet-schemes/${scheme.id}`, {
      method: 'DELETE',
      headers: authHeaders(),
    });
    const data = await res.json();

    if (data.deactivated) alert(data.message);
    fetchData();
  };

  const tierSummary = (scheme: Scheme) =>
    scheme.tiers
      .map((t) =>
        t.appointments_to === null
          ? `${t.appointments_from}+ → ${t.coins_awarded}`
          : `${t.appointments_from}–${t.appointments_to} → ${t.coins_awarded}`
      )
      .join('  ·  ');

  if (isLoading) return <div className={styles.container}>Loading…</div>;

  return (
    <div className={styles.container}>
      <h1 className={styles.title}>Wallet &amp; coin rewards</h1>

      {/* One coin is worth this much everywhere it is spent. */}
      <div className={styles.section}>
        <div className={styles.card}>
          <h3 style={{ marginTop: 0 }}>Coin value</h3>
          <p style={{ color: '#6B7280', fontSize: 14, marginTop: 4 }}>
            What one coin is worth when a salon spends it. Past redemptions keep
            the rate they were made at.
          </p>
          <div style={{ display: 'flex', gap: 10, alignItems: 'center', marginTop: 12 }}>
            <span style={{ fontSize: 18 }}>₹</span>
            <input
              type="number"
              step="0.01"
              min="0"
              value={coinValueInput}
              onChange={(e) => setCoinValueInput(e.target.value)}
              style={{ width: 140, padding: '8px 10px', border: '1px solid #D1D5DB', borderRadius: 8 }}
            />
            <button
              className={styles.button}
              onClick={saveCoinValue}
              disabled={savingCoinValue || coinValueInput === String(coinValue)}
            >
              {savingCoinValue ? 'Saving…' : 'Save'}
            </button>
            <span style={{ color: '#6B7280', fontSize: 13 }}>
              currently ₹{coinValue} per coin
            </span>
          </div>
        </div>
      </div>

      <div className={styles.section}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <div>
            <h3 style={{ margin: 0 }}>Reward ladders</h3>
            <p style={{ color: '#6B7280', fontSize: 14, marginTop: 4 }}>
              Coins are earned on completed online appointments. When several
              ladders are live, the newest one applies.
            </p>
          </div>
          <button className={styles.button} onClick={openCreateModal}>
            New ladder
          </button>
        </div>

        <div className={styles.grid} style={{ marginTop: 16 }}>
          {schemes.length === 0 && (
            <div className={styles.card}>No ladders yet. Create one to start rewarding salons.</div>
          )}

          {schemes.map((scheme) => (
            <div key={scheme.id} className={styles.card}>
              <div style={{ display: 'flex', justifyContent: 'space-between', gap: 8 }}>
                <h3 style={{ margin: 0 }}>{scheme.name}</h3>
                {scheme.id === inForceId ? (
                  <span style={badge('#DCFCE7', '#15803D')}>In force</span>
                ) : scheme.is_active ? (
                  <span style={badge('#E0F2FE', '#0369A1')}>Active</span>
                ) : (
                  <span style={badge('#F3F4F6', '#374151')}>Closed</span>
                )}
              </div>

              {scheme.description && (
                <p style={{ color: '#6B7280', fontSize: 13 }}>{scheme.description}</p>
              )}

              <p style={{ fontSize: 13, color: '#374151', marginBottom: 4 }}>
                {scheme.award_mode === 'per_appointment'
                  ? 'Each appointment in a band earns that band’s coins'
                  : 'A lump is awarded when a band is completed'}
              </p>

              <p style={{ fontFamily: 'ui-monospace, monospace', fontSize: 12, color: '#111827' }}>
                {tierSummary(scheme)}
              </p>

              {(scheme.starts_on || scheme.ends_on) && (
                <p style={{ fontSize: 12, color: '#6B7280' }}>
                  {scheme.starts_on ?? '…'} → {scheme.ends_on ?? '…'}
                </p>
              )}

              <div style={{ display: 'flex', gap: 8, marginTop: 12 }}>
                <button className={styles.button} onClick={() => openEditModal(scheme)}>
                  Edit
                </button>
                <button className={styles.cancelButton} onClick={() => handleDelete(scheme)}>
                  Retire
                </button>
              </div>
            </div>
          ))}
        </div>
      </div>

      {isModalOpen && (
        <div className={styles.modalOverlay}>
          <div className={styles.modalContent}>
            <h2>{editingId ? 'Edit ladder' : 'New ladder'}</h2>

            {error && (
              <p style={{ color: '#DC2626', whiteSpace: 'pre-line', fontSize: 13 }}>{error}</p>
            )}

            <form onSubmit={handleSubmit}>
              <div className={styles.formGroup}>
                <label>Name</label>
                <input
                  value={formData.name}
                  onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                  required
                  placeholder="e.g. Launch rewards 2026"
                />
              </div>

              <div className={styles.formGroup}>
                <label>Description (optional)</label>
                <input
                  value={formData.description}
                  onChange={(e) => setFormData({ ...formData, description: e.target.value })}
                />
              </div>

              <div className={styles.formGroup}>
                <label>How coins are awarded</label>
                <select
                  value={formData.award_mode}
                  onChange={(e) => setFormData({ ...formData, award_mode: e.target.value })}
                >
                  <option value="per_appointment">
                    Every appointment in a band earns that band&apos;s coins
                  </option>
                  <option value="on_completion">
                    One lump when a band is completed
                  </option>
                </select>
              </div>

              <div style={{ display: 'flex', gap: 12 }}>
                <div className={styles.formGroup} style={{ flex: 1 }}>
                  <label>Starts on (optional)</label>
                  <input
                    type="date"
                    value={formData.starts_on}
                    onChange={(e) => setFormData({ ...formData, starts_on: e.target.value })}
                  />
                </div>
                <div className={styles.formGroup} style={{ flex: 1 }}>
                  <label>Ends on (optional)</label>
                  <input
                    type="date"
                    value={formData.ends_on}
                    onChange={(e) => setFormData({ ...formData, ends_on: e.target.value })}
                  />
                </div>
              </div>

              <div className={styles.formGroup}>
                <label>
                  <input
                    type="checkbox"
                    checked={formData.is_active}
                    onChange={(e) => setFormData({ ...formData, is_active: e.target.checked })}
                  />{' '}
                  Active
                </label>
              </div>

              <h4 style={{ marginBottom: 4 }}>Ladder</h4>
              <p style={{ color: '#6B7280', fontSize: 12, marginTop: 0 }}>
                Bands must run back to back starting at 1. Leave the last band&apos;s
                &quot;to&quot; empty so it runs forever.
              </p>

              {formData.tiers.map((tier, index) => (
                <div key={index} className={styles.tierRow}>
                  <input
                    type="number"
                    min={1}
                    value={tier.appointments_from}
                    onChange={(e) => updateTier(index, 'appointments_from', e.target.value)}
                    placeholder="From"
                    title="First appointment in this band"
                    readOnly={index > 0}
                  />
                  <span style={{ color: '#6B7280' }}>→</span>
                  <input
                    type="number"
                    min={1}
                    value={tier.appointments_to ?? ''}
                    onChange={(e) => updateTier(index, 'appointments_to', e.target.value)}
                    placeholder="onwards"
                    title="Last appointment in this band; empty means no end"
                  />
                  <input
                    type="number"
                    min={0}
                    value={tier.coins_awarded}
                    onChange={(e) => updateTier(index, 'coins_awarded', e.target.value)}
                    placeholder="Coins"
                    title="Coins this band awards"
                  />
                  <button type="button" className={styles.cancelButton} onClick={() => removeTier(index)}>
                    ✕
                  </button>
                </div>
              ))}

              <button type="button" className={styles.button} onClick={addTier}>
                Add band
              </button>

              <div className={styles.formActions}>
                <button type="button" className={styles.cancelButton} onClick={() => setIsModalOpen(false)}>
                  Cancel
                </button>
                <button type="submit" className={styles.primaryButton}>
                  Save ladder
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}

const badge = (bg: string, fg: string): React.CSSProperties => ({
  backgroundColor: bg,
  color: fg,
  padding: '2px 10px',
  borderRadius: 12,
  fontSize: 11,
  fontWeight: 700,
  height: 'fit-content',
  whiteSpace: 'nowrap',
});
