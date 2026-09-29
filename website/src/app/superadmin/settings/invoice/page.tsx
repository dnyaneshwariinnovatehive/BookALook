'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
import {
  Alert, Button, Card, Field, PageHeader, Segmented, cx, ui,
} from '@/components/admin/ui';
import { uploadImage } from '@/lib/cloudinary';
import s from './page.module.css';

/**
 * Invoice format.
 *
 * Everything on this page is branding, and branding is a visual decision, so
 * the page is built around showing you the document while you change it. The
 * preview on the right is driven by exactly the same values the server will
 * print — including the show/hide switches — so a section switched off
 * disappears from the preview rather than from a description of itself.
 *
 * The form is rendered from the schema the API returns rather than from a
 * hand-written list of inputs. That means adding a printable section is a
 * change to one PHP array, and this page picks it up with no edit here — and,
 * more importantly, cannot drift out of step with what the server accepts.
 *
 * Every field is held as the value the user is actually editing — a string for
 * text, a number for the sequence padding, a real boolean for a switch — and
 * nothing is derived back out from the parent on each keystroke. Deriving is
 * what makes a field rewrite itself mid-word.
 */

type FieldKind = 'text' | 'textarea' | 'number' | 'color' | 'switch' | 'image';

interface FieldSpec {
  label: string;
  kind: FieldKind;
  group: string;
  hint?: string;
}

type Schema = Record<string, FieldSpec>;
type Form = Record<string, string | number | boolean>;

/** Presentation only — which groups exist, and in what order. */
const GROUPS: { id: string; title: string; subtitle: string }[] = [
  { id: 'issuer', title: 'Issuer', subtitle: 'Who the invoice is from, printed in the letterhead.' },
  { id: 'branding', title: 'Branding', subtitle: 'How the document looks. The accent colour drives the rules and the balance due.' },
  { id: 'numbering', title: 'Numbering', subtitle: 'The reference a customer quotes when they call about a booking.' },
  { id: 'sections', title: 'Sections', subtitle: 'What appears on the document. A section nobody has filled in stays switched off rather than printing a heading over nothing.' },
  { id: 'settlement', title: 'Settlement Statement', subtitle: 'The statement a salon owner is given when a cycle of earnings is paid out. It reuses the issuer, branding and terms above — only what makes a settlement different is set here.' },
];

/** A stand-in appointment, so the preview has something real to show. */
const SAMPLE = {
  billTo: 'Priya Sharma',
  salon: 'Studio Nine',
  provider: 'Aarti Verma',
  slot: 'Tue, 14 Oct 2026',
  time: '10:30 AM',
  lines: [
    { name: 'Signature Haircut', kind: 'service', price: 850, duration: 45 },
    { name: 'Deep Conditioning', kind: 'service', price: 600, duration: 30 },
    { name: 'Bridal Styling Package', kind: 'package', price: 3200, duration: 90 },
  ],
  total: 4650,
  advance: 1500,
};

/**
 * A stand-in settlement cycle.
 *
 * The figures are a worked example rather than a random set, because a preview
 * only teaches anything if the arithmetic visibly works. These follow the same
 * rule the server uses — net is advances held, less commission, less refunds,
 * plus coins settled — so every number here can be checked by hand:
 *
 *   12,000 advances held − 10,000 commission (25% of 40,000 billed) + 500 coins
 *   = 2,500 paid
 *
 * The coins row is a credit, not a deduction: settling them gives the salon
 * part of the commission back, which is why they are added to the net.
 */
const SETTLEMENT_SAMPLE = {
  salon: 'Studio Nine',
  period: '1 – 31 Oct 2026',
  rhythm: 'Monthly',
  appointments: 64,
  billed: 40000,
  advances: 12000,
  commissionRate: 25,
  commission: 10000,
  walletRedeemed: 500,
  net: 2500,
};

