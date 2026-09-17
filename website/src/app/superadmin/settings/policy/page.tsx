'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import styles from './page.module.css';

/**
 * Platform policy.
 *
 * Every field on this page is a rule the whole platform obeys, so the page is
 * built around one idea: you should always be able to see what you are about to
 * change before you change it, and nothing should move under your fingers while
 * you type.
 *
 * The old duration control broke that second rule badly. It derived its own
 * display back out of the parent on every keystroke, so typing "60" into a
 * Minutes box silently became "1 Hours" mid-word, "1440" became "1 Days", and
 * clearing the field refilled it with "0" before you could type anything.
 * Durations are now held as the raw text and unit the user actually chose, and
 * converted to minutes only when saving — so the box says what was typed into
 * it, always.
 */

const MINUTES_IN_HOUR = 60;
const MINUTES_IN_DAY = 1440;

type Unit = 'minutes' | 'hours' | 'days';

interface Duration {
  value: string;
  unit: Unit;
}

/** Splits stored minutes into the largest whole unit, for first display only. */
function toDuration(minutes: number): Duration {
  if (minutes > 0 && minutes % MINUTES_IN_DAY === 0) {
    return { value: String(minutes / MINUTES_IN_DAY), unit: 'days' };
  }
  if (minutes > 0 && minutes % MINUTES_IN_HOUR === 0) {
    return { value: String(minutes / MINUTES_IN_HOUR), unit: 'hours' };
  }
  return { value: String(minutes), unit: 'minutes' };
}

function toMinutes({ value, unit }: Duration): number {
  const num = parseInt(value, 10);
  if (Number.isNaN(num)) return 0;
  if (unit === 'days') return num * MINUTES_IN_DAY;
  if (unit === 'hours') return num * MINUTES_IN_HOUR;
  return num;
}

/** "1 hour 30 minutes" — so the stored value is readable whatever unit is shown. */
function describeMinutes(minutes: number): string {
  if (!Number.isFinite(minutes) || minutes < 0) return '';
  if (minutes === 0) return 'immediately — no cutoff';

  const days = Math.floor(minutes / MINUTES_IN_DAY);
  const hours = Math.floor((minutes % MINUTES_IN_DAY) / MINUTES_IN_HOUR);
  const mins = minutes % MINUTES_IN_HOUR;

  const parts = [
    days ? `${days} day${days === 1 ? '' : 's'}` : '',
    hours ? `${hours} hour${hours === 1 ? '' : 's'}` : '',
    mins ? `${mins} minute${mins === 1 ? '' : 's'}` : '',
  ].filter(Boolean);

  return parts.join(' ');
}

function hourLabel(hour: number): string {
  if (hour === 0) return '12 midnight';
  if (hour === 12) return '12 noon';
  return hour < 12 ? `${hour} am` : `${hour - 12} pm`;
}

// --------------------------------------------------------------------- fields

function Field({
  label,
  hint,
  error,
  children,
}: {
  label: string;
  hint?: React.ReactNode;
  error?: string;
  children: React.ReactNode;
}) {
  return (
    <div className={styles.field}>
      <label className={styles.label}>{label}</label>
      {children}
      {error ? (
        <p className={styles.error}>{error}</p>
      ) : hint ? (
        <p className={styles.hint}>{hint}</p>
      ) : null}
    </div>
  );
}

/**
 * A number and a unit, and nothing clever.
 *
 * Fully controlled by the parent on the exact text and unit chosen. There is no
 * effect and no derived state, which is what stops the box rewriting itself
 * while it is being typed into.
 */
function DurationField({
  label,
  hint,
  duration,
  onChange,
  error,
}: {
  label: string;
  hint: string;
  duration: Duration;
  onChange: (next: Duration) => void;
  error?: string;
}) {
  const minutes = toMinutes(duration);
  const readable = describeMinutes(minutes);

  return (
    <Field
      label={label}
      error={error}
      hint={
        <>
          {hint}
          {!error && duration.value.trim() !== '' && (
            <>
              {' '}
              <span className={styles.resolved}>Currently {readable}.</span>
            </>
          )}
        </>
      }
    >
      <div className={styles.durationRow}>
        <input
          className={`${styles.input} ${error ? styles.inputError : ''}`}
          type="number"
          min="0"
          inputMode="numeric"
          value={duration.value}
          onChange={(e) => onChange({ ...duration, value: e.target.value })}
        />
        <select
          className={styles.select}
          value={duration.unit}
          // Changing the unit reinterprets the number rather than converting
          // it: "90" with Minutes selected means 90 minutes, and picking Hours
          // means you meant 90 hours. Silently rewriting it to "1.5" would be
          // the same surprise this control used to cause.
          onChange={(e) => onChange({ ...duration, unit: e.target.value as Unit })}
        >
          <option value="minutes">Minutes</option>
          <option value="hours">Hours</option>
          <option value="days">Days</option>
        </select>
      </div>
    </Field>
  );
}

