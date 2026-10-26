'use client';

import { useEffect, useState, type ReactNode } from 'react';
import { useParams } from 'next/navigation';
import Link from 'next/link';
import {
  Badge, Button, DescriptionList, EmptyState, Skeleton, StatCard, Tabs, cx, formatINR, ui, useConfirm,
  type Tone,
} from '@/components/admin/ui';
import Icon from '@/components/admin/Icon';
import StaffDetailsModal from './StaffDetailsModal';
import BankDetailsPanel from './BankDetailsPanel';
import styles from './page.module.css';

interface CurrentPlan {
  name: string;
  billing_type: string;
  billing_label: string;
  end_date: string | null;
  days_left: number | null;
  lapsed: boolean;
}

interface Insights {
  bookings: {
    total: number;
    completed: number;
    upcoming: number;
    cancelled: number;
    no_show: number;
    this_month: number;
    walk_ins: number;
    last_at: string | null;
  };
  revenue: { total: number; this_month: number; avg_ticket: number };
  rating: { average: number | null; count: number };
  customers: number;
  staff: { active: number; total: number };
  services: number;
  combos: number;
  top_services: { name: string; times: number }[];
}

interface Salon {
  id: string;
  name: string;
  slug: string;
  status: string;
  created_at: string;
  address: string;
  pincode: string;
  gender_focus: string;
  description: string;
  city?: { name: string };
  sub_area?: { name: string } | null;
  admin?: { name: string; phone: string; email: string };
  assigned_collaborator_id?: string | null;
  assigned_collaborator?: { id: string; name: string; email: string } | null;
  current_plan?: CurrentPlan | null;
  insights?: Insights;
  providers?: { id: string; user?: { name: string; phone: string; email: string }; is_active: boolean }[];
  services?: {
    id: string;
    price: number;
    estimated_duration_minutes?: number;
    template?: {
      name: string;
      estimated_duration_minutes: number;
      category?: { name: string };
    };
  }[];
  combos?: {
    id: string;
    name: string;
    is_active: boolean;
    services?: { pivot?: { combo_special_price: number | string } }[];
  }[];
}

interface Collaborator {
  id: string;
  name: string;
  email?: string;
}

type TabKey = 'overview' | 'collaborator' | 'bank' | 'staff' | 'catalog';

const STATUS_TONE: Record<string, Tone> = {
  active: 'success',
  pending_approval: 'warning',
  needs_correction: 'warning',
  rejected: 'danger',
  suspended: 'danger',
  deactivated: 'neutral',
};

const formatStatus = (status: string) => status.replace(/_/g, ' ');

const formatDate = (value?: string | null, withTime = false) => {
  if (!value) return '—';
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return '—';
  return d.toLocaleDateString('en-IN', {
    day: '2-digit', month: 'short', year: 'numeric',
    ...(withTime ? { hour: '2-digit', minute: '2-digit' } : {}),
  });
};

const pct = (part: number, whole: number) => (whole > 0 ? Math.round((part / whole) * 100) : 0);

