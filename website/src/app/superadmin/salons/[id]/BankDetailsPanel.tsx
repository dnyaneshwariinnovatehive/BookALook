'use client';

import { useCallback, useEffect, useState } from 'react';
import { useConfirm } from '@/components/admin/ui';
import {
  BANK_FIELD_LABELS,
  EMPTY_BANK_DETAILS,
  bankDetailsPayload,
  isBankDetailsEmpty,
  validateBankDetails,
  type BankDetailsInput,
} from '@/lib/bankDetails';
import styles from './page.module.css';

interface BankDetails {
  account_holder_name: string | null;
  bank_name: string | null;
  ifsc: string | null;
  upi_id: string | null;
  account_number_last4: string | null;
  account_number_masked: string | null;
  account_number: string | null;
  has_required: boolean;
  has_any: boolean;
  updated_at: string | null;
}

type Errors = Partial<Record<keyof BankDetailsInput, string>>;

/**
 * A salon's bank details, as SuperAdmin pays its settlements.
 *
 * The account number is masked until "Show full number" is pressed — that
 * reveal is recorded in the audit log by the server. Saving asks first, and
 * says so when it would replace details already on file.
 */
export default function BankDetailsPanel({
  salonId,
  salonName,
  onDirtyChange,
}: {
  salonId: string;
  salonName: string;
  onDirtyChange?: (dirty: boolean) => void;
}) {
  const [details, setDetails] = useState<BankDetails | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState('');
  const [form, setForm] = useState<BankDetailsInput>(EMPTY_BANK_DETAILS);
  const [errors, setErrors] = useState<Errors>({});
  const [saving, setSaving] = useState(false);
  const [revealing, setRevealing] = useState(false);
  const [notice, setNotice] = useState<{ kind: 'ok' | 'error'; text: string } | null>(null);
  const [dirty, setDirty] = useState(false);
  const [confirm, confirmDialog] = useConfirm();

  const fillForm = (d: BankDetails) =>
    setForm({
      bank_account_holder_name: d.account_holder_name ?? '',
      bank_name: d.bank_name ?? '',
      bank_account_number: '',
      bank_ifsc: d.ifsc ?? '',
      bank_upi_id: d.upi_id ?? '',
    });

  const load = useCallback(async () => {
    setLoading(true);
    setLoadError('');
    try {
      const res = await fetch(`/api/proxy/superadmin/salons/${salonId}/bank-details`, { cache: 'no-store' });
      const json = await res.json();
      if (!res.ok || !json.success) throw new Error(json.message || 'Could not load bank details.');
      setDetails(json.bank_details);
      fillForm(json.bank_details);
    } catch (e) {
      setLoadError(e instanceof Error ? e.message : 'Could not load bank details.');
    } finally {
      setLoading(false);
    }
  }, [salonId]);

  useEffect(() => {
    const timer = setTimeout(load, 0);
    return () => clearTimeout(timer);
  }, [load]);

  useEffect(() => {
    onDirtyChange?.(dirty);
    if (!dirty) return;
    // Closing the tab or reloading with unsaved edits asks the browser to warn.
    const warn = (e: BeforeUnloadEvent) => {
      e.preventDefault();
      e.returnValue = '';
    };
    window.addEventListener('beforeunload', warn);
    return () => window.removeEventListener('beforeunload', warn);
  }, [dirty, onDirtyChange]);

  const change = (key: keyof BankDetailsInput, value: string) => {
    setForm((prev) => ({ ...prev, [key]: value }));
    setDirty(true);
    setNotice(null);
    if (errors[key]) setErrors((prev) => ({ ...prev, [key]: undefined }));
  };

  const reveal = async () => {
    const ok = await confirm({
      title: 'Show the full account number?',
      body: `Viewing ${salonName}'s full account number is recorded in the audit log.`,
      confirmLabel: 'Show number',
    });
    if (!ok) return;
    setRevealing(true);
    try {
      const res = await fetch(`/api/proxy/superadmin/salons/${salonId}/bank-details?reveal=1`, { cache: 'no-store' });
      const json = await res.json();
      if (!res.ok || !json.success) throw new Error(json.message || 'Could not show the number.');
      setDetails(json.bank_details);
    } catch (e) {
      setNotice({ kind: 'error', text: e instanceof Error ? e.message : 'Could not show the number.' });
    } finally {
      setRevealing(false);
    }
  };

  const save = async () => {
    if (saving || !details) return;
    setNotice(null);

    const problems = validateBankDetails(form, { hasSavedAccount: Boolean(details.account_number_last4) });
    setErrors(problems);
    if (Object.keys(problems).length > 0) return;
    if (isBankDetailsEmpty(form) && !details.has_any) return;

    const replacing = details.has_any;
    const ok = await confirm(
      replacing
        ? {
            title: 'Replace these bank details?',
            body: `${salonName}'s saved details (${details.bank_name ?? 'bank'} ${details.account_number_masked ?? ''}) will be replaced. Future settlements will be paid to the new details.`,
            confirmLabel: 'Replace details',
            tone: 'danger',
          }
        : {
            title: 'Save these bank details?',
            body: `Settlements for ${salonName} will be paid to this account.`,
            confirmLabel: 'Save details',
          },
    );
    if (!ok) return;

    setSaving(true);
    try {
      const body = { ...bankDetailsPayload(form), bank_upi_id: form.bank_upi_id.trim() };
      const res = await fetch(`/api/proxy/superadmin/salons/${salonId}/bank-details`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify(body),
      });
      const json = await res.json().catch(() => ({}));
      if (!res.ok) {
        if (json?.errors) {
          const fromServer: Errors = {};
          (Object.keys(EMPTY_BANK_DETAILS) as (keyof BankDetailsInput)[]).forEach((k) => {
            if (Array.isArray(json.errors[k])) fromServer[k] = String(json.errors[k][0]);
          });
          setErrors(fromServer);
        }
        throw new Error(json?.message || 'Could not save the bank details.');
      }
      setDetails(json.bank_details);
      fillForm(json.bank_details);
      setDirty(false);
      setNotice({ kind: 'ok', text: replacing ? 'Bank details updated.' : 'Bank details saved.' });
    } catch (e) {
      setNotice({ kind: 'error', text: e instanceof Error ? e.message : 'Could not save the bank details.' });
    } finally {
      setSaving(false);
    }
  };

  const discard = async () => {
    const ok = await confirm({
      title: 'Discard your changes?',
      body: 'The edits you made to the bank details will be lost.',
      confirmLabel: 'Discard',
      tone: 'danger',
    });
    if (!ok || !details) return;
    fillForm(details);
    setErrors({});
    setDirty(false);
  };

  if (loading) return <div className={styles.card}>Loading bank details…</div>;
  if (loadError) return <div className={styles.card}>{loadError}</div>;
  if (!details) return null;

  return (
    <div className={styles.card}>
      {confirmDialog}
      <h2 className={styles.sectionTitle}>Bank details for settlements</h2>

      {!details.has_required && (
        <p className={styles.bankMissing}>
          Not complete — {details.has_any ? 'some details are missing.' : 'no bank account on file.'} Settlements cannot be paid to this salon until the account holder, bank, account number and IFSC are added.
        </p>
      )}

      {details.has_any && (
        <div className={styles.bankSummary}>
          <div className={styles.infoGroup}>
            <span className={styles.label}>Account</span>
            <div className={styles.value}>
              <span className={styles.bankNumber}>{details.account_number ?? details.account_number_masked ?? '—'}</span>
              {details.account_number_last4 && !details.account_number && (
                <button type="button" className={styles.bankLink} onClick={reveal} disabled={revealing}>
                  {revealing ? 'Showing…' : 'Show full number'}
                </button>
              )}
            </div>
          </div>
          <div className={styles.infoGroup}>
            <span className={styles.label}>Holder · Bank · IFSC</span>
            <div className={styles.value}>
              {[details.account_holder_name, details.bank_name, details.ifsc].filter(Boolean).join(' · ') || '—'}
            </div>
          </div>
          <div className={styles.infoGroup}>
            <span className={styles.label}>UPI</span>
            <div className={styles.value}>{details.upi_id || '—'}</div>
          </div>
          {details.updated_at && (
            <p className={styles.assignNote}>Last changed {new Date(details.updated_at).toLocaleString('en-IN')}</p>
          )}
        </div>
      )}

      <h3 className={styles.bankFormTitle}>{details.has_any ? 'Update details' : 'Add details'}</h3>
      <div className={styles.bankForm}>
        {(Object.keys(EMPTY_BANK_DETAILS) as (keyof BankDetailsInput)[]).map((key) => (
          <label key={key} className={styles.bankField}>
            <span className={styles.label}>
              {key === 'bank_account_number' && details.account_number_last4 ? 'New account number' : BANK_FIELD_LABELS[key]}
            </span>
            <input
              className={styles.assignSelect}
              value={form[key]}
              onChange={(e) => change(key, e.target.value)}
              inputMode={key === 'bank_account_number' ? 'numeric' : undefined}
              autoComplete="off"
              placeholder={
                key === 'bank_account_number' && details.account_number_last4
                  ? `Leave empty to keep ${details.account_number_masked}`
                  : key === 'bank_ifsc'
                    ? 'e.g. HDFC0001234'
                    : key === 'bank_upi_id'
                      ? 'e.g. name@okhdfcbank'
                      : undefined
              }
              aria-invalid={Boolean(errors[key])}
              disabled={saving}
            />
            {errors[key] && <span className={styles.bankError}>{errors[key]}</span>}
          </label>
        ))}
      </div>

      <div className={styles.assignRow}>
        <button type="button" className={styles.assignButton} onClick={save} disabled={saving || !dirty}>
          {saving ? 'Saving…' : details.has_any ? 'Update bank details' : 'Save bank details'}
        </button>
        {dirty && (
          <button type="button" className={styles.bankLink} onClick={discard} disabled={saving}>
            Discard changes
          </button>
        )}
      </div>

      {notice && (
        <p className={notice.kind === 'ok' ? styles.bankOk : styles.bankError} role={notice.kind === 'error' ? 'alert' : 'status'}>
          {notice.text}
        </p>
      )}
    </div>
  );
}
