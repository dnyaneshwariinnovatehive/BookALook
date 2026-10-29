'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { Badge, Button, Tabs, cx } from '@/components/admin/ui';
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
 *
 * The six rule groups sit on their own tabs rather than one long scroll. Six
 * unrelated groups stacked in a column is a wall — nobody reads past the third
 * one. One group per tab keeps the save bar useful too: it is already sticky,
 * so switching tabs does not lose your place or your edits, and a tab carrying
 * a validation badge points at the group that needs attention even while you
 * are reading a different one.
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

// ---------------------------------------------------------------------- tabs

type PolicyTab = 'catalog' | 'bookings' | 'subscriptions' | 'dues' | 'coins' | 'payments' | 'links' | 'whatsapp';

const TAB_LABELS: Record<PolicyTab, string> = {
  catalog: 'Services',
  bookings: 'Bookings',
  subscriptions: 'Subscriptions',
  dues: 'Commission dues',
  coins: 'Coins',
  payments: 'Payments',
  links: 'Links & QR',
  whatsapp: 'WhatsApp',
};

/** Which form fields belong to which tab, so a badge can find them. */
const TAB_FIELDS: Record<PolicyTab, (keyof FormState)[]> = {
  catalog: ['combosLimit'],
  bookings: [
    'cancelCutoff', 'rescheduleCutoff', 'startEarly',
    'cancelLimit', 'cancelMode', 'noShowLimit', 'noShowMode', 'limitAction', 'limitWindow', 'limitRelease',
  ],
  subscriptions: ['warningDays', 'reminderHour'],
  dues: [
    'graceDays', 'duesMin', 'duesRemBefore', 'duesRemEvery',
    'duesBannerDays', 'duesAdvanceDays', 'duesDeductDays', 'duesStopDays', 'duesLockDays',
  ],
  coins: ['coinValue', 'welcomeBonusCoins'],
  payments: ['paymentUpiId', 'paymentPayeeName'],
  links: ['publicWebUrl', 'androidAppUrl', 'iosAppUrl', 'androidApkUrl'],
  whatsapp: [
    'reminderLead',
    'waBookingConfirmed',
    'waAppointmentReminder',
    'waAppointmentCancelled',
    'waSalonClosure',
    'waSalonDeactivated',
  ],
};

// ---------------------------------------------------------------------- page

interface FormState {
  warningDays: string;
  cancelCutoff: Duration;
  rescheduleCutoff: Duration;
  startEarly: Duration;
  reminderLead: Duration;
  reminderHour: string;
  graceDays: string;
  welcomeBonusCoins: string;
  coinValue: string;
  publicWebUrl: string;
  androidAppUrl: string;
  iosAppUrl: string;
  androidApkUrl: string;
  paymentUpiId: string;
  paymentPayeeName: string;
  waBookingConfirmed: boolean;
  waAppointmentReminder: boolean;
  waAppointmentCancelled: boolean;
  waSalonClosure: boolean;
  waSalonDeactivated: boolean;
  combosLimit: string;
  // Customer booking limits — one rule for every customer.
  cancelLimit: string;
  cancelMode: string;
  noShowLimit: string;
  noShowMode: string;
  limitAction: string;
  limitWindow: string;
  limitRelease: string;
  // What happens to a Commission Model salon that has not paid what it owes.
  duesMin: string;
  duesRemOn: boolean;
  duesRemBefore: string;
  duesRemEvery: string;
  duesBannerOn: boolean;
  duesBannerDays: string;
  duesAdvanceOn: boolean;
  duesAdvanceDays: string;
  duesDeductOn: boolean;
  duesDeductDays: string;
  duesStopOn: boolean;
  duesStopDays: string;
  duesLockOn: boolean;
  duesLockDays: string;
}

type DuesStepKey = 'Banner' | 'Advance' | 'Deduct' | 'Stop' | 'Lock';

/** The steps after the due date, mildest first, as the Policy form shows them. */
const DUES_STEPS: { key: DuesStepKey; title: string; hint: string }[] = [
  { key: 'Banner', title: 'Warning banner', hint: 'A red strip in the Partner App with the amount and a Pay now button. Blocks nothing.' },
  { key: 'Advance', title: 'Customers pay the full amount online', hint: 'BookALook collects the whole price at booking, so what the salon owes can be recovered from it.' },
  { key: 'Deduct', title: 'Deduct from payouts', hint: 'Overdue dues are taken off the next money BookALook pays the salon.' },
  { key: 'Stop', title: 'Stop new online bookings', hint: 'Customers cannot book the salon. Existing bookings go ahead and the Partner App keeps working.' },
  { key: 'Lock', title: 'Full lock', hint: 'The Partner App locks for everyone and the salon is unavailable to customers.' },
];