export default function InvoiceFormatPage() {
  const [form, setForm] = useState<Form>({});
  // What the server last confirmed. "Changed" always means changed from what
  // is actually stored, which is why this is state and not a ref — a ref
  // mutation is invisible to React and the bar would keep claiming unsaved
  // changes after a save.
  const [saved, setSaved] = useState<Form>({});
  const [schema, setSchema] = useState<Schema>({});
  const [issuedCount, setIssuedCount] = useState(0);
  const [settlementIssuedCount, setSettlementIssuedCount] = useState(0);
  // Which document the preview is showing. Two documents share one letterhead
  // but number separately, so whichever is on screen is the one being reasoned
  // about — a preview that blended both would be of neither.
  const [preview, setPreview] = useState<'invoice' | 'settlement'>('invoice');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [uploadError, setUploadError] = useState<string | null>(null);
  const [banner, setBanner] = useState<{ tone: 'ok' | 'bad'; text: string } | null>(null);

  const fileInput = useRef<HTMLInputElement>(null);

  // Fetched inside the effect rather than through a `load` callback the effect
  // calls, so nothing setStates synchronously in the effect body, and so a
  // response that lands after the user has navigated away is dropped instead of
  // writing to a component that no longer exists.
  useEffect(() => {
    let cancelled = false;

    (async () => {
      try {
        const res = await fetch('/api/superadmin/settings/invoice', { cache: 'no-store' });
        const data = await res.json();
        if (cancelled) return;

        if (!data.success) throw new Error(data.message || 'Could not load the invoice format');

        setSchema(data.schema ?? {});
        setIssuedCount(Number(data.issued_count ?? 0));
        setSettlementIssuedCount(Number(data.settlement_issued_count ?? 0));
        setSaved(data.settings ?? {});
        setForm(data.settings ?? {});
      } catch (e) {
        if (!cancelled) {
          setBanner({
            tone: 'bad',
            text: e instanceof Error ? e.message : 'Could not load the invoice format',
          });
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();

    return () => {
      cancelled = true;
    };
  }, []);

  const set = (key: string, value: string | number | boolean) => {
    setForm((prev) => ({ ...prev, [key]: value }));
    // A "Saved." notice sitting above fields that have been edited since is
    // worse than no notice at all.
    setBanner((prev) => (prev?.tone === 'ok' ? null : prev));
  };

  /**
   * Send the picked file to Cloudinary, then store the URL it returns.
   *
   * The upload is unsigned and goes browser → Cloudinary directly, so no file
   * is handled by this server. The URL is only committed to the form on
   * success: a failed upload must leave whatever logo is already saved in
   * place, otherwise a transient network blip would silently blank the
   * letterhead.
   */
  const handleImagePick = async (key: string, file: File | undefined) => {
    if (!file) return;

    setUploadError(null);
    setUploading(true);

    try {
      const url = await uploadImage(file);
      set(key, url);
    } catch (e) {
      setUploadError(e instanceof Error ? e.message : 'Upload failed. Please try again.');
    } finally {
      setUploading(false);
      // Let the same file be chosen again after a failure, which the input
      // would otherwise silently ignore because its value never changed.
      if (fileInput.current) fileInput.current.value = '';
    }
  };

  const changed = useMemo(
    () => Object.keys(form).filter((key) => form[key] !== saved[key]),
    [form, saved],
  );
  const isDirty = changed.length > 0;

  // Nothing here is worth losing to a stray tab close.
  useEffect(() => {
    if (!isDirty) return;
    const warn = (e: BeforeUnloadEvent) => e.preventDefault();
    window.addEventListener('beforeunload', warn);
    return () => window.removeEventListener('beforeunload', warn);
  }, [isDirty]);

  const handleSave = async () => {
    if (!isDirty || saving) return;

    setSaving(true);
    setBanner(null);

    // Only what actually moved. The audit log records this change, and an
    // entry listing every field when one was touched makes that log useless.
    const body = Object.fromEntries(changed.map((key) => [key, form[key]]));

    try {
      const res = await fetch('/api/superadmin/settings/invoice', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });
      const data = await res.json().catch(() => ({}));

      if (!res.ok) {
        // Laravel returns a field map on 422; its own wording beats "Failed".
        const first = data?.errors ? Object.values(data.errors)[0] : null;
        throw new Error(
          Array.isArray(first) ? String(first[0]) : data?.message || 'Could not save the invoice format',
        );
      }

      // Trust the server's echo rather than local state — it casts, trims and
      // defaults, and a preview showing what we hoped for is worse than none.
      const next = data.settings ?? form;
      setSaved(next);
      setForm(next);
      setBanner({ tone: 'ok', text: `Saved. ${changed.length} field${changed.length === 1 ? '' : 's'} updated.` });
    } catch (err) {
      setBanner({ tone: 'bad', text: err instanceof Error ? err.message : 'Could not save the invoice format' });
    } finally {
      setSaving(false);
    }
  };

  const discard = () => {
    setForm(saved);
    setBanner(null);
  };

  const text = (key: string) => String(form[key] ?? '');
  const flag = (key: string) => form[key] === true || form[key] === 'true' || form[key] === '1';

  const renderField = (key: string, spec: FieldSpec) => {
    switch (spec.kind) {
      case 'image':
        return (
          <Field key={key} label={spec.label} hint={spec.hint}>
            <div className={s.imageRow}>
              <div className={s.imageThumb}>
                {text(key) ? (
                  /* Plain background-image, not next/image: the host is whatever
                     Cloudinary handed back and the page may be showing a logo
                     uploaded seconds ago, so there is nothing to optimise
                     against. encodeURI closes off the url() injection the
                     preview below guards against. */
                  <span
                    className={s.imageThumbFill}
                    style={{ backgroundImage: `url("${encodeURI(text(key))}")` }}
                    aria-hidden="true"
                  />
                ) : (
                  <span className={s.imageThumbEmpty}>None</span>
                )}
              </div>

              <div className={s.imageActions}>
                <input
                  ref={fileInput}
                  type="file"
                  accept="image/png,image/jpeg,image/svg+xml,image/webp"
                  className={s.imageInput}
                  disabled={uploading}
                  onChange={(e) => handleImagePick(key, e.target.files?.[0])}
                />
                <div className={s.imageButtons}>
                  <Button
                    variant="secondary"
                    size="sm"
                    disabled={uploading}
                    onClick={() => fileInput.current?.click()}
                  >
                    {uploading ? 'Uploading…' : text(key) ? 'Replace image' : 'Upload image'}
                  </Button>
                  {text(key) && (
                    <Button
                      variant="ghost"
                      size="sm"
                      disabled={uploading}
                      onClick={() => set(key, '')}
                    >
                      Remove
                    </Button>
                  )}
                </div>
                {text(key) && <div className={s.imageUrl}>{text(key)}</div>}
                {uploadError && (
                  <div className={s.imageError} role="alert">{uploadError}</div>
                )}
              </div>
            </div>
          </Field>
        );

      case 'switch':
        return (
          <label key={key} className={cx(ui.check, flag(key) && ui.checkOn)}>
            <input
              type="checkbox"
              checked={flag(key)}
              onChange={(e) => set(key, e.target.checked)}
            />
            {spec.label}
          </label>
        );

      case 'textarea':
        return (
          <Field key={key} label={spec.label} hint={spec.hint}>
            <textarea
              className={cx(ui.control, s.textarea)}
              value={text(key)}
              placeholder="Leave blank to leave it off the invoice"
              onChange={(e) => set(key, e.target.value)}
            />
          </Field>
        );

      case 'color':
        return (
          <Field key={key} label={spec.label} hint={spec.hint}>
            <div className={s.colorRow}>
              <input
                type="color"
                className={s.swatch}
                value={/^#[0-9a-fA-F]{6}$/.test(text(key)) ? text(key) : '#B08D57'}
                aria-label={`${spec.label} swatch`}
                onChange={(e) => set(key, e.target.value.toUpperCase())}
              />
              <input
                className={ui.control}
                value={text(key)}
                spellCheck={false}
                onChange={(e) => set(key, e.target.value)}
              />
            </div>
          </Field>
        );

      case 'number':
        return (
          <Field key={key} label={spec.label} hint={spec.hint}>
            <input
              type="number"
              className={ui.control}
              min={1}
              max={12}
              value={text(key)}
              onChange={(e) => set(key, e.target.value === '' ? '' : Number(e.target.value))}
            />
          </Field>
        );

      default:
        return (
          <Field key={key} label={spec.label} hint={spec.hint}>
            <input
              className={ui.control}
              value={text(key)}
              onChange={(e) => set(key, e.target.value)}
            />
          </Field>
        );
    }
  };

  if (loading) {
    return <p style={{ padding: 24 }}>Loading the invoice format…</p>;
  }

  // A preview is only honest if it hides exactly what the switches hide.
  const accent = /^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/.test(text('invoice_accent_color'))
    ? text('invoice_accent_color')
    : '#B08D57';
  const prefix = text('invoice_number_prefix').toUpperCase() || 'BAL';
  const padding = Math.max(1, Math.min(12, Number(form.invoice_number_padding) || 5));
  const showLogo = flag('invoice_show_logo');
  const showAddress = flag('invoice_show_business_address');
  const showTax = flag('invoice_show_tax_id');
  const showProvider = flag('invoice_show_provider');
  const showDuration = flag('invoice_show_duration_column');
  const showTerms = flag('invoice_show_terms');
  const showBalance = flag('invoice_show_balance_due');
  const logoUrl = text('invoice_logo_url');
  const businessName = text('invoice_business_name');
  const address = text('invoice_business_address');
  const taxLabel = text('invoice_tax_id_label');
  const taxId = text('invoice_tax_id');
  const footerNote = text('invoice_footer_note');
  const terms = text('invoice_terms');
  const balance = Math.max(0, SAMPLE.total - SAMPLE.advance);

  const settlementPrefix = text('settlement_invoice_number_prefix').toUpperCase() || 'SET';
  const settlementPadding = Math.max(1, Math.min(12, Number(form.settlement_invoice_number_padding) || 5));
  const settlementTitle = text('settlement_invoice_document_title') || 'Settlement Statement';
  const settlementFooter = text('settlement_invoice_footer_note');
  const showBilledRevenue = flag('settlement_invoice_show_billed_revenue');
  const showAppointmentsCount = flag('settlement_invoice_show_appointments_count');
  const rupees = (n: number) => `\u20b9${n.toLocaleString('en-IN')}`;
  const year = new Date().getFullYear();

  return (
    <div>
      <PageHeader
        eyebrow="Platform"
        title="Invoice Format"
        subtitle="How the invoice a customer receives after booking is laid out and branded, and the statement a salon owner is given when earnings are settled. Changes apply to documents issued from now on — anything already issued keeps the format it was created with."
        actions={
          issuedCount > 0 || settlementIssuedCount > 0 ? (
            <span className={s.countNote}>
              {[
                issuedCount > 0
                  ? `${issuedCount.toLocaleString('en-IN')} invoice${issuedCount === 1 ? '' : 's'}`
                  : null,
                settlementIssuedCount > 0
                  ? `${settlementIssuedCount.toLocaleString('en-IN')} statement${settlementIssuedCount === 1 ? '' : 's'}`
                  : null,
              ]
                .filter(Boolean)
                .join(' \u00b7 ')}{' '}
              issued
            </span>
          ) : null
        }
      />

      {banner && <Alert tone={banner.tone === 'ok' ? 'success' : 'error'}>{banner.text}</Alert>}

      <div className={s.layout}>
        <div className={s.form}>
          {GROUPS.map((group) => {
            const keys = Object.keys(schema).filter((key) => schema[key].group === group.id);
            if (!keys.length) return null;

            return (
              <Card
                key={group.id}
                title={group.title}
                subtitle={group.subtitle}
                padded
              >
                <div className={keys.some((k) => schema[k].kind === 'switch') ? s.checks : undefined}>
                  {keys.map((key) => renderField(key, schema[key]))}
                </div>
              </Card>
            );
          })}

          <div className={s.actions}>
            <Button variant="primary" icon="check" loading={saving} disabled={!isDirty} onClick={handleSave}>
              Save format
            </Button>
            <Button variant="ghost" disabled={!isDirty || saving} onClick={discard}>
              Discard
            </Button>
            <span className={s.actionsSpacer} />
            {isDirty && (
              <span className={s.dirtyNote}>
                {changed.length} unsaved change{changed.length === 1 ? '' : 's'}
              </span>
            )}
          </div>
        </div>

        <div className={s.previewSticky}>
          <Card
            title="Preview"
            subtitle="A sample document, using the values above."
            actions={
              <Segmented
                ariaLabel="Document to preview"
                value={preview}
                onChange={setPreview}
                options={[
                  { value: 'invoice', label: 'Invoice' },
                  { value: 'settlement', label: 'Settlement' },
                ]}
              />
            }
            padded
          >
            {preview === 'invoice' ? (
            <div className={s.paper} style={{ ['--pv-accent' as string]: accent }}>
              <div className={s.previewHead}>
                <div className={s.previewBrand}>
                  {showLogo && logoUrl && (
                    <span
                      className={s.previewLogo}
                      /* encodeURI, not a plain interpolation: a logo URL is
                         SuperAdmin-supplied, and an unescaped ")" would close
                         the url() early and let the rest of the value become
                         arbitrary CSS. encodeURI percent-encodes parens. */
                      style={{ backgroundImage: `url("${encodeURI(logoUrl)}")` }}
                      aria-hidden="true"
                    />
                  )}

                  <div>
                    <div className={s.previewName}>{businessName || 'Business name'}</div>
                    {showAddress && address && <div className={s.previewMuted}>{address}</div>}
                    {showTax && taxId && taxLabel && (
                      <div className={s.previewMuted}><strong>{taxLabel}:</strong> {taxId}</div>
                    )}
                  </div>
                </div>
                <div className={s.previewRight}>
                  <div className={s.previewDoc}>Invoice</div>
                  <div className={s.previewNumber}>
                    {prefix}-{new Date().getFullYear()}-{String(1).padStart(padding, '0')}
                  </div>
                  <div className={s.previewMuted}>Issued 28 Sep 2026</div>
                </div>
              </div>

              <div className={s.previewCols}>
                <div className={s.previewCol}>
                  <div className={s.previewLabel}>Billed to</div>
                  <div className={s.previewStrong}>{SAMPLE.billTo}</div>
                  <div className={s.previewMuted}>+91 98765 43210</div>
                </div>
                <div className={s.previewCol}>
                  <div className={s.previewLabel}>Appointment</div>
                  <div className={s.previewStrong}>{SAMPLE.salon}</div>
                  {showProvider && <div className={s.previewMuted}>{SAMPLE.provider}</div>}
                  <div className={s.previewMuted}>{SAMPLE.slot} · {SAMPLE.time}</div>
                </div>
              </div>

              <table className={s.previewTable}>
                <thead>
                  <tr>
                    <th>Service</th>
                    {showDuration && <th className={s.previewNum}>Duration</th>}
                    <th className={s.previewNum}>Amount</th>
                  </tr>
                </thead>
                <tbody>
                  {SAMPLE.lines.map((line) => (
                    <tr key={line.name}>
                      <td>
                        <span className={s.previewStrong}>{line.name}</span>
                        {line.kind === 'package' && (
                          <span className={s.previewTag}>Package</span>
                        )}
                      </td>
                      {showDuration && <td className={s.previewNum}>{line.duration} min</td>}
                      <td className={s.previewNum}>₹{line.price.toLocaleString('en-IN')}</td>
                    </tr>
                  ))}
                </tbody>
              </table>

              <div className={s.previewTotals}>
                <table className={s.previewTotalsTable}>
                  <tbody>
                    <tr>
                      <td>Total</td>
                      <td className={s.previewNum}>₹{SAMPLE.total.toLocaleString('en-IN')}</td>
                    </tr>
                    <tr className={s.previewPaid}>
                      <td>Advance paid</td>
                      <td className={s.previewNum}>&minus; ₹{SAMPLE.advance.toLocaleString('en-IN')}</td>
                    </tr>
                    {showBalance && (
                      <tr className={s.previewDue}>
                        <td>Balance due at salon</td>
                        <td className={s.previewNum}>₹{balance.toLocaleString('en-IN')}</td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>

              <div className={s.previewFoot}>
                {showTerms && terms
                  ? <div style={{ whiteSpace: 'pre-line' }}>{terms}</div>
                  : showTerms
                    ? <span className={s.previewEmpty}>Terms and conditions would print here.</span>
                    : null}
                {footerNote && <div className={s.previewNote}>{footerNote}</div>}
              </div>
            </div>
            ) : (
            /* The settlement statement reuses the same letterhead, accent and
               terms as the customer invoice — the server reads the same
               settings — so only the body and the numbering differ here. */
            <div className={s.paper} style={{ ['--pv-accent' as string]: accent }}>
              <div className={s.previewHead}>
                <div className={s.previewBrand}>
                  {showLogo && logoUrl && (
                    <span
                      className={s.previewLogo}
                      /* Same reasoning as the invoice preview above. */
                      style={{ backgroundImage: `url("${encodeURI(logoUrl)}")` }}
                      aria-hidden="true"
                    />
                  )}

                  <div>
                    <div className={s.previewName}>{businessName || 'Business name'}</div>
                    {showAddress && address && <div className={s.previewMuted}>{address}</div>}
                    {showTax && taxId && taxLabel && (
                      <div className={s.previewMuted}><strong>{taxLabel}:</strong> {taxId}</div>
                    )}
                  </div>
                </div>
                <div className={s.previewRight}>
                  <div className={s.previewDoc}>{settlementTitle}</div>
                  <div className={s.previewNumber}>
                    {settlementPrefix}-{year}-{String(1).padStart(settlementPadding, '0')}
                  </div>
                  <div className={s.previewMuted}>Issued 1 Nov 2026</div>
                </div>
              </div>

              <div className={s.previewCols}>
                <div className={s.previewCol}>
                  <div className={s.previewLabel}>Salon</div>
                  <div className={s.previewStrong}>{SETTLEMENT_SAMPLE.salon}</div>
                  <div className={s.previewMuted}>Settled {SETTLEMENT_SAMPLE.rhythm.toLowerCase()}</div>
                </div>
                <div className={s.previewCol}>
                  <div className={s.previewLabel}>Period</div>
                  <div className={s.previewStrong}>{SETTLEMENT_SAMPLE.period}</div>
                  {showAppointmentsCount && (
                    <div className={s.previewMuted}>
                      {SETTLEMENT_SAMPLE.appointments} completed appointments
                    </div>
                  )}
                </div>
              </div>

              <table className={s.previewTable}>
                <thead>
                  <tr>
                    <th>Statement</th>
                    <th className={s.previewNum}>Amount</th>
                  </tr>
                </thead>
                <tbody>
                  {showBilledRevenue && (
                    <tr>
                      <td>
                        <span className={s.previewStrong}>Total billed by the salon</span>
                        {/* The count is its own switch, so it is not repeated
                            here when that switch is off — the preview would
                            then be hiding something the document shows. */}
                        {showAppointmentsCount && (
                          <span className={s.previewMuted} style={{ display: 'block' }}>
                            Across {SETTLEMENT_SAMPLE.appointments} completed appointments
                          </span>
                        )}
                      </td>
                      <td className={s.previewNum}>{rupees(SETTLEMENT_SAMPLE.billed)}</td>
                    </tr>
                  )}
                  <tr>
                    <td>
                      <span className={s.previewStrong}>Advance collected online</span>
                      <span className={s.previewMuted} style={{ display: 'block' }}>
                        Held by BookALook and released in this cycle
                      </span>
                    </td>
                    <td className={s.previewNum}>{rupees(SETTLEMENT_SAMPLE.advances)}</td>
                  </tr>
                  <tr>
                    <td>
                      <span className={s.previewStrong}>Commission deducted</span>
                      <span className={s.previewMuted} style={{ display: 'block' }}>
                        {SETTLEMENT_SAMPLE.commissionRate}% of billed services
                      </span>
                    </td>
                    <td className={s.previewNum}>&minus; {rupees(SETTLEMENT_SAMPLE.commission)}</td>
                  </tr>
                  <tr>
                    <td>
                      <span className={s.previewStrong}>Wallet balance settled</span>
                      <span className={s.previewMuted} style={{ display: 'block' }}>
                        Coins from bookings, credited back against commission
                      </span>
                    </td>
                    {/* No "+" here: the printed statement shows a bare positive
                        figure, and a preview that adds a sign the document
                        lacks is worse than no preview. */}
                    <td className={s.previewNum}>{rupees(SETTLEMENT_SAMPLE.walletRedeemed)}</td>
                  </tr>
                </tbody>
              </table>

              <div className={s.previewTotals}>
                <table className={s.previewTotalsTable}>
                  <tbody>
                    <tr className={s.previewDue}>
                      <td>Net paid to salon</td>
                      <td className={s.previewNum}>{rupees(SETTLEMENT_SAMPLE.net)}</td>
                    </tr>
                  </tbody>
                </table>
              </div>

              <div className={s.previewFoot}>
                {showTerms && terms
                  ? <div style={{ whiteSpace: 'pre-line' }}>{terms}</div>
                  : showTerms
                    ? <span className={s.previewEmpty}>Terms and conditions would print here.</span>
                    : null}
                {settlementFooter && <div className={s.previewNote}>{settlementFooter}</div>}
                {footerNote && <div className={s.previewNote}>{footerNote}</div>}
              </div>
            </div>
            )}
          </Card>
        </div>
      </div>
    </div>
  );
}
