'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Alert, Badge, Button, Card, DataTable, Field, IconButton, Modal, PageHeader,
  SearchInput, StatCard, cx, ui, useConfirm, type DataColumn, type Tone,
} from '@/components/admin/ui';
import Icon from '@/components/admin/Icon';
import styles from './offers.module.css';

interface ServiceTemplate {
  id: string;
  name: string;
  is_active: boolean;
}

interface ServiceCategory {
  id: string;
  name: string;
  templates: ServiceTemplate[];
}

interface SalonOption {
  id: string;
  name: string;
  city: string;
  address?: string;
}

interface PolicyDefaults {
  min_percentage: number;
  max_percentage: number;
  default_percentage_cap: number;
  min_flat_amount: number;
  max_flat_amount: number;
  default_flat_cap: number;
  platform_max_cap: number;
}

interface OfferData {
  id: string;
  name: string;
  description: string | null;
  scope: 'new_to_platform' | 'new_to_salon';
  discount_type: 'percentage' | 'flat';
  discount_value: number;
  max_discount_cap: number | null;
  flat_booking_cap?: number | null;
  min_service_price: number | null;
  min_eligible_subtotal: number | null;
  min_total_booking_subtotal?: number | null;
  min_total_subtotal?: number | null;
  starts_at: string | null;
  ends_at: string | null;
  max_redemptions: number | null;
  is_active: boolean;
  service_templates_count: number;
  participating_salons_count: number;
  redemptions_count: number;
  is_valid_now?: boolean;
  is_limit_reached?: boolean;
  service_templates?: Array<{ id: string; service_template_id: string; template?: { id: string; name: string } }>;
  participating_salons?: Array<{ id: string; salon_id: string; salon?: { id: string; name: string; city?: { name: string } } }>;
  created_at: string;
  updated_at: string;
}

const DEFAULT_POLICY: PolicyDefaults = {
  min_percentage: 5,
  max_percentage: 50,
  default_percentage_cap: 500,
  min_flat_amount: 1,
  max_flat_amount: 1000,
  default_flat_cap: 1000,
  platform_max_cap: 5000,
};

const toLocalISOString = (dateInput: string | Date | null | undefined): string => {
  if (!dateInput) return '';
  const d = typeof dateInput === 'string' ? new Date(dateInput) : dateInput;
  if (Number.isNaN(d.getTime())) return '';
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
};