export default function SalonDirectoryDetail() {
  const params = useParams();
  const { id } = params;

  const [salon, setSalon] = useState<Salon | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  // Onboarding collaborator. Salons that came in through an enquiry already
  // have one; salons registered from the partner app arrive with none, and the
  // directory is the only place they can be given one.
  const [collaborators, setCollaborators] = useState<Collaborator[]>([]);
  const [selectedCollaborator, setSelectedCollaborator] = useState('');
  const [assigning, setAssigning] = useState(false);
  const [assignNote, setAssignNote] = useState('');
  const [confirm, confirmDialog] = useConfirm();

  const [selectedStaffId, setSelectedStaffId] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<TabKey>('overview');
  // Unsaved bank details are lost when the tab unmounts, so switching away asks.
  const [bankDirty, setBankDirty] = useState(false);

  const switchTab = async (tab: TabKey) => {
    if (tab === activeTab) return;
    if (activeTab === 'bank' && bankDirty) {
      const leave = await confirm({
        title: 'Leave without saving?',
        body: 'Your changes to the bank details have not been saved and will be lost.',
        confirmLabel: 'Discard changes',
        tone: 'danger',
      });
      if (!leave) return;
      setBankDirty(false);
    }
    setActiveTab(tab);
  };

  useEffect(() => {
    async function fetchSalon() {
      try {
        const [salonRes, collabRes] = await Promise.all([
          fetch(`/api/proxy/superadmin/salons/${id}`),
          fetch(`/api/proxy/superadmin/collaborators`),
        ]);

        if (!salonRes.ok) throw new Error('Failed to fetch salon details');
        const json = await salonRes.json();
        if (json.success) {
          setSalon(json.data);
          setSelectedCollaborator(json.data.assigned_collaborator_id || '');
        } else {
          throw new Error(json.message);
        }

        // A missing collaborator list only costs the dropdown, not the page.
        if (collabRes.ok) {
          const collabJson = await collabRes.json();
          setCollaborators(collabJson.data || []);
        }
      } catch (err: unknown) {
        setError(err instanceof Error ? err.message : 'Failed to fetch salon details');
      } finally {
        setLoading(false);
      }
    }
    if (id) fetchSalon();
  }, [id]);

  const handleAssignCollaborator = async () => {
    // The same button writes both directions. Assigning is routine, but picking
    // "No collaborator" posts a null and silently detaches whoever is on the
    // salon right now, so that direction is the one worth a prompt.
    const currentId = salon?.assigned_collaborator_id;
    const current = currentId
      ? collaborators.find((c) => c.id === currentId) ?? salon?.assigned_collaborator
      : null;

    if (!selectedCollaborator && current) {
      const ok = await confirm({
        title: `Detach ${current.name}?`,
        body: `${current.name} stops handling ${salon?.name ?? 'this salon'} and loses access to its bookings, staff and payouts. The salon keeps running with no collaborator.`,
        confirmLabel: 'Detach collaborator',
        tone: 'danger',
      });
      if (!ok) return;
    }

    setAssigning(true);
    setAssignNote('');

    try {
      const res = await fetch(
        `/api/proxy/superadmin/salons/${id}/assign-collaborator`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ collaborator_id: selectedCollaborator || null }),
        }
      );

      const json = await res.json();
      if (!res.ok || !json.success) {
        throw new Error(json.message || 'Failed to assign collaborator');
      }

      setSalon(prev => (prev ? { ...prev, ...json.data } : prev));
      setAssignNote(json.message);
    } catch (err: unknown) {
      setAssignNote(err instanceof Error ? err.message : 'Failed to assign collaborator');
    } finally {
      setAssigning(false);
    }
  };

  if (loading) {
    return (
      <div className={styles.container}>
        <Skeleton height={150} radius={18} />
        <div className={ui.statGrid}>
          {[0, 1, 2, 3].map((i) => <Skeleton key={i} height={104} radius={16} />)}
        </div>
        <Skeleton height={320} radius={18} />
      </div>
    );
  }

  if (error || !salon) {
    return (
      <div className={styles.container}>
        <Link href="/superadmin/salons" className={styles.backLink}>
          <Icon name="chevronLeft" size={15} /> Back to salons
        </Link>
        <EmptyState icon="alert" title="Could not load this salon" hint={error || 'Salon not found'} />
      </div>
    );
  }

  const ins = salon.insights;
  const plan = salon.current_plan;
  const location = [salon.sub_area?.name, salon.city?.name].filter(Boolean).join(', ');
  const planSoon = plan && !plan.lapsed && plan.days_left !== null && plan.days_left <= 5;

  const outcome: { label: string; value: number; tone: string }[] = ins
    ? [
        { label: 'Completed', value: ins.bookings.completed, tone: styles.barSuccess },
        { label: 'Upcoming', value: ins.bookings.upcoming, tone: styles.barAccent },
        { label: 'Cancelled', value: ins.bookings.cancelled, tone: styles.barWarning },
        { label: 'No-show', value: ins.bookings.no_show, tone: styles.barDanger },
      ]
    : [];

  return (
    <div className={styles.container}>
      <Link href="/superadmin/salons" className={styles.backLink}>
        <Icon name="chevronLeft" size={15} /> Back to salons
      </Link>

      {/* ------------------------------------------------------------ hero */}
      <section className={styles.hero}>
        <div className={styles.heroMain}>
          <span className={styles.heroAvatar} aria-hidden>{salon.name.charAt(0).toUpperCase()}</span>
          <div className={styles.heroText}>
            <div className={styles.heroTitleRow}>
              <h1 className={styles.title}>{salon.name}</h1>
              <Badge tone={STATUS_TONE[salon.status] ?? 'neutral'} dot={false}>{formatStatus(salon.status)}</Badge>
            </div>
            <div className={styles.heroMeta}>
              <span><Icon name="pin" size={14} /> {location || 'No location'}</span>
              <span><Icon name="calendar" size={14} /> Joined {formatDate(salon.created_at)}</span>
              {salon.gender_focus && <span><Icon name="users" size={14} /> Serves {salon.gender_focus}</span>}
            </div>
          </div>
        </div>

        <div className={styles.heroSide}>
          <HeroFact label="Owner">
            <b>{salon.admin?.name || '—'}</b>
            {salon.admin?.phone && <a href={`tel:${salon.admin.phone}`}>{salon.admin.phone}</a>}
          </HeroFact>
          <HeroFact label="Plan">
            {plan ? (
              <>
                <b className={styles.inlineBadges}>
                  {plan.name}
                  {plan.lapsed && <Badge tone="danger" dot={false}>Lapsed</Badge>}
                  {planSoon && <Badge tone="warning" dot={false}>{plan.days_left === 0 ? 'Ends today' : `${plan.days_left}d left`}</Badge>}
                </b>
                <span>{plan.billing_label}{plan.end_date ? ` · until ${formatDate(plan.end_date)}` : ''}</span>
              </>
            ) : (
              <b className={styles.warnText}>No active plan</b>
            )}
          </HeroFact>
          <HeroFact label="Collaborator">
            {salon.assigned_collaborator ? (
              <b>{salon.assigned_collaborator.name}</b>
            ) : (
              <button type="button" className={styles.linkButton} onClick={() => switchTab('collaborator')}>
                Assign one
              </button>
            )}
          </HeroFact>
        </div>
      </section>

      {/* ------------------------------------------------------------ KPIs */}
      {ins && (
        <div className={ui.statGrid}>
          <StatCard label="Bookings" icon="calendar" tone="accent" value={ins.bookings.total.toLocaleString('en-IN')}
            sub={`${ins.bookings.this_month} this month · ${ins.bookings.walk_ins} walk-ins`} />
          <StatCard label="Completed revenue" icon="rupee" tone="success" value={formatINR(ins.revenue.total)}
            sub={`${formatINR(ins.revenue.this_month)} this month · ${formatINR(ins.revenue.avg_ticket)} avg`} />
          <StatCard label="Rating" icon="star" tone="warning"
            value={ins.rating.average ? `${ins.rating.average.toFixed(1)} ★` : '—'}
            sub={ins.rating.count ? `${ins.rating.count} review${ins.rating.count === 1 ? '' : 's'}` : 'No reviews yet'} />
          <StatCard label="Customers" icon="users" tone="info" value={ins.customers.toLocaleString('en-IN')}
            sub={`${ins.staff.active} staff · ${ins.services} services`} />
        </div>
      )}

      {/* ------------------------------------------------------------ tabs */}
      <div className={styles.tabsBar}>
        <Tabs<TabKey>
          value={activeTab}
          onChange={switchTab}
          tabs={[
            { value: 'overview', label: 'Overview' },
            { value: 'collaborator', label: 'Collaborator' },
            { value: 'bank', label: 'Bank details' },
            { value: 'staff', label: <>Staff <span className={styles.tabCount}>{salon.providers?.length ?? 0}</span></> },
            { value: 'catalog', label: <>Catalog <span className={styles.tabCount}>{(salon.services?.length ?? 0) + (salon.combos?.length ?? 0)}</span></> },
          ]}
        />
      </div>

      {activeTab === 'overview' && (
        <div className={styles.overviewGrid}>
          <section className={styles.card}>
            <h2 className={styles.sectionTitle}>Bookings by outcome</h2>
            {ins && ins.bookings.total > 0 ? (
              <>
                <div className={styles.outcomeBar} aria-hidden>
                  {outcome.map((o) => o.value > 0 && (
                    <span key={o.label} className={o.tone} style={{ width: `${pct(o.value, ins.bookings.total)}%` }} />
                  ))}
                </div>
                <ul className={styles.outcomeList}>
                  {outcome.map((o) => (
                    <li key={o.label}>
                      <span className={cx(styles.swatch, o.tone)} />
                      <span>{o.label}</span>
                      <b>{o.value}</b>
                      <em>{pct(o.value, ins.bookings.total)}%</em>
                    </li>
                  ))}
                </ul>
                <p className={styles.footNote}>
                  Last booking {formatDate(ins.bookings.last_at, true)}
                </p>
              </>
            ) : (
              <EmptyState icon="calendar" title="No bookings yet" hint="Figures appear once customers book." />
            )}
          </section>

          <section className={styles.card}>
            <h2 className={styles.sectionTitle}>Most booked services</h2>
            {ins && ins.top_services.length > 0 ? (
              <ol className={styles.topList}>
                {ins.top_services.map((svc, i) => (
                  <li key={`${svc.name}-${i}`}>
                    <span className={styles.rank}>{i + 1}</span>
                    <span className={styles.topName}>{svc.name}</span>
                    <span className={styles.topBar}>
                      <span style={{ width: `${pct(svc.times, ins.top_services[0].times)}%` }} />
                    </span>
                    <b>{svc.times}</b>
                  </li>
                ))}
              </ol>
            ) : (
              <EmptyState icon="catalog" title="Nothing completed yet" hint="Shown from completed visits." />
            )}
          </section>

          <section className={styles.card}>
            <h2 className={styles.sectionTitle}>Salon details</h2>
            <DescriptionList
              variant="clean"
              items={[
                ['Address', salon.address || '—'],
                ['Area', salon.sub_area?.name || '—'],
                ['City', salon.city?.name || '—'],
                ['Pincode', salon.pincode || '—'],
                ['Serves', salon.gender_focus || '—'],
                ['Slug', <code key="slug" className={styles.code}>{salon.slug}</code>],
              ]}
            />
            {salon.description && <p className={styles.descValue}>{salon.description}</p>}
          </section>

          <section className={styles.card}>
            <h2 className={styles.sectionTitle}>Owner</h2>
            {salon.admin ? (
              <DescriptionList
                variant="clean"
                items={[
                  ['Name', salon.admin.name],
                  ['Phone', salon.admin.phone ? <a key="p" href={`tel:${salon.admin.phone}`}>{salon.admin.phone}</a> : '—'],
                  ['Email', salon.admin.email ? <a key="e" href={`mailto:${salon.admin.email}`}>{salon.admin.email}</a> : '—'],
                ]}
              />
            ) : (
              <EmptyState icon="users" title="No owner on file" />
            )}
          </section>
        </div>
      )}

      {activeTab === 'collaborator' && (
        <section className={styles.card}>
          <h2 className={styles.sectionTitle}>Onboarding collaborator</h2>
          <p className={styles.sectionHint}>
            The collaborator looks after this salon: its onboarding, staff and payouts.
          </p>

          <div className={styles.currentCollab}>
            <span className={styles.collabAvatar}>
              {salon.assigned_collaborator ? salon.assigned_collaborator.name.charAt(0).toUpperCase() : '?'}
            </span>
            <div>
              <b>{salon.assigned_collaborator?.name ?? 'No collaborator assigned yet'}</b>
              {salon.assigned_collaborator?.email && <span>{salon.assigned_collaborator.email}</span>}
            </div>
          </div>

          <div className={styles.assignRow}>
            <select
              className={styles.assignSelect}
              value={selectedCollaborator}
              onChange={(e) => setSelectedCollaborator(e.target.value)}
              disabled={assigning}
              aria-label="Collaborator"
            >
              <option value="">— No collaborator —</option>
              {collaborators.map((collaborator) => (
                <option key={collaborator.id} value={collaborator.id}>
                  {collaborator.name}
                </option>
              ))}
            </select>

            <Button
              variant="primary"
              onClick={handleAssignCollaborator}
              loading={assigning}
              disabled={assigning || selectedCollaborator === (salon.assigned_collaborator_id || '')}
            >
              {assigning ? 'Saving…' : 'Save assignment'}
            </Button>
          </div>

          {collaborators.length === 0 && (
            <p className={styles.assignNote}>
              No collaborators exist yet. Create one from the Collaborators page first.
            </p>
          )}

          {assignNote && <p className={styles.assignNote}>{assignNote}</p>}
        </section>
      )}

      {activeTab === 'bank' && (
        <BankDetailsPanel salonId={salon.id} salonName={salon.name} onDirtyChange={setBankDirty} />
      )}

      {activeTab === 'staff' && (
        <section className={styles.card}>
          <h2 className={styles.sectionTitle}>Staff</h2>
          {salon.providers && salon.providers.length > 0 ? (
            <div className={styles.staffGrid}>
              {salon.providers.map(provider => (
                <button
                  type="button"
                  key={provider.id}
                  className={cx(styles.staffCard, styles.interactiveStaffCard)}
                  onClick={() => setSelectedStaffId(provider.id)}
                >
                  <div className={styles.staffAvatar}>
                    {provider.user?.name?.charAt(0).toUpperCase() ?? '?'}
                  </div>
                  <div className={styles.staffInfo}>
                    <h4>{provider.user?.name ?? 'Unnamed'}</h4>
                    <p>{provider.user?.phone}</p>
                    {provider.user?.email && <p>{provider.user.email}</p>}
                  </div>
                  <Badge tone={provider.is_active ? 'success' : 'neutral'} dot={false}>
                    {provider.is_active ? 'Active' : 'Inactive'}
                  </Badge>
                </button>
              ))}
            </div>
          ) : (
            <EmptyState icon="users" title="No staff registered" />
          )}
        </section>
      )}

      {activeTab === 'catalog' && (
        <>
          <section className={styles.card}>
            <h2 className={styles.sectionTitle}>Services offered</h2>
            {salon.services && salon.services.length > 0 ? (
              <div className={styles.servicesGrid}>
                {salon.services.map(service => (
                  <div key={service.id} className={styles.serviceItem}>
                    <div>
                      <div className={styles.serviceCategory}>
                        {service.template?.category?.name || 'Uncategorized'}
                      </div>
                      <div className={styles.serviceName}>
                        {service.template?.name || 'Custom Service'}
                      </div>
                    </div>
                    <div className={styles.serviceMeta}>
                      <span className={styles.serviceDuration}>
                        {service.estimated_duration_minutes || service.template?.estimated_duration_minutes || 0} mins
                      </span>
                      <span className={styles.servicePrice}>
                        {formatINR(service.price)}
                      </span>
                    </div>
                  </div>
                ))}
              </div>
            ) : (
              <EmptyState icon="catalog" title="No services configured" />
            )}
          </section>

          <section className={styles.card}>
            <h2 className={styles.sectionTitle}>Combos</h2>
            {salon.combos && salon.combos.length > 0 ? (
              <div className={styles.combosGrid}>
                {salon.combos.map(combo => {
                  const totalPrice = combo.services?.reduce((sum, svc) => sum + Number(svc.pivot?.combo_special_price || 0), 0) || 0;
                  return (
                    <div key={combo.id} className={styles.comboItem}>
                      <div className={styles.comboName}>{combo.name}</div>
                      {combo.services && combo.services.length > 0 && (
                        <div className={styles.comboCount}>{combo.services.length} services included</div>
                      )}
                      <div className={styles.comboPrice}>{formatINR(totalPrice)}</div>
                      {!combo.is_active && <Badge tone="neutral" dot={false}>Inactive</Badge>}
                    </div>
                  );
                })}
              </div>
            ) : (
              <EmptyState icon="catalog" title="No combos configured" />
            )}
          </section>
        </>
      )}

      {selectedStaffId && typeof id === 'string' && (
        <StaffDetailsModal
          salonId={id}
          providerId={selectedStaffId}
          onClose={() => setSelectedStaffId(null)}
        />
      )}

      {confirmDialog}
    </div>
  );
}

function HeroFact({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className={styles.heroFact}>
      <span className={styles.heroFactLabel}>{label}</span>
      <div className={styles.heroFactValue}>{children}</div>
    </div>
  );
}
