'use client';

import { useState, useEffect } from 'react';
import styles from './page.module.css';

/**
 * How every salon pays to trade.
 *
 * Two arrangements and they are not interchangeable. A Subscription Plan is
 * bought up front and expires. The Commission Model is postpaid — one nominated
 * plan's benefits, granted alike to every commission salon, with a percentage
 * SuperAdmin sets per salon and settled monthly on the 1st.
 *
 * The percentage cannot move while that salon still has an open payout, so the
 * control for it stays locked until the money is settled.
 */

const SUBSCRIPTION = 'subscription';
const COMMISSION = 'commission';

const modelLabel = (model: string) =>
  model === COMMISSION ? 'Commission Model' : 'Subscription Plan';

const pct = (value: number | null) =>
  value === null || value === undefined ? '—' : `${Number(value)}%`;

export default function SubscriptionsPage() {
  const [plans, setPlans] = useState<any[]>([]);
  const [salons, setSalons] = useState<any[]>([]);
  const [commissionPlanId, setCommissionPlanId] = useState<string | null>(null);
  const [graceDays, setGraceDays] = useState<number>(7);
  const [subscriptionRequests, setSubscriptionRequests] = useState<any[]>([]);
  const [viewingScreenshot, setViewingScreenshot] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [banner, setBanner] = useState<{ kind: 'ok' | 'error'; text: string } | null>(null);

  // Form State for Creating/Editing Plans
  const [isPlanModalOpen, setIsPlanModalOpen] = useState(false);
  const [editingPlanId, setEditingPlanId] = useState<string | null>(null);
  const [planFormData, setPlanFormData] = useState({
    name: '',
    price: '',
    whatsapp_campaign_limit: '',
    has_customer_segmentation: false,
    has_service_based_targeting: false,
    has_high_value_targeting: false,
    has_advanced_insights: false,
    has_upsell_recommendations: 'none',
    has_cross_sell_recommendations: 'none',
    has_priority_visibility: false,
    is_active: true,
    validity_days: '30',
  });

  // Form State for putting a salon on one of the two arrangements
  const [assigningSalon, setAssigningSalon] = useState<any>(null);
  const [billingModel, setBillingModel] = useState(SUBSCRIPTION);
  const [commissionPercentage, setCommissionPercentage] = useState('');
  const [selectedPlanId, setSelectedPlanId] = useState('');

  // Changing an agreed rate is its own action, with its own gate.
  const [ratingSalon, setRatingSalon] = useState<any>(null);
  const [newRate, setNewRate] = useState('');
  const [rateReason, setRateReason] = useState('');
  const [rateError, setRateError] = useState('');
  const [blockingPayouts, setBlockingPayouts] = useState<any[]>([]);
  const [isSaving, setIsSaving] = useState(false);

  // Salon detail popup — the ⓘ button runs this off the full salon endpoint.
  const [infoSalon, setInfoSalon] = useState<any>(null);
  const [infoLoading, setInfoLoading] = useState(false);

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

  const purchasablePlans = plans.filter((p) => !p.is_commission_plan);

  const fetchData = async () => {
    try {
      const res = await fetch('/api/proxy/superadmin/subscriptions/plans', { headers: authHeaders() });
      const data = await res.json();
      if (data.success) {
        setPlans(data.plans);
        setSalons(data.salons);
        setCommissionPlanId(data.commission_plan_id ?? null);
        setGraceDays(data.commission_grace_days ?? 7);

        const sellable = data.plans.filter((p: any) => !p.is_commission_plan);
        if (sellable.length > 0) setSelectedPlanId(sellable[0].id);
      }

      const reqRes = await fetch('/api/proxy/superadmin/subscription-requests', { headers: authHeaders() });
      const reqData = await reqRes.json();
      if (reqData.success) {
        setSubscriptionRequests(reqData.requests);
      }
    } catch (e) {
      console.error(e);
    } finally {
      setIsLoading(false);
    }
  };

  // Fetch the full salon record and pop the details dialog. The list row only
  // carries subscription-scoped fields, so we go back to the salon endpoint for
  // address, contact, city, staff and service counts.
  const openSalonInfo = async (salon: any) => {
    setInfoSalon({ ...salon, detail: null });
    setInfoLoading(true);
    try {
      const res = await fetch(`/api/proxy/superadmin/salons/${salon.id}`, {
        headers: authHeaders(),
      });
      const data = await res.json();
      if (data.success) {
        setInfoSalon((prev: any) => (prev ? { ...prev, detail: data.data } : prev));
      }
    } catch (e) {
      console.error('Failed to load salon details:', e);
    } finally {
      setInfoLoading(false);
    }
  };

  const openCreateModal = () => {
    setEditingPlanId(null);
    setPlanFormData({
      name: '',
      price: '',
      whatsapp_campaign_limit: '',
      has_customer_segmentation: false,
      has_service_based_targeting: false,
      has_high_value_targeting: false,
      has_advanced_insights: false,
      has_upsell_recommendations: 'none',
      has_cross_sell_recommendations: 'none',
      has_priority_visibility: false,
      is_active: true,
      validity_days: '30',
    });
    setIsPlanModalOpen(true);
  };

  const openEditModal = (plan: any) => {
    setEditingPlanId(plan.id);
    setPlanFormData({
      name: plan.name,
      price: plan.price.toString(),
      whatsapp_campaign_limit: plan.whatsapp_campaign_limit.toString(),
      has_customer_segmentation: plan.has_customer_segmentation,
      has_service_based_targeting: plan.has_service_based_targeting,
      has_high_value_targeting: plan.has_high_value_targeting,
      has_advanced_insights: plan.has_advanced_insights,
      has_upsell_recommendations: plan.has_upsell_recommendations,
      has_cross_sell_recommendations: plan.has_cross_sell_recommendations,
      has_priority_visibility: plan.has_priority_visibility,
      is_active: plan.is_active,
      validity_days: plan.validity_days.toString(),
    });
    setIsPlanModalOpen(true);
  };

  const handleSavePlan = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsSaving(true);
    try {
      const url = editingPlanId
        ? `/api/proxy/superadmin/subscriptions/plans/${editingPlanId}`
        : `/api/proxy/superadmin/subscriptions/plans`;

      const res = await fetch(url, {
        method: editingPlanId ? 'PUT' : 'POST',
        headers: authHeaders(),
        body: JSON.stringify(planFormData),
      });
      const data = await res.json();

      if (!res.ok) throw new Error(data.message || 'Could not save the plan.');

      setIsPlanModalOpen(false);
      await fetchData();
      setBanner({ kind: 'ok', text: `Plan ${editingPlanId ? 'updated' : 'created'}.` });
    } catch (e: any) {
      setBanner({ kind: 'error', text: e.message });
    } finally {
      setIsSaving(false);
    }
  };

  const handleDeletePlan = async (plan: any) => {
    if (!confirm(`Delete “${plan.name}”? Salons subscribed to it must be moved first.`)) return;
    try {
      const res = await fetch(`/api/proxy/superadmin/subscriptions/plans/${plan.id}`, {
        method: 'DELETE',
        headers: authHeaders(),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.message || 'Could not delete the plan.');
      await fetchData();
      setBanner({ kind: 'ok', text: 'Plan deleted.' });
    } catch (e: any) {
      setBanner({ kind: 'error', text: e.message });
    }
  };

  /* Nominate the plan whose benefits every Commission Model salon enjoys. */
  const nominateCommissionPlan = async (plan: any) => {
    const confirmed = confirm(
      `Make “${plan.name}” the Commission Model plan?\n\n` +
        `Every salon on the Commission Model gets this plan's benefits, including ` +
        `those already trading. It will no longer be sellable as a subscription.`
    );
    if (!confirmed) return;

    try {
      const res = await fetch('/api/proxy/superadmin/subscriptions/commission-plan', {
        method: 'POST',
        headers: authHeaders(),
        body: JSON.stringify({ plan_id: plan.id }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.message || 'Could not nominate that plan.');
      await fetchData();
      setBanner({ kind: 'ok', text: data.message });
    } catch (e: any) {
      setBanner({ kind: 'error', text: e.message });
    }
  };

  const openAssign = (salon: any, presetModel?: string) => {
    setAssigningSalon(salon);
    setBillingModel(presetModel ?? salon.billing_model ?? SUBSCRIPTION);
    setCommissionPercentage(
      salon.commission_percentage !== null && salon.commission_percentage !== undefined
        ? String(salon.commission_percentage)
        : ''
    );
    setSelectedPlanId(purchasablePlans[0]?.id ?? '');
  };

  const handleAssignPlan = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!assigningSalon) return;

    setIsSaving(true);
    try {
      const res = await fetch(`/api/proxy/superadmin/salons/${assigningSalon.id}/subscription`, {
        method: 'POST',
        headers: authHeaders(),
        body: JSON.stringify(
          billingModel === COMMISSION
            ? {
                billing_type: COMMISSION,
                commission_percentage: parseFloat(commissionPercentage),
              }
            : { billing_type: SUBSCRIPTION, plan_id: selectedPlanId }
        ),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.message || 'Could not apply that.');

      setAssigningSalon(null);
      await fetchData();
      setBanner({ kind: 'ok', text: data.message });
    } catch (e: any) {
      setBanner({ kind: 'error', text: e.message });
    } finally {
      setIsSaving(false);
    }
  };

  const openRateChange = (salon: any) => {
    setRatingSalon(salon);
    setNewRate(String(salon.commission_percentage ?? ''));
    setRateReason('');
    setRateError('');
    setBlockingPayouts([]);
  };

  /**
   * The new rate applies from today. The backend refuses while the salon has an
   * open payout, so that everything already billed stayed on the old rate.
   */
  const handleRateChange = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!ratingSalon) return;

    setIsSaving(true);
    setRateError('');
    setBlockingPayouts([]);

    try {
      const res = await fetch(`/api/proxy/superadmin/salons/${ratingSalon.id}/commission-rate`, {
        method: 'PUT',
        headers: authHeaders(),
        body: JSON.stringify({
          commission_percentage: parseFloat(newRate),
          reason: rateReason || null,
        }),
      });
      const data = await res.json();

      if (!res.ok) {
        setBlockingPayouts(data.unsettled_payouts ?? []);
        throw new Error(data.message || 'Could not change the rate.');
      }

      setRatingSalon(null);
      await fetchData();
      setBanner({ kind: 'ok', text: data.message });
    } catch (e: any) {
      setRateError(e.message);
    } finally {
      setIsSaving(false);
    }
  };

  if (isLoading) return <div className={styles.container}>Loading…</div>;

  const commissionSalons = salons.filter((s) => s.billing_model === COMMISSION);

  return (
    <div className={styles.container}>
      <h1 className={styles.title}>Plans &amp; billing models</h1>
      <p className={styles.pageIntro}>
        Every salon trades on one of two arrangements. A <strong>Subscription Plan</strong>{' '}
        is prepaid and expires. The <strong>Commission Model</strong> is postpaid — the
        salon pays a percentage of what it bills, settled on the 1st of each month for the
        month just finished.
      </p>

      {banner && (
        <div className={banner.kind === 'ok' ? styles.bannerOk : styles.bannerError}>
          <span>{banner.text}</span>
          <button type="button" onClick={() => setBanner(null)} aria-label="Dismiss">
            ✕
          </button>
        </div>
      )}

      {/* ------------------------------------------------ pending requests */}
      {subscriptionRequests.length > 0 && (
        <div className={styles.section}>
          <div className={styles.pendingPanel}>
            <h2 className={styles.pendingTitle}>
              Waiting on you
              <span className={styles.countChip}>{subscriptionRequests.length}</span>
            </h2>
            <p className={styles.sectionHint}>
              Paid subscriptions to verify, and salons asking to move onto the Commission
              Model. A commission request has no receipt — you agree the percentage when
              you approve it.
            </p>
            <table className={styles.table}>
              <thead>
                <tr>
                  <th>Salon</th>
                  <th>Asking for</th>
                  <th>Plan</th>
                  <th>Raised</th>
                  <th style={{ textAlign: 'right' }}>Action</th>
                </tr>
              </thead>
              <tbody>
                {subscriptionRequests.map((req) => {
                  const isCommission = req.billing_type === COMMISSION;
                  return (
                    <tr key={req.id}>
                      <td>
                        <strong>{req.salon?.name}</strong>
                      </td>
                      <td>
                        <span
                          className={`${styles.pill} ${
                            isCommission ? styles.pillCommission : styles.pillSubscription
                          }`}
                        >
                          {req.billing_label ?? modelLabel(req.billing_type)}
                        </span>
                      </td>
                      <td>{req.plan?.name || '—'}</td>
                      <td>{new Date(req.created_at).toLocaleDateString()}</td>
                      <td style={{ textAlign: 'right' }}>
                        <div className={styles.rowActions}>
                          {req.screenshot_url ? (
                            <button
                              className={styles.smallButton}
                              onClick={() => setViewingScreenshot(req.screenshot_url)}
                            >
                              View receipt
                            </button>
                          ) : (
                            <span className={styles.mutedNote}>Nothing paid yet</span>
                          )}
                          <button
                            className={`${styles.smallButton} ${styles.approveButton}`}
                            onClick={() => {
                              openAssign(req.salon, req.billing_type);
                              if (!isCommission) setSelectedPlanId(req.plan?.id || purchasablePlans[0]?.id);
                            }}
                          >
                            {isCommission ? 'Set rate & approve' : 'Approve & assign'}
                          </button>
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {viewingScreenshot && (
        <div className={styles.modalOverlay} onClick={() => setViewingScreenshot(null)}>
          <div
            className={styles.modalContent}
            style={{ maxWidth: '800px', textAlign: 'center' }}
            onClick={(e) => e.stopPropagation()}
          >
            <h3>Payment receipt</h3>
            <img
              src={viewingScreenshot}
              alt="Payment receipt"
              style={{ maxWidth: '100%', maxHeight: '70vh', objectFit: 'contain', margin: '16px 0' }}
            />
            <div className={styles.formActions}>
              <button type="button" onClick={() => setViewingScreenshot(null)} className={styles.cancelButton}>
                Close
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ------------------------------------------------ commission model */}
      <div className={styles.section}>
        <h2>The Commission Model</h2>
        <p className={styles.sectionHint}>
          Every commission salon enjoys the same benefits, so one plan carries them. The
          percentage is agreed per salon; the plan is not. A salon has {graceDays} day
          {graceDays === 1 ? '' : 's'} after a month closes to settle before it goes
          offline.
        </p>

        {commissionPlanId ? (
          <div className={styles.commissionSummary}>
            <div>
              <div className={styles.summaryLabel}>Benefits carried by</div>
              <div className={styles.summaryValue}>
                {plans.find((p) => p.id === commissionPlanId)?.name ?? '—'}
              </div>
            </div>
            <div>
              <div className={styles.summaryLabel}>Salons on it</div>
              <div className={styles.summaryValue}>{commissionSalons.length}</div>
            </div>
            <div>
              <div className={styles.summaryLabel}>Settlement</div>
              <div className={styles.summaryValue}>Monthly, on the 1st</div>
            </div>
          </div>
        ) : (
          <div className={styles.warningPanel}>
            No plan carries the Commission Model yet, so no salon can be moved onto it.
            Pick one below with <strong>Make commission plan</strong>.
          </div>
        )}
      </div>

      {/* ------------------------------------------------------------ plans */}
      <div className={styles.section}>
        <div className={styles.sectionHeader}>
          <div>
            <h2>Subscription plans</h2>
            <p className={styles.sectionHint}>
              What a salon can buy. One plan also carries the Commission Model — salons on
              that arrangement get its benefits for a percentage instead of a monthly fee.
            </p>
          </div>
          <button className={styles.button} onClick={openCreateModal}>
            + Create new plan
          </button>
        </div>

        <div className={styles.grid}>
          {plans.map((plan) => {
            const isCommissionPlan = plan.id === commissionPlanId;
            return (
              <div
                key={plan.id}
                className={isCommissionPlan ? `${styles.card} ${styles.cardHighlight}` : styles.card}
              >
                <div className={styles.cardTop}>
                  <h3>{plan.name}</h3>
                  {isCommissionPlan ? (
                    <span className={`${styles.pill} ${styles.pillCommission}`}>Commission Model</span>
                  ) : plan.is_active ? (
                    <span className={`${styles.pill} ${styles.pillSubscription}`}>For sale</span>
                  ) : (
                    <span className={`${styles.pill} ${styles.pillMuted}`}>Inactive</span>
                  )}
                </div>

                <dl className={styles.specList}>
                  <div>
                    <dt>Price</dt>
                    <dd>₹{Number(plan.price).toLocaleString('en-IN')}</dd>
                  </div>
                  <div>
                    <dt>Validity</dt>
                    <dd>{plan.validity_days} days</dd>
                  </div>
                  <div>
                    <dt>WhatsApp limit</dt>
                    <dd>{plan.whatsapp_campaign_limit}</dd>
                  </div>
                </dl>

                {isCommissionPlan && (
                  <p className={styles.inlineHint} style={{ marginBottom: 12 }}>
                    Salons on the Commission Model get these benefits without paying the
                    monthly fee. It can still be sold as a subscription.
                  </p>
                )}

                <div className={styles.cardActions}>
                  <button className={styles.smallButton} onClick={() => openEditModal(plan)}>
                    Edit
                  </button>
                  {!isCommissionPlan && (
                    <button className={styles.smallButton} onClick={() => nominateCommissionPlan(plan)}>
                      Make commission plan
                    </button>
                  )}
                  {!isCommissionPlan && (
                    <button className={styles.dangerButton} onClick={() => handleDeletePlan(plan)}>
                      Delete
                    </button>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      </div>

      {isPlanModalOpen && (
        <div className={styles.modalOverlay}>
          <div className={styles.modalContent} style={{ maxWidth: '600px', maxHeight: '90vh', overflowY: 'auto' }}>
            <h3>{editingPlanId ? 'Edit' : 'Create'} plan</h3>
            <form onSubmit={handleSavePlan} className={styles.form}>
              <h4 className={styles.featureSectionTitle} style={{ marginTop: 0 }}>
                Basic details
              </h4>
              <div className={styles.featuresGrid}>
                <div className={styles.formGroup}>
                  <label>Plan name</label>
                  <input
                    type="text"
                    value={planFormData.name}
                    onChange={(e) => setPlanFormData({ ...planFormData, name: e.target.value })}
                    required
                  />
                </div>
                <div className={styles.formGroup}>
                  <label>Price (₹)</label>
                  <input
                    type="number"
                    value={planFormData.price}
                    onChange={(e) => setPlanFormData({ ...planFormData, price: e.target.value })}
                    required
                  />
                </div>
                <div className={styles.formGroup}>
                  <label>Validity days</label>
                  <input
                    type="number"
                    value={planFormData.validity_days}
                    onChange={(e) => setPlanFormData({ ...planFormData, validity_days: e.target.value })}
                    required
                    min="1"
                  />
                </div>
                <div className={styles.formGroup} style={{ gridColumn: 'span 2' }}>
                  <label>WhatsApp campaign limit</label>
                  <input
                    type="number"
                    value={planFormData.whatsapp_campaign_limit}
                    onChange={(e) =>
                      setPlanFormData({ ...planFormData, whatsapp_campaign_limit: e.target.value })
                    }
                    required
                  />
                </div>
              </div>

              <h4 className={styles.featureSectionTitle}>Targeting &amp; insights</h4>
              <div className={styles.featuresGrid}>
                <label className={styles.checkboxLabel}>
                  <input
                    type="checkbox"
                    checked={planFormData.has_customer_segmentation}
                    onChange={(e) =>
                      setPlanFormData({ ...planFormData, has_customer_segmentation: e.target.checked })
                    }
                  />{' '}
                  Customer segmentation
                </label>
                <label className={styles.checkboxLabel}>
                  <input
                    type="checkbox"
                    checked={planFormData.has_service_based_targeting}
                    onChange={(e) =>
                      setPlanFormData({ ...planFormData, has_service_based_targeting: e.target.checked })
                    }
                  />{' '}
                  Service based targeting
                </label>
                <label className={styles.checkboxLabel}>
                  <input
                    type="checkbox"
                    checked={planFormData.has_high_value_targeting}
                    onChange={(e) =>
                      setPlanFormData({ ...planFormData, has_high_value_targeting: e.target.checked })
                    }
                  />{' '}
                  High value targeting
                </label>
                <label className={styles.checkboxLabel}>
                  <input
                    type="checkbox"
                    checked={planFormData.has_advanced_insights}
                    onChange={(e) =>
                      setPlanFormData({ ...planFormData, has_advanced_insights: e.target.checked })
                    }
                  />{' '}
                  Advanced insights
                </label>
                <label className={styles.checkboxLabel}>
                  <input
                    type="checkbox"
                    checked={planFormData.has_priority_visibility}
                    onChange={(e) =>
                      setPlanFormData({ ...planFormData, has_priority_visibility: e.target.checked })
                    }
                  />{' '}
                  Priority visibility
                </label>
                <label className={styles.checkboxLabel}>
                  <input
                    type="checkbox"
                    checked={planFormData.is_active}
                    onChange={(e) => setPlanFormData({ ...planFormData, is_active: e.target.checked })}
                  />{' '}
                  Is active
                </label>
              </div>

              <h4 className={styles.featureSectionTitle}>Advanced recommendations</h4>
              <div className={styles.featuresGrid}>
                <div className={styles.formGroup}>
                  <label>Upsell recommendations</label>
                  <select
                    value={planFormData.has_upsell_recommendations}
                    onChange={(e) =>
                      setPlanFormData({ ...planFormData, has_upsell_recommendations: e.target.value })
                    }
                  >
                    <option value="none">None</option>
                    <option value="basic">Basic</option>
                    <option value="advanced">Advanced</option>
                  </select>
                </div>
                <div className={styles.formGroup}>
                  <label>Cross-sell recommendations</label>
                  <select
                    value={planFormData.has_cross_sell_recommendations}
                    onChange={(e) =>
                      setPlanFormData({ ...planFormData, has_cross_sell_recommendations: e.target.value })
                    }
                  >
                    <option value="none">None</option>
                    <option value="basic">Basic</option>
                    <option value="advanced">Advanced</option>
                  </select>
                </div>
              </div>

              <div className={styles.formActions}>
                <button type="submit" className={styles.primaryButton} disabled={isSaving}>
                  {isSaving ? 'Saving…' : 'Save plan'}
                </button>
                <button type="button" onClick={() => setIsPlanModalOpen(false)} className={styles.cancelButton}>
                  Cancel
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* ----------------------------------------------------------- salons */}
      <div className={styles.section}>
        <h2>Salons</h2>
        <p className={styles.sectionHint}>
          A commission rate can only be changed once that salon has no open payout, so
          everything already billed stays on the rate it was billed at.
        </p>
        <table className={styles.table}>
          <thead>
            <tr>
              <th>Salon</th>
              <th>Owner</th>
              <th>Billing model</th>
              <th>Plan</th>
              <th>Rate</th>
              <th>Access until</th>
              <th style={{ textAlign: 'right' }}>Action</th>
            </tr>
          </thead>
          <tbody>
            {salons.map((salon) => {
              const onCommission = salon.billing_model === COMMISSION;
              const blocked = onCommission && salon.unsettled_payouts > 0;

              return (
                <tr key={salon.id}>
                  <td>
                    <strong>{salon.name}</strong>
                    <button
                      className={styles.infoButton}
                      onClick={() => openSalonInfo(salon)}
                      title="View salon details"
                    >
                      &#9432;
                    </button>
                  </td>
                  <td>{salon.owner}</td>
                  <td>
                    <span
                      className={`${styles.pill} ${
                        onCommission ? styles.pillCommission : styles.pillSubscription
                      }`}
                    >
                      {salon.billing_label ?? modelLabel(salon.billing_model)}
                    </span>
                  </td>
                  <td>{salon.current_plan}</td>
                  <td>
                    {onCommission ? (
                      <>
                        <strong>{pct(salon.commission_percentage)}</strong>
                        {salon.commission_rate_effective_from && (
                          <>
                            <br />
                            <small className={styles.mutedNote}>
                              since {salon.commission_rate_effective_from}
                            </small>
                          </>
                        )}
                      </>
                    ) : (
                      '—'
                    )}
                  </td>
                  <td>
                    {salon.expiry || 'N/A'}
                    {blocked && (
                      <>
                        <br />
                        <small className={styles.blockedNote}>
                          {salon.unsettled_payouts} payout
                          {salon.unsettled_payouts === 1 ? '' : 's'} open
                        </small>
                      </>
                    )}
                  </td>
                  <td style={{ textAlign: 'right' }}>
                    <div className={styles.rowActions}>
                      {onCommission && (
                        <button
                          className={styles.smallButton}
                          onClick={() => openRateChange(salon)}
                          disabled={blocked}
                          title={
                            blocked
                              ? 'Settle this salon’s open payouts before changing the rate'
                              : 'Change the agreed commission percentage'
                          }
                        >
                          Change rate
                        </button>
                      )}
                      <button className={styles.button} onClick={() => openAssign(salon)}>
                        Change model
                      </button>
                    </div>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      {/* --------------------------------------------------- assign a model */}
      {assigningSalon && (
        <div className={styles.modalOverlay}>
          <div className={styles.modalContent}>
            <h3>How {assigningSalon.name} pays</h3>
            <form onSubmit={handleAssignPlan} className={styles.form}>
              <div className={styles.formGroup}>
                <label>Billing model</label>
                <select value={billingModel} onChange={(e) => setBillingModel(e.target.value)}>
                  <option value={SUBSCRIPTION}>Subscription Plan — prepaid, expires</option>
                  <option value={COMMISSION}>Commission Model — postpaid, monthly</option>
                </select>
              </div>

              {billingModel === SUBSCRIPTION ? (
                <div className={styles.formGroup}>
                  <label>Plan to sell them</label>
                  <select
                    value={selectedPlanId}
                    onChange={(e) => setSelectedPlanId(e.target.value)}
                    required
                  >
                    {purchasablePlans.map((p) => (
                      <option key={p.id} value={p.id}>
                        {p.name} — ₹{p.price} ({p.validity_days} days)
                      </option>
                    ))}
                  </select>
                  {purchasablePlans.length === 0 && (
                    <p className={styles.inlineWarning}>
                      Every plan is nominated for the Commission Model. Create one to sell.
                    </p>
                  )}
                </div>
              ) : (
                <>
                  <div className={styles.formGroup}>
                    <label>Commission percentage (%)</label>
                    <input
                      type="number"
                      step="0.01"
                      min="0"
                      max="100"
                      value={commissionPercentage}
                      onChange={(e) => setCommissionPercentage(e.target.value)}
                      required
                    />
                  </div>
                  <p className={styles.inlineHint}>
                    They get the{' '}
                    <strong>{plans.find((p) => p.id === commissionPlanId)?.name ?? 'commission'}</strong>{' '}
                    plan&apos;s benefits and pay {commissionPercentage || '—'}% of everything they
                    bill, settled on the 1st of each month.
                  </p>
                </>
              )}

              <div className={styles.formActions}>
                <button
                  type="submit"
                  className={styles.primaryButton}
                  disabled={isSaving || (billingModel === SUBSCRIPTION && !selectedPlanId)}
                >
                  {isSaving ? 'Applying…' : 'Apply'}
                </button>
                <button type="button" onClick={() => setAssigningSalon(null)} className={styles.cancelButton}>
                  Cancel
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* ------------------------------------------------------ change rate */}
      {ratingSalon && (
        <div className={styles.modalOverlay}>
          <div className={styles.modalContent}>
            <h3>Commission for {ratingSalon.name}</h3>
            <p className={styles.inlineHint}>
              Currently {pct(ratingSalon.commission_percentage)}. The new rate is charged on
              everything billed from today; already-settled payouts keep the rate they were
              charged at.
            </p>

            {rateError && (
              <div className={styles.bannerError} style={{ marginTop: 12 }}>
                <span>{rateError}</span>
              </div>
            )}

            {blockingPayouts.length > 0 && (
              <ul className={styles.blockingList}>
                {blockingPayouts.map((p) => (
                  <li key={p.id}>
                    {p.cycle_start_date} → {p.cycle_end_date} · ₹{p.net_amount} · {p.status}
                  </li>
                ))}
              </ul>
            )}

            <form onSubmit={handleRateChange} className={styles.form}>
              <div className={styles.formGroup}>
                <label>New percentage (%)</label>
                <input
                  type="number"
                  step="0.01"
                  min="0"
                  max="100"
                  value={newRate}
                  onChange={(e) => setNewRate(e.target.value)}
                  required
                />
              </div>
              <div className={styles.formGroup}>
                <label>Reason (optional)</label>
                <input
                  type="text"
                  value={rateReason}
                  onChange={(e) => setRateReason(e.target.value)}
                  placeholder="e.g. Renegotiated at renewal"
                />
              </div>

              <div className={styles.formActions}>
                <button type="submit" className={styles.primaryButton} disabled={isSaving}>
                  {isSaving ? 'Saving…' : 'Change rate'}
                </button>
                <button type="button" onClick={() => setRatingSalon(null)} className={styles.cancelButton}>
                  Cancel
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* -------------------------------------------------- salon details */}
      {infoSalon && (
        <div className={styles.modalOverlay} onClick={() => setInfoSalon(null)}>
          <div
            className={styles.modalContent}
            onClick={(e) => e.stopPropagation()}
            style={{ maxWidth: '560px', maxHeight: '90vh', overflowY: 'auto' }}
          >
            <div className={styles.infoModalHeader}>
              <h3 style={{ margin: 0 }}>{infoSalon.name}</h3>
              <button className={styles.infoClose} onClick={() => setInfoSalon(null)} aria-label="Close">
                &times;
              </button>
            </div>

            {infoLoading && infoSalon.detail == null ? (
              <p className={styles.inlineHint}>Loading details…</p>
            ) : infoSalon.detail ? (
              <div className={styles.infoBody}>
                <div className={styles.infoGrid}>
                  <InfoField label="Status" value={infoSalon.detail.status} />
                  <InfoField label="City" value={infoSalon.detail.city?.name} />
                  <InfoField label="Address" value={infoSalon.detail.address} />
                  <InfoField label="Pincode" value={infoSalon.detail.pincode} />
                  <InfoField label="Gender focus" value={infoSalon.detail.gender_focus} />
                  <InfoField label="Description" value={infoSalon.detail.description} />
                </div>

                <h4 className={styles.infoSectionTitle}>Owner / Admin</h4>
                <div className={styles.infoGrid}>
                  <InfoField label="Name" value={infoSalon.detail.admin?.name} />
                  <InfoField label="Phone" value={infoSalon.detail.admin?.phone} />
                  <InfoField label="Email" value={infoSalon.detail.admin?.email} />
                </div>

                <h4 className={styles.infoSectionTitle}>Billing (as of now)</h4>
                <div className={styles.infoGrid}>
                  <InfoField label="Owner display" value={infoSalon.owner} />
                  <InfoField
                    label="Billing model"
                    value={infoSalon.billing_label ?? modelLabel(infoSalon.billing_model)}
                  />
                  <InfoField label="Plan" value={infoSalon.current_plan} />
                  {infoSalon.billing_model === COMMISSION && (
                    <InfoField
                      label="Commission"
                      value={infoSalon.commission_percentage != null ? `${infoSalon.commission_percentage}%` : '—'}
                    />
                  )}
                  <InfoField label="Access until" value={infoSalon.expiry || 'N/A'} />
                  <InfoField label="Registered" value={infoSalon.detail.created_at} />
                </div>

                <div className={styles.infoStats}>
                  <InfoStat label="Staff" value={infoSalon.detail.providers?.length} />
                  <InfoStat label="Services" value={infoSalon.detail.services?.length} />
                  <InfoStat label="Combos" value={infoSalon.detail.combos?.length} />
                </div>
              </div>
            ) : (
              <p className={styles.inlineHint}>Could not load salon details.</p>
            )}

            <div
              className={styles.formActions}
              style={{ marginTop: 20, justifyContent: 'flex-end' }}
            >
              <button className={styles.primaryButton} onClick={() => setInfoSalon(null)}>
                Close
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

const InfoField = ({ label, value }: { label: string; value: any }) => (
  <div>
    <div className={styles.infoLabel}>{label}</div>
    <div className={styles.infoValue}>{value ?? '—'}</div>
  </div>
);

const InfoStat = ({ label, value }: { label: string; value: any }) => (
  <div className={styles.infoStat}>
    <div className={styles.infoStatValue}>{value ?? '—'}</div>
    <div className={styles.infoStatLabel}>{label}</div>
  </div>
);
