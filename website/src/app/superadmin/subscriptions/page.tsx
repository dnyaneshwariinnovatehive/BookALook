'use client';

import { useState, useEffect, useMemo } from 'react';
import Icon from '@/components/admin/Icon';
import {
  Alert, Badge, Button, Card, DescriptionList, EmptyState, Field, IconButton, Modal, PageHeader,
  Person, SearchInput, Segmented, Skeleton, StatCard, Tabs, cx, formatINR, localISODate, ui, useConfirm,
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

const fmtDateStr = (str?: string | null) => {
  if (!str) return '—';
  try {
    const clean = str.includes('T') ? str : str.replace(' ', 'T');
    const d = new Date(clean);
    if (isNaN(d.getTime())) return str;
    return d.toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' });
  } catch {
    return str;
  }
};


export default function SubscriptionsPage() {
  const [plans, setPlans] = useState<any[]>([]);
  const [salons, setSalons] = useState<any[]>([]);
  const [commissionPlanId, setCommissionPlanId] = useState<string | null>(null);
  const [graceDays, setGraceDays] = useState<number>(7);
  // Fetched with `status=all` rather than pending, so the queue and the history
  // table below are two views of one response. The pending list is derived from
  // it — two fetches of the same rows would be two things to fall out of step.
  const [allRequests, setAllRequests] = useState<any[]>([]);
  const [requestStatus, setRequestStatus] = useState('all');
  const [requestSearch, setRequestSearch] = useState('');
  // The whole request, not just its screenshot URL: the transaction id and note
  // the owner typed are the reason the receipt is being looked at, so they are
  // shown alongside it rather than making the viewer go and find them.
  const [viewingRequest, setViewingRequest] = useState<any>(null);
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

  // Salon detail popup — runs off full salon endpoint, subscription history, appointments & payouts.
  type SalonInfoTab = 'salon_info' | 'owner_details' | 'appointments' | 'finance' | 'payouts' | 'plan_history';
  const [infoSalon, setInfoSalon] = useState<any>(null);
  const [infoLoading, setInfoLoading] = useState(false);
  const [infoSalonTab, setInfoSalonTab] = useState<SalonInfoTab>('salon_info');
  const [infoSubscriptionData, setInfoSubscriptionData] = useState<any>(null);
  const [infoSubscriptionLoading, setInfoSubscriptionLoading] = useState(false);
  const [infoSubscriptionError, setInfoSubscriptionError] = useState('');

  // Appointments & Finance for the salon
  const [infoAppointments, setInfoAppointments] = useState<any[]>([]);
  const [infoAppointmentsLoading, setInfoAppointmentsLoading] = useState(false);
  const [infoAppointmentsError, setInfoAppointmentsError] = useState('');

  // Payout data for the salon
  const [infoPayoutsData, setInfoPayoutsData] = useState<any>(null);
  const [infoPayoutsLoading, setInfoPayoutsLoading] = useState(false);
  const [infoPayoutsError, setInfoPayoutsError] = useState('');
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

      const reqRes = await fetch('/api/proxy/superadmin/subscription-requests?status=all', { headers: authHeaders() });
      const reqData = await reqRes.json();
      if (reqData.success) {
        setAllRequests(Array.isArray(reqData.requests) ? reqData.requests : []);
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
  // salon endpoint for address, contact, city, staff and service counts, to
  // the subscription-history endpoint for plans, to appointments for recent bookings & finance,
  // and to payouts for settlement cycle data.
  const openSalonInfo = (salon: any, initialTab: SalonInfoTab = 'salon_info') => {
    if (!salon?.id) return;
    setInfoSalonTab(initialTab);
    setInfoSalon({ ...salon, detail: null });
    setInfoLoading(true);
    setInfoSubscriptionData(null);
    setInfoSubscriptionLoading(true);
    setInfoSubscriptionError('');
    setInfoAppointments([]);
    setInfoAppointmentsLoading(true);
    setInfoAppointmentsError('');
    setInfoPayoutsData(null);
    setInfoPayoutsLoading(true);
    setInfoPayoutsError('');

    // 1. Full Salon details & Owner admin info
    fetch(`/api/proxy/superadmin/salons/${salon.id}`, {
      headers: authHeaders(),
    })
      .then((res) => res.json())
      .then((data) => {
        if (data.success) {
          setInfoSalon((prev: any) => (prev ? { ...prev, detail: data.data } : prev));
        }
      })
      .catch((e) => console.error('Failed to load salon details:', e))
      .finally(() => setInfoLoading(false));

    // 2. Subscription plans & payment requests history
    fetch(`/api/proxy/superadmin/salons/${salon.id}/subscription-history`, {
      headers: authHeaders(),
    })
      .then((res) => res.json())
      .then((data) => {
        if (data.success) {
          setInfoSubscriptionData(data);
        } else {
          setInfoSubscriptionError(data.message || 'Could not load subscription history.');
        }
      })
      .catch((e) => {
        console.error('Failed to load subscription history:', e);
        setInfoSubscriptionError('Could not reach the server.');
      })
      .finally(() => setInfoSubscriptionLoading(false));

    // 3. Appointments & Appointment-related finance
    fetch(`/api/proxy/superadmin/appointments?salon_id=${salon.id}&per_page=30`, {
      headers: authHeaders(),
    })
      .then((res) => res.json())
      .then((data) => {
        if (data.success && Array.isArray(data.data)) {
          setInfoAppointments(data.data);
        } else if (Array.isArray(data.appointments)) {
          setInfoAppointments(data.appointments);
        } else if (Array.isArray(data)) {
          setInfoAppointments(data);
        }
      })
      .catch((e) => {
        console.error('Failed to load salon appointments:', e);
        setInfoAppointmentsError('Could not load appointments.');
      })
      .finally(() => setInfoAppointmentsLoading(false));

    // 4. Payout settlement data
    fetch(`/api/proxy/superadmin/salons/${salon.id}/payouts`, {
      headers: authHeaders(),
    })
      .then((res) => res.json())
      .then((data) => {
        if (data.success) {
          setInfoPayoutsData(data);
        } else {
          // Fallback check for partner payouts endpoint
          fetch(`/api/proxy/partner/salons/${salon.id}/payouts`, { headers: authHeaders() })
            .then((r) => r.json())
            .then((pData) => {
              if (pData.success) setInfoPayoutsData(pData);
              else setInfoPayoutsError(data.message || 'No payouts available yet.');
            })
            .catch(() => setInfoPayoutsError(data.message || 'No payouts available yet.'));
        }
      })
      .catch((e) => {
        console.error('Failed to load salon payouts:', e);
        setInfoPayoutsError('Could not reach payouts service.');
      })
      .finally(() => setInfoPayoutsLoading(false));
  };

  const openSalonPlanHistory = (salonId?: number | string | null, salonName?: string) => {
    if (!salonId) return;
    const existing = salons.find((s) => String(s.id) === String(salonId));
    openSalonInfo(existing || { id: salonId, name: salonName || 'Salon' }, 'plan_history');
  };

  // Financial KPIs derived from appointments
  const financeMetrics = useMemo(() => {
    if (!infoAppointments || infoAppointments.length === 0) {
      return {
        totalRevenue: 0,
        advancesCollected: 0,
        balanceCollected: 0,
        completedCount: 0,
        cancelledCount: 0,
        avgTicket: 0,
      };
    }

    let totalRevenue = 0;
    let advancesCollected = 0;
    let balanceCollected = 0;
    let completedCount = 0;
    let cancelledCount = 0;

    for (const apt of infoAppointments) {
      const isCompleted = apt.status === 'completed';
      const isCancelled = apt.status === 'cancelled' || apt.status === 'no_show';
      if (isCompleted) completedCount++;
      if (isCancelled) cancelledCount++;

      const bill = parseFloat(apt.final_billed_amount ?? apt.total_amount ?? 0) || 0;
      const adv = parseFloat(apt.advance_amount ?? 0) || 0;
      const bal = parseFloat(apt.balance_amount ?? (bill > adv ? bill - adv : 0)) || 0;

      if (!isCancelled) {
        totalRevenue += bill;
        advancesCollected += adv;
        balanceCollected += bal;
      }
    }

    const validCount = infoAppointments.filter((a) => a.status !== 'cancelled' && a.status !== 'no_show').length;
    const avgTicket = validCount > 0 ? totalRevenue / validCount : 0;

    return {
      totalRevenue,
      advancesCollected,
      balanceCollected,
      completedCount,
      cancelledCount,
      avgTicket,
    };
  }, [infoAppointments]);

  // Appointment counts
  const appointmentCounts = useMemo(() => {
    const total = infoAppointments.length;
    let completed = 0;
    let upcoming = 0;
    let cancelled = 0;
    for (const apt of infoAppointments) {
      if (apt.status === 'completed') completed++;
      else if (apt.status === 'cancelled' || apt.status === 'no_show') cancelled++;
      else upcoming++;
    }
    return { total, completed, upcoming, cancelled };
  }, [infoAppointments]);

  const appointmentStatusTone = (status?: string): 'success' | 'info' | 'warning' | 'danger' | 'neutral' => {
    switch (status) {
      case 'completed': return 'success';
      case 'confirmed':
      case 'in_progress': return 'info';
      case 'pending': return 'warning';
      case 'cancelled':
      case 'no_show': return 'danger';
      default: return 'neutral';
    }
  };

  const payoutStatusTone = (status?: string): 'success' | 'warning' | 'neutral' => {
    switch (status) {
      case 'distributed': return 'success';
      case 'approved': return 'warning';
      default: return 'neutral';
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

  const pendingRequests = useMemo(
    () => allRequests.filter((r) => r.status === 'pending'),
    [allRequests],
  );

  /* The decided history, filtered live. Search covers the fields someone would
     actually have to hand: the salon, the plan, and the transaction reference —
     because the reference is how a bank transfer is traced back to the row that
     authorised it, and searching only by salon would not find it. */
  const decidedRequests = useMemo(() => {
    const q = requestSearch.trim().toLowerCase();

    return allRequests
      .filter((r) => r.status !== 'pending')
      .filter((r) => (requestStatus === 'all' ? true : r.status === requestStatus))
      .filter((r) => {
        if (!q) return true;
        return [r.salon?.name, r.plan?.name, r.billing_label, r.transaction_id, r.note]
          .some((v) => String(v ?? '').toLowerCase().includes(q));
      });
  }, [allRequests, requestStatus, requestSearch]);

  /** A blank typed reference means the owner left it out, not that it is empty. */
  const refText = (req: any) => req.transaction_id || req.note ? (
    <>
      {req.transaction_id && <b className={styles.refId}>{req.transaction_id}</b>}
      {req.note && <span className={styles.refNote}>{req.note}</span>}
    </>
  ) : (
    <span className={styles.mutedNote}>Not given</span>
  );

  const statusTone = (status: string): 'success' | 'danger' | 'neutral' =>
    status === 'approved' ? 'success' : status === 'rejected' ? 'danger' : 'neutral';

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
          tone={pendingRequests.length ? 'warning' : 'success'}
          loading={isLoading}
          value={pendingRequests.length}
          sub={pendingRequests.length ? 'Requests to verify' : 'Nothing pending'}
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
      {pendingRequests.length > 0 && (
        <Card
          className={styles.pendingCard}
          title={<>Waiting on you <Badge tone="warning" dot={false}>{pendingRequests.length}</Badge></>}
          subtitle="Paid subscriptions to verify, and salons asking to move onto the Commission Model. A commission request has no receipt — you agree the percentage when you approve it."
        >
          <div className={ui.tableWrap}>
            <table className={ui.table}>
              <thead>
                <tr>
                  <th>Salon</th>
                  <th>Asking for</th>
                  <th>Plan</th>
                  <th>Transaction reference</th>
                  <th>Raised</th>
                  <th className={ui.alignRight}>Action</th>
                </tr>
              </thead>
              <tbody>
                {pendingRequests.map((req) => {
                  const isCommission = req.billing_type === COMMISSION;
                  return (
                    <tr key={req.id}>
                      <td>
                        <button
                          type="button"
                          className={styles.salonBtn}
                          onClick={() => openSalonInfo(req.salon || { id: req.salon_id, name: req.salon?.name })}
                          title="View salon details"
                        >
                          <Person name={req.salon?.name ?? 'Unknown salon'} size={32} />
                        </button>
                      </td>
                      <td>
                        <Badge tone={isCommission ? 'accent' : 'info'}>{req.billing_label ?? modelLabel(req.billing_type)}</Badge>
                      </td>
                      <td>{req.plan?.name || '—'}</td>
                      {/* What the owner said about their transfer, on the row
                          itself. Deciding a request on the strength of a
                          reference should not require opening the receipt. */}
                      <td><div className={styles.refCell}>{refText(req)}</div></td>
                      <td className={ui.num}>{new Date(req.created_at).toLocaleDateString('en-IN', { day: 'numeric', month: 'short' })}</td>
                      <td className={ui.alignRight}>
                        <div className={styles.rowActions}>
                          {req.screenshot_url ? (
                            <Button size="sm" icon="receipt" onClick={() => setViewingRequest(req)}>Receipt</Button>
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

      {/* ------------------------------------------------ payment history */}
      <Card
        title="Payment history"
        subtitle="Every payment a salon has sent, and what became of it. Approved rows are the record that money arrived; a transaction id typed by the owner is kept against them so a transfer can still be traced to this row later."
        actions={
          <Segmented
            ariaLabel="Filter by decision"
            value={requestStatus}
            onChange={setRequestStatus}
            options={[
              { value: 'all', label: 'All', count: allRequests.filter((r) => r.status !== 'pending').length },
              { value: 'approved', label: 'Approved', count: allRequests.filter((r) => r.status === 'approved').length },
              { value: 'rejected', label: 'Rejected', count: allRequests.filter((r) => r.status === 'rejected').length },
            ]}
          />
        }
      >
        <div className={styles.subToolbar}>
          <SearchInput
            value={requestSearch}
            onChange={setRequestSearch}
            placeholder="Search salon, plan, transaction ID or note."
            ariaLabel="Search payment history"
          />
          <span className={styles.mutedNote}>
            {decidedRequests.length} of {allRequests.filter((r) => r.status !== 'pending').length} shown
          </span>
        </div>

        {isLoading ? (
          <Skeleton height={120} radius={14} />
        ) : decidedRequests.length === 0 ? (
          <EmptyState
            icon="receipt"
            title={requestSearch || requestStatus !== 'all' ? 'Nothing matches that' : 'No payments decided yet'}
            hint={
              requestSearch || requestStatus !== 'all'
                ? 'Try a different status, or clear the search.'
                : 'Once a payment is approved or declined it is listed here.'
            }
          />
        ) : (
          <div className={ui.tableWrap}>
            <table className={ui.table}>
              <thead>
                <tr>
                  <th>Salon</th>
                  <th>Arrangement</th>
                  <th>Plan</th>
                  <th className={ui.alignRight}>Paid</th>
                  <th>Transaction reference</th>
                  <th>Sent</th>
                  <th>Decision</th>
                  <th>Plan history</th>
                  <th className={ui.alignRight}>Receipt</th>
                </tr>
              </thead>
              <tbody>
                {decidedRequests.map((req) => (
                  <tr key={req.id}>
                    <td>
                      <button
                        type="button"
                        className={styles.salonBtn}
                        onClick={() => openSalonInfo(req.salon || { id: req.salon_id, name: req.salon?.name })}
                        title="View salon details"
                      >
                        <Person name={req.salon?.name ?? 'Unknown salon'} size={32} />
                      </button>
                    </td>
                    <td><Badge tone={req.billing_type === COMMISSION ? 'accent' : 'info'}>{req.billing_label ?? modelLabel(req.billing_type)}</Badge></td>
                    <td>{req.plan?.name || '—'}</td>
                    <td className={ui.alignRight}>
                      {req.amount_payable_inr != null ? formatINR(req.amount_payable_inr, 2) : <span className={styles.mutedNote}>—</span>}
                      {Number(req.coins_to_redeem) > 0 && (
                        <div className={styles.refNote}>+{req.coins_to_redeem} coins</div>
                      )}
                    </td>
                    <td><div className={styles.refCell}>{refText(req)}</div></td>
                    <td className={ui.num}>
                      {new Date(req.created_at).toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' })}
                    </td>
                    <td>
                      <Badge tone={statusTone(req.status)} dot={false}>
                        {req.status === 'approved' ? 'Approved' : 'Rejected'}
                      </Badge>
                    </td>
                    <td>
                      <Button
                        size="sm"
                        variant="soft"
                        icon="history"
                        onClick={() => openSalonPlanHistory(req.salon_id ?? req.salon?.id, req.salon?.name)}
                      >
                        Plan history
                      </Button>
                    </td>
                    <td className={ui.alignRight}>
                      {req.screenshot_url ? (
                        <Button size="sm" variant="ghost" icon="receipt" onClick={() => setViewingRequest(req)}>
                          View
                        </Button>
                      ) : (
                        <span className={styles.mutedNote}>None</span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>

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
        open={!!viewingRequest}
        onClose={() => setViewingRequest(null)}
        size="lg"
        title="Payment receipt"
        description={
          viewingRequest
            ? `${viewingRequest.salon?.name ?? 'Unknown salon'} — ${viewingRequest.plan?.name ?? viewingRequest.billing_label ?? ''}`
            : undefined
        }
        footer={
          <>
            {viewingRequest?.screenshot_url && (
              <a href={viewingRequest.screenshot_url} target="_blank" rel="noreferrer" className={cx(ui.btn, ui.btnGhost)}>
                Open original <Icon name="external" size={14} />
              </a>
            )}
            <Button variant="primary" onClick={() => setViewingRequest(null)}>Close</Button>
          </>
        }
      >
        {viewingRequest && (
          <>
            {/* The reference above the image, not below it. Whether the
                screenshot is legible is exactly what is in doubt when a payment
                is disputed, so the text the owner typed has to be readable
                without opening the original. */}
            <div className={styles.receiptHead}>
              {viewingRequest.status && (
                <Badge tone={statusTone(viewingRequest.status)} dot={false}>
                  {viewingRequest.status === 'approved' ? 'Approved' : viewingRequest.status === 'rejected' ? 'Rejected' : 'Under review'}
                </Badge>
              )}
              {viewingRequest.transaction_id && (
                <div className={styles.receiptRef}>
                  <span>Transaction ID</span>
                  <b>{viewingRequest.transaction_id}</b>
                </div>
              )}
              {viewingRequest.note && (
                <div className={styles.receiptRef}>
                  <span>Note from the salon</span>
                  <b>{viewingRequest.note}</b>
                </div>
              )}
            </div>

            {viewingRequest.screenshot_url ? (
              // eslint-disable-next-line @next/next/no-img-element -- user-uploaded receipt from an arbitrary host
              <img src={viewingRequest.screenshot_url} alt="Payment receipt" className={styles.receipt} />
            ) : (
              <p className={styles.mutedNote}>
                No screenshot was sent with this request.
                {viewingRequest.needs_commission_rate && ' Commission requests carry no payment, only a rate to agree.'}
              </p>
            )}
          </>
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
        size="lg"
        title={infoSalon?.name ?? 'Salon'}
        header={
          infoSalon && (
            <div className={styles.salonModalHead}>
              <div className={styles.salonModalHeadMain}>
                <Person name={infoSalon.name} sub={infoSalon.detail?.admin?.name || infoSalon.owner || 'Salon Owner'} size={44} />
                <div className={styles.salonModalHeadPills}>
                  <Badge tone={infoSalon.detail?.status === 'active' ? 'success' : 'neutral'} dot={infoSalon.detail?.status === 'active'}>
                    {infoSalon.detail?.status ? infoSalon.detail.status.charAt(0).toUpperCase() + infoSalon.detail.status.slice(1) : 'Active'}
                  </Badge>
                  <Badge tone={infoSalon.billing_model === COMMISSION ? 'accent' : 'info'}>
                    {infoSalon.billing_label ?? modelLabel(infoSalon.billing_model)}
                  </Badge>
                  {infoSalon.current_plan && infoSalon.current_plan !== 'None' && (
                    <Badge tone="neutral">{infoSalon.current_plan}</Badge>
                  )}
                  {infoSalon.detail?.city?.name && (
                    <span className={styles.headCityPill}>
                      <Icon name="pin" size={13} /> {infoSalon.detail.city.name}
                    </span>
                  )}
                </div>
              </div>
            </div>
          )
        }
        footer={<Button variant="primary" onClick={() => setInfoSalon(null)}>Close</Button>}
      >
        {infoSalon && (
          <div className={styles.salonModalWrapper}>
            <div className={styles.modalTabsWrap}>
              <Tabs<SalonInfoTab>
                value={infoSalonTab}
                onChange={setInfoSalonTab}
                tabs={[
                  { value: 'salon_info', label: <span><Icon name="store" size={15} /> Salon Info</span> },
                  { value: 'owner_details', label: <span><Icon name="users" size={15} /> Owner Details</span> },
                  {
                    value: 'appointments',
                    label: (
                      <span>
                        <Icon name="calendar" size={15} /> Appointments
                        {infoAppointments?.length ? <span className={styles.tabBadge}>{infoAppointments.length}</span> : null}
                      </span>
                    ),
                  },
                  { value: 'finance', label: <span><Icon name="rupee" size={15} /> Finance</span> },
                  {
                    value: 'payouts',
                    label: (
                      <span>
                        <Icon name="wallet" size={15} /> Payouts
                        {infoPayoutsData?.payouts?.length ? <span className={styles.tabBadge}>{infoPayoutsData.payouts.length}</span> : null}
                      </span>
                    ),
                  },
                  {
                    value: 'plan_history',
                    label: (
                      <span>
                        <Icon name="history" size={15} /> Plan History
                        {infoSubscriptionData?.subscriptions?.length ? (
                          <span className={styles.tabBadge}>{infoSubscriptionData.subscriptions.length}</span>
                        ) : null}
                      </span>
                    ),
                  },
                ]}
              />
            </div>

            {/* ===================== TAB 1: SALON INFO ===================== */}
            {infoSalonTab === 'salon_info' && (
              infoLoading && infoSalon.detail == null ? (
                <div className={styles.historyLoadingWrap}>
                  <Skeleton height={80} radius={14} />
                  <Skeleton height={200} radius={14} />
                </div>
              ) : infoSalon.detail ? (
                <div className={styles.sectionFade}>
                  <div className={styles.infoStatsGrid}>
                    <div className={styles.statTile}>
                      <div className={styles.statTileIcon}><Icon name="users" size={18} /></div>
                      <div>
                        <span className={styles.statTileLabel}>Staff Members</span>
                        <b className={styles.statTileValue}>{infoSalon.detail.providers?.length ?? 0}</b>
                      </div>
                    </div>
                    <div className={styles.statTile}>
                      <div className={styles.statTileIcon}><Icon name="catalog" size={18} /></div>
                      <div>
                        <span className={styles.statTileLabel}>Services Offered</span>
                        <b className={styles.statTileValue}>{infoSalon.detail.services?.length ?? 0}</b>
                      </div>
                    </div>
                    <div className={styles.statTile}>
                      <div className={styles.statTileIcon}><Icon name="sparkle" size={18} /></div>
                      <div>
                        <span className={styles.statTileLabel}>Combos &amp; Packages</span>
                        <b className={styles.statTileValue}>{infoSalon.detail.combos?.length ?? 0}</b>
                      </div>
                    </div>
                    <div className={styles.statTile}>
                      <div className={styles.statTileIcon}><Icon name="store" size={18} /></div>
                      <div>
                        <span className={styles.statTileLabel}>Gender Focus</span>
                        <b className={styles.statTileValue}>{infoSalon.detail.gender_focus || 'Unisex'}</b>
                      </div>
                    </div>
                  </div>

                  <div className={styles.detailsCard}>
                    <h4 className={ui.sectionLabel}>Salon Details</h4>
                    <DescriptionList
                      items={[
                        ['Salon Name', infoSalon.name],
                        ['Slug', infoSalon.detail.slug || '—'],
                        ['City', infoSalon.detail.city?.name || '—'],
                        ['Address', infoSalon.detail.address || '—'],
                        ['Pincode', infoSalon.detail.pincode || '—'],
                        ['Gender focus', infoSalon.detail.gender_focus || 'Unisex'],
                        ['Trading arrangement', modelLabel(infoSalon.billing_model)],
                        ['Current plan', infoSalon.current_plan || 'None'],
                        ['Assigned collaborator', infoSalon.detail.assigned_collaborator?.name ? (
                          <span>{infoSalon.detail.assigned_collaborator.name} ({infoSalon.detail.assigned_collaborator.email})</span>
                        ) : 'Unassigned'],
                        ['Registered date', infoSalon.detail.created_at ? fmtDateStr(infoSalon.detail.created_at) : '—'],
                        ...(infoSalon.detail.description ? ([['About / Description', infoSalon.detail.description]] as [string, string][]) : []),
                      ]}
                    />
                  </div>
                </div>
              ) : (
                <EmptyState icon="alert" title="Could not load salon details" />
              )
            )}

            {/* ===================== TAB 2: OWNER DETAILS ===================== */}
            {infoSalonTab === 'owner_details' && (
              <div className={styles.sectionFade}>
                <div className={styles.ownerCard}>
                  <div className={styles.ownerHead}>
                    <div className={styles.ownerAvatar}>
                      <Icon name="users" size={28} />
                    </div>
                    <div className={styles.ownerMeta}>
                      <div className={styles.ownerNameRow}>
                        <h3 className={styles.ownerName}>
                          {infoSalon.detail?.admin?.name || infoSalon.owner || 'Unknown Owner'}
                        </h3>
                        <Badge tone="accent">Salon Admin / Owner</Badge>
                      </div>
                      <p className={styles.ownerSubtitle}>Primary account holder &amp; business manager for this salon</p>
                    </div>
                  </div>

                  <div className={styles.ownerContactGrid}>
                    <div className={styles.contactItem}>
                      <span className={styles.contactIcon}><Icon name="phone" size={18} /></span>
                      <div className={styles.contactInfo}>
                        <span className={styles.contactLabel}>Phone Number</span>
                        <b className={styles.contactValue}>{infoSalon.detail?.admin?.phone || 'Not provided'}</b>
                      </div>
                      {infoSalon.detail?.admin?.phone && (
                        <a href={`tel:${infoSalon.detail.admin.phone}`} className={styles.contactActionBtn} title="Call phone number">
                          <Icon name="phone" size={14} /> Call
                        </a>
                      )}
                    </div>

                    <div className={styles.contactItem}>
                      <span className={styles.contactIcon}><Icon name="mail" size={18} /></span>
                      <div className={styles.contactInfo}>
                        <span className={styles.contactLabel}>Email Address</span>
                        <b className={styles.contactValue}>{infoSalon.detail?.admin?.email || 'Not provided'}</b>
                      </div>
                      {infoSalon.detail?.admin?.email && (
                        <a href={`mailto:${infoSalon.detail.admin.email}`} className={styles.contactActionBtn} title="Send email">
                          <Icon name="mail" size={14} /> Email
                        </a>
                      )}
                    </div>
                  </div>
                </div>

                <div className={styles.detailsCard}>
                  <h4 className={ui.sectionLabel}>Account &amp; Ownership Verification</h4>
                  <DescriptionList
                    items={[
                      ['Owner full name', infoSalon.detail?.admin?.name || infoSalon.owner || '—'],
                      ['Phone number', infoSalon.detail?.admin?.phone || '—'],
                      ['Email address', infoSalon.detail?.admin?.email || '—'],
                      ['Associated salon', `${infoSalon.name} (#${infoSalon.id})`],
                      ['Registered on platform', infoSalon.detail?.created_at ? fmtDateStr(infoSalon.detail.created_at) : '—'],
                      ['Arrangement with platform', modelLabel(infoSalon.billing_model)],
                    ]}
                  />
                </div>
              </div>
            )}

            {/* ===================== TAB 3: APPOINTMENTS ===================== */}
            {infoSalonTab === 'appointments' && (
              infoAppointmentsLoading ? (
                <div className={styles.historyLoadingWrap}>
                  <Skeleton height={70} radius={14} />
                  <Skeleton height={250} radius={14} />
                </div>
              ) : infoAppointmentsError ? (
                <Alert tone="error">{infoAppointmentsError}</Alert>
              ) : (
                <div className={styles.sectionFade}>
                  <div className={styles.infoStatsGrid}>
                    <div className={styles.statTile}>
                      <div className={styles.statTileIcon}><Icon name="calendar" size={18} /></div>
                      <div>
                        <span className={styles.statTileLabel}>Recent Bookings</span>
                        <b className={styles.statTileValue}>{appointmentCounts.total}</b>
                      </div>
                    </div>
                    <div className={styles.statTile}>
                      <div className={cx(styles.statTileIcon, styles.iconSuccess)}><Icon name="checkCircle" size={18} /></div>
                      <div>
                        <span className={styles.statTileLabel}>Completed</span>
                        <b className={styles.statTileValue}>{appointmentCounts.completed}</b>
                      </div>
                    </div>
                    <div className={styles.statTile}>
                      <div className={cx(styles.statTileIcon, styles.iconInfo)}><Icon name="clock" size={18} /></div>
                      <div>
                        <span className={styles.statTileLabel}>Active / Upcoming</span>
                        <b className={styles.statTileValue}>{appointmentCounts.upcoming}</b>
                      </div>
                    </div>
                    <div className={styles.statTile}>
                      <div className={cx(styles.statTileIcon, styles.iconDanger)}><Icon name="close" size={18} /></div>
                      <div>
                        <span className={styles.statTileLabel}>Cancelled</span>
                        <b className={styles.statTileValue}>{appointmentCounts.cancelled}</b>
                      </div>
                    </div>
                  </div>

                  {infoAppointments.length === 0 ? (
                    <EmptyState
                      icon="calendar"
                      title="No recent appointments"
                      hint="Appointments booked by customers or walk-in guests will appear here."
                    />
                  ) : (
                    <div className={styles.historySection}>
                      <h4 className={ui.sectionLabel}>
                        Recent Appointments ({infoAppointments.length})
                      </h4>
                      <div className={ui.tableWrap}>
                        <table className={ui.table}>
                          <thead>
                            <tr>
                              <th>ID / Date</th>
                              <th>Customer</th>
                              <th>Services</th>
                              <th>Provider</th>
                              <th>Source</th>
                              <th>Status</th>
                              <th className={ui.alignRight}>Total</th>
                            </tr>
                          </thead>
                          <tbody>
                            {infoAppointments.slice(0, 15).map((apt) => {
                              const custName = apt.customer?.name || apt.walk_in_customer_name || 'Walk-in Guest';
                              const custPhone = apt.customer?.phone || apt.walk_in_customer_phone;
                              const isWalkIn = apt.booking_source === 'walk_in' || !apt.customer;
                              const serviceNames = (apt.services || []).map((s: any) => s.service?.template?.name || 'Service');

                              return (
                                <tr key={apt.id}>
                                  <td>
                                    <div className={styles.aptIdCol}>
                                      <b>#{apt.id}</b>
                                      <span>{fmtDay(apt.appointment_date)} {apt.start_time ? apt.start_time.slice(0, 5) : ''}</span>
                                    </div>
                                  </td>
                                  <td>
                                    <div className={styles.aptCustCol}>
                                      <span className={styles.custName}>{custName}</span>
                                      {custPhone && <span className={styles.custPhone}>{custPhone}</span>}
                                    </div>
                                  </td>
                                  <td>
                                    <div className={styles.servicesPillsWrap}>
                                      {serviceNames.length > 0 ? (
                                        serviceNames.slice(0, 2).map((sn: string, idx: number) => (
                                          <span key={idx} className={styles.servicePill} title={sn}>{sn}</span>
                                        ))
                                      ) : (
                                        <span className={styles.mutedNote}>—</span>
                                      )}
                                      {serviceNames.length > 2 && (
                                        <span className={styles.servicePillMore}>+{serviceNames.length - 2}</span>
                                      )}
                                    </div>
                                  </td>
                                  <td>
                                    {apt.appointed_provider?.user?.name || apt.serving_provider?.user?.name || <span className={styles.mutedNote}>Any staff</span>}
                                  </td>
                                  <td>
                                    <Badge tone={isWalkIn ? 'accent' : 'info'}>
                                      {isWalkIn ? 'Walk-in' : 'App'}
                                    </Badge>
                                  </td>
                                  <td>
                                    <Badge tone={appointmentStatusTone(apt.status)} dot={apt.status === 'completed' || apt.status === 'confirmed'}>
                                      {apt.status ? apt.status.charAt(0).toUpperCase() + apt.status.slice(1).replace('_', ' ') : '—'}
                                    </Badge>
                                  </td>
                                  <td className={cx(ui.alignRight, styles.boldNum)}>
                                    {apt.final_billed_amount != null
                                      ? formatINR(apt.final_billed_amount)
                                      : apt.total_amount != null
                                      ? formatINR(apt.total_amount)
                                      : '—'}
                                  </td>
                                </tr>
                              );
                            })}
                          </tbody>
                        </table>
                      </div>
                    </div>
                  )}
                </div>
              )
            )}

            {/* ===================== TAB 4: FINANCE ===================== */}
            {infoSalonTab === 'finance' && (
              infoAppointmentsLoading ? (
                <div className={styles.historyLoadingWrap}>
                  <Skeleton height={80} radius={14} />
                  <Skeleton height={250} radius={14} />
                </div>
              ) : (
                <div className={styles.sectionFade}>
                  <div className={styles.financeStatsGrid}>
                    <div className={styles.financeCard}>
                      <div className={styles.financeCardHead}>
                        <span className={styles.financeCardIcon}><Icon name="rupee" size={18} /></span>
                        <span className={styles.financeCardLabel}>Gross Appointment Revenue</span>
                      </div>
                      <b className={styles.financeCardAmount}>{formatINR(financeMetrics.totalRevenue)}</b>
                      <span className={styles.financeCardSub}>From active &amp; completed bookings</span>
                    </div>

                    <div className={styles.financeCard}>
                      <div className={styles.financeCardHead}>
                        <span className={cx(styles.financeCardIcon, styles.iconAccent)}><Icon name="smartphone" size={18} /></span>
                        <span className={styles.financeCardLabel}>Online Advances Collected</span>
                      </div>
                      <b className={styles.financeCardAmount}>{formatINR(financeMetrics.advancesCollected)}</b>
                      <span className={styles.financeCardSub}>Platform advances held for payout</span>
                    </div>

                    <div className={styles.financeCard}>
                      <div className={styles.financeCardHead}>
                        <span className={cx(styles.financeCardIcon, styles.iconSuccess)}><Icon name="store" size={18} /></span>
                        <span className={styles.financeCardLabel}>Balance Collected at Salon</span>
                      </div>
                      <b className={styles.financeCardAmount}>{formatINR(financeMetrics.balanceCollected)}</b>
                      <span className={styles.financeCardSub}>Collected at salon reception desk</span>
                    </div>

                    <div className={styles.financeCard}>
                      <div className={styles.financeCardHead}>
                        <span className={cx(styles.financeCardIcon, styles.iconInfo)}><Icon name="chart" size={18} /></span>
                        <span className={styles.financeCardLabel}>Average Booking Value</span>
                      </div>
                      <b className={styles.financeCardAmount}>{formatINR(financeMetrics.avgTicket)}</b>
                      <span className={styles.financeCardSub}>Average spend per customer booking</span>
                    </div>
                  </div>

                  {infoAppointments.length === 0 ? (
                    <EmptyState
                      icon="rupee"
                      title="No financial transactions yet"
                      hint="Appointment billing records and advance splits will appear once bookings are placed."
                    />
                  ) : (
                    <div className={styles.historySection}>
                      <h4 className={ui.sectionLabel}>
                        Appointment Financial Ledger ({infoAppointments.length})
                      </h4>
                      <div className={ui.tableWrap}>
                        <table className={ui.table}>
                          <thead>
                            <tr>
                              <th>Appointment</th>
                              <th>Customer</th>
                              <th className={ui.alignRight}>Total Bill</th>
                              <th className={ui.alignRight}>Online Advance</th>
                              <th className={ui.alignRight}>Counter Balance</th>
                              <th>Option</th>
                              <th>Status</th>
                            </tr>
                          </thead>
                          <tbody>
                            {infoAppointments.slice(0, 15).map((apt) => {
                              const bill = parseFloat(apt.final_billed_amount ?? apt.total_amount ?? 0) || 0;
                              const adv = parseFloat(apt.advance_amount ?? 0) || 0;
                              const bal = parseFloat(apt.balance_amount ?? (bill > adv ? bill - adv : 0)) || 0;
                              const custName = apt.customer?.name || apt.walk_in_customer_name || 'Walk-in Guest';

                              return (
                                <tr key={apt.id}>
                                  <td>
                                    <div className={styles.aptIdCol}>
                                      <b>#{apt.id}</b>
                                      <span>{fmtDay(apt.appointment_date)}</span>
                                    </div>
                                  </td>
                                  <td>
                                    <span className={styles.custName}>{custName}</span>
                                  </td>
                                  <td className={cx(ui.alignRight, styles.boldNum)}>
                                    {formatINR(bill)}
                                  </td>
                                  <td className={cx(ui.alignRight, styles.advanceCol)}>
                                    {adv > 0 ? formatINR(adv) : <span className={styles.mutedNote}>—</span>}
                                  </td>
                                  <td className={cx(ui.alignRight, styles.balanceCol)}>
                                    {bal > 0 ? formatINR(bal) : <span className={styles.mutedNote}>—</span>}
                                  </td>
                                  <td>
                                    <Badge tone="neutral">
                                      {apt.payment_option ? apt.payment_option.replace('_', ' ') : 'Standard'}
                                    </Badge>
                                  </td>
                                  <td>
                                    <Badge tone={appointmentStatusTone(apt.status)}>
                                      {apt.status ? apt.status.charAt(0).toUpperCase() + apt.status.slice(1).replace('_', ' ') : '—'}
                                    </Badge>
                                  </td>
                                </tr>
                              );
                            })}
                          </tbody>
                        </table>
                      </div>
                    </div>
                  )}
                </div>
              )
            )}

            {/* ===================== TAB 5: PAYOUT DATA ===================== */}
            {infoSalonTab === 'payouts' && (
              infoPayoutsLoading ? (
                <div className={styles.historyLoadingWrap}>
                  <Skeleton height={80} radius={14} />
                  <Skeleton height={200} radius={14} />
                </div>
              ) : infoPayoutsError && (!infoPayoutsData?.payouts || infoPayoutsData.payouts.length === 0) ? (
                <div className={styles.sectionFade}>
                  <Alert tone="info">{infoPayoutsError}</Alert>
                  <EmptyState
                    icon="wallet"
                    title="No payouts generated yet"
                    hint={
                      infoSalon.billing_model === COMMISSION
                        ? 'Monthly commission cycle runs automatically on the 1st of every month.'
                        : 'Weekly advances payout cycle runs automatically every Monday.'
                    }
                  />
                </div>
              ) : (
                <div className={styles.sectionFade}>
                  <div className={styles.financeStatsGrid}>
                    <div className={styles.financeCard}>
                      <div className={styles.financeCardHead}>
                        <span className={cx(styles.financeCardIcon, styles.iconSuccess)}><Icon name="wallet" size={18} /></span>
                        <span className={styles.financeCardLabel}>Lifetime Distributed</span>
                      </div>
                      <b className={styles.financeCardAmount}>
                        {formatINR(infoPayoutsData?.totals?.received_lifetime ?? 0)}
                      </b>
                      <span className={styles.financeCardSub}>Net paid to salon bank account</span>
                    </div>

                    <div className={styles.financeCard}>
                      <div className={styles.financeCardHead}>
                        <span className={styles.financeCardIcon}><Icon name="receipt" size={18} /></span>
                        <span className={styles.financeCardLabel}>Advances Accounted</span>
                      </div>
                      <b className={styles.financeCardAmount}>
                        {formatINR(infoPayoutsData?.totals?.advances_held_lifetime ?? 0)}
                      </b>
                      <span className={styles.financeCardSub}>Gross advances processed</span>
                    </div>

                    <div className={styles.financeCard}>
                      <div className={styles.financeCardHead}>
                        <span className={cx(styles.financeCardIcon, styles.iconAccent)}><Icon name="percent" size={18} /></span>
                        <span className={styles.financeCardLabel}>Commission Deducted</span>
                      </div>
                      <b className={styles.financeCardAmount}>
                        {formatINR(infoPayoutsData?.totals?.commission_deducted_lifetime ?? 0)}
                      </b>
                      <span className={styles.financeCardSub}>Retained by platform</span>
                    </div>

                    <div className={styles.financeCard}>
                      <div className={styles.financeCardHead}>
                        <span className={cx(styles.financeCardIcon, styles.iconInfo)}><Icon name="clock" size={18} /></span>
                        <span className={styles.financeCardLabel}>Settlement Rhythm</span>
                      </div>
                      <b className={styles.financeCardAmount} style={{ fontSize: '15px' }}>
                        {infoSalon.billing_model === COMMISSION ? 'Monthly, on 1st' : 'Weekly, Mondays'}
                      </b>
                      <span className={styles.financeCardSub}>
                        {infoSalon.billing_model === COMMISSION ? 'Postpaid commission deduction' : 'Prepaid subscription advance payout'}
                      </span>
                    </div>
                  </div>

                  {(!infoPayoutsData?.payouts || infoPayoutsData.payouts.length === 0) ? (
                    <EmptyState
                      icon="wallet"
                      title="No payouts generated yet"
                      hint={
                        infoSalon.billing_model === COMMISSION
                          ? 'Monthly commission cycle runs automatically on the 1st of every month.'
                          : 'Weekly advances payout cycle runs automatically every Monday.'
                      }
                    />
                  ) : (
                    <div className={styles.historySection}>
                      <h4 className={ui.sectionLabel}>
                        Payout Settlement Cycles ({infoPayoutsData.payouts.length})
                      </h4>
                      <div className={ui.tableWrap}>
                        <table className={ui.table}>
                          <thead>
                            <tr>
                              <th>Cycle Period</th>
                              <th>Arrangement</th>
                              <th className={ui.alignRight}>Gross Advance</th>
                              <th className={ui.alignRight}>Commission</th>
                              <th className={ui.alignRight}>Net Payout</th>
                              <th>Status</th>
                              <th>Reference</th>
                              <th className={ui.alignRight}>Statement</th>
                            </tr>
                          </thead>
                          <tbody>
                            {infoPayoutsData.payouts.map((p: any) => (
                              <tr key={p.id}>
                                <td>
                                  <div className={styles.aptIdCol}>
                                    <b>{p.cycle_label || `${fmtDay(p.cycle_start_date)} → ${fmtDay(p.cycle_end_date)}`}</b>
                                    <span>{p.appointments_count ?? 0} bookings</span>
                                  </div>
                                </td>
                                <td>
                                  <Badge tone={p.billing_type === COMMISSION ? 'accent' : 'info'}>
                                    {p.billing_label || modelLabel(p.billing_type)}
                                  </Badge>
                                </td>
                                <td className={ui.alignRight}>{formatINR(p.gross_amount, 2)}</td>
                                <td className={cx(ui.alignRight, styles.advanceCol)}>
                                  {p.commission_deducted > 0 ? `-${formatINR(p.commission_deducted, 2)}` : '—'}
                                </td>
                                <td className={cx(ui.alignRight, styles.boldNum)}>
                                  {formatINR(p.net_amount, 2)}
                                </td>
                                <td>
                                  <Badge tone={payoutStatusTone(p.status)} dot={p.status === 'distributed'}>
                                    {p.status ? p.status.charAt(0).toUpperCase() + p.status.slice(1) : '—'}
                                  </Badge>
                                </td>
                                <td>
                                  {p.distribution_reference ? (
                                    <b className={styles.refId}>{p.distribution_reference}</b>
                                  ) : (
                                    <span className={styles.mutedNote}>—</span>
                                  )}
                                </td>
                                <td className={ui.alignRight}>
                                  {p.settlement_invoice?.url ? (
                                    <a href={p.settlement_invoice.url} target="_blank" rel="noreferrer" className={cx(ui.btn, ui.btnSm, ui.btnGhost)}>
                                      Statement <Icon name="external" size={13} />
                                    </a>
                                  ) : (
                                    <span className={styles.mutedNote}>—</span>
                                  )}
                                </td>
                              </tr>
                            ))}
                          </tbody>
                        </table>
                      </div>
                    </div>
                  )}
                </div>
              )
            )}

            {/* ===================== TAB 6: PLAN HISTORY ===================== */}
            {infoSalonTab === 'plan_history' && (
              infoSubscriptionLoading ? (
                <div className={styles.historyLoadingWrap}>
                  <Skeleton height={110} radius={14} />
                  <Skeleton height={200} radius={14} />
                </div>
              ) : infoSubscriptionError ? (
                <Alert tone="error">{infoSubscriptionError}</Alert>
              ) : (
                <div className={styles.sectionFade}>
                  {/* Current Active Plan Details on top */}
                  {(() => {
                    const currentSub = infoSubscriptionData?.current_subscription;
                    const salonMeta = infoSubscriptionData?.salon;
                    const isCommission = (salonMeta?.billing_model ?? infoSalon.billing_model) === COMMISSION;
                    const planName = currentSub?.plan_name ?? (infoSalon.current_plan && infoSalon.current_plan !== 'None' ? infoSalon.current_plan : 'No active plan');
                    const hasActive = currentSub?.status === 'active' || (isCommission && infoSalon.current_plan !== 'None');
                    const activeDaysRemaining = daysUntil(currentSub?.expires_at?.split(' ')[0] ?? infoSalon.expiry);

                    // Find matching plan in subscriptions to extract price & validity if available
                    const matchedPlan = infoSubscriptionData?.subscriptions?.find(
                      (s: any) => s.id === currentSub?.id || (s.plan_name === planName && s.status === 'active')
                    );
                    const price = matchedPlan?.price;
                    const validityDays = matchedPlan?.validity_days;

                    return (
                      <div className={styles.activePlanCard}>
                        <div className={styles.activePlanHead}>
                          <div className={styles.activePlanIcon}>
                            <Icon name={isCommission ? 'percent' : 'crown'} size={24} />
                          </div>
                          <div className={styles.activePlanInfo}>
                            <div className={styles.activePlanTitleRow}>
                              <span className={styles.activePlanLabel}>Current Active Plan</span>
                              <Badge tone={hasActive ? 'success' : 'neutral'} dot={hasActive}>
                                {hasActive ? 'Active' : 'No active plan'}
                              </Badge>
                              {activeDaysRemaining !== null && hasActive && !isCommission && (
                                <Badge tone={activeDaysRemaining <= 7 ? (activeDaysRemaining < 0 ? 'danger' : 'warning') : 'info'}>
                                  {activeDaysRemaining < 0 ? 'Expired' : activeDaysRemaining === 0 ? 'Expires today' : `${activeDaysRemaining}d remaining`}
                                </Badge>
                              )}
                            </div>
                            <h3 className={styles.activePlanName}>{planName}</h3>
                          </div>
                        </div>

                        <div className={styles.activePlanGrid}>
                          <div className={styles.activePlanFact}>
                            <span>Arrangement</span>
                            <b>{modelLabel(salonMeta?.billing_model ?? infoSalon.billing_model)}</b>
                          </div>
                          {isCommission ? (
                            <div className={styles.activePlanFact}>
                              <span>Commission rate</span>
                              <b>{pct(salonMeta?.commission_percentage ?? infoSalon.commission_percentage)}</b>
                            </div>
                          ) : (
                            <div className={styles.activePlanFact}>
                              <span>Price / Validity</span>
                              <b>
                                {price != null ? formatINR(price) : '—'}
                                {validityDays ? ` (${validityDays} days)` : ''}
                              </b>
                            </div>
                          )}
                          <div className={styles.activePlanFact}>
                            <span>Valid from</span>
                            <b>{fmtDateStr(currentSub?.starts_at)}</b>
                          </div>
                          <div className={styles.activePlanFact}>
                            <span>Valid until</span>
                            <b>
                              {currentSub?.expires_at
                                ? fmtDateStr(currentSub.expires_at)
                                : isCommission
                                ? 'Ongoing'
                                : infoSalon.expiry
                                ? fmtDay(infoSalon.expiry)
                                : 'No expiry date'}
                            </b>
                          </div>
                        </div>
                      </div>
                    );
                  })()}

                  {/* All Subscription Plans History Table */}
                  <div className={styles.historySection}>
                    <h4 className={ui.sectionLabel}>
                      Subscription plans ({infoSubscriptionData?.subscriptions?.length ?? 0})
                    </h4>
                    {(!infoSubscriptionData?.subscriptions || infoSubscriptionData.subscriptions.length === 0) ? (
                      <EmptyState
                        icon="crown"
                        title="No subscription history"
                        hint="This salon has not had any subscription plans assigned yet."
                      />
                    ) : (
                      <div className={ui.tableWrap}>
                        <table className={ui.table}>
                          <thead>
                            <tr>
                              <th>Plan</th>
                              <th>Arrangement</th>
                              <th>Price</th>
                              <th>Validity</th>
                              <th>Valid from</th>
                              <th>Expires on</th>
                              <th>Status</th>
                            </tr>
                          </thead>
                          <tbody>
                            {infoSubscriptionData.subscriptions.map((sub: any) => {
                              const isComm = sub.billing_model === COMMISSION;
                              return (
                                <tr key={sub.id}>
                                  <td>
                                    <div className={styles.planCell}>
                                      <span>{sub.plan_name}</span>
                                      {sub.is_custom && <Badge tone="accent">Custom</Badge>}
                                    </div>
                                  </td>
                                  <td>
                                    <Badge tone={isComm ? 'accent' : 'info'}>
                                      {modelLabel(sub.billing_model)}
                                    </Badge>
                                  </td>
                                  <td>{sub.price != null ? formatINR(sub.price) : '—'}</td>
                                  <td className={ui.num}>{sub.validity_days ? `${sub.validity_days} days` : '—'}</td>
                                  <td className={ui.num}>{fmtDateStr(sub.starts_at)}</td>
                                  <td className={ui.num}>{fmtDateStr(sub.expires_at)}</td>
                                  <td>
                                    <Badge
                                      tone={
                                        sub.status === 'active'
                                          ? 'success'
                                          : sub.status === 'expired'
                                          ? 'neutral'
                                          : sub.status === 'cancelled'
                                          ? 'danger'
                                          : 'warning'
                                      }
                                      dot={false}
                                    >
                                      {sub.status ? sub.status.charAt(0).toUpperCase() + sub.status.slice(1) : '—'}
                                    </Badge>
                                  </td>
                                </tr>
                              );
                            })}
                          </tbody>
                        </table>
                      </div>
                    )}
                  </div>

                  {/* Payment Submissions Table if any */}
                  {infoSubscriptionData?.payment_requests && infoSubscriptionData.payment_requests.length > 0 && (
                    <div className={styles.historySection}>
                      <h4 className={cx(ui.sectionLabel, styles.historySectionGap)}>
                        Payment submissions ({infoSubscriptionData.payment_requests.length})
                      </h4>
                      <div className={ui.tableWrap}>
                        <table className={ui.table}>
                          <thead>
                            <tr>
                              <th>Plan</th>
                              <th>Arrangement</th>
                              <th className={ui.alignRight}>Amount</th>
                              <th>Transaction reference</th>
                              <th>Submitted</th>
                              <th>Status</th>
                            </tr>
                          </thead>
                          <tbody>
                            {infoSubscriptionData.payment_requests.map((pr: any) => (
                              <tr key={pr.id}>
                                <td>{pr.plan_name}</td>
                                <td>
                                  <Badge tone={pr.billing_type === COMMISSION ? 'accent' : 'info'}>
                                    {modelLabel(pr.billing_type)}
                                  </Badge>
                                </td>
                                <td className={ui.alignRight}>
                                  {pr.amount_payable_inr != null ? formatINR(pr.amount_payable_inr, 2) : '—'}
                                  {Number(pr.coins_to_redeem) > 0 && (
                                    <div className={styles.refNote}>+{pr.coins_to_redeem} coins</div>
                                  )}
                                </td>
                                <td>
                                  {pr.transaction_id ? (
                                    <b className={styles.refId}>{pr.transaction_id}</b>
                                  ) : (
                                    <span className={styles.mutedNote}>—</span>
                                  )}
                                </td>
                                <td className={ui.num}>{fmtDateStr(pr.created_at)}</td>
                                <td>
                                  <Badge tone={statusTone(pr.status)} dot={false}>
                                    {pr.status ? pr.status.charAt(0).toUpperCase() + pr.status.slice(1) : '—'}
                                  </Badge>
                                </td>
                              </tr>
                            ))}
                          </tbody>
                        </table>
                      </div>
                    </div>
                  )}
                </div>
              )
            )}
          </div>
        )}
      </Modal>

      {confirmDialog}
    </div>
  );
}