/** "0" means no limit, so it reads "Off". */
const LIMIT_OPTIONS = [
  { value: '0', label: 'Off — no limit' },
  ...Array.from({ length: 10 }, (_, i) => ({ value: String(i + 1), label: String(i + 1) })),
];

const MODE_OPTIONS = [
  { value: 'total', label: 'In total' },
  { value: 'consecutive', label: 'Consecutively (in a row)' },
];

const ACTION_OPTIONS = [
  { value: 'block', label: 'Block new bookings' },
  { value: 'full_payment', label: 'Require full payment upfront' },
  { value: 'warn', label: 'Only warn the customer' },
];

const WINDOW_OPTIONS = [
  { value: '30', label: 'Last 30 days' },
  { value: '60', label: 'Last 60 days' },
  { value: '90', label: 'Last 90 days' },
  { value: '180', label: 'Last 6 months' },
  { value: '365', label: 'Last 12 months' },
  { value: '0', label: 'All time' },
];

const RELEASE_OPTIONS = [
  { value: '7', label: '7 days after the last one' },
  { value: '15', label: '15 days after the last one' },
  { value: '30', label: '30 days after the last one' },
  { value: '60', label: '60 days after the last one' },
  { value: '90', label: '90 days after the last one' },
  { value: '0', label: 'Never — only when superadmin clears it' },
];

/** A dropdown that keeps a stored value visible even if it is not a preset. */
function withCurrent(options: { value: string; label: string }[], current: string) {
  return options.some((o) => o.value === current) ? options : [...options, { value: current, label: current }];
}

