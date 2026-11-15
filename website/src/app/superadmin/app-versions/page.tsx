'use client';

import { FormEvent, ReactNode, useCallback, useEffect, useMemo, useState } from 'react';
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
  StatCard,
  cx,
  useConfirm,
} from '@/components/admin/ui';
import Icon, { type IconName } from '@/components/admin/Icon';
import styles from './page.module.css';

/* ------------------------------------------------------------------ types */

type AppId = 'customer' | 'partner';
type ReleaseStatus = 'draft' | 'published' | 'retired';

interface Release {
  id: string;
  app: AppId;
  version: string;
  build_number: number;
  released_at: string | null;
  release_notes: string | null;
  android_store_url: string | null;
  ios_store_url: string | null;
  status: ReleaseStatus;
  created_at: string;
}

interface Policy {
  latest_release_id: string | null;
  minimum_release_id: string | null;
  update_mode: 'optional' | 'mandatory';
  is_enforced: boolean;
  enforce_at: string | null;
  update_message: string | null;
  android_store_url: string | null;
  ios_store_url: string | null;
  resolved_android_url?: string | null;
  is_active?: boolean;
  updated_by?: string | null;
  updated_at?: string | null;
}

interface AuditItem {
  id: string;
  actor: string;
  label: string;
  created_at: string;
}

/**
 * The one decision the policy really encodes. The backend stores it as three
 * fields (is_enforced, update_mode, minimum_release_id); the apps and the API
 * middleware read them like this:
 *
 *  remind   — is_enforced off: anyone older than Latest gets a dismissible
 *             popup. Minimum and mode are ignored.
 *  minimum  — is_enforced on, optional: older than Minimum is blocked in the
 *             app and refused by the API; between Minimum and Latest gets
 *             the popup.
 *  everyone — is_enforced on, mandatory, Minimum = Latest: anyone not on
 *             Latest is blocked in the app and by the API.
 */
type Rule = 'remind' | 'minimum' | 'everyone';

const APP_LABEL: Record<AppId, string> = {
  customer: 'Customer App',
  partner: 'Partner App',
};

/** Android applicationId of each app; the Play listing URL is derived from it. */
const PLAY_PACKAGE: Record<AppId, string> = {
  customer: 'com.bookalook.customer_app',
  partner: 'com.bookalook.partner_app',
};
const playUrl = (app: AppId) => `https://play.google.com/store/apps/details?id=${PLAY_PACKAGE[app]}`;

const STATUS_META: Record<ReleaseStatus, { label: string; tone: 'success' | 'neutral' | 'danger'; hint: string }> = {
  published: {
    label: 'Live',
    tone: 'success',
    hint: 'Available to everyone on the store. Can be chosen as Latest.',
  },
  draft: {
    label: 'Testing',
    tone: 'neutral',
    hint: 'Only on internal testing. Not offered to users yet.',
  },
  retired: {
    label: 'Retired',
    tone: 'danger',
    hint: 'Pulled or replaced. Kept here for history.',
  },
};

/* ---------------------------------------------------------------- helpers */

function parseSemVer(v: string): [number, number, number] {
  const core = v.replace(/^v/i, '').trim().split(/[+-]/)[0] || '';
  const p = core.split('.').map((x) => parseInt(x, 10) || 0);
  return [p[0] || 0, p[1] || 0, p[2] || 0];
}

function compareReleases(a: Pick<Release, 'version' | 'build_number'>, b: Pick<Release, 'version' | 'build_number'>) {
  const [a1, a2, a3] = parseSemVer(a.version);
  const [b1, b2, b3] = parseSemVer(b.version);
  return a1 - b1 || a2 - b2 || a3 - b3 || (a.build_number || 0) - (b.build_number || 0);
}

const SEMVER_RE = /^\d+\.\d+\.\d+$/;

function bumpPatch(v: string) {
  const [a, b, c] = parseSemVer(v);
  return `${a}.${b}.${c + 1}`;
}

const fmtDate = (iso: string | null | undefined) =>
  iso
    ? new Date(iso).toLocaleDateString('en-IN', {
        day: 'numeric',
        month: 'short',
        year: 'numeric',
      })
    : '—';

const fmtDateTime = (iso: string | null | undefined) =>
  iso
    ? new Date(iso).toLocaleString('en-IN', {
        day: 'numeric',
        month: 'short',
        year: 'numeric',
        hour: 'numeric',
        minute: '2-digit',
      })
    : '—';

function timeAgo(iso: string) {
  const s = Math.round((Date.now() - new Date(iso).getTime()) / 1000);
  if (s < 60) return 'just now';
  const m = Math.round(s / 60);
  if (m < 60) return `${m} min ago`;
  const h = Math.round(m / 60);
  if (h < 24) return `${h} hr ago`;
  const d = Math.round(h / 24);
  if (d < 30) return `${d} day${d === 1 ? '' : 's'} ago`;
  return fmtDate(iso);
}

/** ISO → value for <input type="datetime-local"> in the admin's own timezone. */
function toLocalInput(iso: string | null) {
  if (!iso) return '';
  const d = new Date(iso);
  return new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
}

function cleanUrl(url: string) {
  const t = url.trim();
  if (!t) return null;
  return /^[a-z][a-z0-9+.-]*:\/\//i.test(t) ? t : `https://${t}`;
}

const isValidUrl = (url: string) => {
  try {
    new URL(cleanUrl(url) || '');
    return true;
  } catch {
    return false;
  }
};