// ---------------------------------------------------------------------- page

interface FormState {
  warningDays: string;
  cancelCutoff: Duration;
  rescheduleCutoff: Duration;
  startEarly: Duration;
  reminderHour: string;
  graceDays: string;
  welcomeBonusCoins: string;
  coinValue: string;
  publicWebUrl: string;
  androidAppUrl: string;
  iosAppUrl: string;
  androidApkUrl: string;
}

const EMPTY: FormState = {
  warningDays: '3',
  cancelCutoff: { value: '90', unit: 'minutes' },
  rescheduleCutoff: { value: '90', unit: 'minutes' },
  startEarly: { value: '30', unit: 'minutes' },
  reminderHour: '11',
  graceDays: '7',
  welcomeBonusCoins: '2300',
  coinValue: '1',
  publicWebUrl: '',
  androidAppUrl: '',
  iosAppUrl: '',
  androidApkUrl: '',
};

export default function PlatformPolicyPage() {
  const [form, setForm] = useState<FormState>(EMPTY);

  // What the server last confirmed. Everything on this page compares against
  // it, so "changed" always means changed from what is actually stored.
  //
  // State rather than a ref, and the distinction is the whole bug this used to
  // have: a ref mutation is invisible to React, so the diff below kept its
  // stale result after saving and the bar went on claiming unsaved changes
  // until the page was reloaded.
  const [saved, setSaved] = useState<FormState>(EMPTY);

  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [banner, setBanner] = useState<{ tone: 'ok' | 'bad'; text: string } | null>(null);

  const set = <K extends keyof FormState>(key: K, value: FormState[K]) => {
    setForm((prev) => ({ ...prev, [key]: value }));
    // A "Saved." notice sitting above fields that have since been edited is
    // worse than no notice at all.
    setBanner((prev) => (prev?.tone === 'ok' ? null : prev));
  };

  const load = useCallback(async () => {
    try {
      const res = await fetch('/api/superadmin/settings/policy', { cache: 'no-store' });
      const data = await res.json();
      if (!data.success) throw new Error(data.message || 'Could not load settings');

      const s = data.settings;
      const next: FormState = {
        warningDays: String(s.subscription_expiry_warning_days ?? 3),
        cancelCutoff: toDuration(Number(s.cancellation_cutoff_minutes ?? 90)),
        rescheduleCutoff: toDuration(Number(s.reschedule_cutoff_minutes ?? 90)),
        startEarly: toDuration(Number(s.appointment_start_early_minutes ?? 30)),
        reminderHour: String(s.subscription_reminder_hour ?? 11),
        graceDays: String(s.commission_settlement_grace_days ?? 7),
        welcomeBonusCoins: String(s.welcome_bonus_coins ?? 2300),
        coinValue: String(s.coin_value_inr ?? 1),
        publicWebUrl: s.public_web_url || '',
        androidAppUrl: s.android_app_url || '',
        iosAppUrl: s.ios_app_url || '',
        androidApkUrl: s.android_apk_url || '',
      };

      setSaved(next);
      setForm(next);
      setBanner(null);
    } catch (e) {
      setBanner({ tone: 'bad', text: e instanceof Error ? e.message : 'Could not load settings' });
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  // ------------------------------------------------------------- validation

  const errors = useMemo(() => {
    const out: Partial<Record<keyof FormState, string>> = {};

    const wholeNumber = (raw: string) => /^\d+$/.test(raw.trim());

    if (!wholeNumber(form.warningDays)) out.warningDays = 'Enter a whole number of days.';
    else {
      const n = Number(form.warningDays);
      if (n < 1 || n > 30) out.warningDays = 'Must be between 1 and 30 days.';
    }

    (['cancelCutoff', 'rescheduleCutoff', 'startEarly'] as const).forEach((key) => {
      if (!wholeNumber(form[key].value)) out[key] = 'Enter a whole number, or 0 for no cutoff.';
    });

    if (!wholeNumber(form.graceDays) || Number(form.graceDays) > 60) {
      out.graceDays = 'Enter a whole number of days, 0 to 60.';
    }

    if (!wholeNumber(form.welcomeBonusCoins)) {
      out.welcomeBonusCoins = 'Enter a whole number of coins, or 0 to switch the bonus off.';
    }

    if (!/^\d+(\.\d{1,2})?$/.test(form.coinValue.trim()) || Number(form.coinValue) < 0) {
      out.coinValue = 'Enter an amount in rupees, for example 1 or 0.50.';
    }

    const url = form.publicWebUrl.trim();
    if (!url) out.publicWebUrl = 'Required — every printed salon QR code points here.';
    else if (!/^https?:\/\/.+/i.test(url)) out.publicWebUrl = 'Must start with http:// or https://';

    (['androidAppUrl', 'iosAppUrl', 'androidApkUrl'] as const).forEach((key) => {
      const value = form[key].trim();
      if (value && !/^https?:\/\/.+/i.test(value)) {
        out[key] = 'Must start with http:// or https:// — or leave it blank.';
      }
    });

    return out;
  }, [form]);

  const hasErrors = Object.keys(errors).length > 0;

  // ----------------------------------------------------------------- diffing

  /** The API payload for one field, so "changed?" and "send" agree exactly. */
  const payloadFor = useCallback(
    (state: FormState): Record<string, string | number> => ({
      subscription_expiry_warning_days: Number(state.warningDays),
      cancellation_cutoff_minutes: toMinutes(state.cancelCutoff),
      reschedule_cutoff_minutes: toMinutes(state.rescheduleCutoff),
      appointment_start_early_minutes: toMinutes(state.startEarly),
      subscription_reminder_hour: Number(state.reminderHour),
      commission_settlement_grace_days: Number(state.graceDays),
      welcome_bonus_coins: Number(state.welcomeBonusCoins),
      coin_value_inr: Number(state.coinValue),
      public_web_url: state.publicWebUrl.trim().replace(/\/+$/, ''),
      android_app_url: state.androidAppUrl.trim(),
      ios_app_url: state.iosAppUrl.trim(),
      android_apk_url: state.androidApkUrl.trim(),
    }),
    []
  );

  const changed = useMemo(() => {
    if (hasErrors) return [];
    const now = payloadFor(form);
    const before = payloadFor(saved);
    return Object.keys(now).filter((key) => now[key] !== before[key]);
  }, [form, saved, hasErrors, payloadFor]);

  const isDirty = changed.length > 0;

  // Nothing here is worth losing to a stray tab close.
  useEffect(() => {
    if (!isDirty) return;
    const warn = (e: BeforeUnloadEvent) => e.preventDefault();
    window.addEventListener('beforeunload', warn);
    return () => window.removeEventListener('beforeunload', warn);
  }, [isDirty]);

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    if (hasErrors || !isDirty || isSaving) return;

    setIsSaving(true);
    setBanner(null);

    // Only what actually moved. The server records a policy change in the audit
    // log, and an entry listing twelve fields when one was touched would make
    // that log useless.
    const full = payloadFor(form);
    const body = Object.fromEntries(changed.map((key) => [key, full[key]]));

    try {
      const res = await fetch('/api/superadmin/settings/policy', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });
      const data = await res.json().catch(() => ({}));

      if (!res.ok) {
        // Laravel returns a field map on 422; showing the server's own wording
        // beats "Failed to save settings".
        const first = data?.errors ? Object.values(data.errors)[0] : null;
        throw new Error(
          Array.isArray(first) ? String(first[0]) : data?.message || 'Could not save settings'
        );
      }

      setSaved(form);
      setBanner({
        tone: 'ok',
        text: `Saved. ${changed.length} setting${changed.length === 1 ? '' : 's'} updated.`,
      });
    } catch (err) {
      setBanner({ tone: 'bad', text: err instanceof Error ? err.message : 'Could not save settings' });
    } finally {
      setIsSaving(false);
    }
  };

  const discard = () => {
    setForm(saved);
    setBanner(null);
  };

  if (isLoading) {
    return (
      <div className={styles.container}>
        <p className={styles.loading}>Loading settings…</p>
      </div>
    );
  }

  const coinsWorth = (Number(form.welcomeBonusCoins) || 0) * (Number(form.coinValue) || 0);

  return (
    <div className={styles.container}>
      <header className={styles.header}>
        <h1 className={styles.title}>Platform Policy</h1>
        <p className={styles.subtitle}>
          Rules every salon and customer on the platform is bound by. Changes
          take effect immediately and are recorded in the audit log.
        </p>
      </header>

      {banner && (
        <div className={`${styles.banner} ${banner.tone === 'ok' ? styles.bannerOk : styles.bannerBad}`}>
          {banner.text}
        </div>
      )}

      <form onSubmit={handleSave} className={styles.form}>
        <section className={styles.section}>
          <h2 className={styles.sectionTitle}>Bookings &amp; cancellations</h2>
          <p className={styles.sectionHint}>
            How close to an appointment a customer can still change their mind,
            and how early a salon can start one.
          </p>

          <DurationField
            label="Cancellation cutoff"
            hint="How long before an appointment cancelling is blocked."
            duration={form.cancelCutoff}
            onChange={(d) => set('cancelCutoff', d)}
            error={errors.cancelCutoff}
          />

          <DurationField
            label="Reschedule cutoff"
            hint="How long before an appointment rescheduling is blocked."
            duration={form.rescheduleCutoff}
            onChange={(d) => set('rescheduleCutoff', d)}
            error={errors.rescheduleCutoff}
          />

          <DurationField
            label="Early start allowance"
            hint="How early a salon may start an appointment before its booked time."
            duration={form.startEarly}
            onChange={(d) => set('startEarly', d)}
            error={errors.startEarly}
          />
        </section>

        <section className={styles.section}>
          <h2 className={styles.sectionTitle}>Subscriptions &amp; reminders</h2>
          <p className={styles.sectionHint}>
            When salon owners are chased about a plan that is running out.
          </p>

          <Field
            label="Warn before a plan expires"
            error={errors.warningDays}
            hint="Days of notice before a subscription lapses, shown as a banner in the Partner App."
          >
            <div className={styles.suffixRow}>
              <input
                className={`${styles.input} ${errors.warningDays ? styles.inputError : ''}`}
                type="number"
                min="1"
                max="30"
                inputMode="numeric"
                value={form.warningDays}
                onChange={(e) => set('warningDays', e.target.value)}
              />
              <span className={styles.suffix}>days</span>
            </div>
          </Field>

          <Field
            label="Send reminders at"
            hint="Renewal reminders go out once a day at this hour. Mid-morning works best — owners are at the salon and not yet in the rush."
          >
            <select
              className={styles.select}
              value={form.reminderHour}
              onChange={(e) => set('reminderHour', e.target.value)}
            >
              {Array.from({ length: 24 }, (_, hour) => (
                <option key={hour} value={String(hour)}>
                  {hourLabel(hour)}
                </option>
              ))}
            </select>
          </Field>

          <Field
            label="Commission settlement grace period"
            error={errors.graceDays}
            hint="Days after a month closes before a Commission Model salon with an unsettled bill loses access."
          >
            <div className={styles.suffixRow}>
              <input
                className={`${styles.input} ${errors.graceDays ? styles.inputError : ''}`}
                type="number"
                min="0"
                max="60"
                inputMode="numeric"
                value={form.graceDays}
                onChange={(e) => set('graceDays', e.target.value)}
              />
              <span className={styles.suffix}>days</span>
            </div>
          </Field>
        </section>

        <section className={styles.section}>
          <h2 className={styles.sectionTitle}>Rewards &amp; coins</h2>
          <p className={styles.sectionHint}>
            Coins are earned on completed bookings and spent on subscriptions or
            against commission owed.
          </p>

          <Field
            label="What one coin is worth"
            error={errors.coinValue}
            hint="Used everywhere coins are converted to money — plan discounts and commission settlements alike."
          >
            <div className={styles.suffixRow}>
              <span className={styles.prefix}>₹</span>
              <input
                className={`${styles.input} ${errors.coinValue ? styles.inputError : ''}`}
                type="number"
                min="0"
                step="0.01"
                inputMode="decimal"
                value={form.coinValue}
                onChange={(e) => set('coinValue', e.target.value)}
              />
              <span className={styles.suffix}>per coin</span>
            </div>
          </Field>

          <Field
            label="Free coins on approval"
            error={errors.welcomeBonusCoins}
            hint={
              <>
                Given to a salon the moment you approve it, so its first
                subscription is already part-paid.{' '}
                <span className={styles.resolved}>
                  Worth ₹{coinsWorth.toLocaleString('en-IN')} at the current rate.
                </span>{' '}
                Changing this only affects salons approved from now on. Set it to
                0 to stop giving new salons a bonus.
              </>
            }
          >
            <div className={styles.suffixRow}>
              <input
                className={`${styles.input} ${errors.welcomeBonusCoins ? styles.inputError : ''}`}
                type="number"
                min="0"
                inputMode="numeric"
                value={form.welcomeBonusCoins}
                onChange={(e) => set('welcomeBonusCoins', e.target.value)}
              />
              <span className={styles.suffix}>coins</span>
            </div>
          </Field>
        </section>

        <section className={styles.section}>
          <h2 className={styles.sectionTitle}>Salon QR codes &amp; the app</h2>
          <p className={styles.sectionHint}>
            Every salon&apos;s printed QR code points at the address below.
            Changing it redirects every poster already on a wall — which is the
            point, but get it right before they are printed.
          </p>

          <Field
            label="Public website address"
            error={errors.publicWebUrl}
            hint={
              <>
                A scanned salon QR opens{' '}
                <code className={styles.code}>
                  {(form.publicWebUrl.trim().replace(/\/+$/, '') || 'https://…')}/s/salon-name
                </code>
              </>
            }
          >
            <input
              className={`${styles.input} ${errors.publicWebUrl ? styles.inputError : ''}`}
              type="text"
              inputMode="url"
              placeholder="https://bookalook.in"
              value={form.publicWebUrl}
              onChange={(e) => set('publicWebUrl', e.target.value)}
            />
          </Field>

          <Field
            label="Play Store link"
            error={errors.androidAppUrl}
            hint="Leave blank until the listing is live — a blank link hides the button rather than sending customers to a page that does not exist."
          >
            <input
              className={`${styles.input} ${errors.androidAppUrl ? styles.inputError : ''}`}
              type="text"
              inputMode="url"
              placeholder="https://play.google.com/store/apps/details?id=…"
              value={form.androidAppUrl}
              onChange={(e) => set('androidAppUrl', e.target.value)}
            />
          </Field>

          <Field label="App Store link" error={errors.iosAppUrl} hint="Blank hides the iPhone button.">
            <input
              className={`${styles.input} ${errors.iosAppUrl ? styles.inputError : ''}`}
              type="text"
              inputMode="url"
              placeholder="https://apps.apple.com/in/app/…"
              value={form.iosAppUrl}
              onChange={(e) => set('iosAppUrl', e.target.value)}
            />
          </Field>

          <Field
            label="Direct Android build (APK)"
            error={errors.androidApkUrl}
            hint="Used before the Play Store listing is approved. If both are set, the Play Store link wins."
          >
            <input
              className={`${styles.input} ${errors.androidApkUrl ? styles.inputError : ''}`}
              type="text"
              inputMode="url"
              placeholder="https://bookalook.in/downloads/bookalook.apk"
              value={form.androidApkUrl}
              onChange={(e) => set('androidApkUrl', e.target.value)}
            />
          </Field>
        </section>

        {/* Stays in view on a long form, and says what is about to happen. */}
        <div className={`${styles.saveBar} ${isDirty || hasErrors ? styles.saveBarActive : ''}`}>
          <span className={styles.saveStatus}>
            {hasErrors
              ? `${Object.keys(errors).length} field${Object.keys(errors).length === 1 ? '' : 's'} need fixing`
              : isDirty
                ? `${changed.length} unsaved change${changed.length === 1 ? '' : 's'}`
                : 'All changes saved'}
          </span>

          <div className={styles.saveActions}>
            {isDirty && (
              <button type="button" className={styles.ghostButton} onClick={discard} disabled={isSaving}>
                Discard
              </button>
            )}
            <button
              type="submit"
              className={styles.button}
              disabled={isSaving || hasErrors || !isDirty}
            >
              {isSaving ? 'Saving…' : 'Save changes'}
            </button>
          </div>
        </div>
      </form>
    </div>
  );
}
