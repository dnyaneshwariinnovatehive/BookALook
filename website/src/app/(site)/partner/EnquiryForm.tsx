'use client';

import { useEffect, useRef, useState } from 'react';
import {
  BANK_FIELD_LABELS,
  EMPTY_BANK_DETAILS,
  bankDetailsPayload,
  validateBankDetails,
  type BankDetailsInput,
} from '@/lib/bankDetails';
import st from '../site.module.css';
import p from './partner.module.css';

/* ============================================================================
   The salon registration (enquiry) form.

   Moved here from the old landing page with its behaviour untouched: the same
   fields and names, the same required rules, the same city → area loading, the
   same photo checks, the same optional bank details and the same multipart
   POST to /api/enquiries with the same error handling. Only the markup around
   it — labels, layout, styling — is new.
   ============================================================================ */

export default function EnquiryForm() {
  const [formData, setFormData] = useState({
    salon_name: '',
    owner_name: '',
    phone: '',
    state: '',
    city_id: '',
    sub_area_id: '',
    street_address: '',
    pincode: '',
    message: ''
  });
  const [photo, setPhoto] = useState<File | null>(null);
  const [photoPreview, setPhotoPreview] = useState<string | null>(null);
  // Optional: where BookALook should send the salon's settlements. Carried to
  // the salon when it is onboarded; the owner can also add it later in the app.
  const [bank, setBank] = useState<BankDetailsInput>(EMPTY_BANK_DETAILS);
  const [bankErrors, setBankErrors] = useState<Partial<Record<keyof BankDetailsInput, string>>>({});
  const [status, setStatus] = useState<'idle' | 'submitting' | 'success' | 'error'>('idle');
  const [errorMessage, setErrorMessage] = useState('');

  // Presentation only: the form collapses to a short thank-you once it is
  // sent, so bring that message into view rather than leave it off screen.
  const box = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (status === 'success') box.current?.scrollIntoView({ behavior: 'smooth', block: 'center' });
  }, [status]);

  // City and area are picked, never typed. Typed cities left this table holding
  // "navi mumbai" and "Pimpri Chinchwad", which nobody could be matched against.
  const [cities, setCities] = useState<{ id: string; name: string; state: string }[]>([]);
  const [states, setStates] = useState<string[]>([]);
  const [subAreas, setSubAreas] = useState<{ id: string; name: string }[]>([]);
  const [loadingAreas, setLoadingAreas] = useState(false);

  useEffect(() => {
    fetch(`${process.env.NEXT_PUBLIC_BACKEND_URL}/api/cities`, { headers: { Accept: 'application/json' } })
      .then((r) => r.json())
      .then((list) => {
        if (Array.isArray(list)) {
          setCities(list);
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          const uniqueStates = Array.from(new Set(list.map((c: any) => c.state).filter(Boolean))) as string[];
          uniqueStates.sort();
          setStates(uniqueStates);
        }
      })
      .catch(() => setCities([]));
  }, []);

  // Areas belong to a city, so the second dropdown refills whenever the first
  // changes — and clears any area already chosen, which would now be in the
  // wrong city.
  useEffect(() => {
    if (!formData.city_id) {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setSubAreas([]);
      return;
    }

    setLoadingAreas(true);
    fetch(`${process.env.NEXT_PUBLIC_BACKEND_URL}/api/cities/${formData.city_id}/sub-areas`, {
      headers: { Accept: 'application/json' },
    })
      .then((r) => r.json())
      .then((d) => setSubAreas(d?.sub_areas ?? []))
      .catch(() => setSubAreas([]))
      .finally(() => setLoadingAreas(false));
  }, [formData.city_id]);

  const handleInputChange = (
    e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>
  ) => {
    const { name, value } = e.target;
    setFormData(prev => ({
      ...prev,
      [name]: value,
      ...(name === 'state' ? { city_id: '', sub_area_id: '' } : {}),
      ...(name === 'city_id' ? { sub_area_id: '' } : {}),
    }));
  };

  const handlePhotoChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    if (!file.type.startsWith('image/')) {
      setErrorMessage('Please select a valid image file (JPEG, PNG, WebP).');
      return;
    }

    if (file.size > 5 * 1024 * 1024) {
      setErrorMessage('The image size cannot exceed 5MB.');
      return;
    }

    setErrorMessage('');
    setPhoto(file);
    const reader = new FileReader();
    reader.onloadend = () => {
      setPhotoPreview(reader.result as string);
    };
    reader.readAsDataURL(file);
  };

  const handleRemovePhoto = () => {
    setPhoto(null);
    setPhotoPreview(null);
  };

  const filteredCities = formData.state
    ? cities.filter(c => c.state === formData.state)
    : [];

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (status === 'submitting') return;

    const problems = validateBankDetails(bank);
    setBankErrors(problems);
    if (Object.keys(problems).length > 0) {
      setStatus('error');
      setErrorMessage('Please check the bank details, or leave them all empty.');
      return;
    }

    setStatus('submitting');
    setErrorMessage('');

    try {
      const payload = new FormData();
      payload.append('salon_name', formData.salon_name);
      payload.append('owner_name', formData.owner_name);
      payload.append('phone', formData.phone);
      payload.append('city_id', formData.city_id);
      payload.append('sub_area_id', formData.sub_area_id);
      payload.append('street_address', formData.street_address);
      payload.append('pincode', formData.pincode);
      if (formData.message) {
        payload.append('message', formData.message);
      }
      if (photo) {
        payload.append('photo', photo);
      }
      Object.entries(bankDetailsPayload(bank)).forEach(([key, value]) => {
        if (value) payload.append(key, value);
      });

      const response = await fetch(`${process.env.NEXT_PUBLIC_BACKEND_URL}/api/enquiries`, {
        method: 'POST',
        headers: {
          'Accept': 'application/json',
        },
        body: payload,
      });

      if (response.ok) {
        setStatus('success');
        setFormData({ salon_name: '', owner_name: '', phone: '', state: '', city_id: '', sub_area_id: '', street_address: '', pincode: '', message: '' });
        setBank(EMPTY_BANK_DETAILS);
        setBankErrors({});
        setPhoto(null);
        setPhotoPreview(null);
      } else {
        const data = await response.json();
        setStatus('error');
        // Laravel returns a field map; its own wording is more use than a
        // generic failure line.
        const firstError = data?.errors ? Object.values(data.errors)[0] : null;
        if (data?.errors) {
          const fromServer: Partial<Record<keyof BankDetailsInput, string>> = {};
          (Object.keys(EMPTY_BANK_DETAILS) as (keyof BankDetailsInput)[]).forEach((k) => {
            const msg = data.errors[k];
            if (Array.isArray(msg) && msg.length) fromServer[k] = String(msg[0]);
          });
          setBankErrors(fromServer);
        }
        setErrorMessage(
          Array.isArray(firstError)
            ? String(firstError[0])
            : data.message || 'Failed to submit enquiry. Please check your details.'
        );
      }
    } catch {
      setStatus('error');
      setErrorMessage('A network error occurred. Please try again.');
    }
  };

  return (
    <div ref={box} id="enquiry-section" className={`enquiry-section ${p.form}`}>
      <h2 className={p.formTitle}>Partner With Us</h2>
      <p className={p.formSub}>Fill out the form below and our team will get in touch to onboard your salon.</p>

      {status === 'success' ? (
        <div className={p.success} role="status">
          <span aria-hidden="true">✓</span>
          Thank you! Your enquiry has been submitted successfully. Our team will contact you soon.
        </div>
      ) : (
        <form onSubmit={handleSubmit} className={p.fields}>
          {status === 'error' && (
            <div className={`${p.alert} ${p.full}`} role="alert">
              {errorMessage}
            </div>
          )}

          <div className={p.fld}>
            <label htmlFor="enq-salon-name">Salon Name <em>*</em></label>
            <input
              id="enq-salon-name"
              type="text"
              name="salon_name"
              required
              value={formData.salon_name}
              onChange={handleInputChange}
            />
          </div>

          <div className={p.fld}>
            <label htmlFor="enq-owner-name">Owner Name <em>*</em></label>
            <input
              id="enq-owner-name"
              type="text"
              name="owner_name"
              required
              value={formData.owner_name}
              onChange={handleInputChange}
            />
          </div>

          <div className={p.fld}>
            <label htmlFor="enq-phone">Phone Number <em>*</em></label>
            <input
              id="enq-phone"
              type="tel"
              name="phone"
              required
              value={formData.phone}
              onChange={handleInputChange}
            />
          </div>

          <div className={p.fld}>
            <label htmlFor="enq-state">State <em>*</em></label>
            <select
              id="enq-state"
              name="state"
              required
              value={formData.state}
              onChange={handleInputChange}
            >
              <option value="">Select your state</option>
              {states.map((s) => (
                <option key={s} value={s}>{s}</option>
              ))}
            </select>
          </div>

          <div className={p.fld}>
            <label htmlFor="enq-city">City <em>*</em></label>
            <select
              id="enq-city"
              name="city_id"
              required
              disabled={!formData.state}
              value={formData.city_id}
              onChange={handleInputChange}
            >
              <option value="">
                {!formData.state ? 'Choose a state first' : 'Select your city'}
              </option>
              {filteredCities.map((c) => (
                <option key={c.id} value={c.id}>{c.name}</option>
              ))}
            </select>
          </div>

          <div className={p.fld}>
            <label htmlFor="enq-area">Area <em>*</em></label>
            <select
              id="enq-area"
              name="sub_area_id"
              required
              disabled={!formData.city_id || loadingAreas}
              value={formData.sub_area_id}
              onChange={handleInputChange}
            >
              <option value="">
                {!formData.city_id
                  ? 'Choose a city first'
                  : loadingAreas
                    ? 'Loading areas…'
                    : subAreas.length === 0
                      ? 'No areas listed for this city yet'
                      : 'Select your area'}
              </option>
              {subAreas.map((a) => (
                <option key={a.id} value={a.id}>{a.name}</option>
              ))}
            </select>
            <p className={p.hint}>Helps us send someone who already works near you.</p>
          </div>

          <div className={p.fld}>
            <label htmlFor="enq-street">Street Address <em>*</em></label>
            <textarea
              id="enq-street"
              name="street_address"
              required
              rows={2}
              value={formData.street_address}
              onChange={handleInputChange}
            />
          </div>

          <div className={p.fld}>
            <label htmlFor="enq-pincode">Pincode <em>*</em></label>
            <input
              id="enq-pincode"
              type="text"
              name="pincode"
              required
              value={formData.pincode}
              onChange={handleInputChange}
            />
          </div>

          <div className={`${p.fld} ${p.full}`}>
            <label htmlFor="enq-message">Message (Optional)</label>
            <textarea
              id="enq-message"
              name="message"
              rows={3}
              value={formData.message}
              onChange={handleInputChange}
              placeholder="Tell us anything else about your salon..."
            ></textarea>
          </div>

          <div className={`${p.fld} ${p.full}`}>
            <span className={p.label}>Salon Photo (Optional)</span>
            {photoPreview ? (
              <div className={p.preview}>
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={photoPreview} alt="Salon preview" />
                <div>
                  <b>{photo?.name}</b>
                  <small>{(photo ? (photo.size / (1024 * 1024)).toFixed(2) : 0)} MB</small>
                </div>
                <button type="button" onClick={handleRemovePhoto}>Remove</button>
              </div>
            ) : (
              <label className={p.drop}>
                <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                  <rect width="18" height="18" x="3" y="3" rx="2" ry="2" />
                  <circle cx="9" cy="9" r="2" />
                  <path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21" />
                </svg>
                <b>Click to upload a salon photo</b>
                <span>PNG, JPG, or WebP up to 5MB</span>
                <input
                  type="file"
                  accept="image/png,image/jpeg,image/webp"
                  onChange={handlePhotoChange}
                />
              </label>
            )}
          </div>

          <details className={`${p.bank} ${p.full}`} open={Object.keys(bankErrors).length > 0 || undefined}>
            <summary>Bank details for payouts (optional)</summary>
            <p className={p.hint}>
              Where BookALook sends your settlements. You can skip this and add it later in the BookALook Partner app.
            </p>
            <div className={p.bankGrid}>
              {(Object.keys(EMPTY_BANK_DETAILS) as (keyof BankDetailsInput)[]).map((key) => (
                <div key={key} className={p.fld}>
                  <label htmlFor={key}>{BANK_FIELD_LABELS[key]}</label>
                  <input
                    id={key}
                    name={key}
                    type="text"
                    inputMode={key === 'bank_account_number' ? 'numeric' : undefined}
                    autoComplete="off"
                    value={bank[key]}
                    onChange={(e) => {
                      const value = e.target.value;
                      setBank((prev) => ({ ...prev, [key]: value }));
                      if (bankErrors[key]) setBankErrors((prev) => ({ ...prev, [key]: undefined }));
                    }}
                    placeholder={key === 'bank_ifsc' ? 'e.g. HDFC0001234' : key === 'bank_upi_id' ? 'e.g. name@okhdfcbank' : undefined}
                    aria-invalid={Boolean(bankErrors[key])}
                    style={{ textTransform: key === 'bank_ifsc' ? 'uppercase' : undefined }}
                  />
                  {bankErrors[key] && <p className={p.fieldError}>{bankErrors[key]}</p>}
                </div>
              ))}
            </div>
          </details>

          <button
            type="submit"
            disabled={status === 'submitting'}
            className={`${st.btn} ${st.btnLg} ${st.btnBlock} ${p.full}`}
          >
            {status === 'submitting' ? 'Submitting...' : 'Submit Enquiry'}
          </button>
        </form>
      )}
    </div>
  );
}
