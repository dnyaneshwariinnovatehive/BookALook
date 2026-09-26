'use client';

import { useState, useEffect, useMemo } from 'react';
import Icon from '@/components/admin/Icon';
import {
  Alert, Badge, Button, Card, DescriptionList, EmptyState, Field, IconButton, Modal, PageHeader,
  Person, SearchInput, Segmented, Skeleton, StatCard, cx, formatINR, localISODate, ui, useConfirm,
} from '@/components/admin/ui';
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

/* eslint-disable @typescript-eslint/no-explicit-any -- plans/salons come back as untyped JSON */

const SUBSCRIPTION = 'subscription';
const COMMISSION = 'commission';

const modelLabel = (model: string) =>
  model === COMMISSION ? 'Commission Model' : 'Subscription Plan';

const pct = (value: number | null) =>
  value === null || value === undefined ? '—' : `${Number(value)}%`;

const EMPTY_PLAN = {
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
};

type PlanForm = typeof EMPTY_PLAN;

const FEATURE_FLAGS: { key: keyof PlanForm; label: string }[] = [
  { key: 'has_customer_segmentation', label: 'Customer segmentation' },
  { key: 'has_service_based_targeting', label: 'Service-based targeting' },
  { key: 'has_high_value_targeting', label: 'High-value targeting' },
  { key: 'has_advanced_insights', label: 'Advanced insights' },
  { key: 'has_priority_visibility', label: 'Priority visibility' },
];

const LEVEL_LABEL: Record<string, string> = { none: 'None', basic: 'Basic', advanced: 'Advanced' };

/** Days from today until a Y-m-d date (negative once it has passed). */
const daysUntil = (ymd?: string | null) => {
  if (!ymd) return null;
  const [y, m, d] = ymd.split('-').map(Number);
  const [ty, tm, td] = localISODate().split('-').map(Number);
  return Math.round((Date.UTC(y, m - 1, d) - Date.UTC(ty, tm - 1, td)) / 86400000);
};

const fmtDay = (ymd?: string | null) => {
  if (!ymd) return '—';
  const [y, m, d] = ymd.split('-').map(Number);
  return new Date(y, m - 1, d).toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' });
};

