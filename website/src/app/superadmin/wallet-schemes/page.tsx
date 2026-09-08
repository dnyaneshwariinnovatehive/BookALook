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

  /* Purely cosmetic feedback so the page never feels unresponsive. */
  const [coinValueSaved, setCoinValueSaved] = useState(false);
  const [coinValueError, setCoinValueError] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [deletingId, setDeletingId] = useState<string | null>(null);

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

  /* Escape closes the dialog and the page behind it stays put while it is open. */
  useEffect(() => {
    if (!isModalOpen) return;

    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setIsModalOpen(false);
    };

    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    window.addEventListener('keydown', onKeyDown);

    return () => {
      document.body.style.overflow = previousOverflow;
      window.removeEventListener('keydown', onKeyDown);
    };
  }, [isModalOpen]);

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
    setCoinValueError('');
    setCoinValueSaved(false);
    try {
      const res = await fetch('/api/proxy/superadmin/settings/policy', {
        method: 'PUT',
        headers: authHeaders(),
        body: JSON.stringify({ coin_value_inr: Number(coinValueInput) }),
      });
      if (!res.ok) throw new Error('Could not save the coin value.');
      setCoinValue(Number(coinValueInput));
      setCoinValueSaved(true);
      setTimeout(() => setCoinValueSaved(false), 2500);
    } catch (e: any) {
      setCoinValueError(e.message);
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
    setIsSubmitting(true);

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
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleDelete = async (scheme: Scheme) => {
    if (!confirm(`Retire "${scheme.name}"?`)) return;

    setDeletingId(scheme.id);
    try {
      const res = await fetch(`/api/proxy/superadmin/wallet-schemes/${scheme.id}`, {
        method: 'DELETE',
        headers: authHeaders(),
      });
      const data = await res.json();

      if (data.deactivated) alert(data.message);
      fetchData();
    } finally {
      setDeletingId(null);
    }
  };

  const bandLabel = (t: Tier) =>
    t.appointments_to === null
      ? `${t.appointments_from}+ appointments`
      : `${t.appointments_from}–${t.appointments_to} appointments`;

  const liveCount = schemes.filter((s) => s.is_active).length;

  if (isLoading) {
    return (
      <div className={styles.container}>
        <div className={styles.pageHeader}>
          <div>
            <div className={styles.skeleton} style={{ width: 260, height: 30 }} />
            <div className={styles.skeleton} style={{ width: 380, height: 16, marginTop: 10 }} />
          </div>
          <div className={styles.skeleton} style={{ width: 130, height: 40, borderRadius: 999 }} />
        </div>

        <div className={styles.section}>
          <div className={styles.skeletonCard}>
            <div className={styles.skeleton} style={{ width: 120, height: 18 }} />
            <div className={styles.skeleton} style={{ width: '60%', height: 14, marginTop: 10 }} />
            <div className={styles.skeleton} style={{ width: 300, height: 42, marginTop: 18 }} />
          </div>
        </div>

        <div className={styles.grid}>
          {[0, 1, 2].map((i) => (
            <div key={i} className={styles.skeletonCard}>
              <div className={styles.skeleton} style={{ width: '55%', height: 20 }} />
              <div className={styles.skeleton} style={{ width: '85%', height: 14, marginTop: 12 }} />
              <div className={styles.skeleton} style={{ width: '100%', height: 84, marginTop: 16 }} />
              <div className={styles.skeleton} style={{ width: '100%', height: 36, marginTop: 16, borderRadius: 999 }} />
            </div>
          ))}
        </div>
      </div>
    );
  }

  return (
    <div className={styles.container}>
      <header className={styles.pageHeader}>
        <div>
          <h1 className={styles.title}>Wallet &amp; coin rewards</h1>
          <p className={styles.subtitle}>
            Set what a coin is worth and how salons earn coins on completed
            online appointments.
          </p>
        </div>
        <button className={styles.button} onClick={openCreateModal}>
          <PlusIcon />
          New ladder
        </button>
      </header>

      {/* One coin is worth this much everywhere it is spent. */}
      <section className={styles.section}>
        <div className={styles.panel}>
          <div className={styles.panelHeader}>
            <div>
              <h2 className={styles.panelTitle}>
                <span className={styles.panelIcon} aria-hidden="true">
                  <CoinIcon />
                </span>
                Coin value
              </h2>
              <p className={styles.panelSubtitle}>
                What one coin is worth when a salon spends it. Past redemptions
                keep the rate they were made at.
              </p>
            </div>
            <span className={styles.coinCurrent}>
              Currently
              <strong className={styles.coinCurrentValue}>₹{coinValue}</strong>
              per coin
            </span>
          </div>

          <div className={styles.panelBody} style={{ paddingTop: 0 }}>
            {coinValueError && (
              <p className={styles.errorBanner}>
                <AlertIcon />
                {coinValueError}
              </p>
            )}

            <div className={styles.coinRow}>
              <div className={styles.inputWrap}>
                <span className={styles.currencyPrefix} aria-hidden="true">₹</span>
                <input
                  className={styles.coinInput}
                  type="number"
                  step="0.01"
                  min="0"
                  aria-label="Coin value in rupees"
                  value={coinValueInput}
                  onChange={(e) => setCoinValueInput(e.target.value)}
                />
              </div>
              <button
                className={styles.button}
                onClick={saveCoinValue}
                disabled={savingCoinValue || coinValueInput === String(coinValue)}
              >
                {savingCoinValue ? 'Saving…' : 'Save'}
              </button>
              {coinValueSaved && (
                <span className={styles.savedFlag} role="status">
                  <CheckIcon />
                  Saved
                </span>
              )}
            </div>
          </div>
        </div>
      </section>

      <section className={styles.section}>
        <div className={styles.panelHeader} style={{ padding: '0 0 16px' }}>
          <div>
            <h2 className={styles.panelTitle}>
              Reward ladders
              <span className={styles.badge + ' ' + styles.badgeClosed}>
                {schemes.length} total · {liveCount} active
              </span>
            </h2>
            <p className={styles.panelSubtitle}>
              Coins are earned on completed online appointments. When several
              ladders are live, the newest one applies.
            </p>
          </div>
        </div>

        <div className={styles.grid}>
          {schemes.length === 0 && (
            <div className={styles.emptyState}>
              <span className={styles.emptyIcon} aria-hidden="true">
                <LadderIcon />
              </span>
              <h3 className={styles.emptyTitle}>No ladders yet</h3>
              <p className={styles.emptyText}>
                Create one to start rewarding salons with coins for the
                appointments they complete.
              </p>
              <button className={styles.button} onClick={openCreateModal}>
                <PlusIcon />
                New ladder
              </button>
            </div>
          )}

          {schemes.map((scheme) => (
            <article
              key={scheme.id}
              className={
                scheme.id === inForceId
                  ? `${styles.card} ${styles.cardInForce}`
                  : styles.card
              }
            >
              <div className={styles.cardTop}>
                <h3 className={styles.schemeName}>{scheme.name}</h3>
                {scheme.id === inForceId ? (
                  <span className={`${styles.badge} ${styles.badgeInForce}`}>
                    <span className={styles.dot} /> In force
                  </span>
                ) : scheme.is_active ? (
                  <span className={`${styles.badge} ${styles.badgeActive}`}>Active</span>
                ) : (
                  <span className={`${styles.badge} ${styles.badgeClosed}`}>Closed</span>
                )}
              </div>

              {scheme.description && (
                <p className={styles.schemeDescription}>{scheme.description}</p>
              )}

              <p className={styles.modeRow}>
                <GiftIcon />
                {scheme.award_mode === 'per_appointment'
                  ? 'Each appointment in a band earns that band’s coins'
                  : 'A lump is awarded when a band is completed'}
              </p>

              <div className={styles.ladderLabel}>Bands</div>
              <div className={styles.ladder}>
                {scheme.tiers.map((t, i) => (
                  <div key={i} className={styles.ladderRow}>
                    <span className={styles.ladderBand}>{bandLabel(t)}</span>
                    <span className={styles.ladderCoins}>
                      <span className={styles.coinChip} aria-hidden="true" />
                      {t.coins_awarded}
                      {t.coins_awarded === 1 ? ' coin' : ' coins'}
                    </span>
                  </div>
                ))}
              </div>

              {(scheme.starts_on || scheme.ends_on) && (
                <p className={styles.dateRow}>
                  <CalendarIcon />
                  {scheme.starts_on ?? '…'} → {scheme.ends_on ?? '…'}
                </p>
              )}

              <div className={styles.cardActions}>
                <button className={styles.ghostButton} onClick={() => openEditModal(scheme)}>
                  <PencilIcon />
                  Edit
                </button>
                <button
                  className={styles.dangerButton}
                  onClick={() => handleDelete(scheme)}
                  disabled={deletingId === scheme.id}
                >
                  {deletingId === scheme.id ? 'Retiring…' : 'Retire'}
                </button>
              </div>
            </article>
          ))}
        </div>
      </section>

      {isModalOpen && (
        <div
          className={styles.modalOverlay}
          onMouseDown={(e) => {
            if (e.target === e.currentTarget) setIsModalOpen(false);
          }}
        >
          <div
            className={styles.modalContent}
            role="dialog"
            aria-modal="true"
            aria-labelledby="ladder-dialog-title"
          >
            <div className={styles.modalHeader}>
              <h2 className={styles.modalTitle} id="ladder-dialog-title">
                {editingId ? 'Edit ladder' : 'New ladder'}
              </h2>
              <button
                type="button"
                className={styles.modalClose}
                onClick={() => setIsModalOpen(false)}
                aria-label="Close"
              >
                <CloseIcon />
              </button>
            </div>

            <form onSubmit={handleSubmit} style={{ display: 'contents' }}>
              <div className={styles.modalBody}>
                {error && (
                  <p className={styles.errorBanner}>
                    <AlertIcon />
                    {error}
                  </p>
                )}

                <div className={styles.formGroup}>
                  <label htmlFor="ladder-name">Name</label>
                  <input
                    id="ladder-name"
                    value={formData.name}
                    onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                    required
                    placeholder="e.g. Launch rewards 2026"
                  />
                </div>

                <div className={styles.formGroup}>
                  <label htmlFor="ladder-description">
                    Description <span className={styles.optional}>(optional)</span>
                  </label>
                  <input
                    id="ladder-description"
                    value={formData.description}
                    onChange={(e) => setFormData({ ...formData, description: e.target.value })}
                    placeholder="A short note for other admins"
                  />
                </div>

                <div className={styles.formGroup}>
                  <label htmlFor="ladder-mode">How coins are awarded</label>
                  <select
                    id="ladder-mode"
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

                <div className={styles.formRow}>
                  <div className={styles.formGroup}>
                    <label htmlFor="ladder-starts">
                      Starts on <span className={styles.optional}>(optional)</span>
                    </label>
                    <input
                      id="ladder-starts"
                      type="date"
                      value={formData.starts_on}
                      onChange={(e) => setFormData({ ...formData, starts_on: e.target.value })}
                    />
                  </div>
                  <div className={styles.formGroup}>
                    <label htmlFor="ladder-ends">
                      Ends on <span className={styles.optional}>(optional)</span>
                    </label>
                    <input
                      id="ladder-ends"
                      type="date"
                      value={formData.ends_on}
                      onChange={(e) => setFormData({ ...formData, ends_on: e.target.value })}
                    />
                  </div>
                </div>

                <label className={styles.switchRow}>
                  <span>
                    <span className={styles.switchText}>Active</span>
                    <span className={styles.switchHint}>
                      Inactive ladders award nothing and stay on file.
                    </span>
                  </span>
                  <span className={styles.switch}>
                    <input
                      type="checkbox"
                      checked={formData.is_active}
                      onChange={(e) => setFormData({ ...formData, is_active: e.target.checked })}
                    />
                    <span className={styles.switchTrack} />
                  </span>
                </label>

                <div className={styles.editorSection}>
                  <h3 className={styles.editorTitle}>Ladder</h3>
                  <p className={styles.hint}>
                    Bands must run back to back starting at 1. Leave the last
                    band&apos;s &quot;to&quot; empty so it runs forever.
                  </p>

                  <div className={styles.tierHead}>
                    <span>From</span>
                    <span />
                    <span>To</span>
                    <span>Coins</span>
                    <span />
                  </div>

                  {formData.tiers.map((tier, index) => (
                    <div key={index} className={styles.tierRow}>
                      <label className={`${styles.tierField} ${styles.tierFrom}`}>
                        <span className={styles.tierFieldLabel}>From</span>
                        <input
                          type="number"
                          min={1}
                          value={tier.appointments_from}
                          onChange={(e) => updateTier(index, 'appointments_from', e.target.value)}
                          placeholder="From"
                          aria-label={`Band ${index + 1} first appointment`}
                          title="First appointment in this band"
                          readOnly={index > 0}
                        />
                      </label>
                      <span className={styles.tierArrow} aria-hidden="true">→</span>
                      <label className={`${styles.tierField} ${styles.tierTo}`}>
                        <span className={styles.tierFieldLabel}>To</span>
                        <input
                          type="number"
                          min={1}
                          value={tier.appointments_to ?? ''}
                          onChange={(e) => updateTier(index, 'appointments_to', e.target.value)}
                          placeholder="onwards"
                          aria-label={`Band ${index + 1} last appointment`}
                          title="Last appointment in this band; empty means no end"
                        />
                      </label>
                      <label className={`${styles.tierField} ${styles.tierCoins}`}>
                        <span className={styles.tierFieldLabel}>Coins</span>
                        <input
                          type="number"
                          min={0}
                          value={tier.coins_awarded}
                          onChange={(e) => updateTier(index, 'coins_awarded', e.target.value)}
                          placeholder="Coins"
                          aria-label={`Band ${index + 1} coins awarded`}
                          title="Coins this band awards"
                        />
                      </label>
                      <button
                        type="button"
                        className={styles.tierRemove}
                        onClick={() => removeTier(index)}
                        disabled={formData.tiers.length === 1}
                        aria-label={`Remove band ${index + 1}`}
                        title="Remove this band"
                      >
                        <TrashIcon />
                      </button>
                    </div>
                  ))}

                  <button type="button" className={styles.addBand} onClick={addTier}>
                    <PlusIcon />
                    Add band
                  </button>
                </div>
              </div>

              <div className={styles.modalFooter}>
                <button
                  type="button"
                  className={styles.cancelButton}
                  onClick={() => setIsModalOpen(false)}
                >
                  Cancel
                </button>
                <button type="submit" className={styles.primaryButton} disabled={isSubmitting}>
                  {isSubmitting ? 'Saving…' : 'Save ladder'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}

/* ------------------------------------------------------------------ icons */

const iconProps = {
  width: 16,
  height: 16,
  viewBox: '0 0 24 24',
  fill: 'none',
  stroke: 'currentColor',
  strokeWidth: 2,
  strokeLinecap: 'round' as const,
  strokeLinejoin: 'round' as const,
};

const PlusIcon = () => (
  <svg {...iconProps} aria-hidden="true">
    <path d="M12 5v14M5 12h14" />
  </svg>
);

const CheckIcon = () => (
  <svg {...iconProps} width={14} height={14} aria-hidden="true">
    <path d="M20 6 9 17l-5-5" />
  </svg>
);

const CloseIcon = () => (
  <svg {...iconProps} width={18} height={18} aria-hidden="true">
    <path d="M18 6 6 18M6 6l12 12" />
  </svg>
);

const AlertIcon = () => (
  <svg {...iconProps} width={15} height={15} aria-hidden="true">
    <circle cx="12" cy="12" r="10" />
    <path d="M12 8v4M12 16h.01" />
  </svg>
);

const CoinIcon = () => (
  <svg {...iconProps} width={18} height={18} aria-hidden="true">
    <circle cx="12" cy="12" r="9" />
    <path d="M14.5 8.5h-5M14.5 12h-5M11 15.5 9.5 12M9.5 8.5c3 0 3 3.5 0 3.5" />
  </svg>
);

const GiftIcon = () => (
  <svg {...iconProps} width={15} height={15} aria-hidden="true">
    <rect x="3" y="8" width="18" height="4" rx="1" />
    <path d="M12 8v13M5 12v7a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-7" />
    <path d="M12 8H7.5a2.5 2.5 0 0 1 0-5C11 3 12 8 12 8zM12 8h4.5a2.5 2.5 0 0 0 0-5C13 3 12 8 12 8z" />
  </svg>
);

const CalendarIcon = () => (
  <svg {...iconProps} width={14} height={14} aria-hidden="true">
    <rect x="3" y="5" width="18" height="16" rx="2" />
    <path d="M16 3v4M8 3v4M3 11h18" />
  </svg>
);

const PencilIcon = () => (
  <svg {...iconProps} width={15} height={15} aria-hidden="true">
    <path d="M12 20h9" />
    <path d="M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4Z" />
  </svg>
);

const TrashIcon = () => (
  <svg {...iconProps} width={15} height={15} aria-hidden="true">
    <path d="M3 6h18M8 6V4a1 1 0 0 1 1-1h6a1 1 0 0 1 1 1v2M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6" />
  </svg>
);

const LadderIcon = () => (
  <svg {...iconProps} width={26} height={26} aria-hidden="true">
    <path d="M6 3v18M18 3v18M6 8h12M6 13h12M6 18h12" />
  </svg>
);