export default function OffersPage() {
  const [offers, setOffers] = useState<OfferData[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState<{ message: string; tone: 'success' | 'error' | 'info' } | null>(null);

  // Options cache
  const [categories, setCategories] = useState<ServiceCategory[]>([]);
  const [salons, setSalons] = useState<SalonOption[]>([]);
  const [policy, setPolicy] = useState<PolicyDefaults>(DEFAULT_POLICY);

  // Filters
  const [search, setSearch] = useState('');
  const [scopeFilter, setScopeFilter] = useState('');
  const [typeFilter, setTypeFilter] = useState('');
  const [statusFilter, setStatusFilter] = useState('');

  // Dialog & Modal
  const [confirm, confirmDialog] = useConfirm();
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [editingOfferId, setEditingOfferId] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [formError, setFormError] = useState('');

  // Form states
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [scope, setScope] = useState<'new_to_platform' | 'new_to_salon'>('new_to_platform');
  const [discountType, setDiscountType] = useState<'percentage' | 'flat'>('percentage');
  const [discountValue, setDiscountValue] = useState<number | ''>(20);
  const [maxDiscountCap, setMaxDiscountCap] = useState<number | ''>(500);
  const [flatBookingCap, setFlatBookingCap] = useState<number | ''>(1000);
  const [minServicePrice, setMinServicePrice] = useState<number | ''>(0);
  const [minEligibleSubtotal, setMinEligibleSubtotal] = useState<number | ''>(0);
  const [minTotalSubtotal, setMinTotalSubtotal] = useState<number | ''>(0);
  const [startsAt, setStartsAt] = useState('');
  const [endsAt, setEndsAt] = useState('');
  const [maxRedemptions, setMaxRedemptions] = useState<number | ''>('');
  const [isActive, setIsActive] = useState(true);

  // Selection states in form
  const [selectedTemplateIds, setSelectedTemplateIds] = useState<string[]>([]);
  const [serviceSearch, setServiceSearch] = useState('');
  const [selectedSalonIds, setSelectedSalonIds] = useState<string[]>([]);
  const [salonSearch, setSalonSearch] = useState('');

  // Fetch offers list
  const fetchOffers = useCallback(async () => {
    setLoading(true);
    try {
      const res = await fetch('/api/superadmin/offers', { cache: 'no-store' });
      const json = await res.json();
      if (!res.ok || !json.success) {
        throw new Error(json.message || 'Failed to load offers');
      }
      setOffers(json.data || []);
      setError('');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Error loading offers');
    } finally {
      setLoading(false);
    }
  }, []);

  // Fetch options (services, salons, policy limits)
  const fetchOptions = useCallback(async () => {
    try {
      const res = await fetch('/api/superadmin/offers/options', { cache: 'no-store' });
      const json = await res.json();
      if (res.ok && json.success) {
        setCategories(json.data.categories || []);
        setSalons(json.data.salons || []);
        if (json.data.policy) {
          setPolicy(json.data.policy);
        }
      }
    } catch (err) {
      console.error('Failed to load offer options:', err);
    }
  }, []);

  useEffect(() => {
    fetchOffers();
    fetchOptions();
  }, [fetchOffers, fetchOptions]);

  // Statistics calculation
  const stats = useMemo(() => {
    const total = offers.length;
    const active = offers.filter((o) => o.is_active && (o.is_valid_now ?? true)).length;
    const platformWide = offers.filter((o) => o.scope === 'new_to_platform').length;
    const salonSpecific = offers.filter((o) => o.scope === 'new_to_salon').length;
    const redemptions = offers.reduce((sum, o) => sum + (Number(o.redemptions_count) || 0), 0);
    return { total, active, platformWide, salonSpecific, redemptions };
  }, [offers]);

  // Filtered rows for DataTable
  const filteredOffers = useMemo(() => {
    return offers.filter((o) => {
      if (search) {
        const q = search.toLowerCase();
        const matchName = o.name.toLowerCase().includes(q);
        const matchDesc = o.description?.toLowerCase().includes(q) || false;
        if (!matchName && !matchDesc) return false;
      }
      if (scopeFilter && o.scope !== scopeFilter) return false;
      if (typeFilter && o.discount_type !== typeFilter) return false;
      if (statusFilter) {
        const isExpired = o.ends_at && new Date(o.ends_at) < new Date();
        if (statusFilter === 'active' && (!o.is_active || isExpired)) return false;
        if (statusFilter === 'paused' && (o.is_active || isExpired)) return false;
        if (statusFilter === 'expired' && !isExpired) return false;
      }
      return true;
    });
  }, [offers, search, scopeFilter, typeFilter, statusFilter]);

  // Reset form to defaults
  const resetForm = useCallback(() => {
    setName('');
    setDescription('');
    setScope('new_to_platform');
    setDiscountType('percentage');
    setDiscountValue(20);
    setMaxDiscountCap(policy.default_percentage_cap || 500);
    setFlatBookingCap(policy.default_flat_cap || 1000);
    setMinServicePrice(0);
    setMinEligibleSubtotal(0);
    setMinTotalSubtotal(0);
    setStartsAt(toLocalISOString(new Date()));
    setEndsAt('');
    setMaxRedemptions('');
    setIsActive(true);
    setSelectedTemplateIds([]);
    setSelectedSalonIds([]);
    setServiceSearch('');
    setSalonSearch('');
    setEditingOfferId(null);
    setFormError('');
  }, [policy]);

  // Open Create Modal
  const handleOpenCreate = () => {
    resetForm();
    setIsModalOpen(true);
  };

  // Open Edit Modal with prefilled data
  const handleOpenEdit = async (offer: OfferData) => {
    setEditingOfferId(offer.id);
    setName(offer.name);
    setDescription(offer.description || '');
    setScope(offer.scope);
    setDiscountType(offer.discount_type);
    setDiscountValue(offer.discount_value);
    setMaxDiscountCap(offer.max_discount_cap ?? '');
    setFlatBookingCap(offer.max_discount_cap ?? offer.flat_booking_cap ?? '');
    setMinServicePrice(offer.min_service_price ?? 0);
    setMinEligibleSubtotal(offer.min_eligible_subtotal ?? 0);
    setMinTotalSubtotal(offer.min_total_booking_subtotal ?? offer.min_total_subtotal ?? 0);
    setStartsAt(toLocalISOString(offer.starts_at));
    setEndsAt(toLocalISOString(offer.ends_at));
    setMaxRedemptions(offer.max_redemptions ?? '');
    setIsActive(offer.is_active);

    // Fetch full offer details to obtain selected service templates & participating salons
    try {
      const res = await fetch(`/api/superadmin/offers/${offer.id}`);
      const json = await res.json();
      if (res.ok && json.success && json.data) {
        const full = json.data;
        const sIds = (full.service_templates || [])
          .map((st: { id?: string; service_template_id?: string; pivot?: { service_template_id?: string } }) =>
            st.service_template_id || st.id || st.pivot?.service_template_id,
          )
          .filter(Boolean) as string[];
        const salIds = (full.participating_salons || [])
          .map((ps: { id?: string; salon_id?: string; pivot?: { salon_id?: string } }) =>
            ps.salon_id || ps.id || ps.pivot?.salon_id,
          )
          .filter(Boolean) as string[];
        setSelectedTemplateIds(sIds);
        setSelectedSalonIds(salIds);
      }
    } catch (err) {
      console.error('Failed to fetch full offer:', err);
    }

    setFormError('');
    setIsModalOpen(true);
  };

  // Toggle active state
  const handleToggleActive = async (offer: OfferData) => {
    const nextState = !offer.is_active;
    const ok = await confirm({
      title: nextState ? `Activate "${offer.name}"?` : `Pause "${offer.name}"?`,
      body: nextState
        ? 'The offer will become available immediately to eligible first-time customers.'
        : 'The offer will be paused and will no longer apply to new customer bookings.',
      confirmLabel: nextState ? 'Activate' : 'Pause',
      tone: nextState ? 'accent' : 'danger',
    });
    if (!ok) return;

    try {
      const res = await fetch(`/api/superadmin/offers/${offer.id}/toggle-active`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: JSON.stringify({ is_active: nextState }),
      });
      const json = await res.json();
      if (!res.ok || !json.success) {
        throw new Error(json.message || 'Failed to update offer status');
      }
      setNotice({
        message: `Offer "${offer.name}" is now ${nextState ? 'active' : 'paused'}.`,
        tone: 'success',
      });
      fetchOffers();
    } catch (err) {
      setNotice({
        message: err instanceof Error ? err.message : 'Error updating offer status',
        tone: 'error',
      });
    }
  };

  // Delete offer
  const handleDelete = async (offer: OfferData) => {
    const ok = await confirm({
      title: `Delete "${offer.name}"?`,
      body: 'This will permanently remove the offer configuration. Offers with existing redemptions cannot be deleted.',
      confirmLabel: 'Delete Offer',
      tone: 'danger',
    });
    if (!ok) return;

    try {
      const res = await fetch(`/api/superadmin/offers/${offer.id}`, {
        method: 'DELETE',
      });
      const json = await res.json();
      if (!res.ok || !json.success) {
        throw new Error(json.message || 'Failed to delete offer');
      }
      setNotice({
        message: `Offer "${offer.name}" deleted successfully.`,
        tone: 'success',
      });
      fetchOffers();
    } catch (err) {
      setNotice({
        message: err instanceof Error ? err.message : 'Error deleting offer',
        tone: 'error',
      });
    }
  };

  // Client-side validation before submit
  const validateForm = (): string | null => {
    if (!name.trim()) return 'Offer name is required.';
    if (name.length > 255) return 'Offer name must not exceed 255 characters.';

    if (discountType === 'percentage') {
      const val = Number(discountValue);
      if (Number.isNaN(val) || val < policy.min_percentage || val > policy.max_percentage) {
        return `Percentage discount must be between ${policy.min_percentage}% and ${policy.max_percentage}%.`;
      }
      const cap = Number(maxDiscountCap);
      if (maxDiscountCap !== '' && (Number.isNaN(cap) || cap < 0 || cap > policy.platform_max_cap)) {
        return `Maximum percentage discount cap must be between ₹0 and ₹${policy.platform_max_cap}.`;
      }
    } else {
      const val = Number(discountValue);
      if (Number.isNaN(val) || val < policy.min_flat_amount || val > policy.max_flat_amount) {
        return `Flat discount amount must be between ₹${policy.min_flat_amount} and ₹${policy.max_flat_amount}.`;
      }
      const cap = Number(flatBookingCap);
      if (flatBookingCap !== '' && (Number.isNaN(cap) || cap < 0 || cap > policy.platform_max_cap)) {
        return `Maximum booking cap must be between ₹0 and ₹${policy.platform_max_cap}.`;
      }
    }

    if (minServicePrice !== '' && Number(minServicePrice) < 0) return 'Minimum service price cannot be negative.';
    if (minEligibleSubtotal !== '' && Number(minEligibleSubtotal) < 0) return 'Minimum eligible subtotal cannot be negative.';
    if (minTotalSubtotal !== '' && Number(minTotalSubtotal) < 0) return 'Minimum total subtotal cannot be negative.';

    if (startsAt && endsAt && new Date(endsAt) <= new Date(startsAt)) {
      return 'End date and time must be strictly after start date and time.';
    }

    if (scope === 'new_to_salon' && selectedSalonIds.length === 0) {
      return 'For "New to Salon" offers, at least one participating salon must be selected.';
    }

    if (selectedTemplateIds.length === 0) {
      return 'Please explicitly select at least one service template. Blanket / unselected offers are not permitted.';
    }

    return null;
  };

  // Submit create or edit form
  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const errorMsg = validateForm();
    if (errorMsg) {
      setFormError(errorMsg);
      return;
    }

    setIsSubmitting(true);
    setFormError('');

    const payload: Record<string, unknown> = {
      name: name.trim(),
      description: description.trim() || null,
      scope,
      discount_type: discountType,
      discount_value: Number(discountValue),
      max_discount_cap: discountType === 'percentage'
        ? (maxDiscountCap !== '' ? Number(maxDiscountCap) : null)
        : (flatBookingCap !== '' ? Number(flatBookingCap) : null),
      flat_booking_cap: discountType === 'flat' && flatBookingCap !== '' ? Number(flatBookingCap) : null,
      min_service_price: minServicePrice !== '' ? Number(minServicePrice) : 0,
      min_eligible_subtotal: minEligibleSubtotal !== '' ? Number(minEligibleSubtotal) : 0,
      min_total_booking_subtotal: minTotalSubtotal !== '' ? Number(minTotalSubtotal) : 0,
      min_total_subtotal: minTotalSubtotal !== '' ? Number(minTotalSubtotal) : 0,
      starts_at: startsAt ? new Date(startsAt).toISOString() : null,
      ends_at: endsAt ? new Date(endsAt).toISOString() : null,
      max_redemptions: maxRedemptions !== '' ? Number(maxRedemptions) : null,
      is_active: isActive,
      service_template_ids: selectedTemplateIds,
      salon_ids: selectedSalonIds,
    };

    try {
      const url = editingOfferId
        ? `/api/superadmin/offers/${editingOfferId}`
        : '/api/superadmin/offers';
      const method = editingOfferId ? 'PUT' : 'POST';

      const res = await fetch(url, {
        method,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      });

      const json = await res.json();
      if (!res.ok || !json.success) {
        if (json.errors) {
          const firstErr = Object.values(json.errors).flat()[0];
          throw new Error(String(firstErr || json.message || 'Validation error'));
        }
        throw new Error(json.message || `Failed to ${editingOfferId ? 'update' : 'create'} offer`);
      }

      setIsModalOpen(false);
      resetForm();
      setNotice({
        message: `Offer "${payload.name}" was ${editingOfferId ? 'updated' : 'created'} successfully.`,
        tone: 'success',
      });
      fetchOffers();
    } catch (err) {
      setFormError(err instanceof Error ? err.message : 'Error saving offer');
    } finally {
      setIsSubmitting(false);
    }
  };

  // Helper for status badge tone and label
  const getOfferStatus = (offer: OfferData): { label: string; tone: Tone } => {
    if (offer.ends_at && new Date(offer.ends_at) < new Date()) {
      return { label: 'Expired', tone: 'danger' };
    }
    if (offer.is_limit_reached) {
      return { label: 'Limit Reached', tone: 'warning' };
    }
    if (!offer.is_active) {
      return { label: 'Paused', tone: 'neutral' };
    }
    return { label: 'Active', tone: 'success' };
  };

  // DataTable columns definition
  const columns = useMemo<DataColumn<OfferData>[]>(
    () => [
      {
        key: 'name',
        header: 'Offer Name & Details',
        sortValue: (o) => o.name,
        render: (o) => (
          <div className={styles.offerNameCell}>
            <span className={styles.offerTitle}>{o.name}</span>
            {o.description && <span className={styles.offerDesc} title={o.description}>{o.description}</span>}
          </div>
        ),
      },
      {
        key: 'scope',
        header: 'Scope',
        sortValue: (o) => o.scope,
        render: (o) => (
          <Badge tone={o.scope === 'new_to_platform' ? 'accent' : 'info'} dot={false}>
            {o.scope === 'new_to_platform' ? 'New to Platform' : 'New to Salon'}
          </Badge>
        ),
      },
      {
        key: 'discount',
        header: 'Discount & Caps',
        sortValue: (o) => o.discount_value,
        render: (o) => (
          <div className={styles.discountValueCell}>
            <span className={styles.discountMain}>
              {o.discount_type === 'percentage' ? `${o.discount_value}% off` : `₹${o.discount_value} flat`}
            </span>
            <span className={styles.discountSub}>
              {o.discount_type === 'percentage'
                ? `Cap: ₹${o.max_discount_cap ?? 'No Cap'}`
                : `Booking Cap: ₹${o.flat_booking_cap ?? o.max_discount_cap ?? 'No Cap'}`}
            </span>
          </div>
        ),
      },
      {
        key: 'targeting',
        header: 'Participating Salons / Services',
        render: (o) => (
          <div className={styles.offerNameCell}>
            <span style={{ fontSize: '13px', fontWeight: 550, color: 'var(--text-heading)' }}>
              {o.scope === 'new_to_platform' && o.participating_salons_count === 0
                ? 'All Platform Salons'
                : `${o.participating_salons_count} Salons`}
            </span>
            <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>
              {o.service_templates_count === 0 ? 'All Eligible Services' : `${o.service_templates_count} Specific Services`}
            </span>
          </div>
        ),
      },
      {
        key: 'validity',
        header: 'Validity & Redemptions',
        render: (o) => {
          const start = o.starts_at ? new Date(o.starts_at).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' }) : 'Immediate';
          const end = o.ends_at ? new Date(o.ends_at).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' }) : 'No Expiry';
          return (
            <div className={styles.offerNameCell}>
              <span style={{ fontSize: '12.5px', color: 'var(--text-heading)' }}>{start} → {end}</span>
              <span style={{ fontSize: '11.5px', color: 'var(--text-muted)' }}>
                {o.redemptions_count} redemptions {o.max_redemptions ? `/ ${o.max_redemptions} cap` : ''}
              </span>
            </div>
          );
        },
      },
      {
        key: 'status',
        header: 'Status',
        sortValue: (o) => (o.is_active ? 1 : 0),
        render: (o) => {
          const s = getOfferStatus(o);
          return <Badge tone={s.tone}>{s.label}</Badge>;
        },
      },
      {
        key: 'actions',
        header: 'Actions',
        align: 'right',
        render: (o) => (
          <div className={styles.actionsCell}>
            <IconButton
              icon="edit"
              label={`Edit ${o.name}`}
              onClick={() => handleOpenEdit(o)}
            />
            <Button
              variant={o.is_active ? 'soft' : 'primary'}
              size="sm"
              onClick={() => handleToggleActive(o)}
            >
              {o.is_active ? 'Pause' : 'Activate'}
            </Button>
            <IconButton
              icon="trash"
              label={`Delete ${o.name}`}
              onClick={() => handleDelete(o)}
            />
          </div>
        ),
      },
    ],
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [],
  );

  // Filtered service templates for selection
  const filteredCategories = useMemo(() => {
    if (!serviceSearch.trim()) return categories;
    const q = serviceSearch.toLowerCase();
    return categories
      .map((cat) => ({
        ...cat,
        templates: cat.templates.filter((tpl) => tpl.name.toLowerCase().includes(q)),
      }))
      .filter((cat) => cat.templates.length > 0);
  }, [categories, serviceSearch]);

  // Filtered salons for selection
  const filteredSalons = useMemo(() => {
    if (!salonSearch.trim()) return salons;
    const q = salonSearch.toLowerCase();
    return salons.filter(
      (s) => s.name.toLowerCase().includes(q) || s.city.toLowerCase().includes(q),
    );
  }, [salons, salonSearch]);

  // Plain-English live preview text
  const livePreview = useMemo(() => {
    const scopeText =
      scope === 'new_to_platform'
        ? 'First-time BookALook users (platform-wide)'
        : `First-time clients at ${selectedSalonIds.length > 0 ? `${selectedSalonIds.length} chosen salon(s)` : 'selected salon(s)'}`;

    const discountText =
      discountType === 'percentage'
        ? `${discountValue || 0}% off eligible services (capped at ₹${maxDiscountCap || '∞'})`
        : `₹${discountValue || 0} flat off per eligible service (max ₹${flatBookingCap || '∞'} per booking)`;

    const serviceText = selectedTemplateIds.length > 0
      ? `${selectedTemplateIds.length} explicitly selected service template(s)`
      : 'no services selected (at least 1 required)';

    const minConditions: string[] = [];
    if (Number(minServicePrice) > 0) minConditions.push(`service price ≥ ₹${minServicePrice}`);
    if (Number(minEligibleSubtotal) > 0) minConditions.push(`eligible subtotal ≥ ₹${minEligibleSubtotal}`);
    if (Number(minTotalSubtotal) > 0) minConditions.push(`total booking subtotal ≥ ₹${minTotalSubtotal}`);
    const condText = minConditions.length > 0 ? ` Requires ${minConditions.join(', ')}.` : '';

    return `${scopeText} will receive ${discountText} on ${serviceText}.${condText}`;
  }, [
    scope,
    selectedSalonIds.length,
    discountType,
    discountValue,
    maxDiscountCap,
    flatBookingCap,
    selectedTemplateIds.length,
    minServicePrice,
    minEligibleSubtotal,
    minTotalSubtotal,
  ]);

  return (
    <div className={styles.container}>
      {confirmDialog}

      <PageHeader
        eyebrow="Promotions & Acquisition"
        title="First-Time Customer Offers"
        subtitle="Configure first-time customer discounts across the platform or specific salons with strict budget and policy controls."
        actions={
          <Button variant="primary" icon="plus" onClick={handleOpenCreate}>
            Create Offer
          </Button>
        }
      />

      {/* Overview Stat Cards */}
      <div className={styles.statsGrid}>
        <StatCard label="Total Offers" value={stats.total} icon="percent" tone="accent" />
        <StatCard label="Active Offers" value={stats.active} icon="checkCircle" tone="success" />
        <StatCard label="New to Platform" value={stats.platformWide} icon="crown" tone="info" />
        <StatCard label="New to Salon" value={stats.salonSpecific} icon="store" tone="warning" />
        <StatCard label="Total Redemptions" value={stats.redemptions} icon="receipt" tone="neutral" />
      </div>

      {notice && (
        <div style={{ marginBottom: '16px' }}>
          <Alert tone={notice.tone} onClose={() => setNotice(null)}>
            {notice.message}
          </Alert>
        </div>
      )}

      {error && (
        <div style={{ marginBottom: '16px' }}>
          <Alert tone="error">{error}</Alert>
        </div>
      )}

      {/* Main Table Shell */}
      <div className={styles.tableShell}>
        <DataTable
          columns={columns}
          rows={filteredOffers}
          rowKey={(o) => o.id}
          loading={loading && offers.length === 0}
          error={error || undefined}
          noun="offers"
          exportName="first-time-offers"
          caption="First-Time Customer Discount Offers"
          empty={{
            title: search || scopeFilter || typeFilter || statusFilter ? 'No offers match your filters' : 'No first-time customer offers configured yet',
            hint: search || scopeFilter || typeFilter || statusFilter ? 'Try clearing your search query or filters.' : 'Click "Create Offer" above to configure your first promotional discount.',
            action: !offers.length ? (
              <Button variant="primary" icon="plus" onClick={handleOpenCreate}>
                Create First Offer
              </Button>
            ) : undefined,
          }}
          toolbar={
            <div className={styles.toolbarRow}>
              <SearchInput
                value={search}
                onChange={setSearch}
                placeholder="Search offers by name or description…"
                ariaLabel="Search offers"
                className={styles.searchField}
              />
              <select
                className={styles.filterSelect}
                value={scopeFilter}
                onChange={(e) => setScopeFilter(e.target.value)}
                aria-label="Filter by Scope"
              >
                <option value="">All Scopes</option>
                <option value="new_to_platform">New to Platform</option>
                <option value="new_to_salon">New to Salon</option>
              </select>
              <select
                className={styles.filterSelect}
                value={typeFilter}
                onChange={(e) => setTypeFilter(e.target.value)}
                aria-label="Filter by Type"
              >
                <option value="">All Discount Types</option>
                <option value="percentage">Percentage (%)</option>
                <option value="flat">Flat Amount (₹)</option>
              </select>
              <select
                className={styles.filterSelect}
                value={statusFilter}
                onChange={(e) => setStatusFilter(e.target.value)}
                aria-label="Filter by Status"
              >
                <option value="">All Statuses</option>
                <option value="active">Active Only</option>
                <option value="paused">Paused Only</option>
                <option value="expired">Expired Only</option>
              </select>
            </div>
          }
        />
      </div>

      {/* Create / Edit Modal Dialog */}
      <Modal
        open={isModalOpen}
        onClose={() => {
          if (!isSubmitting) setIsModalOpen(false);
        }}
        size="lg"
        title={editingOfferId ? 'Edit First-Time Offer' : 'Create First-Time Customer Offer'}
        description="Configure rules, eligibility scope, service catalogs, and budget caps for this promotional offer."
        footer={
          <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '10px', width: '100%' }}>
            <Button variant="ghost" disabled={isSubmitting} onClick={() => setIsModalOpen(false)}>
              Cancel
            </Button>
            <Button variant="primary" loading={isSubmitting} onClick={handleSubmit}>
              {editingOfferId ? 'Update Offer' : 'Create & Save Offer'}
            </Button>
          </div>
        }
      >
        <form onSubmit={handleSubmit} className={styles.modalForm}>
          {formError && <Alert tone="error">{formError}</Alert>}

          {/* Section 1: Basic Information */}
          <div className={styles.formSection}>
            <div className={styles.sectionHeader}>
              <span className={styles.sectionTitle}>
                <Icon name="sliders" size={16} /> 1. Offer Identity & Eligibility Scope
              </span>
            </div>

            <div className={styles.formGrid2}>
              <Field label="Offer Name" hint="Appears internally and on customer discount tags">
                <input
                  type="text"
                  className={ui.control}
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  placeholder="e.g. Welcome 20% Off Platform First Booking"
                  required
                  maxLength={255}
                />
              </Field>

              <Field label="Optional Description" hint="Internal notes or customer-facing terms">
                <input
                  type="text"
                  className={ui.control}
                  value={description}
                  onChange={(e) => setDescription(e.target.value)}
                  placeholder="e.g. Valid on hair & facial services for new signups"
                />
              </Field>
            </div>

            <Field label="Eligibility Scope" hint="Determine which customers qualify for this offer">
              <div className={styles.radioGroup}>
                <label
                  className={cx(styles.radioCard, scope === 'new_to_platform' && styles.radioCardSelected)}
                >
                  <input
                    type="radio"
                    name="scope"
                    value="new_to_platform"
                    checked={scope === 'new_to_platform'}
                    onChange={() => setScope('new_to_platform')}
                  />
                  <div className={styles.radioContent}>
                    <span className={styles.radioLabel}>New to Platform</span>
                    <span className={styles.radioDesc}>
                      Only customers with zero prior completed or in-progress bookings across all salons.
                    </span>
                  </div>
                </label>

                <label
                  className={cx(styles.radioCard, scope === 'new_to_salon' && styles.radioCardSelected)}
                >
                  <input
                    type="radio"
                    name="scope"
                    value="new_to_salon"
                    checked={scope === 'new_to_salon'}
                    onChange={() => setScope('new_to_salon')}
                  />
                  <div className={styles.radioContent}>
                    <span className={styles.radioLabel}>New to Salon</span>
                    <span className={styles.radioDesc}>
                      Customers who have never completed a booking at the specific participating salon(s).
                    </span>
                  </div>
                </label>
              </div>
            </Field>
          </div>

          {/* Section 2: Discount Model & Policy Caps */}
          <div className={styles.formSection}>
            <div className={styles.sectionHeader}>
              <span className={styles.sectionTitle}>
                <Icon name="percent" size={16} /> 2. Discount Model & Policy Limits
              </span>
            </div>

            <Field label="Discount Type">
              <div className={styles.radioGroup}>
                <label
                  className={cx(styles.radioCard, discountType === 'percentage' && styles.radioCardSelected)}
                >
                  <input
                    type="radio"
                    name="discountType"
                    value="percentage"
                    checked={discountType === 'percentage'}
                    onChange={() => setDiscountType('percentage')}
                  />
                  <div className={styles.radioContent}>
                    <span className={styles.radioLabel}>Percentage Discount (%)</span>
                    <span className={styles.radioDesc}>
                      Calculates a percentage savings per eligible service line, bounded by a maximum monetary cap.
                    </span>
                  </div>
                </label>

                <label
                  className={cx(styles.radioCard, discountType === 'flat' && styles.radioCardSelected)}
                >
                  <input
                    type="radio"
                    name="discountType"
                    value="flat"
                    checked={discountType === 'flat'}
                    onChange={() => setDiscountType('flat')}
                  />
                  <div className={styles.radioContent}>
                    <span className={styles.radioLabel}>Flat Amount (₹)</span>
                    <span className={styles.radioDesc}>
                      Applies a fixed ₹ discount per eligible service line, capped by total booking limit.
                    </span>
                  </div>
                </label>
              </div>
            </Field>

            {discountType === 'percentage' ? (
              <div className={styles.formGrid2}>
                <Field
                  label={`Percentage Value (${policy.min_percentage}% – ${policy.max_percentage}%)`}
                  hint={`Platform policy range: ${policy.min_percentage}% to ${policy.max_percentage}%`}
                >
                  <input
                    type="number"
                    className={ui.control}
                    value={discountValue}
                    onChange={(e) => setDiscountValue(e.target.value === '' ? '' : Number(e.target.value))}
                    min={policy.min_percentage}
                    max={policy.max_percentage}
                    step={1}
                    required
                  />
                </Field>

                <Field
                  label="Maximum Discount Cap (₹)"
                  hint={`Ceiling limit per booking (Max: ₹${policy.platform_max_cap})`}
                >
                  <input
                    type="number"
                    className={ui.control}
                    value={maxDiscountCap}
                    onChange={(e) => setMaxDiscountCap(e.target.value === '' ? '' : Number(e.target.value))}
                    min={0}
                    max={policy.platform_max_cap}
                    placeholder="e.g. 500"
                  />
                </Field>
              </div>
            ) : (
              <div className={styles.formGrid2}>
                <Field
                  label={`Flat Amount Per Eligible Service (₹${policy.min_flat_amount} – ₹${policy.max_flat_amount})`}
                  hint="Applied to each qualifying service line in the customer's cart"
                >
                  <input
                    type="number"
                    className={ui.control}
                    value={discountValue}
                    onChange={(e) => setDiscountValue(e.target.value === '' ? '' : Number(e.target.value))}
                    min={policy.min_flat_amount}
                    max={policy.max_flat_amount}
                    step={1}
                    required
                  />
                </Field>

                <Field
                  label="Maximum Total Discount Per Booking (₹)"
                  hint={`Overall booking cap (Max: ₹${policy.platform_max_cap})`}
                >
                  <input
                    type="number"
                    className={ui.control}
                    value={flatBookingCap}
                    onChange={(e) => setFlatBookingCap(e.target.value === '' ? '' : Number(e.target.value))}
                    min={0}
                    max={policy.platform_max_cap}
                    placeholder="e.g. 1000"
                  />
                </Field>
              </div>
            )}
          </div>

          {/* Section 3: Minimum Spend Conditions */}
          <div className={styles.formSection}>
            <div className={styles.sectionHeader}>
              <span className={styles.sectionTitle}>
                <Icon name="rupee" size={16} /> 3. Minimum Spend Conditions
              </span>
            </div>

            <div className={styles.formGrid3}>
              <Field
                label="Min Service Price (₹)"
                hint="Service must cost at least this amount to qualify"
              >
                <input
                  type="number"
                  className={ui.control}
                  value={minServicePrice}
                  onChange={(e) => setMinServicePrice(e.target.value === '' ? '' : Number(e.target.value))}
                  min={0}
                />
              </Field>

              <Field
                label="Min Eligible Subtotal (₹)"
                hint="Sum of qualifying services must meet this"
              >
                <input
                  type="number"
                  className={ui.control}
                  value={minEligibleSubtotal}
                  onChange={(e) => setMinEligibleSubtotal(e.target.value === '' ? '' : Number(e.target.value))}
                  min={0}
                />
              </Field>

              <Field
                label="Min Total Booking Subtotal (₹)"
                hint="Total cart booking subtotal must meet this"
              >
                <input
                  type="number"
                  className={ui.control}
                  value={minTotalSubtotal}
                  onChange={(e) => setMinTotalSubtotal(e.target.value === '' ? '' : Number(e.target.value))}
                  min={0}
                />
              </Field>
            </div>
          </div>

          {/* Section 4: Service Template Selection */}
          <div className={styles.formSection}>
            <div className={styles.sectionHeader}>
              <span className={styles.sectionTitle}>
                <Icon name="catalog" size={16} /> 4. Explicitly Targeted Service Templates
              </span>
              <span style={{ fontSize: '12px', color: selectedTemplateIds.length > 0 ? 'var(--text-muted)' : 'var(--color-danger, #ef4444)', fontWeight: 600 }}>
                {selectedTemplateIds.length > 0 ? `${selectedTemplateIds.length} service(s) selected` : 'At least 1 service required *'}
              </span>
            </div>

            <p style={{ fontSize: '12px', color: 'var(--text-muted)', margin: '0 0 10px 0' }}>
              Policy requires first-time discount offers to explicitly target specific service templates. Use the selector below to check eligible services or click "Select All" to enroll all current templates.
            </p>

            <div className={styles.selectorContainer}>
              <div className={styles.selectorHeader}>
                <input
                  type="search"
                  className={styles.selectorSearch}
                  placeholder="Filter service templates by name…"
                  value={serviceSearch}
                  onChange={(e) => setServiceSearch(e.target.value)}
                />
                <Button
                  variant="soft"
                  size="sm"
                  onClick={() => {
                    const allIds = categories.flatMap((c) => c.templates.map((t) => t.id));
                    setSelectedTemplateIds(selectedTemplateIds.length === allIds.length ? [] : allIds);
                  }}
                >
                  {selectedTemplateIds.length === categories.flatMap((c) => c.templates).length ? 'Deselect All' : 'Select All'}
                </Button>
              </div>

              <div className={styles.selectorList}>
                {filteredCategories.map((cat) => (
                  <div key={cat.id} className={styles.categoryGroup}>
                    <div className={styles.categoryTitle}>
                      <span>{cat.name}</span>
                      <span style={{ fontSize: '11px', textTransform: 'none' }}>
                        ({cat.templates.filter((t) => selectedTemplateIds.includes(t.id)).length}/{cat.templates.length})
                      </span>
                    </div>
                    {cat.templates.map((tpl) => {
                      const isSelected = selectedTemplateIds.includes(tpl.id);
                      return (
                        <label key={tpl.id} className={styles.selectorItem}>
                          <input
                            type="checkbox"
                            checked={isSelected}
                            onChange={() => {
                              setSelectedTemplateIds((prev) =>
                                isSelected ? prev.filter((id) => id !== tpl.id) : [...prev, tpl.id],
                              );
                            }}
                          />
                          <span>{tpl.name}</span>
                        </label>
                      );
                    })}
                  </div>
                ))}
                {filteredCategories.length === 0 && (
                  <div style={{ padding: '16px', textAlign: 'center', color: 'var(--text-muted)', fontSize: '12px' }}>
                    No service templates match your search.
                  </div>
                )}
              </div>
            </div>
          </div>

          {/* Section 5: Participating Salons Selection */}
          <div className={styles.formSection}>
            <div className={styles.sectionHeader}>
              <span className={styles.sectionTitle}>
                <Icon name="store" size={16} /> 5. Participating Salons
              </span>
              <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>
                {scope === 'new_to_platform' && selectedSalonIds.length === 0
                  ? 'All platform salons included'
                  : `${selectedSalonIds.length} salon(s) selected`}
              </span>
            </div>

            {scope === 'new_to_platform' && (
              <p style={{ fontSize: '12px', color: 'var(--text-muted)', margin: '0 0 8px 0' }}>
                For platform-wide offers, leaving all salons unselected applies the offer across all salons on BookALook. Alternatively, select specific salons below.
              </p>
            )}

            {scope === 'new_to_salon' && (
              <p style={{ fontSize: '12px', color: 'var(--accent-text)', margin: '0 0 8px 0', fontWeight: 600 }}>
                ⚠️ Requirement: You must explicitly select at least one participating salon for "New to Salon" offers.
              </p>
            )}

            <div className={styles.selectorContainer}>
              <div className={styles.selectorHeader}>
                <input
                  type="search"
                  className={styles.selectorSearch}
                  placeholder="Filter salons by name or city…"
                  value={salonSearch}
                  onChange={(e) => setSalonSearch(e.target.value)}
                />
                <Button
                  variant="soft"
                  size="sm"
                  onClick={() => {
                    const allIds = salons.map((s) => s.id);
                    setSelectedSalonIds(selectedSalonIds.length === allIds.length ? [] : allIds);
                  }}
                >
                  {selectedSalonIds.length === salons.length ? 'Deselect All' : 'Select All'}
                </Button>
              </div>

              <div className={styles.selectorList}>
                {filteredSalons.map((salon) => {
                  const isSelected = selectedSalonIds.includes(salon.id);
                  return (
                    <label key={salon.id} className={styles.selectorItem}>
                      <input
                        type="checkbox"
                        checked={isSelected}
                        onChange={() => {
                          setSelectedSalonIds((prev) =>
                            isSelected ? prev.filter((id) => id !== salon.id) : [...prev, salon.id],
                          );
                        }}
                      />
                      <div style={{ display: 'flex', flexDirection: 'column' }}>
                        <span style={{ fontWeight: 550 }}>{salon.name}</span>
                        <span className={styles.itemMeta}>
                          {salon.city} {salon.address ? `• ${salon.address}` : ''}
                        </span>
                      </div>
                    </label>
                  );
                })}
                {filteredSalons.length === 0 && (
                  <div style={{ padding: '16px', textAlign: 'center', color: 'var(--text-muted)', fontSize: '12px' }}>
                    No salons match your search.
                  </div>
                )}
              </div>
            </div>
          </div>

          {/* Section 6: Schedule & Campaign Limits */}
          <div className={styles.formSection}>
            <div className={styles.sectionHeader}>
              <span className={styles.sectionTitle}>
                <Icon name="calendar" size={16} /> 6. Schedule, Redemption Limits & Status
              </span>
            </div>

            <div className={styles.formGrid3}>
              <Field label="Starts At" hint="Offer becomes active from this moment">
                <input
                  type="datetime-local"
                  className={ui.control}
                  value={startsAt}
                  onChange={(e) => setStartsAt(e.target.value)}
                />
              </Field>

              <Field label="Ends At (Optional)" hint="Leave blank for continuous run">
                <input
                  type="datetime-local"
                  className={ui.control}
                  value={endsAt}
                  onChange={(e) => setEndsAt(e.target.value)}
                />
              </Field>

              <Field label="Campaign Redemption Cap" hint="Max times this offer can be claimed">
                <input
                  type="number"
                  className={ui.control}
                  value={maxRedemptions}
                  onChange={(e) => setMaxRedemptions(e.target.value === '' ? '' : Number(e.target.value))}
                  min={1}
                  placeholder="e.g. 500 (Optional)"
                />
              </Field>
            </div>

            <label className={ui.check} style={{ marginTop: '8px' }}>
              <input
                type="checkbox"
                checked={isActive}
                onChange={(e) => setIsActive(e.target.checked)}
              />
              <span>Activate this offer immediately upon saving</span>
            </label>
          </div>

          {/* Section 7: Live Summary & Preview Box */}
          <div className={styles.previewBox}>
            <span className={styles.previewTitle}>
              <Icon name="sparkle" size={15} /> Live Configuration Summary
            </span>
            <span className={styles.previewText}>{livePreview}</span>
            {scope === 'new_to_salon' && selectedSalonIds.length === 0 && (
              <span className={styles.validationWarning}>
                <Icon name="alert" size={14} /> At least 1 participating salon must be selected for this offer.
              </span>
            )}
          </div>
        </form>
      </Modal>
    </div>
  );
}
