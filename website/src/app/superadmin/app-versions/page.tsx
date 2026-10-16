'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Alert,
  Badge,
  Button,
  Card,
  EmptyState,
  Field,
  Modal,
  PageHeader,
  Segmented,
  Skeleton,
  useConfirm,
} from '@/components/admin/ui';
import Icon from '@/components/admin/Icon';
import styles from './page.module.css';

type AppId = 'customer' | 'partner';

interface Release {
  id: string;
  app: AppId;
  version: string;
  build_number: number;
  released_at: string | null;
  release_notes: string | null;
  android_store_url: string | null;
  ios_store_url: string | null;
  status: 'draft' | 'published' | 'retired';
  created_by?: { id: string; name: string } | null;
  updater?: { id: string; name: string } | null;
  created_at: string;
}

interface Policy {
  id?: string;
  app: AppId;
  latest_release_id: string | null;
  minimum_release_id: string | null;
  update_mode: 'optional' | 'mandatory';
  is_enforced: boolean;
  enforce_at: string | null;
  update_message: string | null;
  android_store_url: string | null;
  ios_store_url: string | null;
  resolved_android_url?: string | null;
  resolved_ios_url?: string | null;
  is_active?: boolean;
  latest_release?: Release | null;
  minimum_release?: Release | null;
  updated_by?: string | null;
  updated_at?: string | null;
}

interface AuditItem {
  id: string;
  action: string;
  actor: string;
  label: string;
  before: any;
  after: any;
  metadata?: any;
  created_at: string;
}

function parseSemVer(v: string): [number, number, number] {
  const clean = v.replace(/^v/i, '').trim();
  const parts = clean.split('.').map((p) => parseInt(p, 10) || 0);
  return [parts[0] || 0, parts[1] || 0, parts[2] || 0];
}

function compareReleases(v1: string, b1: number, v2: string, b2: number): number {
  const [maj1, min1, pat1] = parseSemVer(v1);
  const [maj2, min2, pat2] = parseSemVer(v2);

  if (maj1 !== maj2) return maj1 - maj2;
  if (min1 !== min2) return min1 - min2;
  if (pat1 !== pat2) return pat1 - pat2;
  return (b1 || 0) - (b2 || 0);
}

