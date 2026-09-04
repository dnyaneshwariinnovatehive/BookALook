'use client';

import { useEffect, useState } from 'react';
import styles from './page.module.css';

interface Appointment {
  id: string;
  salon: { name: string };
  customer?: { name: string; phone: string };
  appointedProvider: { user: { name: string } };
  servingProvider?: { user: { name: string } };
  appointment_date: string;
  start_time: string;
  status: string;
  total_amount: string;
}

interface Meta {
  current_page: number;
  last_page: number;
  total: number;
}

export default function GlobalAppointmentsDashboard() {
  const [appointments, setAppointments] = useState<Appointment[]>([]);
  const [meta, setMeta] = useState<Meta | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  
  // Filters
  const [date, setDate] = useState('');
  const [status, setStatus] = useState('');
  const [page, setPage] = useState(1);

  // Modal states
  const [isQrModalOpen, setIsQrModalOpen] = useState(false);
  const [qrToken, setQrToken] = useState('');
  const [servingProviderId, setServingProviderId] = useState('');
  const [qrError, setQrError] = useState('');
  const [qrSuccess, setQrSuccess] = useState('');

  const [isAddServiceModalOpen, setIsAddServiceModalOpen] = useState(false);
  const [selectedAppointmentId, setSelectedAppointmentId] = useState('');
  const [serviceId, setServiceId] = useState('');
  const [providerId, setProviderId] = useState('');
  const [addServiceError, setAddServiceError] = useState('');

  // We should ideally fetch services and providers based on the selected salon, 
  // but for the demo, we'll keep it simple.

  const fetchAppointments = async () => {
    setLoading(true);
    try {
      const queryParams = new URLSearchParams();
      if (date) queryParams.append('date', date);
      if (status) queryParams.append('status', status);
      queryParams.append('page', page.toString());

      const token = localStorage.getItem('sa_token');
      const res = await fetch(`http://localhost:8000/api/superadmin/appointments?${queryParams.toString()}`, {
        headers: {
          'Authorization': `Bearer ${token}`
        }
      });
      
      if (!res.ok) throw new Error('Failed to fetch appointments');
      
      const json = await res.json();
      setAppointments(json.data);
      setMeta({
        current_page: json.current_page,
        last_page: json.last_page,
        total: json.total
      });
    } catch (err: any) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchAppointments();
  }, [date, status, page]);

  const getStatusBadgeClass = (status: string) => {
    switch(status) {
      case 'scheduled': return styles.badgeScheduled;
      case 'in_progress': return styles.badgeInProgress;
      case 'completed': return styles.badgeCompleted;
      case 'cancelled': return styles.badgeCancelled;
      case 'no_show': return styles.badgeNoShow;
      default: return styles.badgeScheduled;
    }
  };

  const formatStatus = (status: string) => {
    return status.replace('_', ' ');
  };

  const handleVerifyQr = async (e: React.FormEvent) => {
    e.preventDefault();
    setQrError('');
    setQrSuccess('');
    
    try {
      const token = localStorage.getItem('sa_token');
      const res = await fetch(`http://localhost:8000/api/superadmin/appointments/verify-qr`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`
        },
        body: JSON.stringify({
          qr_token: qrToken,
          serving_provider_id: servingProviderId
        })
      });
      
      const data = await res.json();
      
      if (res.ok) {
        setQrSuccess('Session started successfully!');
        setQrToken('');
        setServingProviderId('');
        fetchAppointments();
        setTimeout(() => setIsQrModalOpen(false), 2000);
      } else {
        setQrError(data.message || 'Failed to verify QR Code.');
      }
    } catch (err: any) {
      setQrError(err.message);
    }
  };

  const handleAddService = async (e: React.FormEvent) => {
    e.preventDefault();
    setAddServiceError('');
    
    try {
      const token = localStorage.getItem('sa_token');
      const res = await fetch(`http://localhost:8000/api/superadmin/appointments/${selectedAppointmentId}/add-service`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`
        },
        body: JSON.stringify({
          service_id: serviceId,
          provider_id: providerId
        })
      });
      
      const data = await res.json();
      
      if (res.ok) {
        setIsAddServiceModalOpen(false);
        setServiceId('');
        setProviderId('');
        fetchAppointments();
      } else {
        setAddServiceError(data.message || 'Failed to add service.');
      }
    } catch (err: any) {
      setAddServiceError(err.message);
    }
  };

  return (
    <div className={styles.container}>
      <div className={styles.header}>
        <div>
          <h1 className={styles.title}>Global Appointments</h1>
          <p className={styles.subtitle}>View and manage all appointments across all salons.</p>
        </div>
        <div style={{ marginTop: '16px', display: 'flex', gap: '12px' }}>
            <button className={styles.primaryButton} onClick={() => setIsQrModalOpen(true)}>
                Scan QR / Start Session
            </button>
        </div>
      </div>

      <div className={styles.filters}>
        <input 
          type="date" 
          className={styles.dateInput}
          value={date}
          onChange={(e) => { setDate(e.target.value); setPage(1); }}
        />
        <select 
          className={styles.selectInput} 
          value={status} 
          onChange={(e) => { setStatus(e.target.value); setPage(1); }}
        >
          <option value="">All Statuses</option>
          <option value="scheduled">Scheduled</option>
          <option value="in_progress">In Progress</option>
          <option value="completed">Completed</option>
          <option value="cancelled">Cancelled</option>
          <option value="no_show">No Show</option>
        </select>
      </div>

      <div className={styles.tableContainer}>
        <table className={styles.table}>
          <thead>
            <tr>
              <th className={styles.th}>Date & Time</th>
              <th className={styles.th}>Customer</th>
              <th className={styles.th}>Salon</th>
              <th className={styles.th}>Provider</th>
              <th className={styles.th}>Status</th>
              <th className={styles.th}>Total</th>
              <th className={styles.th} style={{ textAlign: 'right' }}>Action</th>
            </tr>
          </thead>
          <tbody>
            {loading && appointments.length === 0 ? (
              <tr>
                <td colSpan={7} className={styles.emptyState}>Loading...</td>
              </tr>
            ) : error ? (
              <tr>
                <td colSpan={7} className={styles.emptyState} style={{ color: 'red' }}>{error}</td>
              </tr>
            ) : appointments.length === 0 ? (
              <tr>
                <td colSpan={7} className={styles.emptyState}>No appointments found.</td>
              </tr>
            ) : (
              appointments.map((apt) => (
                <tr key={apt.id} className={styles.tr}>
                  <td className={styles.td}>
                    {new Date(apt.appointment_date).toLocaleDateString()} <br/>
                    <small style={{ color: '#6B7280' }}>{apt.start_time}</small>
                  </td>
                  <td className={styles.td}>{apt.customer?.name || 'Walk-in'}</td>
                  <td className={styles.td}>{apt.salon.name}</td>
                  <td className={styles.td}>
                    {apt.servingProvider?.user?.name || apt.appointedProvider?.user?.name}
                  </td>
                  <td className={styles.td}>
                    <span className={`${styles.badge} ${getStatusBadgeClass(apt.status)}`}>
                      {formatStatus(apt.status)}
                    </span>
                  </td>
                  <td className={styles.td}>₹{apt.total_amount}</td>
                  <td className={styles.td} style={{ textAlign: 'right' }}>
                    {apt.status === 'in_progress' && (
                        <button 
                            className={styles.secondaryButton} 
                            style={{ padding: '6px 12px', fontSize: '13px' }}
                            onClick={() => {
                                setSelectedAppointmentId(apt.id);
                                setIsAddServiceModalOpen(true);
                            }}
                        >
                            + Add Service
                        </button>
                    )}
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
        
        {meta && meta.last_page > 1 && (
          <div className={styles.pagination}>
            <div className={styles.pageInfo}>
              Showing page {meta.current_page} of {meta.last_page} ({meta.total} total)
            </div>
            <div className={styles.pageControls}>
              <button 
                className={styles.pageButton} 
                disabled={meta.current_page === 1}
                onClick={() => setPage(p => Math.max(1, p - 1))}
              >
                Previous
              </button>
              <button 
                className={styles.pageButton} 
                disabled={meta.current_page === meta.last_page}
                onClick={() => setPage(p => Math.min(meta.last_page, p + 1))}
              >
                Next
              </button>
            </div>
          </div>
        )}
      </div>

      {/* Verify QR Modal */}
      {isQrModalOpen && (
        <div className={styles.modalOverlay}>
          <div className={styles.modalContent}>
            <div className={styles.modalHeader}>
              <h2 className={styles.modalTitle}>Scan QR & Start Session</h2>
              <button className={styles.closeButton} onClick={() => setIsQrModalOpen(false)}>&times;</button>
            </div>
            <div className={styles.modalBody}>
              {qrError && <p style={{ color: 'red', marginBottom: '12px' }}>{qrError}</p>}
              {qrSuccess && <p style={{ color: 'green', marginBottom: '12px' }}>{qrSuccess}</p>}
              <form id="qrForm" onSubmit={handleVerifyQr}>
                <div className={styles.formGroup}>
                  <label>QR Token (Simulated Scan)</label>
                  <input 
                    type="text" 
                    className={styles.formInput} 
                    value={qrToken}
                    onChange={(e) => setQrToken(e.target.value)}
                    required
                  />
                </div>
                <div className={styles.formGroup}>
                  <label>Serving Provider ID</label>
                  <input 
                    type="text" 
                    className={styles.formInput} 
                    value={servingProviderId}
                    onChange={(e) => setServingProviderId(e.target.value)}
                    required
                    placeholder="Enter Provider UUID"
                  />
                  <small style={{ color: '#6B7280' }}>*In a real app, this would be a dropdown of staff in the salon.</small>
                </div>
              </form>
            </div>
            <div className={styles.modalFooter}>
              <button className={styles.secondaryButton} onClick={() => setIsQrModalOpen(false)}>Cancel</button>
              <button type="submit" form="qrForm" className={styles.primaryButton}>Verify & Start</button>
            </div>
          </div>
        </div>
      )}

      {/* Add Service Modal */}
      {isAddServiceModalOpen && (
        <div className={styles.modalOverlay}>
          <div className={styles.modalContent}>
            <div className={styles.modalHeader}>
              <h2 className={styles.modalTitle}>Add Mid-Appointment Service</h2>
              <button className={styles.closeButton} onClick={() => setIsAddServiceModalOpen(false)}>&times;</button>
            </div>
            <div className={styles.modalBody}>
              {addServiceError && <p style={{ color: 'red', marginBottom: '12px' }}>{addServiceError}</p>}
              <form id="addServiceForm" onSubmit={handleAddService}>
                <div className={styles.formGroup}>
                  <label>Service ID</label>
                  <input 
                    type="text" 
                    className={styles.formInput} 
                    value={serviceId}
                    onChange={(e) => setServiceId(e.target.value)}
                    required
                    placeholder="Enter Service UUID"
                  />
                </div>
                <div className={styles.formGroup}>
                  <label>Provider ID (Who is doing this?)</label>
                  <input 
                    type="text" 
                    className={styles.formInput} 
                    value={providerId}
                    onChange={(e) => setProviderId(e.target.value)}
                    required
                    placeholder="Enter Provider UUID"
                  />
                </div>
              </form>
            </div>
            <div className={styles.modalFooter}>
              <button className={styles.secondaryButton} onClick={() => setIsAddServiceModalOpen(false)}>Cancel</button>
              <button type="submit" form="addServiceForm" className={styles.primaryButton}>Add Service</button>
            </div>
          </div>
        </div>
      )}

    </div>
  );
}
