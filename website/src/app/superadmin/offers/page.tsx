'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Alert, Badge, Button, DataTable, DescriptionList, IconButton, Modal, PageHeader,
  SearchInput, Skeleton, StatCard, useConfirm, type DataColumn, type Tone,
} from '@/components/admin/ui';
import styles from './offers.module.css';

/**
 * First-time customer offers, across every salon.
 *
 * Offers belong to salons: each salon creates them for itself from the Partner
 * App. This page is for oversight — see every offer and the salon that made
 * it, pause one that should not be running, or remove it. SuperAdmin no longer
 * creates or edits offers. The platform-wide offers created here before are
 * retired and shown as such.
 */

interface OfferData {
  id: string;
  salon_id: string | null;
  name: string;
  description: string | null;
  scope: 'new_to_platform' | 'new_to_salon';
  discount_type: 'percentage' | 'flat';
  discount_value: number;
  max_discount_cap: number | null;
  min_service_price: number | null;
  min_eligible_subtotal: number | null;
  min_total_booking_subtotal?: number | null;
  starts_at: string | null;
  ends_at: string | null;
  max_redemptions: number | null;
  is_active: boolean;
  service_templates_count: number;
  redemptions_count: number;
  is_valid_now?: boolean;
  is_limit_reached?: boolean;
  created_by_salon: { id: string; name: string } | null;
  is_retired_platform_offer: boolean;
  created_at: string;
}

interface OfferDetail extends OfferData {
  service_templates?: { id: string; name: string; category?: { name: string } | null }[];
}

const SCOPE_LABEL: Record<OfferData['scope'], string> = {
  new_to_platform: 'New to BookALook',
  new_to_salon: 'New to this salon',
};

const fmtDate = (v: string | null) =>
  v ? new Date(v).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' }) : null;

const discountText = (o: OfferData) =>
  o.discount_type === 'percentage'
    ? `${Number(o.discount_value)}% off${o.max_discount_cap ? ` · up to ₹${Number(o.max_discount_cap)}` : ''}`
    : `₹${Number(o.discount_value)} off${o.max_discount_cap ? ` · max ₹${Number(o.max_discount_cap)} per booking` : ''}`;

function statusOf(o: OfferData): { label: string; tone: Tone } {
  if (o.is_retired_platform_offer) return { label: 'Retired', tone: 'neutral' };
  if (o.ends_at && new Date(o.ends_at) < new Date()) return { label: 'Expired', tone: 'danger' };
  if (o.is_limit_reached) return { label: 'Limit reached', tone: 'warning' };
  if (!o.is_active) return { label: 'Paused', tone: 'neutral' };
  return { label: 'Active', tone: 'success' };
}

