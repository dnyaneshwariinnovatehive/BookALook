'use client';

import { useState, useEffect } from 'react';
import styles from './page.module.css';

function parseMinutes(minutes: number) {
  if (minutes > 0 && minutes % 1440 === 0) return { value: (minutes / 1440).toString(), unit: 'days' };
  if (minutes > 0 && minutes % 60 === 0) return { value: (minutes / 60).toString(), unit: 'hours' };
  return { value: minutes.toString(), unit: 'minutes' };
}

function toMinutes(value: string, unit: string) {
  const num = parseInt(value, 10);
  if (isNaN(num)) return 0;
  if (unit === 'days') return num * 1440;
  if (unit === 'hours') return num * 60;
  return num;
}

const DurationInput = ({
  label,
  description,
  totalMinutes,
  onChange
}: {
  label: string;
  description: string;
  totalMinutes: number;
  onChange: (minutes: number) => void;
}) => {
  const [value, setValue] = useState('0');
  const [unit, setUnit] = useState('minutes');

  // Initialize state when totalMinutes changes from prop (e.g., initial load)
  useEffect(() => {
    const parsed = parseMinutes(totalMinutes);
    setValue(parsed.value);
    setUnit(parsed.unit);
  }, [totalMinutes]);

  const handleValueChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setValue(e.target.value);
    onChange(toMinutes(e.target.value, unit));
  };

  const handleUnitChange = (e: React.ChangeEvent<HTMLSelectElement>) => {
    setUnit(e.target.value);
    onChange(toMinutes(value, e.target.value));
  };

  return (
    <div className={styles.formGroup}>
      <label>{label}</label>
      <div style={{ display: 'flex', gap: '10px' }}>
        <input
          type="number"
          min="0"
          value={value}
          onChange={handleValueChange}
          required
          style={{ flex: 1 }}
        />
        <select value={unit} onChange={handleUnitChange} style={{ flex: 1, padding: '8px', borderRadius: '4px', border: '1px solid var(--border)' }}>
          <option value="minutes">Minutes</option>
          <option value="hours">Hours</option>
          <option value="days">Days</option>
        </select>
      </div>
      <p style={{ marginTop: '8px', fontSize: '14px', color: 'var(--text-body)' }}>{description}</p>
    </div>
  );
};