function ruleOf(p: Policy | null): Rule {
  if (!p || !p.is_enforced) return 'remind';
  return p.update_mode === 'mandatory' ? 'everyone' : 'minimum';
}

const v = (r: Pick<Release, 'version'> | null | undefined) => (r ? `v${r.version}` : '—');

/* ------------------------------------------------------------- the page */

export default function AppVersionsPage() {
  const [app, setApp] = useState<AppId>('customer');
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(false);
  const [releases, setReleases] = useState<Release[]>([]);
  const [policies, setPolicies] = useState<Record<AppId, Policy | null>>({
    customer: null,
    partner: null,
  });
  const [audit, setAudit] = useState<AuditItem[]>([]);
  const [showAllAudit, setShowAllAudit] = useState(false);
  const [feedback, setFeedback] = useState<{
    tone: 'success' | 'error';
    message: string;
  } | null>(null);
  const [saving, setSaving] = useState(false);

  // Rule form
  const [latestId, setLatestId] = useState('');
  const [minimumId, setMinimumId] = useState('');
  const [rule, setRule] = useState<Rule>('remind');
  const [startLater, setStartLater] = useState(false);
  const [startAt, setStartAt] = useState('');
  const [message, setMessage] = useState('');
  const [androidUrl, setAndroidUrl] = useState('');
  const [iosUrl, setIosUrl] = useState('');
  const [rolloutConfirmed, setRolloutConfirmed] = useState(false);

  const [modalOpen, setModalOpen] = useState(false);
  const [editing, setEditing] = useState<Release | null>(null);

  const [confirm, confirmDialog] = useConfirm();

  const load = useCallback(async () => {
    try {
      const res = await fetch('/api/proxy/superadmin/app-versions', {
        cache: 'no-store',
      });
      const data = await res.json();
      if (!res.ok || !data.success) throw new Error(data.message);
      setReleases(data.releases || []);
      setPolicies(data.policies || { customer: null, partner: null });
      setAudit(data.audit_history || []);
      setLoadError(false);
    } catch {
      setLoadError(true);
    } finally {
      setLoading(false);
    }
  }, []);

  // Deferred a tick, as on the Policy Settings page, so the fetch's state
  // updates never run synchronously inside the effect.
  useEffect(() => {
    const timer = setTimeout(load, 0);
    return () => clearTimeout(timer);
  }, [load]);

  const retry = () => {
    setLoading(true);
    setLoadError(false);
    load();
  };

  const policy = policies[app];

  /** This app's releases, newest first. */
  const appReleases = useMemo(
    () => releases.filter((r) => r.app === app).sort((a, b) => compareReleases(b, a)),
    [releases, app],
  );
  const liveReleases = useMemo(() => appReleases.filter((r) => r.status === 'published'), [appReleases]);
  const byId = useCallback((id: string) => appReleases.find((r) => r.id === id) || null, [appReleases]);

  const savedLatest = policy?.latest_release_id ? byId(policy.latest_release_id) : null;
  const savedMinimum = policy?.minimum_release_id ? byId(policy.minimum_release_id) : null;

  /** Put the form back to what is saved. */
  const resetForm = useCallback(() => {
    const live = (id: string | null | undefined) => (id && liveReleases.some((r) => r.id === id) ? id : '');
    const latest = live(policy?.latest_release_id) || liveReleases[0]?.id || '';
    setLatestId(latest);
    setMinimumId(live(policy?.minimum_release_id) || latest);
    setRule(ruleOf(policy));
    setStartLater(Boolean(policy?.enforce_at));
    setStartAt(toLocalInput(policy?.enforce_at ?? null));
    setMessage(policy?.update_message || '');
    setAndroidUrl(policy?.android_store_url || '');
    setIosUrl(policy?.ios_store_url || '');
    setRolloutConfirmed(false);
  }, [policy, liveReleases]);

  // Re-seed the form when the app switches or a saved rule comes back from the
  // server — during render, not in an effect, so there is no flash of stale
  // values. New releases alone do not re-seed, so a just-recorded release can
  // be pre-selected as latest without being overwritten.
  const syncKey = loading ? '' : `${app}|${policy?.updated_at ?? 'none'}|${liveReleases.length > 0}`;
  const [syncedKey, setSyncedKey] = useState('');
  if (syncKey && syncKey !== syncedKey) {
    setSyncedKey(syncKey);
    resetForm();
  }

  const latest = byId(latestId);
  const minimum = rule === 'everyone' ? latest : rule === 'minimum' ? byId(minimumId) : null;

  /** What the form would save — compared with the saved policy for "dirty". */
  const payload = useMemo(
    () => ({
      latest_release_id: latestId,
      // Required by the API even when nothing is blocked; it is ignored then.
      minimum_release_id: rule === 'everyone' ? latestId : rule === 'minimum' ? minimumId : minimumId || latestId,
      update_mode: rule === 'everyone' ? 'mandatory' : 'optional',
      is_enforced: rule !== 'remind',
      enforce_at: rule !== 'remind' && startLater && startAt ? new Date(startAt).toISOString() : null,
      update_message: message.trim() || null,
      android_store_url: cleanUrl(androidUrl),
      ios_store_url: cleanUrl(iosUrl),
    }),
    [latestId, minimumId, rule, startLater, startAt, message, androidUrl, iosUrl],
  );

  const isDirty = useMemo(() => {
    if (!policy) return Boolean(latestId);
    const savedAt = policy.enforce_at ? new Date(policy.enforce_at).toISOString() : null;
    return (
      payload.latest_release_id !== (policy.latest_release_id || '') ||
      (rule !== 'remind' && payload.minimum_release_id !== (policy.minimum_release_id || '')) ||
      payload.update_mode !== policy.update_mode ||
      payload.is_enforced !== policy.is_enforced ||
      payload.enforce_at !== savedAt ||
      payload.update_message !== (policy.update_message || null) ||
      payload.android_store_url !== (policy.android_store_url || null) ||
      payload.ios_store_url !== (policy.ios_store_url || null)
    );
  }, [payload, policy, rule, latestId]);

  // Leaving the page with unsaved rule changes loses them silently otherwise.
  useEffect(() => {
    if (!isDirty) return;
    const warn = (e: BeforeUnloadEvent) => e.preventDefault();
    window.addEventListener('beforeunload', warn);
    return () => window.removeEventListener('beforeunload', warn);
  }, [isDirty]);

  /* ---- validation (shown inline, also gates Save) */

  const blocks = rule !== 'remind';
  const errors: Partial<Record<'latest' | 'minimum' | 'startAt' | 'android' | 'ios' | 'rollout', string>> = {};
  if (!latestId) errors.latest = 'Choose the newest version that is live on the store.';
  if (rule === 'minimum' && !minimumId) errors.minimum = 'Choose the oldest version people may keep using.';
  if (rule === 'minimum' && latest && minimum && compareReleases(minimum, latest) > 0)
    errors.minimum = 'This cannot be newer than the latest version.';
  if (blocks && startLater && !startAt) errors.startAt = 'Pick when blocking should start.';
  else if (blocks && startLater && new Date(startAt) <= new Date()) errors.startAt = 'This time has already passed.';
  if (androidUrl.trim() && !isValidUrl(androidUrl)) errors.android = 'This is not a valid link.';
  if (iosUrl.trim() && !isValidUrl(iosUrl)) errors.ios = 'This is not a valid link.';
  if (blocks && isDirty && !rolloutConfirmed) errors.rollout = 'Confirm the rollout before blocking anyone.';
  const canSave = isDirty && Object.keys(errors).length === 0;

  const effectiveAndroid = cleanUrl(androidUrl) || latest?.android_store_url || null;
  const androidMismatch =
    effectiveAndroid &&
    /play\.google\.com/.test(effectiveAndroid) &&
    !effectiveAndroid.includes(`id=${PLAY_PACKAGE[app]}`);

  /* ---- actions */

  const switchApp = async (next: AppId) => {
    if (next === app) return;
    if (
      isDirty &&
      !(await confirm({
        title: 'Discard unsaved changes?',
        body: `Your changes to the ${APP_LABEL[app]} update rule have not been saved.`,
        confirmLabel: 'Discard changes',
        tone: 'danger',
      }))
    )
      return;
    setFeedback(null);
    setApp(next);
  };

  const save = async () => {
    if (!canSave || !latest) return;
    const when = payload.enforce_at ? `From ${fmtDateTime(payload.enforce_at)}` : 'As soon as you save';
    const summary =
      rule === 'remind'
        ? `People older than ${v(latest)} will see a reminder they can dismiss. Nobody is blocked.`
        : rule === 'minimum'
          ? `${when}, people older than ${v(minimum)} cannot use the app until they update. Others older than ${v(
              latest,
            )} get a reminder.`
          : `${when}, everyone not on ${v(latest)} cannot use the app until they update.`;
    const ok = await confirm({
      title: `Save update rule for the ${APP_LABEL[app]}?`,
      body: summary,
      confirmLabel: blocks ? 'Save and start blocking' : 'Save rule',
      tone: blocks ? 'danger' : 'accent',
    });
    if (!ok) return;

    setSaving(true);
    setFeedback(null);
    try {
      const res = await fetch(`/api/proxy/superadmin/app-versions/policies/${app}`, {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
          Accept: 'application/json',
        },
        body: JSON.stringify(payload),
      });
      const data = await res.json();
      if (!res.ok || !data.success) throw new Error(firstError(data) || 'Could not save the update rule.');
      setFeedback({
        tone: 'success',
        message: `${APP_LABEL[app]} update rule saved. Apps pick it up within a few minutes.`,
      });
      await load();
    } catch (e) {
      setFeedback({
        tone: 'error',
        message: e instanceof Error ? e.message : 'Could not save the update rule.',
      });
    } finally {
      setSaving(false);
    }
  };

  const openNewRelease = () => {
    setEditing(null);
    setModalOpen(true);
  };

  /* ---- render */

  return (
    <div className={styles.page}>
      <PageHeader
        eyebrow="Platform"
        title="App Versions"
        subtitle="Record each app release and decide what people on older versions see: a reminder, or a block until they update."
        actions={
          <Button variant="primary" icon="plus" onClick={openNewRelease} disabled={loading || loadError}>
            New release
          </Button>
        }
      />

      <div className={styles.switchRow}>
        <Segmented
          ariaLabel="Choose app"
          value={app}
          onChange={switchApp}
          options={(['customer', 'partner'] as AppId[]).map((id) => ({
            value: id,
            label: (
              <span className={styles.segLabel}>
                {APP_LABEL[id]}
                {!loading && <RuleDot rule={ruleOf(policies[id])} active={policies[id]?.is_active} />}
              </span>
            ),
          }))}
        />
        {policy?.updated_at && (
          <span className={styles.metaNote}>
            Rule last changed {timeAgo(policy.updated_at)}
            {policy.updated_by ? ` by ${policy.updated_by}` : ''}
          </span>
        )}
      </div>

      {feedback && (
        <Alert tone={feedback.tone} onClose={() => setFeedback(null)}>
          {feedback.message}
        </Alert>
      )}

      {loadError ? (
        <Card padded>
          <EmptyState
            icon="alert"
            title="Could not load app versions"
            hint="The server did not respond. Check your connection and try again."
            action={
              <Button icon="refresh" onClick={retry}>
                Try again
              </Button>
            }
          />
        </Card>
      ) : (
        <>
          {/* ---------- current state at a glance */}
          <div className={styles.stats}>
            <StatCard
              loading={loading}
              label="Latest version"
              icon="smartphone"
              value={savedLatest ? v(savedLatest) : 'Not set'}
              sub={
                savedLatest
                  ? `Build ${savedLatest.build_number} · ${fmtDate(savedLatest.released_at)}`
                  : 'Register your first release'
              }
            />
            <StatCard
              loading={loading}
              label="What older versions see"
              icon={ruleOf(policy) === 'remind' ? 'bell' : 'alert'}
              tone={ruleOf(policy) === 'remind' ? 'info' : policy?.is_active ? 'danger' : 'warning'}
              value={
                !policy
                  ? 'Nothing yet'
                  : ruleOf(policy) === 'remind'
                    ? 'Reminder'
                    : policy.is_active
                      ? 'Blocked'
                      : 'Block scheduled'
              }
              sub={
                !policy
                  ? 'No rule saved'
                  : ruleOf(policy) === 'remind'
                    ? 'Nobody is blocked'
                    : !policy.is_active && policy.enforce_at
                      ? `Starts ${fmtDateTime(policy.enforce_at)}`
                      : `Below ${v(savedMinimum)} must update`
              }
            />
            <StatCard
              loading={loading}
              label="Play Store link"
              icon="external"
              tone={policy?.resolved_android_url ? 'success' : 'warning'}
              value={policy?.resolved_android_url ? 'Set' : 'Missing'}
              sub={
                policy?.resolved_android_url ? (
                  <a href={policy.resolved_android_url} target="_blank" rel="noreferrer" className={styles.statLink}>
                    Open listing
                  </a>
                ) : (
                  'The Update button has nowhere to go'
                )
              }
            />
          </div>

          {loading ? (
            <Card padded>
              <Skeleton height={320} />
            </Card>
          ) : liveReleases.length === 0 ? (
            <Card padded>
              <EmptyState
                icon="smartphone"
                title={`No live ${APP_LABEL[app]} release yet`}
                hint="Record the version that is on the Play Store (for example 1.0.0, build 1) and mark it Live. Then you can set the update rule."
                action={
                  <Button variant="primary" icon="plus" onClick={openNewRelease}>
                    Record a release
                  </Button>
                }
              />
            </Card>
          ) : (
            <div className={styles.grid}>
              {/* ---------- the rule */}
              <Card title="Update rule" subtitle={`What ${APP_LABEL[app]} users on older versions experience.`}>
                <div className={styles.form}>
                  <section className={styles.step}>
                    <StepHead
                      n={1}
                      title="Latest version"
                      hint="The newest version that is live on the Play Store for everyone."
                    />
                    <Field label="Version" hint={errors.latest}>
                      <select className="control" value={latestId} onChange={(e) => setLatestId(e.target.value)}>
                        {liveReleases.map((r, i) => (
                          <option key={r.id} value={r.id}>
                            {v(r)} · build {r.build_number}
                            {i === 0 ? ' · newest' : ''}
                          </option>
                        ))}
                      </select>
                    </Field>
                    {liveReleases[0] && latestId && liveReleases[0].id !== latestId && (
                      <button
                        type="button"
                        className={styles.inlineNudge}
                        onClick={() => setLatestId(liveReleases[0].id)}
                      >
                        <Icon name="arrowUp" size={14} /> {v(liveReleases[0])} is newer — use it
                      </button>
                    )}
                  </section>

                  <section className={styles.step}>
                    <StepHead
                      n={2}
                      title="People on older versions"
                      hint="Only block when you must: a security or payment bug, or a backend change old versions cannot handle."
                    />
                    <div className={styles.choices} role="radiogroup" aria-label="What people on older versions see">
                      <Choice
                        checked={rule === 'remind'}
                        onSelect={() => setRule('remind')}
                        icon="bell"
                        tone="info"
                        title="Remind them"
                        body={`A “New version available” popup they can dismiss. Nobody is blocked.`}
                        tag="Recommended"
                      />
                      <Choice
                        checked={rule === 'minimum'}
                        onSelect={() => setRule('minimum')}
                        icon="alert"
                        tone="warning"
                        title="Block very old versions"
                        body="Versions older than the one you choose stop working until updated. Everyone else gets the reminder."
                      />
                      <Choice
                        checked={rule === 'everyone'}
                        onSelect={() => setRule('everyone')}
                        icon="userX"
                        tone="danger"
                        title="Everyone must update"
                        body={`Anyone not on ${v(latest)} sees a full-screen update screen and cannot use the app.`}
                      />
                    </div>

                    {rule === 'minimum' && (
                      <Field
                        label="Oldest version still allowed"
                        hint={errors.minimum || 'Anything older than this is blocked.'}
                        className={errors.minimum ? styles.fieldError : undefined}
                      >
                        <select className="control" value={minimumId} onChange={(e) => setMinimumId(e.target.value)}>
                          {liveReleases
                            .filter((r) => !latest || compareReleases(r, latest) <= 0)
                            .map((r) => (
                              <option key={r.id} value={r.id}>
                                {v(r)} · build {r.build_number}
                                {r.id === latestId ? ' · same as latest' : ''}
                              </option>
                            ))}
                        </select>
                      </Field>
                    )}

                    {blocks && (
                      <div className={styles.blockOptions}>
                        <div className={styles.startChoice} role="radiogroup" aria-label="When blocking starts">
                          <span className={styles.subLabel}>Start blocking</span>
                          <Segmented
                            ariaLabel="When blocking starts"
                            value={startLater ? 'later' : 'now'}
                            onChange={(val) => setStartLater(val === 'later')}
                            options={[
                              { value: 'now', label: 'As soon as I save' },
                              { value: 'later', label: 'At a set time' },
                            ]}
                          />
                        </div>
                        {startLater && (
                          <Field
                            label="Blocking starts at"
                            hint={
                              errors.startAt || 'Until then, everyone gets the reminder. 2–3 days of warning is kind.'
                            }
                            className={errors.startAt ? styles.fieldError : undefined}
                          >
                            <input
                              type="datetime-local"
                              className="control"
                              value={startAt}
                              onChange={(e) => setStartAt(e.target.value)}
                            />
                          </Field>
                        )}
                        {isDirty && (
                          <label className={cx(styles.rolloutCheck, errors.rollout && styles.rolloutCheckOpen)}>
                            <input
                              type="checkbox"
                              checked={rolloutConfirmed}
                              onChange={(e) => setRolloutConfirmed(e.target.checked)}
                            />
                            <span>
                              <strong>{v(latest)} is live for 100% of users on Google Play.</strong>
                              <span className={styles.rolloutHint}>
                                If the staged rollout has not finished, blocked people tap Update and Play has nothing
                                to give them — they are locked out.
                              </span>
                            </span>
                          </label>
                        )}
                      </div>
                    )}
                  </section>

                  <section className={styles.step}>
                    <StepHead n={3} title="Message and store links" hint="Shown on the update popup and screen." />
                    <Field
                      label="Message to users (optional)"
                      hint={`${message.length}/200 · Leave blank for the default wording.`}
                    >
                      <textarea
                        rows={2}
                        maxLength={200}
                        className="control"
                        placeholder="A new version with faster booking and important fixes is ready."
                        value={message}
                        onChange={(e) => setMessage(e.target.value)}
                      />
                    </Field>
                    <Field
                      label="Play Store link"
                      className={errors.android ? styles.fieldError : undefined}
                      hint={
                        errors.android ||
                        (androidMismatch
                          ? `This link is not for ${PLAY_PACKAGE[app]} — the ${APP_LABEL[app]}'s package.`
                          : !androidUrl && latest?.android_store_url
                            ? `Blank uses the link saved on ${v(latest)}.`
                            : 'Where the Update button sends Android users.')
                      }
                    >
                      <div className={styles.inputWithAction}>
                        <input
                          type="url"
                          className="control"
                          placeholder={playUrl(app)}
                          value={androidUrl}
                          onChange={(e) => setAndroidUrl(e.target.value)}
                        />
                        {androidUrl !== playUrl(app) && (
                          <Button size="sm" variant="secondary" onClick={() => setAndroidUrl(playUrl(app))}>
                            Use {APP_LABEL[app]} link
                          </Button>
                        )}
                      </div>
                    </Field>
                    <Field
                      label="App Store link (iPhone)"
                      className={errors.ios ? styles.fieldError : undefined}
                      hint={errors.ios || 'Leave blank until the iPhone app is published.'}
                    >
                      <input
                        type="url"
                        className="control"
                        placeholder="https://apps.apple.com/in/app/…"
                        value={iosUrl}
                        onChange={(e) => setIosUrl(e.target.value)}
                      />
                    </Field>
                  </section>
                </div>

                <div className={cx(styles.saveBar, isDirty && styles.saveBarDirty)}>
                  <span className={styles.saveState}>
                    {isDirty ? (
                      <>
                        <span className={styles.dirtyDot} /> Unsaved changes
                      </>
                    ) : (
                      <>
                        <Icon name="checkCircle" size={15} /> Saved
                      </>
                    )}
                  </span>
                  <div className={styles.saveActions}>
                    {isDirty && (
                      <Button variant="ghost" onClick={resetForm} disabled={saving}>
                        Discard
                      </Button>
                    )}
                    <Button variant={blocks ? 'danger' : 'primary'} loading={saving} disabled={!canSave} onClick={save}>
                      {blocks ? 'Save and block' : 'Save rule'}
                    </Button>
                  </div>
                </div>
              </Card>

              {/* ---------- consequences + how-to */}
              <div className={styles.side}>
                <Card
                  title="Who sees what"
                  subtitle={isDirty ? 'Preview of your unsaved changes.' : 'With the rule as saved.'}
                  padded
                >
                  <ImpactPreview
                    rule={rule}
                    latest={latest}
                    minimum={minimum}
                    startsAt={blocks && startLater && startAt ? new Date(startAt).toISOString() : null}
                  />
                </Card>

                <Card title="Releasing a new version" padded>
                  <ol className={styles.checklist}>
                    <li>
                      Bump <code>version</code> in <code>pubspec.yaml</code> — the build number after <code>+</code>{' '}
                      must go up every upload.
                    </li>
                    <li>Upload to Play internal testing and check it on a phone.</li>
                    <li>Promote to production as a staged rollout: 10% → 50% → 100%.</li>
                    <li>
                      At 100%, click <strong>New release</strong> here, mark it Live, and choose it as the latest
                      version.
                    </li>
                    <li>Block older versions only if you have to, ideally with a few days’ notice.</li>
                  </ol>
                </Card>
              </div>
            </div>
          )}

          {/* ---------- releases */}
          {!loading && appReleases.length > 0 && (
            <Card
              title="Releases"
              subtitle={`${appReleases.length} recorded · ${liveReleases.length} live`}
              actions={
                <Button size="sm" icon="plus" onClick={openNewRelease}>
                  New release
                </Button>
              }
            >
              <div className={styles.tableWrap}>
                <table className={styles.table}>
                  <thead>
                    <tr>
                      <th>Version</th>
                      <th>Status</th>
                      <th>Released</th>
                      <th>What’s new</th>
                      <th aria-label="Actions" />
                    </tr>
                  </thead>
                  <tbody>
                    {appReleases.map((r) => {
                      const isLatest = savedLatest?.id === r.id;
                      const isMin = ruleOf(policy) === 'minimum' && savedMinimum?.id === r.id;
                      return (
                        <tr key={r.id} className={r.status === 'retired' ? styles.rowMuted : undefined}>
                          <td>
                            <div className={styles.versionCell}>
                              <span className={styles.version}>{v(r)}</span>
                              <span className={styles.build}>build {r.build_number}</span>
                            </div>
                            {(isLatest || isMin) && (
                              <div className={styles.rowBadges}>
                                {isLatest && <Badge tone="accent">Latest</Badge>}
                                {isMin && <Badge tone="warning">Oldest allowed</Badge>}
                              </div>
                            )}
                          </td>
                          <td>
                            <Badge tone={STATUS_META[r.status].tone}>{STATUS_META[r.status].label}</Badge>
                          </td>
                          <td className={styles.nowrap}>{fmtDate(r.released_at)}</td>
                          <td className={styles.notesCell}>
                            {r.release_notes ? (
                              <span title={r.release_notes}>{r.release_notes}</span>
                            ) : (
                              <span className={styles.muted}>—</span>
                            )}
                          </td>
                          <td className={styles.actionsCell}>
                            {r.status === 'published' && latestId !== r.id && compareReleases(r, latest || r) > 0 && (
                              <Button
                                size="sm"
                                variant="secondary"
                                onClick={() => {
                                  setLatestId(r.id);
                                  window.scrollTo({
                                    top: 0,
                                    behavior: 'smooth',
                                  });
                                }}
                              >
                                Make latest
                              </Button>
                            )}
                            <Button
                              size="sm"
                              variant="ghost"
                              icon="edit"
                              onClick={() => {
                                setEditing(r);
                                setModalOpen(true);
                              }}
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
            </Card>
          )}

          {/* ---------- history */}
          {!loading && audit.length > 0 && (
            <Card title="Activity" subtitle="Changes to releases and update rules, newest first." padded>
              <ul className={styles.timeline}>
                {(showAllAudit ? audit : audit.slice(0, 6)).map((item) => (
                  <li key={item.id} className={styles.timelineItem}>
                    <span className={styles.timelineDot} />
                    <div className={styles.timelineBody}>
                      <span className={styles.timelineText}>{item.label}</span>
                      <span className={styles.timelineMeta} title={fmtDateTime(item.created_at)}>
                        {item.actor} · {timeAgo(item.created_at)}
                      </span>
                    </div>
                  </li>
                ))}
              </ul>
              {audit.length > 6 && (
                <Button variant="ghost" size="sm" onClick={() => setShowAllAudit((s) => !s)}>
                  {showAllAudit ? 'Show less' : `Show all ${audit.length}`}
                </Button>
              )}
            </Card>
          )}
        </>
      )}

      {modalOpen && (
        <ReleaseModal
          key={editing?.id ?? 'new'}
          app={app}
          editing={editing}
          releases={appReleases}
          onClose={() => setModalOpen(false)}
          onSaved={async (msg, savedRelease) => {
            setModalOpen(false);
            setFeedback({ tone: 'success', message: msg });
            await load();
            // A newer live release is almost always the next "latest" — offer it
            // in the form rather than making the admin hunt for it.
            if (
              savedRelease &&
              savedRelease.status === 'published' &&
              (!latest || compareReleases(savedRelease, latest) > 0)
            ) {
              setLatestId(savedRelease.id);
            }
          }}
        />
      )}

      {confirmDialog}
    </div>
  );
}

/* ------------------------------------------------------------ pieces */

function firstError(data: { message?: string; errors?: Record<string, string[]> }) {
  const fieldErr = data.errors && Object.values(data.errors)[0]?.[0];
  return fieldErr || data.message;
}

function RuleDot({ rule, active }: { rule: Rule; active?: boolean }) {
  const cls = rule === 'remind' ? styles.dotInfo : active ? styles.dotDanger : styles.dotWarning;
  const label = rule === 'remind' ? 'Reminder only' : active ? 'Blocking older versions' : 'Blocking scheduled';
  return <span className={cx(styles.ruleDot, cls)} title={label} aria-label={label} />;
}

function StepHead({ n, title, hint }: { n: number; title: string; hint: string }) {
  return (
    <div className={styles.stepHead}>
      <span className={styles.stepNum}>{n}</span>
      <div>
        <div className={styles.stepTitle}>{title}</div>
        <div className={styles.stepHint}>{hint}</div>
      </div>
    </div>
  );
}

function Choice({
  checked,
  onSelect,
  icon,
  tone,
  title,
  body,
  tag,
}: {
  checked: boolean;
  onSelect: () => void;
  icon: IconName;
  tone: 'info' | 'warning' | 'danger';
  title: string;
  body: string;
  tag?: string;
}) {
  return (
    <label className={cx(styles.choice, checked && styles.choiceOn, checked && styles[`choice_${tone}`])}>
      <input type="radio" name="update-rule" checked={checked} onChange={onSelect} className={styles.srOnly} />
      <span className={cx(styles.choiceIcon, styles[`tone_${tone}`])}>
        <Icon name={icon} size={18} />
      </span>
      <span className={styles.choiceText}>
        <span className={styles.choiceTitle}>
          {title}
          {tag && <span className={styles.choiceTag}>{tag}</span>}
        </span>
        <span className={styles.choiceBody}>{body}</span>
      </span>
      <span className={styles.choiceRadio} aria-hidden />
    </label>
  );
}

function ImpactPreview({
  rule,
  latest,
  minimum,
  startsAt,
}: {
  rule: Rule;
  latest: Release | null;
  minimum: Release | null;
  startsAt: string | null;
}) {
  if (!latest) return <p className={styles.muted}>Choose a latest version to see the effect.</p>;

  const rows: {
    who: ReactNode;
    sees: string;
    tone: 'success' | 'info' | 'danger';
  }[] = [{ who: <>On {v(latest)}</>, sees: 'Nothing — up to date', tone: 'success' }];
  if (rule === 'remind') {
    rows.push({
      who: <>Older than {v(latest)}</>,
      sees: 'Reminder popup, can dismiss',
      tone: 'info',
    });
  } else if (rule === 'everyone' || (minimum && minimum.id === latest.id)) {
    rows.push({
      who: <>Older than {v(latest)}</>,
      sees: 'Blocked until they update',
      tone: 'danger',
    });
  } else if (minimum) {
    rows.push({
      who: (
        <>
          {v(minimum)} up to {v(latest)}
        </>
      ),
      sees: 'Reminder popup, can dismiss',
      tone: 'info',
    });
    rows.push({
      who: <>Older than {v(minimum)}</>,
      sees: 'Blocked until they update',
      tone: 'danger',
    });
  }

  return (
    <div className={styles.impact}>
      {rows.map((r, i) => (
        <div key={i} className={styles.impactRow}>
          <span className={styles.impactWho}>{r.who}</span>
          <Badge tone={r.tone}>{r.sees}</Badge>
        </div>
      ))}
      {rule !== 'remind' && (
        <p className={styles.impactNote}>
          <Icon name="info" size={14} />
          {startsAt
            ? `Blocking starts ${fmtDateTime(startsAt)}. Until then everyone gets the reminder.`
            : 'Blocked phones also have their requests refused by the server, so an old app cannot keep booking.'}
        </p>
      )}
    </div>
  );
}

/* ------------------------------------------------------- release modal */

function ReleaseModal({
  app,
  editing,
  releases,
  onClose,
  onSaved,
}: {
  app: AppId;
  editing: Release | null;
  releases: Release[];
  onClose: () => void;
  onSaved: (message: string, release: Release | null) => void | Promise<void>;
}) {
  const others = useMemo(() => releases.filter((r) => r.id !== editing?.id), [releases, editing]);
  const highestBuild = others.reduce((m, r) => Math.max(m, r.build_number), 0);
  const newest = others[0] || null;

  // Seeded once per mount (the parent keys this by release). For a new
  // release, suggest the next patch and build — the usual case.
  const [version, setVersion] = useState(() => editing?.version ?? (newest ? bumpPatch(newest.version) : '1.0.0'));
  const [build, setBuild] = useState(() => String(editing?.build_number ?? highestBuild + 1));
  const [status, setStatus] = useState<ReleaseStatus>(() => editing?.status ?? 'published');
  const [releasedAt, setReleasedAt] = useState(() =>
    editing ? (editing.released_at ? editing.released_at.slice(0, 10) : '') : new Date().toISOString().slice(0, 10),
  );
  const [notes, setNotes] = useState(() => editing?.release_notes ?? '');
  const [androidUrl, setAndroidUrl] = useState(() => editing?.android_store_url ?? '');
  const [iosUrl, setIosUrl] = useState(() => editing?.ios_store_url ?? '');
  const [showLinks, setShowLinks] = useState(() => Boolean(editing?.android_store_url || editing?.ios_store_url));
  const [submitting, setSubmitting] = useState(false);
  const [serverError, setServerError] = useState<string | null>(null);
  const [touched, setTouched] = useState(false);

  const cleanVersion = version.trim().replace(/^v/i, '');
  const buildNum = parseInt(build, 10);
  const errors: Partial<Record<'version' | 'build' | 'android' | 'ios', string>> = {};
  if (!SEMVER_RE.test(cleanVersion)) errors.version = 'Use three numbers, like 1.0.1.';
  if (!Number.isInteger(buildNum) || buildNum < 1) errors.build = 'A whole number, 1 or more.';
  else if (others.some((r) => r.version === cleanVersion && r.build_number === buildNum))
    errors.build = `v${cleanVersion} build ${buildNum} is already recorded.`;
  if (androidUrl.trim() && !isValidUrl(androidUrl)) errors.android = 'This is not a valid link.';
  if (iosUrl.trim() && !isValidUrl(iosUrl)) errors.ios = 'This is not a valid link.';
  const buildWarning =
    !editing && !errors.build && buildNum <= highestBuild
      ? `Play only accepts a build higher than ${highestBuild}, the highest recorded so far.`
      : null;
  const valid = Object.keys(errors).length === 0;

  const submit = async (e?: FormEvent) => {
    e?.preventDefault();
    setTouched(true);
    if (!valid) return;
    setSubmitting(true);
    setServerError(null);
    try {
      const body = {
        app,
        version: cleanVersion,
        build_number: buildNum,
        released_at: releasedAt ? new Date(releasedAt).toISOString() : null,
        status,
        android_store_url: cleanUrl(androidUrl),
        ios_store_url: cleanUrl(iosUrl),
        release_notes: notes.trim() || null,
      };
      const res = await fetch(
        editing
          ? `/api/proxy/superadmin/app-versions/releases/${editing.id}`
          : '/api/proxy/superadmin/app-versions/releases',
        {
          method: editing ? 'PUT' : 'POST',
          headers: {
            'Content-Type': 'application/json',
            Accept: 'application/json',
          },
          body: JSON.stringify(body),
        },
      );
      const data = await res.json();
      if (!res.ok || !data.success) throw new Error(firstError(data) || 'Could not save the release.');
      await onSaved(
        editing ? `v${cleanVersion} updated.` : `v${cleanVersion} (build ${buildNum}) recorded.`,
        (data.release as Release) || null,
      );
    } catch (err) {
      setServerError(err instanceof Error ? err.message : 'Could not save the release.');
    } finally {
      setSubmitting(false);
    }
  };

  const show = (k: keyof typeof errors) => (touched || k === 'build' ? errors[k] : undefined);

  return (
    <Modal
      open
      onClose={onClose}
      title={editing ? `Edit v${editing.version}` : `New ${APP_LABEL[app]} release`}
      description={editing ? APP_LABEL[app] : 'Record a version after it is uploaded to the Play Store.'}
      footer={
        <>
          <Button variant="ghost" onClick={onClose}>
            Cancel
          </Button>
          <Button variant="primary" type="submit" form="release-form" loading={submitting}>
            {editing ? 'Save changes' : 'Record release'}
          </Button>
        </>
      }
    >
      <form id="release-form" onSubmit={submit} className={styles.modalForm} noValidate>
        {serverError && <Alert tone="error">{serverError}</Alert>}

        <div className={styles.twoCol}>
          <Field
            label="Version"
            hint={show('version') || 'Three numbers, like 1.0.1'}
            className={show('version') ? styles.fieldError : undefined}
          >
            <input
              className="control"
              inputMode="decimal"
              value={version}
              onChange={(e) => setVersion(e.target.value)}
              onBlur={() => setTouched(true)}
              placeholder="1.0.1"
              autoFocus
            />
          </Field>
          <Field
            label="Build number"
            hint={show('build') || buildWarning || `Highest so far: ${highestBuild || 'none'}`}
            className={show('build') ? styles.fieldError : buildWarning ? styles.fieldWarn : undefined}
          >
            <input
              className="control"
              type="number"
              min={1}
              value={build}
              onChange={(e) => setBuild(e.target.value)}
              placeholder="2"
            />
          </Field>
        </div>

        {SEMVER_RE.test(cleanVersion) && Number.isInteger(buildNum) && buildNum > 0 && (
          <div className={styles.pubspec}>
            <span>
              Must match the app’s <code>pubspec.yaml</code>:
            </span>
            <code className={styles.pubspecLine}>
              version: {cleanVersion}+{buildNum}
            </code>
          </div>
        )}

        <fieldset className={styles.statusSet}>
          <legend className={styles.subLabel}>Status</legend>
          <div className={styles.statusOptions}>
            {(['published', 'draft', 'retired'] as ReleaseStatus[]).map((s) => (
              <label key={s} className={cx(styles.statusOption, status === s && styles.statusOptionOn)}>
                <input
                  type="radio"
                  name="release-status"
                  checked={status === s}
                  onChange={() => setStatus(s)}
                  className={styles.srOnly}
                />
                <Badge tone={STATUS_META[s].tone}>{STATUS_META[s].label}</Badge>
                <span className={styles.statusHint}>{STATUS_META[s].hint}</span>
              </label>
            ))}
          </div>
        </fieldset>

        <div className={styles.twoCol}>
          <Field label="Release date">
            <input type="date" className="control" value={releasedAt} onChange={(e) => setReleasedAt(e.target.value)} />
          </Field>
        </div>

        <Field label="What’s new (optional)" hint="Shown to users on the update popup and screen. Keep it short.">
          <textarea
            rows={3}
            className="control"
            placeholder="Faster booking, clearer refund status, bug fixes."
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
          />
        </Field>

        <button
          type="button"
          className={styles.disclosure}
          onClick={() => setShowLinks((s) => !s)}
          aria-expanded={showLinks}
        >
          <Icon name={showLinks ? 'chevronDown' : 'chevronRight'} size={14} />
          Store links for this release only
          <span className={styles.muted}> — usually not needed</span>
        </button>
        {showLinks && (
          <div className={styles.linkFields}>
            <p className={styles.muted}>
              Used only if the update rule has no store link of its own. Normally set the link once on the rule instead.
            </p>
            <Field
              label="Play Store link"
              hint={show('android')}
              className={show('android') ? styles.fieldError : undefined}
            >
              <input
                type="url"
                className="control"
                placeholder={playUrl(app)}
                value={androidUrl}
                onChange={(e) => setAndroidUrl(e.target.value)}
              />
            </Field>
            <Field label="App Store link" hint={show('ios')} className={show('ios') ? styles.fieldError : undefined}>
              <input
                type="url"
                className="control"
                placeholder="https://apps.apple.com/in/app/…"
                value={iosUrl}
                onChange={(e) => setIosUrl(e.target.value)}
              />
            </Field>
          </div>
        )}
      </form>
    </Modal>
  );
}