export default function FirstTimeOffersPage() {
  const [offers, setOffers] = useState<OfferData[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState<{ message: string; tone: 'success' | 'error' } | null>(null);

  const [search, setSearch] = useState('');
  const [salonFilter, setSalonFilter] = useState('');
  const [scopeFilter, setScopeFilter] = useState('');
  const [statusFilter, setStatusFilter] = useState('');

  const [detail, setDetail] = useState<OfferDetail | null>(null);
  const [detailLoading, setDetailLoading] = useState(false);
  const [confirm, confirmDialog] = useConfirm();

  const fetchOffers = useCallback(async () => {
    setLoading(true);
    try {
      const res = await fetch('/api/superadmin/offers', { cache: 'no-store' });
      const json = await res.json();
      if (!res.ok || !json.success) throw new Error(json.message || 'Failed to load offers');
      setOffers(json.data || []);
      setError('');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Error loading offers');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    const t = setTimeout(fetchOffers, 0);
    return () => clearTimeout(t);
  }, [fetchOffers]);

  // Salons that have made at least one offer, for the filter.
  const salonOptions = useMemo(() => {
    const map = new Map<string, string>();
    offers.forEach((o) => o.created_by_salon && map.set(o.created_by_salon.id, o.created_by_salon.name));
    return [...map.entries()].sort((a, b) => a[1].localeCompare(b[1]));
  }, [offers]);

  const stats = useMemo(() => {
    const live = offers.filter((o) => statusOf(o).label === 'Active');
    return {
      total: offers.filter((o) => !o.is_retired_platform_offer).length,
      active: live.length,
      salons: salonOptions.length,
      redemptions: offers.reduce((sum, o) => sum + (Number(o.redemptions_count) || 0), 0),
    };
  }, [offers, salonOptions]);

  const filtered = useMemo(() => offers.filter((o) => {
    if (search) {
      const q = search.toLowerCase();
      const hay = `${o.name} ${o.description ?? ''} ${o.created_by_salon?.name ?? ''}`.toLowerCase();
      if (!hay.includes(q)) return false;
    }
    if (salonFilter === 'platform' && !o.is_retired_platform_offer) return false;
    if (salonFilter && salonFilter !== 'platform' && o.created_by_salon?.id !== salonFilter) return false;
    if (scopeFilter && o.scope !== scopeFilter) return false;
    if (statusFilter && statusOf(o).label.toLowerCase() !== statusFilter) return false;
    return true;
  }), [offers, search, salonFilter, scopeFilter, statusFilter]);

  const openDetail = useCallback(async (offer: OfferData) => {
    setDetail(offer);
    setDetailLoading(true);
    try {
      const res = await fetch(`/api/superadmin/offers/${offer.id}`, { cache: 'no-store' });
      const json = await res.json();
      if (res.ok && json.success) setDetail({ ...offer, ...json.data });
    } finally {
      setDetailLoading(false);
    }
  }, []);

  const toggle = useCallback(async (offer: OfferData) => {
    const next = !offer.is_active;
    const salon = offer.created_by_salon?.name ?? 'the salon';
    const ok = await confirm({
      title: next ? `Switch "${offer.name}" back on?` : `Pause "${offer.name}"?`,
      body: next
        ? `It will apply again to eligible first-time customers at ${salon}.`
        : `It stops applying to new bookings at ${salon}. Bookings that already used it keep their discount. ${salon} will see it as paused in the Partner App.`,
      confirmLabel: next ? 'Switch on' : 'Pause offer',
      tone: next ? 'accent' : 'danger',
    });
    if (!ok) return;

    try {
      const res = await fetch(`/api/superadmin/offers/${offer.id}/toggle-active`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify({ is_active: next }),
      });
      const json = await res.json();
      if (!res.ok || !json.success) throw new Error(json.message || 'Failed to update the offer');
      setNotice({ message: `"${offer.name}" is now ${next ? 'active' : 'paused'}.`, tone: 'success' });
      fetchOffers();
    } catch (err) {
      setNotice({ message: err instanceof Error ? err.message : 'Error updating the offer', tone: 'error' });
    }
  }, [confirm, fetchOffers]);

  const remove = useCallback(async (offer: OfferData) => {
    const ok = await confirm({
      title: `Delete "${offer.name}"?`,
      body: `It is removed from ${offer.created_by_salon?.name ?? 'the platform'}. Offers that have already been redeemed cannot be deleted — pause them instead.`,
      confirmLabel: 'Delete offer',
      tone: 'danger',
    });
    if (!ok) return;

    try {
      const res = await fetch(`/api/superadmin/offers/${offer.id}`, { method: 'DELETE' });
      const json = await res.json();
      if (!res.ok || !json.success) throw new Error(json.message || 'Failed to delete the offer');
      setNotice({ message: `"${offer.name}" was deleted.`, tone: 'success' });
      fetchOffers();
    } catch (err) {
      setNotice({ message: err instanceof Error ? err.message : 'Error deleting the offer', tone: 'error' });
    }
  }, [confirm, fetchOffers]);

  const columns = useMemo<DataColumn<OfferData>[]>(() => [
    {
      key: 'salon',
      header: 'Created by',
      sortValue: (o) => o.created_by_salon?.name ?? '',
      csvValue: (o) => o.created_by_salon?.name ?? 'BookALook (retired platform offer)',
      render: (o) => o.created_by_salon ? (
        <div className={styles.offerNameCell}>
          <span className={styles.offerTitle}>{o.created_by_salon.name}</span>
          <span className={styles.offerDesc}>Salon’s own offer</span>
        </div>
      ) : (
        <div className={styles.offerNameCell}>
          <span className={styles.offerTitle}>BookALook</span>
          <span className={styles.offerDesc}>Old platform offer — retired</span>
        </div>
      ),
    },
    {
      key: 'name',
      header: 'Offer',
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
      header: 'Who qualifies',
      sortValue: (o) => o.scope,
      csvValue: (o) => SCOPE_LABEL[o.scope],
      render: (o) => (
        <Badge tone={o.scope === 'new_to_platform' ? 'accent' : 'info'} dot={false}>{SCOPE_LABEL[o.scope]}</Badge>
      ),
    },
    {
      key: 'discount',
      header: 'Discount',
      sortValue: (o) => Number(o.discount_value),
      csvValue: (o) => discountText(o),
      render: (o) => (
        <div className={styles.discountValueCell}>
          <span className={styles.discountMain}>
            {o.discount_type === 'percentage' ? `${Number(o.discount_value)}% off` : `₹${Number(o.discount_value)} off`}
          </span>
          <span className={styles.discountSub}>
            {o.max_discount_cap ? `Up to ₹${Number(o.max_discount_cap)}` : 'No cap'} · {o.service_templates_count} service{o.service_templates_count === 1 ? '' : 's'}
          </span>
        </div>
      ),
    },
    {
      key: 'validity',
      header: 'Runs',
      sortValue: (o) => o.ends_at ?? '',
      render: (o) => (
        <div className={styles.offerNameCell}>
          <span style={{ fontSize: '12.5px', color: 'var(--text-heading)' }}>
            {fmtDate(o.starts_at) ?? 'From creation'} → {fmtDate(o.ends_at) ?? 'No end date'}
          </span>
          <span style={{ fontSize: '11.5px', color: 'var(--text-muted)' }}>
            {o.redemptions_count} used{o.max_redemptions ? ` of ${o.max_redemptions}` : ''}
          </span>
        </div>
      ),
    },
    {
      key: 'status',
      header: 'Status',
      sortValue: (o) => statusOf(o).label,
      csvValue: (o) => statusOf(o).label,
      render: (o) => {
        const st = statusOf(o);
        return <Badge tone={st.tone}>{st.label}</Badge>;
      },
    },
    {
      key: 'actions',
      header: 'Actions',
      align: 'right',
      render: (o) => (
        <div className={styles.actionsCell}>
          <IconButton icon="info" label={`View ${o.name}`} onClick={() => openDetail(o)} />
          {!o.is_retired_platform_offer && (
            <Button variant={o.is_active ? 'soft' : 'primary'} size="sm" onClick={() => toggle(o)}>
              {o.is_active ? 'Pause' : 'Switch on'}
            </Button>
          )}
          <IconButton icon="trash" label={`Delete ${o.name}`} onClick={() => remove(o)} />
        </div>
      ),
    },
  ], [openDetail, toggle, remove]);

  const filtersOn = Boolean(search || salonFilter || scopeFilter || statusFilter);

  return (
    <div className={styles.container}>
      {confirmDialog}

      <PageHeader
        eyebrow="Promotions"
        title="First-Time Customer Offers"
        subtitle="Every salon creates its own first-time offers in the Partner App, for its own salon. Here you can see all of them, who made each one, and pause or remove any that break the rules."
      />

      <div className={styles.statsGrid}>
        <StatCard label="Salon offers" value={stats.total} icon="percent" tone="accent" />
        <StatCard label="Active now" value={stats.active} icon="checkCircle" tone="success" />
        <StatCard label="Salons with offers" value={stats.salons} icon="store" tone="info" />
        <StatCard label="Times used" value={stats.redemptions} icon="receipt" tone="neutral" />
      </div>

      {notice && (
        <div style={{ marginBottom: '16px' }}>
          <Alert tone={notice.tone} onClose={() => setNotice(null)}>{notice.message}</Alert>
        </div>
      )}

      <div className={styles.tableShell}>
        <DataTable
          columns={columns}
          rows={filtered}
          rowKey={(o) => o.id}
          loading={loading && offers.length === 0}
          error={error || undefined}
          noun="offers"
          exportName="first-time-offers"
          caption="First-time customer offers created by salons"
          empty={{
            title: filtersOn ? 'No offers match these filters' : 'No salon has created an offer yet',
            hint: filtersOn
              ? 'Try clearing the search or filters.'
              : 'Salons create first-time offers for their own salon from the Partner App (More → Offers).',
          }}
          toolbar={
            <div className={styles.toolbarRow}>
              <SearchInput
                value={search}
                onChange={setSearch}
                placeholder="Search by offer or salon…"
                ariaLabel="Search offers"
                className={styles.searchField}
              />
              <select className={styles.filterSelect} value={salonFilter} onChange={(e) => setSalonFilter(e.target.value)} aria-label="Filter by salon">
                <option value="">All salons</option>
                {salonOptions.map(([id, name]) => <option key={id} value={id}>{name}</option>)}
                <option value="platform">Retired platform offers</option>
              </select>
              <select className={styles.filterSelect} value={scopeFilter} onChange={(e) => setScopeFilter(e.target.value)} aria-label="Filter by who qualifies">
                <option value="">Anyone new</option>
                <option value="new_to_salon">New to the salon</option>
                <option value="new_to_platform">New to BookALook</option>
              </select>
              <select className={styles.filterSelect} value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)} aria-label="Filter by status">
                <option value="">Any status</option>
                <option value="active">Active</option>
                <option value="paused">Paused</option>
                <option value="expired">Expired</option>
                <option value="limit reached">Limit reached</option>
                <option value="retired">Retired</option>
              </select>
            </div>
          }
        />
      </div>

      <Modal
        open={detail !== null}
        onClose={() => setDetail(null)}
        title={detail?.name ?? 'Offer'}
        description={detail?.created_by_salon ? `Created by ${detail.created_by_salon.name}` : 'Old platform offer — retired'}
        footer={
          <div style={{ display: 'flex', justifyContent: 'flex-end', width: '100%' }}>
            <Button variant="ghost" onClick={() => setDetail(null)}>Close</Button>
          </div>
        }
      >
        {detail && (
          <>
            {detail.description && <p style={{ margin: '0 0 14px', color: 'var(--text-body)' }}>{detail.description}</p>}
            <DescriptionList
              items={[
                ['Salon', detail.created_by_salon?.name ?? 'BookALook (retired)'],
                ['Status', <Badge key="st" tone={statusOf(detail).tone}>{statusOf(detail).label}</Badge>],
                ['Who qualifies', SCOPE_LABEL[detail.scope]],
                ['Discount', discountText(detail)],
                ['Minimum service price', detail.min_service_price ? `₹${Number(detail.min_service_price)}` : 'None'],
                ['Minimum bill', detail.min_total_booking_subtotal ? `₹${Number(detail.min_total_booking_subtotal)}` : 'None'],
                ['Runs', `${fmtDate(detail.starts_at) ?? 'From creation'} → ${fmtDate(detail.ends_at) ?? 'No end date'}`],
                ['Used', `${detail.redemptions_count}${detail.max_redemptions ? ` of ${detail.max_redemptions}` : ''}`],
                ['Created', fmtDate(detail.created_at) ?? '—'],
              ]}
            />
            <h4 style={{ margin: '18px 0 8px', fontSize: '14px' }}>Services it applies to</h4>
            {detailLoading ? (
              <Skeleton height={60} radius={10} />
            ) : detail.service_templates && detail.service_templates.length > 0 ? (
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: '6px' }}>
                {detail.service_templates.map((t) => (
                  <Badge key={t.id} tone="info" dot={false}>{t.name}{t.category ? ` · ${t.category.name}` : ''}</Badge>
                ))}
              </div>
            ) : (
              <p style={{ margin: 0, color: 'var(--text-muted)', fontSize: '13px' }}>No services listed.</p>
            )}
          </>
        )}
      </Modal>
    </div>
  );
}
