"use client";

import Image from 'next/image';
import Link from 'next/link';
import { useEffect, useState } from 'react';
import './globals.css';

export default function LandingPage() {
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
  const [status, setStatus] = useState<'idle' | 'submitting' | 'success' | 'error'>('idle');
  const [errorMessage, setErrorMessage] = useState('');

  // City and area are picked, never typed. Typed cities left this table holding
  // "navi mumbai" and "Pimpri Chinchwad", which no collaborator could be
  // matched against.
  const [cities, setCities] = useState<{ id: string; name: string; state: string }[]>([]);
  const [states, setStates] = useState<string[]>([]);
  const [subAreas, setSubAreas] = useState<{ id: string; name: string }[]>([]);
  const [loadingAreas, setLoadingAreas] = useState(false);

  useEffect(() => {
    fetch('http://localhost:8000/api/cities', { headers: { Accept: 'application/json' } })
      .then((r) => r.json())
      .then((list) => {
        if (Array.isArray(list)) {
          setCities(list);
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
      setSubAreas([]);
      return;
    }

    setLoadingAreas(true);
    fetch(`http://localhost:8000/api/cities/${formData.city_id}/sub-areas`, {
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

  const filteredCities = formData.state 
    ? cities.filter(c => c.state === formData.state) 
    : [];

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setStatus('submitting');
    setErrorMessage('');

    try {
      const response = await fetch('http://localhost:8000/api/enquiries', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: JSON.stringify(formData),
      });

      if (response.ok) {
        setStatus('success');
        setFormData({ salon_name: '', owner_name: '', phone: '', state: '', city_id: '', sub_area_id: '', street_address: '', pincode: '', message: '' });
      } else {
        const data = await response.json();
        setStatus('error');
        // Laravel returns a field map; its own wording is more use than a
        // generic failure line.
        const firstError = data?.errors ? Object.values(data.errors)[0] : null;
        setErrorMessage(
          Array.isArray(firstError)
            ? String(firstError[0])
            : data.message || 'Failed to submit enquiry. Please check your details.'
        );
      }
    } catch (error) {
      setStatus('error');
      setErrorMessage('A network error occurred. Please try again.');
    }
  };

  return (
    <div className="landing-container" style={{ minHeight: '100vh', display: 'flex', flexDirection: 'column', alignItems: 'center', backgroundColor: '#f9f9f9' }}>
      <div style={{ padding: '2rem 0' }}>
        <Image src="/logo.png" alt="BookALook" width={180} height={50} style={{ objectFit: 'contain' }} priority />
      </div>

      <section id="enquiry-section" className="enquiry-section" style={{ padding: '0 2rem 4rem 2rem', width: '100%', display: 'flex', justifyContent: 'center' }}>
        <div style={{ maxWidth: '600px', width: '100%', background: 'white', padding: '2rem', borderRadius: '12px', boxShadow: '0 4px 6px rgba(0,0,0,0.05)' }}>
          <h2 style={{ textAlign: 'center', marginBottom: '0.5rem' }}>Partner With Us</h2>
          <p style={{ textAlign: 'center', color: '#666', marginBottom: '2rem' }}>Fill out the form below and our team will get in touch to onboard your salon.</p>
          
          {status === 'success' ? (
            <div style={{ padding: '1rem', backgroundColor: '#e8f5e9', color: '#2e7d32', borderRadius: '8px', textAlign: 'center', fontWeight: 'bold' }}>
              Thank you! Your enquiry has been submitted successfully. Our team will contact you soon.
            </div>
          ) : (
            <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
              {status === 'error' && (
                <div style={{ padding: '0.75rem', backgroundColor: '#ffebee', color: '#c62828', borderRadius: '8px', fontSize: '0.9rem' }}>
                  {errorMessage}
                </div>
              )}
              
              <div>
                <label style={{ display: 'block', marginBottom: '0.5rem', fontWeight: 500 }}>Salon Name *</label>
                <input 
                  type="text" 
                  name="salon_name" 
                  required 
                  value={formData.salon_name} 
                  onChange={handleInputChange}
                  style={{ width: '100%', padding: '0.75rem', border: '1px solid #ccc', borderRadius: '8px' }}
                />
              </div>

              <div>
                <label style={{ display: 'block', marginBottom: '0.5rem', fontWeight: 500 }}>Owner Name *</label>
                <input 
                  type="text" 
                  name="owner_name" 
                  required 
                  value={formData.owner_name} 
                  onChange={handleInputChange}
                  style={{ width: '100%', padding: '0.75rem', border: '1px solid #ccc', borderRadius: '8px' }}
                />
              </div>

              <div>
                <label style={{ display: 'block', marginBottom: '0.5rem', fontWeight: 500 }}>Phone Number *</label>
                <input 
                  type="tel" 
                  name="phone" 
                  required 
                  value={formData.phone} 
                  onChange={handleInputChange}
                  style={{ width: '100%', padding: '0.75rem', border: '1px solid #ccc', borderRadius: '8px' }}
                />
              </div>

              <div>
                <label style={{ display: 'block', marginBottom: '0.5rem', fontWeight: 500 }}>State *</label>
                <select
                  name="state"
                  required
                  value={formData.state}
                  onChange={handleInputChange}
                  style={{ width: '100%', padding: '0.75rem', border: '1px solid #ccc', borderRadius: '8px', background: 'white' }}
                >
                  <option value="">Select your state</option>
                  {states.map((s) => (
                    <option key={s} value={s}>{s}</option>
                  ))}
                </select>
              </div>

              <div>
                <label style={{ display: 'block', marginBottom: '0.5rem', fontWeight: 500 }}>City *</label>
                <select
                  name="city_id"
                  required
                  disabled={!formData.state}
                  value={formData.city_id}
                  onChange={handleInputChange}
                  style={{ width: '100%', padding: '0.75rem', border: '1px solid #ccc', borderRadius: '8px', background: 'white' }}
                >
                  <option value="">
                    {!formData.state ? 'Choose a state first' : 'Select your city'}
                  </option>
                  {filteredCities.map((c) => (
                    <option key={c.id} value={c.id}>{c.name}</option>
                  ))}
                </select>
              </div>

              <div>
                <label style={{ display: 'block', marginBottom: '0.5rem', fontWeight: 500 }}>Area *</label>
                <select
                  name="sub_area_id"
                  required
                  disabled={!formData.city_id || loadingAreas}
                  value={formData.sub_area_id}
                  onChange={handleInputChange}
                  style={{ width: '100%', padding: '0.75rem', border: '1px solid #ccc', borderRadius: '8px', background: 'white' }}
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
                <p style={{ marginTop: '0.4rem', fontSize: '0.8rem', color: '#777' }}>
                  Helps us send someone who already works near you.
                </p>
              </div>

              <div>
                <label style={{ display: 'block', marginBottom: '0.5rem', fontWeight: 500 }}>Street Address *</label>
                <textarea
                  name="street_address"
                  required
                  rows={2}
                  value={formData.street_address}
                  onChange={handleInputChange}
                  style={{ width: '100%', padding: '0.75rem', border: '1px solid #ccc', borderRadius: '8px' }}
                />
              </div>

              <div>
                <label style={{ display: 'block', marginBottom: '0.5rem', fontWeight: 500 }}>Pincode *</label>
                <input
                  type="text"
                  name="pincode"
                  required
                  value={formData.pincode}
                  onChange={handleInputChange}
                  style={{ width: '100%', padding: '0.75rem', border: '1px solid #ccc', borderRadius: '8px' }}
                />
              </div>

              <div>
                <label style={{ display: 'block', marginBottom: '0.5rem', fontWeight: 500 }}>Message (Optional)</label>
                <textarea 
                  name="message" 
                  rows={4}
                  value={formData.message} 
                  onChange={handleInputChange}
                  style={{ width: '100%', padding: '0.75rem', border: '1px solid #ccc', borderRadius: '8px' }}
                ></textarea>
              </div>

              <button 
                type="submit" 
                disabled={status === 'submitting'}
                style={{ 
                  padding: '1rem', 
                  backgroundColor: status === 'submitting' ? '#9c27b088' : '#9c27b0', 
                  color: 'white', 
                  border: 'none', 
                  borderRadius: '8px', 
                  fontWeight: 'bold',
                  fontSize: '1rem',
                  cursor: status === 'submitting' ? 'not-allowed' : 'pointer',
                  marginTop: '1rem'
                }}
              >
                {status === 'submitting' ? 'Submitting...' : 'Submit Enquiry'}
              </button>
            </form>
          )}
        </div>
      </section>
    </div>
  );
}