export default function SubscriptionsPage() {
  const [plans, setPlans] = useState<any[]>([]);
  const [salons, setSalons] = useState<any[]>([]);
  const [commissionPlanId, setCommissionPlanId] = useState<string | null>(null);
  const [graceDays, setGraceDays] = useState<number>(7);
  const [subscriptionRequests, setSubscriptionRequests] = useState<any[]>([]);
  const [viewingScreenshot, setViewingScreenshot] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState('');
  const [banner, setBanner] = useState<{ kind: 'ok' | 'error'; text: string } | null>(null);
  const [confirm, confirmDialog] = useConfirm();

  // Form State for Creating/Editing Plans
  const [isPlanModalOpen, setIsPlanModalOpen] = useState(false);
  const [editingPlanId, setEditingPlanId] = useState<string | null>(null);
  const [planFormData, setPlanFormData] = useState<PlanForm>(EMPTY_PLAN);

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

  // Salon detail popup — runs off the full salon endpoint.
  const [infoSalon, setInfoSalon] = useState<any>(null);
  const [infoLoading, setInfoLoading] = useState(false);
  const [salonSearch, setSalonSearch] = useState('');
  const [salonFilterModel, setSalonFilterModel] = useState('');
  const [salonSort, setSalonSort] = useState('name_asc');

  // Success notes fade on their own; errors stay until dismissed.
  useEffect(() => {
    if (banner?.kind !== 'ok') return;
    const t = setTimeout(() => setBanner(null), 6000);
    return () => clearTimeout(t);
  }, [banner]);

  const authHeaders = (): Record<string, string> => ({
    'Content-Type': 'application/json',
  });

  const purchasablePlans = plans.filter((p) => !p.is_commission_plan);

  const fetchData = async () => {
    try {
      const res = await fetch('/api/proxy/superadmin/subscriptions/plans', { headers: authHeaders() });
      const data = await res.json();
      if (data.success) {
        setLoadError('');
        const planList = Array.isArray(data.plans) ? data.plans : [];
        setPlans(planList);
        setSalons(Array.isArray(data.salons) ? data.salons : []);
        setCommissionPlanId(data.commission_plan_id ?? null);
        setGraceDays(data.commission_grace_days ?? 7);

        const sellable = planList.filter((p: any) => !p.is_commission_plan);
        if (sellable.length > 0) setSelectedPlanId(sellable[0].id);
      } else {
        setLoadError(data.message || 'Could not load plans.');
      }

      const reqRes = await fetch('/api/proxy/superadmin/subscription-requests', { headers: authHeaders() });
      const reqData = await reqRes.json();
      if (reqData.success) {
        setSubscriptionRequests(Array.isArray(reqData.requests) ? reqData.requests : []);
      }
    } catch (e) {
      console.error(e);
      setLoadError('Could not reach the server.');
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- state is only set after the network responds
    fetchData();
    // Load once on mount; fetchData is re-called explicitly after every change.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // The list row only carries subscription-scoped fields, so we go back to the
  // salon endpoint for address, contact, city, staff and service counts.
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
    setPlanFormData(EMPTY_PLAN);
    setIsPlanModalOpen(true);
  };

  const openEditModal = (plan: any) => {
    setEditingPlanId(plan.id);
    setPlanFormData({
      name: plan.name ?? '',
      price: String(plan.price ?? ''),
      whatsapp_campaign_limit: String(plan.whatsapp_campaign_limit ?? ''),
      has_customer_segmentation: !!plan.has_customer_segmentation,
      has_service_based_targeting: !!plan.has_service_based_targeting,
      has_high_value_targeting: !!plan.has_high_value_targeting,
      has_advanced_insights: !!plan.has_advanced_insights,
      has_upsell_recommendations: plan.has_upsell_recommendations ?? 'none',
      has_cross_sell_recommendations: plan.has_cross_sell_recommendations ?? 'none',
      has_priority_visibility: !!plan.has_priority_visibility,
      is_active: !!plan.is_active,
      validity_days: String(plan.validity_days ?? '30'),
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
    const ok = await confirm({
      title: `Delete “${plan.name}”?`,
      body: 'Salons subscribed to it must be moved to another plan first. This cannot be undone.',
      confirmLabel: 'Delete plan',
      tone: 'danger',
    });
    if (!ok) return;
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
    const ok = await confirm({
      title: `Make “${plan.name}” the Commission Model plan?`,
      body: 'Every salon on the Commission Model gets this plan’s benefits, including those already trading. It will no longer be sellable as a subscription.',
      confirmLabel: 'Make commission plan',
    });
    if (!ok) return;

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

  const openAssign = (salon: any, presetModel?: string, presetPlanId?: string) => {
    setAssigningSalon(salon);
    setBillingModel(presetModel ?? salon.billing_model ?? SUBSCRIPTION);
    setCommissionPercentage(
      salon.commission_percentage !== null && salon.commission_percentage !== undefined
        ? String(salon.commission_percentage)
        : ''
    );
    setSelectedPlanId(presetPlanId ?? purchasablePlans[0]?.id ?? '');
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

  const commissionSalons = salons.filter((s) => s.billing_model === COMMISSION);
  const subscriptionSalons = salons.filter((s) => s.billing_model !== COMMISSION);
  const expiringSoon = salons.filter((s) => {
    const d = daysUntil(s.expiry);
    return s.billing_model !== COMMISSION && d !== null && d >= 0 && d <= 7;
  });
  const commissionPlan = plans.find((p) => p.id === commissionPlanId);

  const planSalonCounts = useMemo(() => {
    const counts: Record<string, number> = {};
    for (const s of salons) if (s.current_plan) counts[s.current_plan] = (counts[s.current_plan] ?? 0) + 1;
    return counts;
  }, [salons]);

  const filteredSalons = salons.filter(s => {
    if (salonFilterModel === 'expiring') {
      if (!expiringSoon.includes(s)) return false;
    } else if (salonFilterModel && (s.billing_model === COMMISSION ? COMMISSION : SUBSCRIPTION) !== salonFilterModel) {
      return false;
    }
    if (salonSearch) {
      const q = salonSearch.toLowerCase();
      return (s.name || '').toLowerCase().includes(q) || (s.owner || '').toLowerCase().includes(q);
    }
    return true;
  }).sort((a, b) => {
    if (salonSort === 'name_asc') return (a.name || '').localeCompare(b.name || '');
    if (salonSort === 'name_desc') return (b.name || '').localeCompare(a.name || '');
    if (salonSort === 'rate_desc') return (b.commission_percentage || 0) - (a.commission_percentage || 0);
    if (salonSort === 'expiry_asc') return (a.expiry || 'Z').localeCompare(b.expiry || 'Z');
    return 0;
  });

  return (
    <div className={styles.container}>
      <PageHeader
        eyebrow="Billing"
        title="Plans & billing models"
        subtitle={
          <>
            Every salon trades on one of two arrangements. A <strong>Subscription Plan</strong> is prepaid and
            expires. The <strong>Commission Model</strong> is postpaid — a percentage of what the salon bills,
            settled on the 1st for the month just finished.
          </>
        }
        actions={<Button variant="primary" icon="plus" onClick={openCreateModal}>New plan</Button>}
      />

      {banner && (
        <Alert tone={banner.kind === 'ok' ? 'success' : 'error'} onClose={() => setBanner(null)}>
          {banner.text}
        </Alert>
      )}

      {loadError && !isLoading && (
        <Alert tone="error">
          {loadError} <button type="button" className={styles.linkBtn} onClick={fetchData}>Retry</button>
        </Alert>
      )}

      {/* ------------------------------------------------ overview */}
      <div className={ui.statGrid}>
        <StatCard label="On subscription" icon="crown" tone="info" loading={isLoading} value={subscriptionSalons.length} sub={`${purchasablePlans.length} plan${purchasablePlans.length === 1 ? '' : 's'} for sale`} />
        <StatCard label="On commission" icon="percent" tone="accent" loading={isLoading} value={commissionSalons.length} sub="Settled monthly, on the 1st" />
        <StatCard
          label="Waiting on you"
          icon="receipt"
          tone={subscriptionRequests.length ? 'warning' : 'success'}
          loading={isLoading}
          value={subscriptionRequests.length}
          sub={subscriptionRequests.length ? 'Requests to verify' : 'Nothing pending'}
        />
        <StatCard
          label="Expiring in 7 days"
          icon="clock"
          tone={expiringSoon.length ? 'danger' : 'neutral'}
          loading={isLoading}
          value={expiringSoon.length}
          sub={expiringSoon.length ? 'Subscriptions about to lapse' : 'No renewals due'}
        />
      </div>

      {/* ------------------------------------------------ pending requests */}
      {subscriptionRequests.length > 0 && (
        <Card
          className={styles.pendingCard}
          title={<>Waiting on you <Badge tone="warning" dot={false}>{subscriptionRequests.length}</Badge></>}
          subtitle="Paid subscriptions to verify, and salons asking to move onto the Commission Model. A commission request has no receipt — you agree the percentage when you approve it."
        >
          <div className={ui.tableWrap}>
            <table className={ui.table}>
              <thead>
                <tr>
                  <th>Salon</th>
                  <th>Asking for</th>
                  <th>Plan</th>
                  <th>Raised</th>
                  <th className={ui.alignRight}>Action</th>
                </tr>
              </thead>
              <tbody>
                {subscriptionRequests.map((req) => {
                  const isCommission = req.billing_type === COMMISSION;
                  return (
                    <tr key={req.id}>
                      <td><Person name={req.salon?.name ?? 'Unknown salon'} size={32} /></td>
                      <td>
                        <Badge tone={isCommission ? 'accent' : 'info'}>{req.billing_label ?? modelLabel(req.billing_type)}</Badge>
                      </td>
                      <td>{req.plan?.name || '—'}</td>
                      <td className={ui.num}>{new Date(req.created_at).toLocaleDateString('en-IN', { day: 'numeric', month: 'short' })}</td>
                      <td className={ui.alignRight}>
                        <div className={styles.rowActions}>
                          {req.screenshot_url ? (
                            <Button size="sm" icon="receipt" onClick={() => setViewingScreenshot(req.screenshot_url)}>Receipt</Button>
                          ) : (
                            !isCommission && <span className={styles.mutedNote}>Nothing paid yet</span>
                          )}
                          <Button
                            size="sm"
                            variant="primary"
                            icon="check"
                            onClick={() => openAssign(req.salon, req.billing_type, isCommission ? undefined : req.plan?.id)}
                          >
                            {isCommission ? 'Set rate & approve' : 'Approve'}
                          </Button>
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </Card>
      )}

      {/* ------------------------------------------------ commission model */}
      <Card padded>
        <div className={styles.commission}>
          <div className={styles.commissionIntro}>
            <span className={styles.commissionIcon}><Icon name="percent" size={22} /></span>
            <div>
              <h2 className={ui.cardTitle}>The Commission Model</h2>
              <p className={ui.cardSubtitle}>
                Every commission salon enjoys the same benefits, so one plan carries them. The percentage is agreed
                per salon; the plan is not. A salon has {graceDays} day{graceDays === 1 ? '' : 's'} after a month
                closes to settle before it goes offline.
              </p>
            </div>
          </div>

          {isLoading ? (
            <Skeleton height={64} radius={14} />
          ) : commissionPlanId ? (
            <div className={styles.commissionFacts}>
              <Field label="Benefits carried by">
                <select
                  className={ui.control}
                  value={commissionPlanId || ''}
                  onChange={(e) => {
                    const plan = plans.find((p) => p.id === e.target.value);
                    if (plan) nominateCommissionPlan(plan);
                  }}
                >
                  {plans.map((p) => (
                    <option key={p.id} value={p.id}>{p.name}</option>
                  ))}
                </select>
              </Field>
              <div className={styles.fact}>
                <span>Salons on it</span>
                <b>{commissionSalons.length}</b>
              </div>
              <div className={styles.fact}>
                <span>Settlement</span>
                <b>Monthly, 1st</b>
              </div>
            </div>
          ) : (
            <Alert tone="warning">
              No plan carries the Commission Model yet, so no salon can be moved onto it. Pick one below with{' '}
              <strong>Make commission plan</strong>.
            </Alert>
          )}
        </div>
      </Card>

      {/* ------------------------------------------------------------ plans */}
      <section>
        <div className={styles.sectionHead}>
          <div>
            <h2 className={ui.cardTitle}>Subscription plans</h2>
            <p className={ui.cardSubtitle}>What a salon can buy. The commission plan’s benefits go to commission salons instead of being sold.</p>
          </div>
        </div>

        {isLoading ? (
          <div className={styles.planGrid}>
            {[1, 2, 3].map((i) => <Skeleton key={i} height={300} radius={18} />)}
          </div>
        ) : plans.length === 0 ? (
          <Card padded>
            <EmptyState
              icon="crown"
              title="No plans yet"
              hint="Create the first plan salons can subscribe to."
              action={<Button variant="primary" icon="plus" onClick={openCreateModal}>New plan</Button>}
            />
          </Card>
        ) : (
          <div className={styles.planGrid}>
            {plans.map((plan) => {
              const isCommissionPlan = plan.id === commissionPlanId;
              const count = planSalonCounts[plan.name] ?? 0;
              return (
                <article key={plan.id} className={cx(styles.plan, isCommissionPlan && styles.planFeatured, !plan.is_active && !isCommissionPlan && styles.planInactive)}>
                  <div className={styles.planTop}>
                    <h3 className={styles.planName}>{plan.name}</h3>
                    {isCommissionPlan ? (
                      <Badge tone="accent">Commission plan</Badge>
                    ) : plan.is_active ? (
                      <Badge tone="success">For sale</Badge>
                    ) : (
                      <Badge tone="neutral">Inactive</Badge>
                    )}
                  </div>

                  <div className={styles.planPrice}>
                    <span className={styles.planAmount}>{formatINR(plan.price)}</span>
                    <span className={styles.planPer}>/ {plan.validity_days} days</span>
                  </div>
                  <p className={styles.planMeta}>
                    {count} salon{count === 1 ? '' : 's'} on this plan
                  </p>

                  <ul className={styles.featureList}>
                    <li className={styles.featureOn}>
                      <Icon name="message" size={15} />
                      {Number(plan.whatsapp_campaign_limit).toLocaleString('en-IN')} WhatsApp campaign{Number(plan.whatsapp_campaign_limit) === 1 ? '' : 's'}
                    </li>
                    {FEATURE_FLAGS.map((f) => (
                      <li key={f.key} className={plan[f.key] ? styles.featureOn : styles.featureOff}>
                        <Icon name={plan[f.key] ? 'check' : 'close'} size={15} strokeWidth={2.2} />
                        {f.label}
                      </li>
                    ))}
                    <li className={plan.has_upsell_recommendations !== 'none' ? styles.featureOn : styles.featureOff}>
                      <Icon name={plan.has_upsell_recommendations !== 'none' ? 'check' : 'close'} size={15} strokeWidth={2.2} />
                      Upsell · {LEVEL_LABEL[plan.has_upsell_recommendations] ?? '—'}
                    </li>
                    <li className={plan.has_cross_sell_recommendations !== 'none' ? styles.featureOn : styles.featureOff}>
                      <Icon name={plan.has_cross_sell_recommendations !== 'none' ? 'check' : 'close'} size={15} strokeWidth={2.2} />
                      Cross-sell · {LEVEL_LABEL[plan.has_cross_sell_recommendations] ?? '—'}
                    </li>
                  </ul>

                  {isCommissionPlan && (
                    <p className={styles.planNote}>
                      Commission salons get these benefits without the fee. It isn’t sold while it carries the Commission Model.
                    </p>
                  )}

                  <div className={styles.planActions}>
                    <Button size="sm" icon="edit" onClick={() => openEditModal(plan)}>Edit</Button>
                    {!isCommissionPlan && (
                      <>
                        <Button size="sm" variant="soft" onClick={() => nominateCommissionPlan(plan)}>Make commission plan</Button>
                        <IconButton icon="trash" label={`Delete ${plan.name}`} className={styles.deleteBtn} onClick={() => handleDeletePlan(plan)} />
                      </>
                    )}
                  </div>
                </article>
              );
            })}
          </div>
        )}
      </section>

      {/* ----------------------------------------------------------- salons */}
      <Card>
        <div className={ui.toolbar}>
          <div className={styles.salonsTitle}>
            <h2 className={ui.cardTitle}>Salons</h2>
            <p className={ui.cardSubtitle}>A commission rate can only change once that salon has no open payout.</p>
          </div>
          <Segmented
            ariaLabel="Billing model"
            value={salonFilterModel}
            onChange={setSalonFilterModel}
            options={[
              { value: '', label: 'All', count: salons.length },
              { value: SUBSCRIPTION, label: 'Subscription', count: subscriptionSalons.length },
              { value: COMMISSION, label: 'Commission', count: commissionSalons.length },
              ...(expiringSoon.length ? [{ value: 'expiring', label: 'Expiring', count: expiringSoon.length }] : []),
            ]}
          />
        </div>
        <div className={cx(ui.toolbar, styles.subToolbar)}>
          <SearchInput className={ui.toolbarGrow} value={salonSearch} onChange={setSalonSearch} placeholder="Search salon or owner…" />
          <select className={cx(ui.control, styles.sortSelect)} value={salonSort} onChange={(e) => setSalonSort(e.target.value)} aria-label="Sort salons">
            <option value="name_asc">Name (A–Z)</option>
            <option value="name_desc">Name (Z–A)</option>
            <option value="rate_desc">Commission rate (high–low)</option>
            <option value="expiry_asc">Access ends (soonest)</option>
          </select>
        </div>

        <div className={ui.tableWrap}>
          <table className={ui.table}>
            <thead>
              <tr>
                <th>Salon</th>
                <th>Billing model</th>
                <th>Plan</th>
                <th>Rate</th>
                <th>Access until</th>
                <th className={ui.alignRight}>Action</th>
              </tr>
            </thead>
            <tbody>
              {isLoading ? (
                Array.from({ length: 5 }, (_, i) => (
                  <tr key={i}>
                    <td><div className={ui.personCell}><Skeleton width={34} height={34} radius={11} /><Skeleton width={140} /></div></td>
                    <td><Skeleton width={120} height={22} radius={999} /></td>
                    <td><Skeleton width={80} /></td>
                    <td><Skeleton width={40} /></td>
                    <td><Skeleton width={90} /></td>
                    <td><Skeleton width={120} /></td>
                  </tr>
                ))
              ) : filteredSalons.length === 0 ? (
                <tr>
                  <td colSpan={6}>
                    <EmptyState icon="store" title="No salons match" hint="Try another search or billing model." />
                  </td>
                </tr>
              ) : (
                filteredSalons.map((salon) => {
                  const onCommission = salon.billing_model === COMMISSION;
                  const blocked = onCommission && salon.unsettled_payouts > 0;
                  const left = onCommission ? null : daysUntil(salon.expiry);

                  return (
                    <tr key={salon.id}>
                      <td>
                        <button type="button" className={styles.salonBtn} onClick={() => openSalonInfo(salon)} title="View salon details">
                          <Person name={salon.name} sub={salon.owner} size={34} />
                        </button>
                      </td>
                      <td>
                        <Badge tone={onCommission ? 'accent' : 'info'}>{salon.billing_label ?? modelLabel(salon.billing_model)}</Badge>
                      </td>
                      <td className={salon.current_plan === 'None' ? styles.mutedNote : ui.cellPrimary}>{salon.current_plan}</td>
                      <td>
                        {onCommission ? (
                          <>
                            <div className={cx(ui.cellPrimary, ui.num)}>{pct(salon.commission_percentage)}</div>
                            {salon.commission_rate_effective_from && (
                              <div className={ui.cellSub}>since {fmtDay(salon.commission_rate_effective_from)}</div>
                            )}
                          </>
                        ) : (
                          <span className={styles.mutedNote}>—</span>
                        )}
                      </td>
                      <td>
                        {onCommission ? (
                          <span className={styles.mutedNote}>Ongoing</span>
                        ) : salon.expiry ? (
                          <>
                            <div className={ui.num}>{fmtDay(salon.expiry)}</div>
                            {left !== null && left < 0 && <Badge tone="danger" dot={false}>Expired</Badge>}
                            {left !== null && left >= 0 && left <= 7 && (
                              <Badge tone="warning" dot={false}>{left === 0 ? 'Ends today' : `${left} day${left === 1 ? '' : 's'} left`}</Badge>
                            )}
                          </>
                        ) : (
                          <span className={styles.mutedNote}>No access</span>
                        )}
                        {blocked && (
                          <div className={styles.blockedNote}>
                            <Icon name="alert" size={12} />
                            {salon.unsettled_payouts} payout{salon.unsettled_payouts === 1 ? '' : 's'} open
                          </div>
                        )}
                      </td>
                      <td className={ui.alignRight}>
                        <div className={styles.rowActions}>
                          {onCommission && (
                            <Button
                              size="sm"
                              onClick={() => openRateChange(salon)}
                              disabled={blocked}
                              title={blocked ? 'Settle this salon’s open payouts before changing the rate' : 'Change the agreed commission percentage'}
                            >
                              Change rate
                            </Button>
                          )}
                          <Button size="sm" variant="soft" onClick={() => openAssign(salon)}>Change model</Button>
                        </div>
                      </td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </table>
        </div>
      </Card>

      {/* ============================================================ overlays */}

      <Modal
        open={!!viewingScreenshot}
        onClose={() => setViewingScreenshot(null)}
        size="lg"
        title="Payment receipt"
        footer={
          <>
            {viewingScreenshot && (
              <a href={viewingScreenshot} target="_blank" rel="noreferrer" className={cx(ui.btn, ui.btnGhost)}>
                Open original <Icon name="external" size={14} />
              </a>
            )}
            <Button variant="primary" onClick={() => setViewingScreenshot(null)}>Close</Button>
          </>
        }
      >
        {viewingScreenshot && (
          // eslint-disable-next-line @next/next/no-img-element -- user-uploaded receipt from an arbitrary host
          <img src={viewingScreenshot} alt="Payment receipt" className={styles.receipt} />
        )}
      </Modal>

      <Modal
        open={isPlanModalOpen}
        onClose={() => setIsPlanModalOpen(false)}
        size="lg"
        title={editingPlanId ? 'Edit plan' : 'New plan'}
        description="What a salon gets, and what it costs."
        footer={
          <>
            <Button variant="ghost" onClick={() => setIsPlanModalOpen(false)}>Cancel</Button>
            <Button variant="primary" type="submit" form="planForm" loading={isSaving}>
              {editingPlanId ? 'Save changes' : 'Create plan'}
            </Button>
          </>
        }
      >
        <form id="planForm" onSubmit={handleSavePlan} className={styles.form}>
          <h4 className={ui.sectionLabel}>Basics</h4>
          <div className={styles.formGrid}>
            <Field label="Plan name" className={styles.span2}>
              <input className={ui.control} value={planFormData.name} onChange={(e) => setPlanFormData({ ...planFormData, name: e.target.value })} required placeholder="e.g. Growth" />
            </Field>
            <Field label="Price (₹)">
              <input className={ui.control} type="number" min="0" value={planFormData.price} onChange={(e) => setPlanFormData({ ...planFormData, price: e.target.value })} required />
            </Field>
            <Field label="Validity (days)">
              <input className={ui.control} type="number" min="1" value={planFormData.validity_days} onChange={(e) => setPlanFormData({ ...planFormData, validity_days: e.target.value })} required />
            </Field>
            <Field label="WhatsApp campaign limit" hint="Campaigns a salon can send per validity period." className={styles.span2}>
              <input className={ui.control} type="number" min="0" value={planFormData.whatsapp_campaign_limit} onChange={(e) => setPlanFormData({ ...planFormData, whatsapp_campaign_limit: e.target.value })} required />
            </Field>
          </div>

          <h4 className={ui.sectionLabel}>Targeting &amp; insights</h4>
          <div className={styles.checkGrid}>
            {FEATURE_FLAGS.map((f) => {
              const on = !!planFormData[f.key];
              return (
                <label key={f.key} className={cx(ui.check, on && ui.checkOn)}>
                  <input type="checkbox" checked={on} onChange={(e) => setPlanFormData({ ...planFormData, [f.key]: e.target.checked })} />
                  {f.label}
                </label>
              );
            })}
          </div>

          <h4 className={ui.sectionLabel}>Recommendations</h4>
          <div className={styles.formGrid}>
            <Field label="Upsell recommendations">
              <select className={ui.control} value={planFormData.has_upsell_recommendations} onChange={(e) => setPlanFormData({ ...planFormData, has_upsell_recommendations: e.target.value })}>
                <option value="none">None</option>
                <option value="basic">Basic</option>
                <option value="advanced">Advanced</option>
              </select>
            </Field>
            <Field label="Cross-sell recommendations">
              <select className={ui.control} value={planFormData.has_cross_sell_recommendations} onChange={(e) => setPlanFormData({ ...planFormData, has_cross_sell_recommendations: e.target.value })}>
                <option value="none">None</option>
                <option value="basic">Basic</option>
                <option value="advanced">Advanced</option>
              </select>
            </Field>
          </div>

          <label className={cx(ui.check, planFormData.is_active && ui.checkOn, styles.activeToggle)}>
            <input type="checkbox" checked={planFormData.is_active} onChange={(e) => setPlanFormData({ ...planFormData, is_active: e.target.checked })} />
            <span>
              <b>Available for sale</b>
              <span className={styles.checkHint}>Inactive plans stay on existing salons but can’t be newly assigned.</span>
            </span>
          </label>
        </form>
      </Modal>

      <Modal
        open={!!assigningSalon}
        onClose={() => setAssigningSalon(null)}
        title={assigningSalon ? `How ${assigningSalon.name} pays` : ''}
        description="Switching models takes effect immediately."
        footer={
          <>
            <Button variant="ghost" onClick={() => setAssigningSalon(null)}>Cancel</Button>
            <Button
              variant="primary"
              type="submit"
              form="assignForm"
              loading={isSaving}
              disabled={billingModel === SUBSCRIPTION && !selectedPlanId}
            >
              Apply
            </Button>
          </>
        }
      >
        <form id="assignForm" onSubmit={handleAssignPlan} className={styles.form}>
          <div className={styles.modelChoice} role="radiogroup" aria-label="Billing model">
            {[
              { value: SUBSCRIPTION, title: 'Subscription Plan', desc: 'Prepaid, expires at the end of the plan.', icon: 'crown' as const },
              { value: COMMISSION, title: 'Commission Model', desc: 'Postpaid, a % of billing settled monthly.', icon: 'percent' as const },
            ].map((m) => (
              <label key={m.value} className={cx(styles.modelCard, billingModel === m.value && styles.modelCardOn)}>
                <input type="radio" name="billing_model" value={m.value} checked={billingModel === m.value} onChange={() => setBillingModel(m.value)} />
                <span className={styles.modelIcon}><Icon name={m.icon} size={18} /></span>
                <span className={styles.modelTitle}>{m.title}</span>
                <span className={styles.modelDesc}>{m.desc}</span>
              </label>
            ))}
          </div>

          {billingModel === SUBSCRIPTION ? (
            <Field label="Plan to sell them">
              <select className={ui.control} value={selectedPlanId} onChange={(e) => setSelectedPlanId(e.target.value)} required>
                {purchasablePlans.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.name} — {formatINR(p.price)} ({p.validity_days} days)
                  </option>
                ))}
              </select>
              {purchasablePlans.length === 0 && (
                <Alert tone="warning">Every plan is nominated for the Commission Model. Create one to sell.</Alert>
              )}
            </Field>
          ) : (
            <>
              <Field label="Commission percentage">
                <div className={styles.suffixInput}>
                  <input className={ui.control} type="number" step="0.01" min="0" max="100" value={commissionPercentage} onChange={(e) => setCommissionPercentage(e.target.value)} required />
                  <span>%</span>
                </div>
              </Field>
              <p className={styles.hint}>
                They get the <strong>{commissionPlan?.name ?? 'commission'}</strong> plan’s benefits and pay{' '}
                {commissionPercentage || '—'}% of everything they bill, settled on the 1st of each month.
              </p>
            </>
          )}
        </form>
      </Modal>

      <Modal
        open={!!ratingSalon}
        onClose={() => setRatingSalon(null)}
        title={ratingSalon ? `Commission for ${ratingSalon.name}` : ''}
        description={
          ratingSalon &&
          `Currently ${pct(ratingSalon.commission_percentage)}. The new rate is charged on everything billed from today; settled payouts keep the rate they were charged at.`
        }
        footer={
          <>
            <Button variant="ghost" onClick={() => setRatingSalon(null)}>Cancel</Button>
            <Button variant="primary" type="submit" form="rateForm" loading={isSaving}>Change rate</Button>
          </>
        }
      >
        <form id="rateForm" onSubmit={handleRateChange} className={styles.form}>
          {rateError && <Alert tone="error">{rateError}</Alert>}
          {blockingPayouts.length > 0 && (
            <ul className={styles.blockingList}>
              {blockingPayouts.map((p) => (
                <li key={p.id}>
                  <span>{fmtDay(p.cycle_start_date)} → {fmtDay(p.cycle_end_date)}</span>
                  <b>{formatINR(p.net_amount, 2)}</b>
                  <Badge tone="warning">{p.status}</Badge>
                </li>
              ))}
            </ul>
          )}
          <Field label="New percentage">
            <div className={styles.suffixInput}>
              <input className={ui.control} type="number" step="0.01" min="0" max="100" value={newRate} onChange={(e) => setNewRate(e.target.value)} required />
              <span>%</span>
            </div>
          </Field>
          <Field label="Reason" hint="Optional — recorded in the audit log.">
            <input className={ui.control} value={rateReason} onChange={(e) => setRateReason(e.target.value)} placeholder="e.g. Renegotiated at renewal" />
          </Field>
        </form>
      </Modal>

      <Modal
        open={!!infoSalon}
        onClose={() => setInfoSalon(null)}
        size="md"
        title={infoSalon?.name ?? 'Salon'}
        header={infoSalon && <Person name={infoSalon.name} sub={infoSalon.owner} size={44} />}
        footer={<Button variant="primary" onClick={() => setInfoSalon(null)}>Close</Button>}
      >
        {infoSalon && (infoLoading && infoSalon.detail == null ? (
          <div className={styles.form}>
            <Skeleton height={140} radius={14} />
            <Skeleton height={100} radius={14} />
          </div>
        ) : infoSalon.detail ? (
          <>
            <div className={styles.infoStats}>
              <div className={styles.fact}><span>Staff</span><b>{infoSalon.detail.providers?.length ?? '—'}</b></div>
              <div className={styles.fact}><span>Services</span><b>{infoSalon.detail.services?.length ?? '—'}</b></div>
              <div className={styles.fact}><span>Combos</span><b>{infoSalon.detail.combos?.length ?? '—'}</b></div>
            </div>
            <h4 className={ui.sectionLabel}>Salon</h4>
            <DescriptionList
              items={[
                ['Status', infoSalon.detail.status],
                ['City', infoSalon.detail.city?.name],
                ['Address', infoSalon.detail.address],
                ['Pincode', infoSalon.detail.pincode],
                ['Gender focus', infoSalon.detail.gender_focus],
                ['Description', infoSalon.detail.description],
              ]}
            />
            <h4 className={ui.sectionLabel}>Owner</h4>
            <DescriptionList
              items={[
                ['Name', infoSalon.detail.admin?.name],
                ['Phone', infoSalon.detail.admin?.phone],
                ['Email', infoSalon.detail.admin?.email],
              ]}
            />
            <h4 className={ui.sectionLabel}>Billing</h4>
            <DescriptionList
              items={[
                ['Model', infoSalon.billing_label ?? modelLabel(infoSalon.billing_model)],
                ['Plan', infoSalon.current_plan],
                ...(infoSalon.billing_model === COMMISSION
                  ? ([['Commission', pct(infoSalon.commission_percentage)]] as [string, string][])
                  : []),
                ['Access until', infoSalon.expiry ? fmtDay(infoSalon.expiry) : 'N/A'],
                ['Registered', infoSalon.detail.created_at ? new Date(infoSalon.detail.created_at).toLocaleDateString('en-IN') : '—'],
              ]}
            />
          </>
        ) : (
          <EmptyState icon="alert" title="Could not load salon details" />
        ))}
      </Modal>

      {confirmDialog}
    </div>
  );
}