const EMPTY: FormState = {
  warningDays: '3',
  cancelCutoff: { value: '90', unit: 'minutes' },
  rescheduleCutoff: { value: '90', unit: 'minutes' },
  startEarly: { value: '30', unit: 'minutes' },
  reminderLead: { value: '120', unit: 'minutes' },
  reminderHour: '11',
  graceDays: '7',
  welcomeBonusCoins: '2300',
  coinValue: '1',
  publicWebUrl: '',
  androidAppUrl: '',
  iosAppUrl: '',
  androidApkUrl: '',
  paymentUpiId: '',
  paymentPayeeName: '',
  waBookingConfirmed: true,
  waAppointmentReminder: true,
  waAppointmentCancelled: true,
  waSalonClosure: true,
  waSalonDeactivated: true,
  combosLimit: '10',
  cancelLimit: '0',
  cancelMode: 'total',
  noShowLimit: '0',
  noShowMode: 'total',
  limitAction: 'block',
  duesMin: '200',
  duesRemOn: true,
  duesRemBefore: '3',
  duesRemEvery: '3',
  duesBannerOn: true,
  duesBannerDays: '0',
  duesAdvanceOn: true,
  duesAdvanceDays: '3',
  duesDeductOn: true,
  duesDeductDays: '3',
  duesStopOn: true,
  duesStopDays: '10',
  duesLockOn: true,
  duesLockDays: '20',
  limitWindow: '90',
  limitRelease: '30',
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

  // Editing is never lost to a tab switch — the form is one state object, and
  // the tab only chooses what is drawn from it.
  const [tab, setTab] = useState<PolicyTab>('catalog');

  // Bumped after every successful save. Used as a React key on the status text
  // so the "saved" animation replays each time instead of only on first mount —
  // a confirmation that runs once and then sits still is easy to miss, and this
  // is the only proof the write actually landed.
  const [savePulse, setSavePulse] = useState(0);

  // The payment QR is an image, uploaded the moment it is picked rather than
  // with the form — so it sits outside the form state.
  const [paymentQrUrl, setPaymentQrUrl] = useState<string>('');
  const [qrBusy, setQrBusy] = useState(false);

  const uploadQr = async (file: File) => {
    setQrBusy(true);
    setBanner(null);
    try {
      const body = new FormData();
      body.append('qr', file);
      const res = await fetch('/api/proxy/superadmin/settings/payment-qr', { method: 'POST', body });
      const data = await res.json().catch(() => ({}));
      if (!res.ok || !data.success) throw new Error(data.message || 'Could not upload the QR');
      setPaymentQrUrl(data.payment_qr_url || '');
      setBanner({ tone: 'ok', text: 'Payment QR updated. Salons see it the next time they open a pay screen.' });
    } catch (e) {
      setBanner({ tone: 'bad', text: e instanceof Error ? e.message : 'Could not upload the QR' });
    } finally {
      setQrBusy(false);
    }
  };

  const removeQr = async () => {
    setQrBusy(true);
    try {
      const res = await fetch('/api/proxy/superadmin/settings/payment-qr', { method: 'DELETE' });
      if (!res.ok) throw new Error('Could not remove the QR');
      setPaymentQrUrl('');
    } catch (e) {
      setBanner({ tone: 'bad', text: e instanceof Error ? e.message : 'Could not remove the QR' });
    } finally {
      setQrBusy(false);
    }
  };

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
      setPaymentQrUrl(s.payment_qr_url || '');
      const next: FormState = {
        warningDays: String(s.subscription_expiry_warning_days ?? 3),
        cancelCutoff: toDuration(Number(s.cancellation_cutoff_minutes ?? 90)),
        rescheduleCutoff: toDuration(Number(s.reschedule_cutoff_minutes ?? 90)),
        startEarly: toDuration(Number(s.appointment_start_early_minutes ?? 30)),
        reminderLead: toDuration(Number(s.appointment_reminder_lead_minutes ?? 120)),
        reminderHour: String(s.subscription_reminder_hour ?? 11),
        graceDays: String(s.commission_settlement_grace_days ?? 7),
        welcomeBonusCoins: String(s.welcome_bonus_coins ?? 2300),
        coinValue: String(s.coin_value_inr ?? 1),
        publicWebUrl: s.public_web_url || '',
        androidAppUrl: s.android_app_url || '',
        iosAppUrl: s.ios_app_url || '',
        androidApkUrl: s.android_apk_url || '',
        paymentUpiId: s.payment_upi_id || '',
        paymentPayeeName: s.payment_payee_name || '',
        waBookingConfirmed: s.whatsapp_booking_confirmed_enabled ?? true,
        waAppointmentReminder: s.whatsapp_appointment_reminder_enabled ?? true,
        waAppointmentCancelled: s.whatsapp_appointment_cancelled_enabled ?? true,
        waSalonClosure: s.whatsapp_salon_closure_enabled ?? true,
        waSalonDeactivated: s.whatsapp_salon_deactivated_enabled ?? true,
        combosLimit: String(s.combos_limit_per_salon ?? 10),
        cancelLimit: String(s.customer_cancellation_limit ?? 0),
        cancelMode: String(s.customer_cancellation_count_mode ?? 'total'),
        noShowLimit: String(s.customer_no_show_limit ?? 0),
        noShowMode: String(s.customer_no_show_count_mode ?? 'total'),
        limitAction: String(s.customer_limit_action ?? 'block'),
        limitWindow: String(s.customer_limit_window_days ?? 90),
        limitRelease: String(s.customer_limit_release_days ?? 30),
        duesMin: String(s.commission_dues_min_amount ?? 200),
        duesRemOn: s.commission_dues_reminder_enabled ?? true,
        duesRemBefore: String(s.commission_dues_reminder_before_days ?? 3),
        duesRemEvery: String(s.commission_dues_reminder_every_days ?? 3),
        duesBannerOn: s.commission_dues_banner_enabled ?? true,
        duesBannerDays: String(s.commission_dues_banner_days ?? 0),
        duesAdvanceOn: s.commission_dues_force_advance_enabled ?? true,
        duesAdvanceDays: String(s.commission_dues_force_advance_days ?? 3),
        duesDeductOn: s.commission_dues_deduct_enabled ?? true,
        duesDeductDays: String(s.commission_dues_deduct_days ?? 3),
        duesStopOn: s.commission_dues_stop_bookings_enabled ?? true,
        duesStopDays: String(s.commission_dues_stop_bookings_days ?? 10),
        duesLockOn: s.commission_dues_full_lock_enabled ?? true,
        duesLockDays: String(s.commission_dues_full_lock_days ?? 20),
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
    const timer = setTimeout(load, 0);
    return () => clearTimeout(timer);
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

    (['cancelCutoff', 'rescheduleCutoff', 'startEarly', 'reminderLead'] as const).forEach((key) => {
      if (!wholeNumber(form[key].value)) out[key] = 'Enter a whole number, or 0 for no cutoff.';
    });

    if (!wholeNumber(form.combosLimit)) {
      out.combosLimit = 'Enter a whole number.';
    }

    if (!wholeNumber(form.graceDays) || Number(form.graceDays) > 60) {
      out.graceDays = 'Enter a whole number of days, 0 to 60.';
    }

    if (!wholeNumber(form.duesMin)) out.duesMin = 'Enter a whole number of rupees.';
    (['duesRemBefore', 'duesRemEvery'] as const).forEach((key) => {
      if (!wholeNumber(form[key]) || Number(form[key]) > 30) out[key] = 'Enter 0 to 30 days.';
    });
    (['duesBannerDays', 'duesAdvanceDays', 'duesDeductDays', 'duesStopDays', 'duesLockDays'] as const).forEach((key) => {
      if (!wholeNumber(form[key]) || Number(form[key]) > 365) out[key] = 'Enter 0 to 365 days.';
    });

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
    (state: FormState): Record<string, string | number | boolean> => ({
      subscription_expiry_warning_days: Number(state.warningDays),
      cancellation_cutoff_minutes: toMinutes(state.cancelCutoff),
      reschedule_cutoff_minutes: toMinutes(state.rescheduleCutoff),
      appointment_start_early_minutes: toMinutes(state.startEarly),
      appointment_reminder_lead_minutes: toMinutes(state.reminderLead),
      subscription_reminder_hour: Number(state.reminderHour),
      commission_settlement_grace_days: Number(state.graceDays),
      welcome_bonus_coins: Number(state.welcomeBonusCoins),
      coin_value_inr: Number(state.coinValue),
      public_web_url: state.publicWebUrl.trim().replace(/\/+$/, ''),
      android_app_url: state.androidAppUrl.trim(),
      ios_app_url: state.iosAppUrl.trim(),
      android_apk_url: state.androidApkUrl.trim(),
      payment_upi_id: state.paymentUpiId.trim(),
      payment_payee_name: state.paymentPayeeName.trim(),
      whatsapp_booking_confirmed_enabled: state.waBookingConfirmed,
      whatsapp_appointment_reminder_enabled: state.waAppointmentReminder,
      whatsapp_appointment_cancelled_enabled: state.waAppointmentCancelled,
      whatsapp_salon_closure_enabled: state.waSalonClosure,
      whatsapp_salon_deactivated_enabled: state.waSalonDeactivated,
      combos_limit_per_salon: Number(state.combosLimit),
      customer_cancellation_limit: Number(state.cancelLimit),
      customer_cancellation_count_mode: state.cancelMode,
      customer_no_show_limit: Number(state.noShowLimit),
      customer_no_show_count_mode: state.noShowMode,
      customer_limit_action: state.limitAction,
      customer_limit_window_days: Number(state.limitWindow),
      customer_limit_release_days: Number(state.limitRelease),
      commission_dues_min_amount: Number(state.duesMin),
      commission_dues_reminder_enabled: state.duesRemOn,
      commission_dues_reminder_before_days: Number(state.duesRemBefore),
      commission_dues_reminder_every_days: Number(state.duesRemEvery),
      commission_dues_banner_enabled: state.duesBannerOn,
      commission_dues_banner_days: Number(state.duesBannerDays),
      commission_dues_force_advance_enabled: state.duesAdvanceOn,
      commission_dues_force_advance_days: Number(state.duesAdvanceDays),
      commission_dues_deduct_enabled: state.duesDeductOn,
      commission_dues_deduct_days: Number(state.duesDeductDays),
      commission_dues_stop_bookings_enabled: state.duesStopOn,
      commission_dues_stop_bookings_days: Number(state.duesStopDays),
      commission_dues_full_lock_enabled: state.duesLockOn,
      commission_dues_full_lock_days: Number(state.duesLockDays),
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
      setSavePulse((n) => n + 1);
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
        <Tabs<PolicyTab>
          value={tab}
          onChange={setTab}
          tabs={(Object.keys(TAB_LABELS) as PolicyTab[]).map((value) => {
            // A group you cannot currently see must still be able to say it needs
            // fixing, or the sticky bar claims errors you have no way of finding.
            const broken = TAB_FIELDS[value].filter((key) => errors[key]).length;
            return {
              value,
              label: (
                <>
                  {TAB_LABELS[value]}
                  {broken > 0 && <span className={styles.tabBadge}>{broken}</span>}
                </>
              ),
            };
          })}
        />

        <div className={styles.tabBody}>
        {tab === 'catalog' && (
        <section className={styles.section}>
          <h2 className={styles.sectionTitle}>Service Catalog</h2>
          <p className={styles.sectionHint}>Limits and rules for the services and combos salons can offer.</p>
          <Field
            label="Max service combos"
            error={errors.combosLimit}
            hint="The maximum number of service combos any single salon can create."
          >
            <div className={styles.suffixRow}>
              <input
                className={`${styles.input} ${errors.combosLimit ? styles.inputError : ''}`}
                type="number"
                min="0"
                inputMode="numeric"
                value={form.combosLimit}
                onChange={(e) => set('combosLimit', e.target.value)}
              />
              <span className={styles.suffix}>combos</span>
            </div>
          </Field>
        </section>
        )}

        {tab === 'bookings' && (
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
            hint="How early a salon may start an appointment before its booked time. Also dictates when the service provider's contact details become available to the customer."
            duration={form.startEarly}
            onChange={(d) => set('startEarly', d)}
            error={errors.startEarly}
          />
        </section>
        )}

        {tab === 'bookings' && (
        <section className={styles.section}>
          <h2 className={styles.sectionTitle}>Customer cancellation &amp; no-show limits</h2>
          <p className={styles.sectionHint}>
            One rule for every customer, counted across all salons. Only cancellations the customer makes
            count — never a salon cancelling or a reschedule.
          </p>

          <div className={styles.limitGrid}>
            <Field label="Cancellations allowed" hint="Once a customer reaches this many, the action below applies.">
              <select className={styles.select} value={form.cancelLimit} onChange={(e) => set('cancelLimit', e.target.value)}>
                {withCurrent(LIMIT_OPTIONS, form.cancelLimit).map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
              </select>
            </Field>
            <Field label="Count cancellations" hint="In a row resets after every completed visit.">
              <select className={styles.select} value={form.cancelMode} disabled={form.cancelLimit === '0'} onChange={(e) => set('cancelMode', e.target.value)}>
                {MODE_OPTIONS.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
              </select>
            </Field>
            <Field label="No-shows allowed" hint="Booked, never turned up, marked No-show by the salon.">
              <select className={styles.select} value={form.noShowLimit} onChange={(e) => set('noShowLimit', e.target.value)}>
                {withCurrent(LIMIT_OPTIONS, form.noShowLimit).map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
              </select>
            </Field>
            <Field label="Count no-shows" hint="In a row resets after every completed visit.">
              <select className={styles.select} value={form.noShowMode} disabled={form.noShowLimit === '0'} onChange={(e) => set('noShowMode', e.target.value)}>
                {MODE_OPTIONS.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
              </select>
            </Field>
          </div>

          <Field
            label="When a customer reaches a limit"
            hint={form.limitAction === 'full_payment'
              ? 'Needs online payments switched on. If they are off, choose Block instead.'
              : form.limitAction === 'block'
                ? 'They see why, and when it lifts, when they try to book.'
                : 'They can still book; the app tells them where they stand.'}
          >
            <select className={styles.select} value={form.limitAction} onChange={(e) => set('limitAction', e.target.value)}>
              {ACTION_OPTIONS.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
            </select>
          </Field>

          <div className={styles.limitGrid}>
            <Field label="“In total” looks back over" hint="Older cancellations and no-shows stop counting.">
              <select className={styles.select} value={form.limitWindow} onChange={(e) => set('limitWindow', e.target.value)}>
                {withCurrent(WINDOW_OPTIONS, form.limitWindow).map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
              </select>
            </Field>
            <Field label="Restriction lifts" hint="Superadmin can always clear a customer from the Customers page.">
              <select className={styles.select} value={form.limitRelease} onChange={(e) => set('limitRelease', e.target.value)}>
                {withCurrent(RELEASE_OPTIONS, form.limitRelease).map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
              </select>
            </Field>
          </div>

          <p className={styles.limitSummary}>
            {form.cancelLimit === '0' && form.noShowLimit === '0'
              ? 'Limits are off: customers can cancel and miss appointments without any restriction.'
              : `${[
                  form.cancelLimit !== '0' ? `${form.cancelLimit} cancellation${form.cancelLimit === '1' ? '' : 's'} ${form.cancelMode === 'consecutive' ? 'in a row' : 'in total'}` : '',
                  form.noShowLimit !== '0' ? `${form.noShowLimit} no-show${form.noShowLimit === '1' ? '' : 's'} ${form.noShowMode === 'consecutive' ? 'in a row' : 'in total'}` : '',
                ].filter(Boolean).join(' or ')} → ${ACTION_OPTIONS.find((o) => o.value === form.limitAction)?.label.toLowerCase()}, ${
                  form.limitRelease === '0' ? 'until superadmin clears it' : `lifting ${form.limitRelease} days after the last one`
                }.`}
          </p>
        </section>
        )}

        {tab === 'subscriptions' && (
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

        </section>
        )}

        {tab === 'dues' && (
        <section className={styles.section}>
          <h2 className={styles.sectionTitle}>Commission dues</h2>
          <p className={styles.sectionHint}>
            What happens to a Commission Model salon that has not paid what it owes BookALook — usually
            because advances were not collected. Each step starts a number of days after the due date and
            lifts on its own the moment the salon pays. You can override any salon from Overdue Salons.
          </p>

          <div className={styles.limitGrid}>
            <Field
              label="Payment due"
              error={errors.graceDays}
              hint="Days after a month closes before its commission is due."
            >
              <div className={styles.suffixRow}>
                <input
                  className={cx(styles.input, errors.graceDays && styles.inputError)}
                  type="number" min="0" max="60" inputMode="numeric"
                  value={form.graceDays}
                  onChange={(e) => set('graceDays', e.target.value)}
                />
                <span className={styles.suffix}>days</span>
              </div>
            </Field>
            <Field
              label="Ignore dues below"
              error={errors.duesMin}
              hint="Smaller amounts never trigger a step."
            >
              <div className={styles.suffixRow}>
                <span className={styles.suffix}>₹</span>
                <input
                  className={cx(styles.input, errors.duesMin && styles.inputError)}
                  type="number" min="0" inputMode="numeric"
                  value={form.duesMin}
                  onChange={(e) => set('duesMin', e.target.value)}
                />
              </div>
            </Field>
          </div>

          <div className={styles.duesStep}>
            <label className={styles.duesToggle}>
              <input type="checkbox" className={styles.checkbox} checked={form.duesRemOn}
                onChange={(e) => set('duesRemOn', e.target.checked)} />
              <span>
                <b>Reminders</b>
                <small>Push and in-app message to the owner.</small>
              </span>
            </label>
            <div className={styles.duesDays}>
              <div className={styles.suffixRow}>
                <input
                  className={cx(styles.input, errors.duesRemBefore && styles.inputError)}
                  type="number" min="0" max="30" inputMode="numeric" disabled={!form.duesRemOn}
                  value={form.duesRemBefore}
                  onChange={(e) => set('duesRemBefore', e.target.value)}
                  aria-label="Days before the due date"
                />
                <span className={styles.suffix}>days before due, then every</span>
                <input
                  className={cx(styles.input, errors.duesRemEvery && styles.inputError)}
                  type="number" min="0" max="30" inputMode="numeric" disabled={!form.duesRemOn}
                  value={form.duesRemEvery}
                  onChange={(e) => set('duesRemEvery', e.target.value)}
                  aria-label="Days between reminders"
                />
                <span className={styles.suffix}>days</span>
              </div>
            </div>
          </div>

          {DUES_STEPS.map((step) => {
            const onKey = `dues${step.key}On` as keyof FormState;
            const daysKey = `dues${step.key}Days` as keyof FormState;
            const on = form[onKey] as boolean;
            return (
              <div key={step.key} className={cx(styles.duesStep, !on && styles.duesStepOff)}>
                <label className={styles.duesToggle}>
                  <input type="checkbox" className={styles.checkbox} checked={on}
                    onChange={(e) => set(onKey, e.target.checked as never)} />
                  <span>
                    <b>{step.title}</b>
                    <small>{step.hint}</small>
                  </span>
                </label>
                <div className={styles.duesDays}>
                  <div className={styles.suffixRow}>
                    <span className={styles.suffix}>from day</span>
                    <input
                      className={cx(styles.input, errors[daysKey] && styles.inputError)}
                      type="number" min="0" max="365" inputMode="numeric" disabled={!on}
                      value={form[daysKey] as string}
                      onChange={(e) => set(daysKey, e.target.value as never)}
                      aria-label={`${step.title}: days after the due date`}
                    />
                    <span className={styles.suffix}>after due</span>
                  </div>
                  {errors[daysKey] && <p className={styles.error}>{errors[daysKey]}</p>}
                </div>
              </div>
            );
          })}

          <div className={styles.limitSummary}>
            {(() => {
              const grace = Number(form.graceDays) || 0;
              const parts = [`A month's commission is due ${grace} day${grace === 1 ? '' : 's'} after it closes`];
              if (form.duesRemOn) parts.push(`reminders from ${form.duesRemBefore} days before`);
              const timeline = DUES_STEPS
                .filter((st) => form[`dues${st.key}On` as keyof FormState])
                .map((st) => ({ day: Number(form[`dues${st.key}Days` as keyof FormState]) || 0, title: st.title.toLowerCase() }))
                .sort((a, b) => a.day - b.day)
                .map((st) => (st.day === 0 ? `on the due date: ${st.title}` : `day ${st.day}: ${st.title}`));
              return `${parts.join('; ')}${timeline.length ? `; ${timeline.join('; ')}` : '; no other steps'}.`;
            })()}
          </div>
        </section>
        )}

        {tab === 'coins' && (
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
        )}

        {tab === 'links' && (
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
        )}

        {tab === 'payments' && (
        <section className={styles.section}>
          <h2 className={styles.sectionTitle}>Where salons pay BookALook</h2>
          <p className={styles.sectionHint}>
            Shown to salon owners when they buy a plan and when they pay what a
            payout says they owe. They scan it, pay, and upload the screenshot for
            you to verify.
          </p>

          <Field
            label="Payment QR"
            hint="A clear image of your UPI QR code. It replaces the current one immediately."
          >
            <div style={{ display: 'flex', gap: 16, alignItems: 'center', flexWrap: 'wrap' }}>
              {paymentQrUrl ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img
                  src={paymentQrUrl}
                  alt="Payment QR"
                  style={{ width: 140, height: 140, objectFit: 'contain', borderRadius: 8, border: '1px solid var(--border-strong)', background: '#fff' }}
                />
              ) : (
                <div style={{ width: 140, height: 140, display: 'grid', placeItems: 'center', borderRadius: 8, border: '1px dashed var(--border-strong)', color: 'var(--text-body)', fontSize: 13, textAlign: 'center', padding: 8 }}>
                  No QR yet — salons are told to contact you
                </div>
              )}
              <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                <label className={styles.input} style={{ cursor: qrBusy ? 'wait' : 'pointer', textAlign: 'center' }}>
                  {qrBusy ? 'Working…' : paymentQrUrl ? 'Replace QR' : 'Upload QR'}
                  <input
                    type="file"
                    accept="image/png,image/jpeg,image/webp"
                    hidden
                    disabled={qrBusy}
                    onChange={(e) => {
                      const file = e.target.files?.[0];
                      e.target.value = '';
                      if (file) uploadQr(file);
                    }}
                  />
                </label>
                {paymentQrUrl && (
                  <button type="button" className={styles.input} disabled={qrBusy} onClick={removeQr}>
                    Remove QR
                  </button>
                )}
              </div>
            </div>
          </Field>

          <Field
            label="UPI ID"
            hint="Shown under the QR with a copy button, for owners who prefer to type it."
          >
            <input
              className={styles.input}
              type="text"
              placeholder="e.g. bookalook@okhdfcbank"
              value={form.paymentUpiId}
              onChange={(e) => set('paymentUpiId', e.target.value)}
            />
          </Field>

          <Field
            label="Payee name"
            hint="The name their UPI app will show, so they can check they are paying BookALook."
          >
            <input
              className={styles.input}
              type="text"
              placeholder="e.g. InnovateHive Technologies"
              value={form.paymentPayeeName}
              onChange={(e) => set('paymentPayeeName', e.target.value)}
            />
          </Field>
        </section>
        )}

        {tab === 'whatsapp' && (
        <section className={styles.section}>
          <h2 className={styles.sectionTitle}>WhatsApp Notifications</h2>
          <p className={styles.sectionHint}>
            Global toggles for automated WhatsApp messages. Disabling a toggle stops all outgoing messages for that event across the entire platform.
          </p>

          <label className={styles.checkboxLabel}>
            <input
              type="checkbox"
              className={styles.checkbox}
              checked={form.waBookingConfirmed}
              onChange={(e) => set('waBookingConfirmed', e.target.checked)}
            />
            <div className={styles.checkboxText}>
              <span className={styles.checkboxTitle}>Booking Confirmed</span>
              <span className={styles.checkboxHint}>Sent when a customer successfully confirms an appointment.</span>
            </div>
          </label>

          <label className={styles.checkboxLabel}>
            <input
              type="checkbox"
              className={styles.checkbox}
              checked={form.waAppointmentReminder}
              onChange={(e) => set('waAppointmentReminder', e.target.checked)}
            />
            <div className={styles.checkboxText}>
              <span className={styles.checkboxTitle}>Appointment Reminder</span>
              <span className={styles.checkboxHint}>Sent to remind the customer of an upcoming appointment.</span>
            </div>
          </label>

          {form.waAppointmentReminder && (
            <div style={{ marginLeft: '1rem', paddingLeft: '1rem', borderLeft: '2px solid var(--border-color)', marginBottom: '1.5rem' }}>
              <DurationField
                label="Reminder advance time"
                hint="How much time before the appointment to send the reminder."
                duration={form.reminderLead}
                onChange={(d) => set('reminderLead', d)}
                error={errors.reminderLead}
              />
            </div>
          )}

          <label className={styles.checkboxLabel}>
            <input
              type="checkbox"
              className={styles.checkbox}
              checked={form.waAppointmentCancelled}
              onChange={(e) => set('waAppointmentCancelled', e.target.checked)}
            />
            <div className={styles.checkboxText}>
              <span className={styles.checkboxTitle}>Appointment Cancelled</span>
              <span className={styles.checkboxHint}>Sent when an appointment is cancelled by either party.</span>
            </div>
          </label>

          <label className={styles.checkboxLabel}>
            <input
              type="checkbox"
              className={styles.checkbox}
              checked={form.waSalonClosure}
              onChange={(e) => set('waSalonClosure', e.target.checked)}
            />
            <div className={styles.checkboxText}>
              <span className={styles.checkboxTitle}>Salon Closure (Reschedule)</span>
              <span className={styles.checkboxHint}>Sent when a salon admin cancels a day, including a link to reschedule.</span>
            </div>
          </label>

          <label className={styles.checkboxLabel}>
            <input
              type="checkbox"
              className={styles.checkbox}
              checked={form.waSalonDeactivated}
              onChange={(e) => set('waSalonDeactivated', e.target.checked)}
            />
            <div className={styles.checkboxText}>
              <span className={styles.checkboxTitle}>Salon Deactivated (Admin)</span>
              <span className={styles.checkboxHint}>Sent to a salon admin when their salon is deactivated, attaching pending dues.</span>
            </div>
          </label>
        </section>
        )}
        </div>

        {/* Stays in view on a long form, and says what is about to happen. */}
        <div
          className={cx(
            styles.saveBar,
            isSaving && styles.saveBarBusy,
            hasErrors && styles.saveBarError,
            isDirty && !hasErrors && !isSaving && styles.saveBarActive,
          )}
        >
          {/* One badge, three tones, so the state is readable from the shape and
              the colour rather than from reading a line of text. The key is
              savePulse: remounting the badge is what replays the pop after each
              write, so a confirmation is a moment you notice, not a colour that
              quietly changed while you were looking at a field. */}
          <span key={savePulse} className={styles.saveStatus}>
            <Badge
              tone={hasErrors ? 'danger' : isSaving ? 'accent' : isDirty ? 'warning' : 'success'}
              pulse={!hasErrors && !isDirty && !isSaving}
            >
              {hasErrors
                ? `${Object.keys(errors).length} field${Object.keys(errors).length === 1 ? '' : 's'} need fixing`
                : isSaving
                  ? 'Saving…'
                  : isDirty
                    ? `${changed.length} unsaved change${changed.length === 1 ? '' : 's'}`
                    : 'All changes saved'}
            </Badge>
          </span>

          <div className={styles.saveActions}>
            {isDirty && (
              <Button variant="ghost" icon="refresh" onClick={discard} disabled={isSaving}>
                Discard
              </Button>
            )}
            <Button
              type="submit"
              variant="primary"
              icon="check"
              loading={isSaving}
              disabled={hasErrors || !isDirty}
            >
              Save changes
            </Button>
          </div>
        </div>
      </form>
    </div>
  );
}