export default function AppVersionsPage() {
  const [currentApp, setCurrentApp] = useState<AppId>('customer');
  const [loading, setLoading] = useState(true);
  const [savingPolicy, setSavingPolicy] = useState(false);
  const [releases, setReleases] = useState<Release[]>([]);
  const [policies, setPolicies] = useState<Record<AppId, Policy | null>>({
    customer: null,
    partner: null,
  });
  const [auditHistory, setAuditHistory] = useState<AuditItem[]>([]);
  const [feedback, setFeedback] = useState<{ tone: 'success' | 'error' | 'warning'; message: string } | null>(null);

  // Form state for current app's policy
  const [formLatestId, setFormLatestId] = useState<string>('');
  const [formMinimumId, setFormMinimumId] = useState<string>('');
  const [formUpdateMode, setFormUpdateMode] = useState<'optional' | 'mandatory'>('optional');
  const [formIsEnforced, setFormIsEnforced] = useState<boolean>(false);
  const [formEnforceAt, setFormEnforceAt] = useState<string>('');
  const [formUpdateMessage, setFormUpdateMessage] = useState<string>('');
  const [formAndroidUrl, setFormAndroidUrl] = useState<string>('');
  const [formIosUrl, setFormIosUrl] = useState<string>('');

  // Release Modal state
  const [isReleaseModalOpen, setIsReleaseModalOpen] = useState(false);
  const [editingRelease, setEditingRelease] = useState<Release | null>(null);
  const [modalVersion, setModalVersion] = useState('');
  const [modalBuildNumber, setModalBuildNumber] = useState('');
  const [modalReleasedAt, setModalReleasedAt] = useState('');
  const [modalStatus, setModalStatus] = useState<'draft' | 'published' | 'retired'>('published');
  const [modalAndroidUrl, setModalAndroidUrl] = useState('');
  const [modalIosUrl, setModalIosUrl] = useState('');
  const [modalNotes, setModalNotes] = useState('');
  const [submittingRelease, setSubmittingRelease] = useState(false);

  const [confirm, confirmDialog] = useConfirm();

  const authHeaders = () => ({
    'Content-Type': 'application/json',
  });

  const fetchData = useCallback(async () => {
    try {
      setLoading(true);
      const res = await fetch('/api/proxy/superadmin/app-versions', {
        headers: authHeaders(),
        cache: 'no-store',
      });
      const data = await res.json();
      if (data.success) {
        setReleases(data.releases || []);
        setPolicies(data.policies || { customer: null, partner: null });
        setAuditHistory(data.audit_history || []);
      }
    } catch (e) {
      console.error('Failed to load app versions data:', e);
      setFeedback({ tone: 'error', message: 'Failed to load app version configuration from backend.' });
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchData();
  }, [fetchData]);

  // Sync form with current app's policy
  useEffect(() => {
    const policy = policies[currentApp];
    if (policy) {
      setFormLatestId(policy.latest_release_id || '');
      setFormMinimumId(policy.minimum_release_id || '');
      setFormUpdateMode(policy.update_mode || 'optional');
      setFormIsEnforced(Boolean(policy.is_enforced));
      // Format ISO datetime to YYYY-MM-DDTHH:mm for datetime-local input
      if (policy.enforce_at) {
        try {
          const d = new Date(policy.enforce_at);
          const localIso = new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
          setFormEnforceAt(localIso);
        } catch {
          setFormEnforceAt('');
        }
      } else {
        setFormEnforceAt('');
      }
      setFormUpdateMessage(policy.update_message || '');
      setFormAndroidUrl(policy.android_store_url || '');
      setFormIosUrl(policy.ios_store_url || '');
    } else {
      setFormLatestId('');
      setFormMinimumId('');
      setFormUpdateMode('optional');
      setFormIsEnforced(false);
      setFormEnforceAt('');
      setFormUpdateMessage('');
      setFormAndroidUrl('');
      setFormIosUrl('');
    }
  }, [currentApp, policies]);

  // Releases filtered by active app
  const appReleases = useMemo(() => {
    return releases.filter((r) => r.app === currentApp);
  }, [releases, currentApp]);

  // Only published releases can be selected in active update policies
  const publishedReleases = useMemo(() => {
    return appReleases
      .filter((r) => r.status === 'published')
      .sort((a, b) => compareReleases(b.version, b.build_number, a.version, a.build_number));
  }, [appReleases]);

  const selectedLatest = useMemo(() => {
    return publishedReleases.find((r) => r.id === formLatestId) || null;
  }, [publishedReleases, formLatestId]);

  const selectedMinimum = useMemo(() => {
    return publishedReleases.find((r) => r.id === formMinimumId) || null;
  }, [publishedReleases, formMinimumId]);

  // Semantic version comparison check
  const semverMismatchError = useMemo(() => {
    if (!selectedLatest || !selectedMinimum) return null;
    const diff = compareReleases(
      selectedMinimum.version,
      selectedMinimum.build_number,
      selectedLatest.version,
      selectedLatest.build_number
    );
    if (diff > 0) {
      return `Minimum supported version (v${selectedMinimum.version} #${selectedMinimum.build_number}) cannot be higher than the latest published version (v${selectedLatest.version} #${selectedLatest.build_number}).`;
    }
    return null;
  }, [selectedLatest, selectedMinimum]);

  // Missing store URL detection
  const missingStoreUrlsWarning = useMemo(() => {
    if (!selectedLatest) return null;
    const effectiveAndroid = formAndroidUrl || selectedLatest.android_store_url;
    const effectiveIos = formIosUrl || selectedLatest.ios_store_url;
    const missing: string[] = [];
    if (!effectiveAndroid) missing.push('Google Play Store URL');
    if (!effectiveIos) missing.push('Apple App Store URL');
    if (missing.length > 0) {
      return `${missing.join(' and ')} not configured. Users redirected to update will not have a valid store link.`;
    }
    return null;
  }, [selectedLatest, formAndroidUrl, formIosUrl]);

  // Detect if form has unsaved modifications
  const isDirty = useMemo(() => {
    const policy = policies[currentApp];
    if (!policy) {
      return Boolean(formLatestId || formMinimumId || formIsEnforced || formUpdateMessage);
    }
    const currentEnforceAtIso = formEnforceAt ? new Date(formEnforceAt).toISOString() : null;
    const origEnforceAtIso = policy.enforce_at ? new Date(policy.enforce_at).toISOString() : null;

    return (
      formLatestId !== (policy.latest_release_id || '') ||
      formMinimumId !== (policy.minimum_release_id || '') ||
      formUpdateMode !== policy.update_mode ||
      formIsEnforced !== policy.is_enforced ||
      currentEnforceAtIso !== origEnforceAtIso ||
      formUpdateMessage !== (policy.update_message || '') ||
      formAndroidUrl !== (policy.android_store_url || '') ||
      formIosUrl !== (policy.ios_store_url || '')
    );
  }, [
    currentApp,
    policies,
    formLatestId,
    formMinimumId,
    formUpdateMode,
    formIsEnforced,
    formEnforceAt,
    formUpdateMessage,
    formAndroidUrl,
    formIosUrl,
  ]);

  const handleSavePolicy = async () => {
    if (!formLatestId || !formMinimumId) {
      setFeedback({ tone: 'error', message: 'Please select both Latest and Minimum Supported releases.' });
      return;
    }
    if (semverMismatchError) {
      setFeedback({ tone: 'error', message: semverMismatchError });
      return;
    }

    const appName = currentApp === 'customer' ? 'Customer App' : 'Partner App';
    const confirmed = await confirm({
      title: `Publish Update Policy for ${appName}?`,
      body: `This will update the active policy for ${appName}. Enforcement is currently set to ${
        formIsEnforced ? 'ENABLED (active)' : 'DISABLED'
      }. Minimum version required: v${selectedMinimum?.version} #${selectedMinimum?.build_number}.`,
      confirmLabel: 'Save & Publish Policy',
      tone: 'accent',
    });

    if (!confirmed) return;

    try {
      setSavingPolicy(true);
      setFeedback(null);

      const payload = {
        latest_release_id: formLatestId,
        minimum_release_id: formMinimumId,
        update_mode: formUpdateMode,
        is_enforced: formIsEnforced,
        enforce_at: formEnforceAt ? new Date(formEnforceAt).toISOString() : null,
        update_message: formUpdateMessage.trim() || null,
        android_store_url: formAndroidUrl.trim() || null,
        ios_store_url: formIosUrl.trim() || null,
      };

      const res = await fetch(`/api/proxy/superadmin/app-versions/policies/${currentApp}`, {
        method: 'PUT',
        headers: authHeaders(),
        body: JSON.stringify(payload),
      });

      const data = await res.json();
      if (!res.ok || !data.success) {
        throw new Error(data.message || 'Failed to save update policy.');
      }

      setFeedback({
        tone: 'success',
        message: `${appName} update policy saved successfully. Cache has been invalidated.`,
      });
      fetchData();
    } catch (err: any) {
      setFeedback({ tone: 'error', message: err.message || 'Error saving update policy.' });
    } finally {
      setSavingPolicy(false);
    }
  };

  const openCreateReleaseModal = () => {
    setEditingRelease(null);
    setModalVersion('');
    setModalBuildNumber('');
    setModalReleasedAt(new Date().toISOString().slice(0, 10));
    setModalStatus('published');
    setModalAndroidUrl('');
    setModalIosUrl('');
    setModalNotes('');
    setIsReleaseModalOpen(true);
  };

  const openEditReleaseModal = (r: Release) => {
    setEditingRelease(r);
    setModalVersion(r.version);
    setModalBuildNumber(String(r.build_number));
    setModalReleasedAt(r.released_at ? r.released_at.slice(0, 10) : '');
    setModalStatus(r.status);
    setModalAndroidUrl(r.android_store_url || '');
    setModalIosUrl(r.ios_store_url || '');
    setModalNotes(r.release_notes || '');
    setIsReleaseModalOpen(true);
  };

  const handleSaveRelease = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!modalVersion.trim() || !modalBuildNumber.trim()) {
      setFeedback({ tone: 'error', message: 'Version and Build Number are required.' });
      return;
    }

    try {
      setSubmittingRelease(true);
      setFeedback(null);

      const payload = {
        app: currentApp,
        version: modalVersion.trim(),
        build_number: parseInt(modalBuildNumber, 10),
        released_at: modalReleasedAt ? new Date(modalReleasedAt).toISOString() : null,
        status: modalStatus,
        android_store_url: modalAndroidUrl.trim() || null,
        ios_store_url: modalIosUrl.trim() || null,
        release_notes: modalNotes.trim() || null,
      };

      const url = editingRelease
        ? `/api/proxy/superadmin/app-versions/releases/${editingRelease.id}`
        : '/api/proxy/superadmin/app-versions/releases';

      const method = editingRelease ? 'PUT' : 'POST';

      const res = await fetch(url, {
        method,
        headers: authHeaders(),
        body: JSON.stringify(payload),
      });

      const data = await res.json();
      if (!res.ok || !data.success) {
        throw new Error(data.message || 'Failed to save release.');
      }

      setIsReleaseModalOpen(false);
      setFeedback({
        tone: 'success',
        message: editingRelease
          ? `Release v${payload.version} updated successfully.`
          : `Release v${payload.version} registered successfully.`,
      });
      fetchData();
    } catch (err: any) {
      setFeedback({ tone: 'error', message: err.message || 'Error saving release.' });
    } finally {
      setSubmittingRelease(false);
    }
  };

  const activePolicy = policies[currentApp];

  return (
    <div className={styles.container}>
      <PageHeader
        eyebrow="Platform Maintenance"
        title="App Version Management"
        subtitle="Manage releases, store distribution links, and control server-side force updates for BookALook mobile apps."
        actions={
          <Button variant="primary" icon="plus" onClick={openCreateReleaseModal}>
            Register New Release
          </Button>
        }
      />

      {feedback && (
        <Alert tone={feedback.tone} onClose={() => setFeedback(null)}>
          {feedback.message}
        </Alert>
      )}

      {/* App Selector Tabs */}
      <div className={styles.topBar}>
        <div className={styles.appSelector}>
          <Segmented
            ariaLabel="Select Application"
            value={currentApp}
            onChange={(val) => setCurrentApp(val as AppId)}
            options={[
              { value: 'customer', label: 'Customer App' },
              { value: 'partner', label: 'Partner App' },
            ]}
          />
        </div>
      </div>

      {loading ? (
        <Card padded>
          <Skeleton height={200} />
        </Card>
      ) : (
        <div className={styles.grid}>
          {/* Active Policy Settings */}
          <Card
            title={`Active Update Policy — ${currentApp === 'customer' ? 'Customer App' : 'Partner App'}`}
            subtitle="Define minimum supported version, update mode, and automated server-side enforcement."
            padded
          >
            <div className={styles.policyCard}>
              {/* Status Banner */}
              <div
                className={`${styles.statusBanner} ${
                  formIsEnforced ? styles.statusActive : styles.statusDisabled
                }`}
              >
                <div className={styles.statusInfo}>
                  <Badge tone={formIsEnforced ? 'success' : 'neutral'} pulse={formIsEnforced}>
                    {formIsEnforced ? 'ENFORCEMENT ENABLED' : 'ENFORCEMENT DISABLED'}
                  </Badge>
                  <div>
                    <div className={styles.statusTitle}>
                      {formIsEnforced
                        ? formEnforceAt && new Date(formEnforceAt) > new Date()
                          ? `Scheduled: Starts ${new Date(formEnforceAt).toLocaleString()}`
                          : 'Blocking Outdated Clients (HTTP 426)'
                        : 'Updates are non-blocking'}
                    </div>
                    <div className={styles.statusDesc}>
                      {activePolicy?.updated_by
                        ? `Last updated by ${activePolicy.updated_by} on ${new Date(
                            activePolicy.updated_at || ''
                          ).toLocaleDateString()}`
                        : 'No prior update recorded.'}
                    </div>
                  </div>
                </div>
              </div>

              {/* Version Selectors */}
              <div className={styles.formGrid}>
                <Field
                  label="Latest Published Release"
                  hint="The most recent release available to end users."
                >
                  <select
                    className="control"
                    value={formLatestId}
                    onChange={(e) => setFormLatestId(e.target.value)}
                  >
                    <option value="">— Select Latest Release —</option>
                    {publishedReleases.map((r) => (
                      <option key={r.id} value={r.id}>
                        v{r.version} (Build #{r.build_number}) — {r.released_at ? r.released_at.slice(0, 10) : 'No date'}
                      </option>
                    ))}
                  </select>
                </Field>

                <Field
                  label="Minimum Supported Version"
                  hint="Clients older than this build will be required to update."
                >
                  <select
                    className="control"
                    value={formMinimumId}
                    onChange={(e) => setFormMinimumId(e.target.value)}
                  >
                    <option value="">— Select Minimum Release —</option>
                    {publishedReleases.map((r) => (
                      <option key={r.id} value={r.id}>
                        v{r.version} (Build #{r.build_number}) — {r.released_at ? r.released_at.slice(0, 10) : 'No date'}
                      </option>
                    ))}
                  </select>
                </Field>

                {semverMismatchError && (
                  <div className={styles.fullCol}>
                    <Alert tone="error">{semverMismatchError}</Alert>
                  </div>
                )}

                <Field label="Update Mode" hint="Optional encourages updates; Mandatory blocks usage.">
                  <select
                    className="control"
                    value={formUpdateMode}
                    onChange={(e) => setFormUpdateMode(e.target.value as any)}
                  >
                    <option value="optional">Optional (Soft Prompt)</option>
                    <option value="mandatory">Mandatory (Hard Enforce)</option>
                  </select>
                </Field>

                <Field
                  label="Scheduled Enforcement Date & Time (Optional)"
                  hint="Leave empty for immediate enforcement."
                >
                  <input
                    type="datetime-local"
                    className="control"
                    value={formEnforceAt}
                    onChange={(e) => setFormEnforceAt(e.target.value)}
                  />
                </Field>

                {/* Enforcement Toggle */}
                <div className={`${styles.fullCol} ${styles.toggleRow}`}>
                  <div>
                    <div className={styles.toggleLabel}>Enable Server-Side Enforcement</div>
                    <div className={styles.toggleHint}>
                      When enabled, API requests from clients below minimum version return HTTP 426 Upgrade Required.
                    </div>
                  </div>
                  <label className={styles.switch}>
                    <input
                      type="checkbox"
                      checked={formIsEnforced}
                      onChange={(e) => setFormIsEnforced(e.target.checked)}
                    />
                    <span className={styles.slider} />
                  </label>
                </div>

                {/* Store URLs */}
                <Field
                  label="Android Store URL"
                  hint="Play Store link. Defaults to latest release URL if left blank."
                >
                  <input
                    type="url"
                    className="control"
                    placeholder="https://play.google.com/store/apps/details?id=..."
                    value={formAndroidUrl}
                    onChange={(e) => setFormAndroidUrl(e.target.value)}
                  />
                </Field>

                <Field
                  label="iOS App Store URL"
                  hint="App Store link. Defaults to latest release URL if left blank."
                >
                  <input
                    type="url"
                    className="control"
                    placeholder="https://apps.apple.com/app/..."
                    value={formIosUrl}
                    onChange={(e) => setFormIosUrl(e.target.value)}
                  />
                </Field>

                {/* Update Message */}
                <div className={styles.fullCol}>
                  <Field
                    label="User-Facing Update Message"
                    hint="Message displayed on the update screen or dialog when the user opens an outdated app."
                  >
                    <textarea
                      rows={3}
                      className="control"
                      placeholder="A new version with important speed improvements and security updates is now available."
                      value={formUpdateMessage}
                      onChange={(e) => setFormUpdateMessage(e.target.value)}
                    />
                  </Field>
                </div>

                {/* Store URL warning if missing */}
                {missingStoreUrlsWarning && (
                  <div className={styles.fullCol}>
                    <div className={styles.warningBox}>
                      <Icon name="alert" size={18} />
                      <div>
                        <strong>Store URL Notice:</strong>
                        <div>{missingStoreUrlsWarning}</div>
                      </div>
                    </div>
                  </div>
                )}
              </div>

              {/* Action Bar */}
              <div className={styles.actionsBar}>
                <Button
                  variant="primary"
                  loading={savingPolicy}
                  disabled={!isDirty || Boolean(semverMismatchError)}
                  onClick={handleSavePolicy}
                >
                  Save & Publish Policy
                </Button>
              </div>
            </div>
          </Card>

          {/* Quick Summary / Status */}
          <Card
            title="App Distribution Status"
            subtitle="Platform configuration overview."
            padded
          >
            <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
              <div>
                <div style={{ fontSize: 12, fontWeight: 700, color: 'var(--text-muted)', textTransform: 'uppercase' }}>
                  Target Application
                </div>
                <div style={{ fontSize: 16, fontWeight: 800, marginTop: 4 }}>
                  {currentApp === 'customer' ? 'Customer App' : 'Partner App'}
                </div>
              </div>

              <div>
                <div style={{ fontSize: 12, fontWeight: 700, color: 'var(--text-muted)', textTransform: 'uppercase' }}>
                  Active Minimum Version
                </div>
                <div style={{ fontSize: 14, fontWeight: 600, marginTop: 4 }}>
                  {activePolicy?.minimum_release ? (
                    <>
                      v{activePolicy.minimum_release.version} (Build #{activePolicy.minimum_release.build_number})
                    </>
                  ) : (
                    <span style={{ color: 'var(--text-muted)' }}>Not configured yet</span>
                  )}
                </div>
              </div>

              <div>
                <div style={{ fontSize: 12, fontWeight: 700, color: 'var(--text-muted)', textTransform: 'uppercase' }}>
                  Active Latest Version
                </div>
                <div style={{ fontSize: 14, fontWeight: 600, marginTop: 4 }}>
                  {activePolicy?.latest_release ? (
                    <>
                      v{activePolicy.latest_release.version} (Build #{activePolicy.latest_release.build_number})
                    </>
                  ) : (
                    <span style={{ color: 'var(--text-muted)' }}>Not configured yet</span>
                  )}
                </div>
              </div>

              <div>
                <div style={{ fontSize: 12, fontWeight: 700, color: 'var(--text-muted)', textTransform: 'uppercase' }}>
                  Resolved Store URLs
                </div>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 6, marginTop: 6 }}>
                  <div className={styles.urlPill} title={activePolicy?.resolved_android_url || 'Missing'}>
                    <Icon name="smartphone" size={13} />
                    Android:{' '}
                    {activePolicy?.resolved_android_url ? (
                      <a href={activePolicy.resolved_android_url} target="_blank" rel="noreferrer">
                        {activePolicy.resolved_android_url}
                      </a>
                    ) : (
                      'None'
                    )}
                  </div>
                  <div className={styles.urlPill} title={activePolicy?.resolved_ios_url || 'Missing'}>
                    <Icon name="smartphone" size={13} />
                    iOS:{' '}
                    {activePolicy?.resolved_ios_url ? (
                      <a href={activePolicy.resolved_ios_url} target="_blank" rel="noreferrer">
                        {activePolicy.resolved_ios_url}
                      </a>
                    ) : (
                      'None'
                    )}
                  </div>
                </div>
              </div>

              <div>
                <div style={{ fontSize: 12, fontWeight: 700, color: 'var(--text-muted)', textTransform: 'uppercase' }}>
                  Registered Releases
                </div>
                <div style={{ fontSize: 14, fontWeight: 600, marginTop: 4 }}>
                  {appReleases.length} Total ({publishedReleases.length} Published)
                </div>
              </div>
            </div>
          </Card>
        </div>
      )}

      {/* Release Registry Section */}
      <Card
        title={`Release Registry — ${currentApp === 'customer' ? 'Customer App' : 'Partner App'}`}
        subtitle="Historical catalog of all registered app binaries and release notes."
        actions={
          <Button variant="secondary" size="sm" icon="plus" onClick={openCreateReleaseModal}>
            Register Release
          </Button>
        }
      >
        {appReleases.length === 0 ? (
          <EmptyState
            icon="smartphone"
            title="No releases registered yet"
            hint={`Register your first release for the ${
              currentApp === 'customer' ? 'Customer' : 'Partner'
            } App to populate update policies.`}
            action={
              <Button variant="primary" icon="plus" onClick={openCreateReleaseModal}>
                Register Release
              </Button>
            }
          />
        ) : (
          <div className={styles.tableWrap}>
            <table className={styles.table}>
              <thead>
                <tr>
                  <th>Version</th>
                  <th>Build #</th>
                  <th>Release Date</th>
                  <th>Status</th>
                  <th>Store Links</th>
                  <th>Release Notes</th>
                  <th style={{ textAlign: 'right' }}>Actions</th>
                </tr>
              </thead>
              <tbody>
                {appReleases.map((r) => {
                  const isCurrentLatest = activePolicy?.latest_release_id === r.id;
                  const isCurrentMinimum = activePolicy?.minimum_release_id === r.id;
                  return (
                    <tr key={r.id}>
                      <td>
                        <div className={styles.versionBadge}>v{r.version}</div>
                        {(isCurrentLatest || isCurrentMinimum) && (
                          <div style={{ display: 'flex', gap: 4, marginTop: 4 }}>
                            {isCurrentLatest && <Badge tone="accent">Latest</Badge>}
                            {isCurrentMinimum && <Badge tone="warning">Min Supported</Badge>}
                          </div>
                        )}
                      </td>
                      <td>
                        <span className={styles.buildNum}>#{r.build_number}</span>
                      </td>
                      <td>
                        {r.released_at ? new Date(r.released_at).toLocaleDateString() : '—'}
                      </td>
                      <td>
                        <Badge
                          tone={
                            r.status === 'published'
                              ? 'success'
                              : r.status === 'draft'
                              ? 'neutral'
                              : 'danger'
                          }
                        >
                          {r.status.toUpperCase()}
                        </Badge>
                      </td>
                      <td>
                        <div style={{ display: 'flex', gap: 6 }}>
                          {r.android_store_url && (
                            <a
                              href={r.android_store_url}
                              target="_blank"
                              rel="noreferrer"
                              title="Android Store URL"
                              style={{ color: 'var(--accent-color)' }}
                            >
                              Android
                            </a>
                          )}
                          {r.ios_store_url && (
                            <a
                              href={r.ios_store_url}
                              target="_blank"
                              rel="noreferrer"
                              title="iOS App Store URL"
                              style={{ color: 'var(--accent-color)' }}
                            >
                              iOS
                            </a>
                          )}
                          {!r.android_store_url && !r.ios_store_url && (
                            <span style={{ color: 'var(--text-muted)' }}>None</span>
                          )}
                        </div>
                      </td>
                      <td style={{ maxWidth: 260 }}>
                        <div
                          style={{
                            overflow: 'hidden',
                            textOverflow: 'ellipsis',
                            whiteSpace: 'nowrap',
                            color: 'var(--text-muted)',
                          }}
                          title={r.release_notes || ''}
                        >
                          {r.release_notes || '—'}
                        </div>
                      </td>
                      <td style={{ textAlign: 'right' }}>
                        <Button
                          variant="ghost"
                          size="sm"
                          icon="edit"
                          onClick={() => openEditReleaseModal(r)}
                        >
                          Edit
                        </Button>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      {/* Audit History Card */}
      <Card
        title="Version Management Audit Trail"
        subtitle="Recent administrative changes to app releases and force update policies."
        padded
        className={styles.auditLogCard}
      >
        {auditHistory.length === 0 ? (
          <div style={{ color: 'var(--text-muted)', fontSize: 13 }}>No audit records found yet.</div>
        ) : (
          <div>
            {auditHistory.map((item) => (
              <div key={item.id} className={styles.auditItem}>
                <div>
                  <div className={styles.auditActor}>{item.label}</div>
                  <div style={{ color: 'var(--text-muted)', fontSize: 12, marginTop: 2 }}>
                    Triggered by <strong>{item.actor}</strong>
                  </div>
                </div>
                <div className={styles.auditTime}>
                  {new Date(item.created_at).toLocaleString()}
                </div>
              </div>
            ))}
          </div>
        )}
      </Card>

      {/* Register / Edit Release Modal */}
      <Modal
        open={isReleaseModalOpen}
        onClose={() => setIsReleaseModalOpen(false)}
        title={editingRelease ? `Edit Release v${editingRelease.version}` : 'Register New Release'}
        description={`Configure version details and download URLs for ${
          currentApp === 'customer' ? 'Customer App' : 'Partner App'
        }.`}
        footer={
          <>
            <Button variant="ghost" onClick={() => setIsReleaseModalOpen(false)}>
              Cancel
            </Button>
            <Button
              variant="primary"
              loading={submittingRelease}
              onClick={handleSaveRelease}
            >
              {editingRelease ? 'Update Release' : 'Register Release'}
            </Button>
          </>
        }
      >
        <form onSubmit={handleSaveRelease} style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
          <div className={styles.formGrid}>
            <Field label="Version String" hint="e.g. 2.4.0">
              <input
                type="text"
                required
                className="control"
                placeholder="2.4.0"
                value={modalVersion}
                onChange={(e) => setModalVersion(e.target.value)}
              />
            </Field>

            <Field label="Numeric Build Number" hint="e.g. 42">
              <input
                type="number"
                min="1"
                required
                className="control"
                placeholder="42"
                value={modalBuildNumber}
                onChange={(e) => setModalBuildNumber(e.target.value)}
              />
            </Field>

            <Field label="Release Date">
              <input
                type="date"
                className="control"
                value={modalReleasedAt}
                onChange={(e) => setModalReleasedAt(e.target.value)}
              />
            </Field>

            <Field label="Release Status">
              <select
                className="control"
                value={modalStatus}
                onChange={(e) => setModalStatus(e.target.value as any)}
              >
                <option value="draft">Draft (Internal Testing)</option>
                <option value="published">Published (Available in Store)</option>
                <option value="retired">Retired (Deprecated)</option>
              </select>
            </Field>

            <div className={styles.fullCol}>
              <Field label="Android Store / APK URL (Optional)">
                <input
                  type="url"
                  className="control"
                  placeholder="https://play.google.com/store/apps/details?id=in.bookalook.app"
                  value={modalAndroidUrl}
                  onChange={(e) => setModalAndroidUrl(e.target.value)}
                />
              </Field>
            </div>

            <div className={styles.fullCol}>
              <Field label="iOS App Store URL (Optional)">
                <input
                  type="url"
                  className="control"
                  placeholder="https://apps.apple.com/app/bookalook/id123456789"
                  value={modalIosUrl}
                  onChange={(e) => setModalIosUrl(e.target.value)}
                />
              </Field>
            </div>

            <div className={styles.fullCol}>
              <Field label="Release Notes (Optional)">
                <textarea
                  rows={3}
                  className="control"
                  placeholder="Describe bug fixes, new features, or optimizations included in this build."
                  value={modalNotes}
                  onChange={(e) => setModalNotes(e.target.value)}
                />
              </Field>
            </div>
          </div>
        </form>
      </Modal>

      {confirmDialog}
    </div>
  );
}