export default function PlatformPolicyPage() {
  const [warningDays, setWarningDays] = useState('3');
  const [cancelCutoff, setCancelCutoff] = useState(90);
  const [rescheduleCutoff, setRescheduleCutoff] = useState(90);
  const [startEarly, setStartEarly] = useState(30);
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);

  // Where a scanned salon QR lands, and where that page sends people who do
  // not have the app. Held as settings because every poster already printed
  // follows whatever these say.
  const [publicWebUrl, setPublicWebUrl] = useState('');
  const [androidAppUrl, setAndroidAppUrl] = useState('');
  const [iosAppUrl, setIosAppUrl] = useState('');
  const [androidApkUrl, setAndroidApkUrl] = useState('');

  useEffect(() => {
    fetchData();
  }, []);

  const fetchData = async () => {
    try {
      const res = await fetch('/api/superadmin/settings/policy');
      const data = await res.json();
      if (data.success) {
        setWarningDays(data.settings.subscription_expiry_warning_days?.toString() || '3');
        setCancelCutoff(parseInt(data.settings.cancellation_cutoff_minutes || '90', 10));
        setRescheduleCutoff(parseInt(data.settings.reschedule_cutoff_minutes || '90', 10));
        setStartEarly(parseInt(data.settings.appointment_start_early_minutes || '30', 10));
        setPublicWebUrl(data.settings.public_web_url || '');
        setAndroidAppUrl(data.settings.android_app_url || '');
        setIosAppUrl(data.settings.ios_app_url || '');
        setAndroidApkUrl(data.settings.android_apk_url || '');
      }
    } catch (e) {
      console.error(e);
    } finally {
      setIsLoading(false);
    }
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsSaving(true);
    try {
      const res = await fetch('/api/superadmin/settings/policy', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          subscription_expiry_warning_days: parseInt(warningDays, 10),
          cancellation_cutoff_minutes: cancelCutoff,
          reschedule_cutoff_minutes: rescheduleCutoff,
          appointment_start_early_minutes: startEarly,
          public_web_url: publicWebUrl.trim(),
          // Sent even when blank: clearing one is how SuperAdmin takes a dead
          // store button off the landing page.
          android_app_url: androidAppUrl.trim(),
          ios_app_url: iosAppUrl.trim(),
          android_apk_url: androidApkUrl.trim(),
        })
      });
      if (res.ok) {
        alert('Settings saved successfully');
      } else {
        alert('Failed to save settings');
      }
    } catch (e) {
      console.error(e);
    } finally {
      setIsSaving(false);
    }
  };

  if (isLoading) return <div>Loading...</div>;

  return (
    <div className={styles.container}>
      <h1 className={styles.title}>Platform Policy Settings</h1>
      
      <div className={styles.card}>
        <form onSubmit={handleSave}>
          <div className={styles.formGroup}>
            <label>Subscription Expiry Warning Window (Days)</label>
            <input 
              type="number" 
              min="1"
              max="30"
              value={warningDays}
              onChange={(e) => setWarningDays(e.target.value)}
              required
            />
            <p style={{ marginTop: '8px', fontSize: '14px', color: 'var(--text-body)' }}>
              Number of days before a salon's subscription expires to show the warning banner in the Partner App.
            </p>
          </div>

          <DurationInput
            label="Cancellation Cutoff"
            description="How long before an appointment cancellation is blocked."
            totalMinutes={cancelCutoff}
            onChange={setCancelCutoff}
          />

          <DurationInput
            label="Reschedule Cutoff"
            description="How long before an appointment rescheduling is blocked."
            totalMinutes={rescheduleCutoff}
            onChange={setRescheduleCutoff}
          />

          <DurationInput
            label="Appointment Start Early Allowance"
            description="How early a provider can start an appointment before its scheduled time."
            totalMinutes={startEarly}
            onChange={setStartEarly}
          />
          
          <h2 style={{ fontSize: '1.05rem', fontWeight: 600, margin: '32px 0 4px' }}>
            Salon QR codes &amp; the app
          </h2>
          <p style={{ fontSize: '14px', color: 'var(--text-body)', margin: '0 0 20px', lineHeight: 1.6 }}>
            Every salon&apos;s printed QR code points at the address below. Changing
            it redirects every poster already on a wall — which is the point, but
            get it right before they are printed.
          </p>

          <div className={styles.formGroup}>
            <label>Public website address</label>
            <input
              type="url"
              value={publicWebUrl}
              onChange={(e) => setPublicWebUrl(e.target.value)}
              placeholder="https://bookalook.in"
              required
            />
            <p style={{ marginTop: '8px', fontSize: '14px', color: 'var(--text-body)' }}>
              A scanned salon QR opens <code>{publicWebUrl || 'https://…'}/s/salon-name</code>.
            </p>
          </div>

          <div className={styles.formGroup}>
            <label>Play Store link</label>
            <input
              type="text"
              value={androidAppUrl}
              onChange={(e) => setAndroidAppUrl(e.target.value)}
              placeholder="https://play.google.com/store/apps/details?id=…"
            />
            <p style={{ marginTop: '8px', fontSize: '14px', color: 'var(--text-body)' }}>
              Leave blank until the listing is live. A blank link hides the button
              rather than sending customers to a page that does not exist.
            </p>
          </div>

          <div className={styles.formGroup}>
            <label>App Store link</label>
            <input
              type="text"
              value={iosAppUrl}
              onChange={(e) => setIosAppUrl(e.target.value)}
              placeholder="https://apps.apple.com/in/app/…"
            />
          </div>

          <div className={styles.formGroup}>
            <label>Direct Android build (APK)</label>
            <input
              type="text"
              value={androidApkUrl}
              onChange={(e) => setAndroidApkUrl(e.target.value)}
              placeholder="https://bookalook.in/downloads/bookalook.apk"
            />
            <p style={{ marginTop: '8px', fontSize: '14px', color: 'var(--text-body)' }}>
              Used before the Play Store listing is approved. If both are set, the
              Play Store link wins.
            </p>
          </div>

          <button type="submit" className={styles.button} disabled={isSaving}>
            {isSaving ? 'Saving...' : 'Save Settings'}
          </button>
        </form>
      </div>
    </div>
  );
}
