'use client';

import { useEffect, useState } from 'react';
import styles from './page.module.css';

// The API is Laravel, so every relation arrives snake_cased.
interface UserRef {
  id?: string;
  name?: string;
  phone?: string;
  email?: string;
  role?: string;
}

interface ProviderRef {
  id?: string;
  user?: UserRef;
}

interface ServiceRef {
  id?: string;
  price?: string | number;
  template?: { name?: string; estimated_duration_minutes?: number };
}

interface ServiceLine {
  id: string;
  service?: ServiceRef;
  combo_id?: string | null;
  price_at_booking?: string | number;
  original_service_price?: string | number;
  duration_minutes_at_booking?: number;
  line_status?: string;
  serving_provider?: ProviderRef | null;
}

interface ServiceAddition {
  id: string;
  service?: ServiceRef;
  provider?: ProviderRef;
  added_by?: UserRef;
  price_at_addition?: string | number;
  duration_minutes_at_addition?: number;
  status?: string;
  added_at?: string;
}

interface Appointment {
  id: string;
  salon: { id: string; name: string; phone?: string; email?: string; address?: string; status?: string };
  customer?: UserRef | null;
  appointed_provider?: ProviderRef | null;
  serving_provider?: ProviderRef | null;
  services?: ServiceLine[];
  service_additions?: ServiceAddition[];
  cancelled_by_user?: UserRef | null;

  booking_source?: string;
  appointment_date: string;
  start_time: string;
  end_time?: string;
  status: string;

  payment_option?: string;
  total_amount: string;
  advance_amount?: string;
  balance_amount?: string;
  final_billed_amount?: string | null;

  walk_in_customer_name?: string | null;
  walk_in_customer_phone?: string | null;
  walk_in_customer_gender?: string | null;

  verification_method?: string;
  qr_verified_at?: string | null;
  cancelled_by?: string | null;
  cancellation_reason?: string | null;
  cancelled_at?: string | null;
  rescheduled_from_id?: string | null;
  reschedule_reason?: string | null;
  salon_closure_id?: string | null;
  closure_notified_at?: string | null;
  salon_closure?: { id?: string; closed_date?: string; reason?: string | null } | null;
  started_at?: string | null;
  completed_at?: string | null;
  no_show_at?: string | null;
  created_at?: string;
}

interface Meta {
  current_page: number;
  last_page: number;
  total: number;
}

interface Salon {
  id: string;
  name: string;
}

export default function GlobalAppointmentsDashboard() {
  const [appointments, setAppointments] = useState<Appointment[]>([]);
  const [meta, setMeta] = useState<Meta | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  
  // Filters
  const [dateMode, setDateMode] = useState('specific');
  const [date, setDate] = useState(() => {
    const today = new Date();
    return today.toISOString().split('T')[0];
  });
  const [status, setStatus] = useState('');
  const [salonId, setSalonId] = useState('');
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const [salons, setSalons] = useState<Salon[]>([]);

  // Modal states
  const [isAddServiceModalOpen, setIsAddServiceModalOpen] = useState(false);
  const [selectedAppointmentId, setSelectedAppointmentId] = useState('');
  const [serviceId, setServiceId] = useState('');
  const [providerId, setProviderId] = useState('');
  const [addServiceError, setAddServiceError] = useState('');
  const [infoModalData, setInfoModalData] = useState<{type: 'salon' | 'customer', data: any} | null>(null);
  const [detailsAppointment, setDetailsAppointment] = useState<Appointment | null>(null);

  // We should ideally fetch services and providers based on the selected salon, 
  // but for the demo, we'll keep it simple.

  const fetchAppointments = async (isPolling = false) => {
    if (!isPolling) setLoading(true);
    try {
      const queryParams = new URLSearchParams();
      if (dateMode === 'specific' && date) {
        queryParams.append('date', date);
      } else if (dateMode === 'week') {
        const today = new Date();
        const nextWeek = new Date();
        nextWeek.setDate(nextWeek.getDate() + 7);
        queryParams.append('start_date', today.toISOString().split('T')[0]);
        queryParams.append('end_date', nextWeek.toISOString().split('T')[0]);
      } else if (dateMode === 'month') {
        const d = new Date();
        const start = new Date(d.getFullYear(), d.getMonth(), 1);
        const end = new Date(d.getFullYear(), d.getMonth() + 1, 0);
        queryParams.append('start_date', start.toISOString().split('T')[0]);
        queryParams.append('end_date', end.toISOString().split('T')[0]);
      }

      if (status) queryParams.append('status', status);
      if (salonId) queryParams.append('salon_id', salonId);
      if (search) queryParams.append('search', search);
      queryParams.append('page', page.toString());

      const token = localStorage.getItem('sa_token');
      const res = await fetch(`/api/proxy/superadmin/appointments?${queryParams.toString()}`, {
        headers: {
          'Authorization': `Bearer ${token}`
        }
      });
      
      if (!res.ok) {
        if (res.status === 401) {
          localStorage.removeItem('sa_token');
          window.location.href = '/superadmin/login';
          return;
        }
        const errorData = await res.json().catch(() => null);
        throw new Error(errorData?.message || 'Failed to fetch appointments');
      }
      
      const json = await res.json();
      setAppointments(json.data);
      setMeta({
        current_page: json.current_page,
        last_page: json.last_page,
        total: json.total
      });
      setError(''); // Clear error if fetch succeeds
    } catch (err: any) {
      if (!isPolling) setError(err.message);
    } finally {
      if (!isPolling) setLoading(false);
    }
  };

  const fetchSalons = async () => {
    try {
      const token = localStorage.getItem('sa_token');
      const res = await fetch('/api/proxy/superadmin/salons?per_page=100', {
        headers: { 'Authorization': `Bearer ${token}` }
      });
      if (res.ok) {
        const json = await res.json();
        setSalons(json.data || []);
      }
    } catch (e) {
      console.error('Failed to fetch salons', e);
    }
  };

  useEffect(() => {
    fetchSalons();
  }, []);

  useEffect(() => {
    fetchAppointments();
    
    // Poll every 5 seconds for real-time updates
    const intervalId = setInterval(() => {
      fetchAppointments(true);
    }, 5000);

    return () => clearInterval(intervalId);
  }, [date, dateMode, status, salonId, search, page]);

  const getStatusBadgeClass = (status: string) => {
    switch(status) {
      case 'scheduled': return styles.badgeScheduled;
      case 'in_progress': return styles.badgeInProgress;
      case 'completed': return styles.badgeCompleted;
      case 'cancelled': return styles.badgeCancelled;
      case 'no_show': return styles.badgeNoShow;
      case 'awaiting_reschedule': return styles.badgeAwaitingReschedule;
      default: return styles.badgeScheduled;
    }
  };

  const formatStatus = (status: string) => {
    return status.replace(/_/g, ' ');
  };

  // ---------------------------------------------------------------- display

  const providerName = (apt: Appointment) =>
    apt.serving_provider?.user?.name || apt.appointed_provider?.user?.name || null;

  const serviceName = (line: { service?: ServiceRef }) =>
    line.service?.template?.name || 'Unnamed service';

  const serviceNames = (apt: Appointment) => [
    ...(apt.services || []).map(serviceName),
    ...(apt.service_additions || []).map(serviceName),
  ];

  const customerName = (apt: Appointment) =>
    apt.customer?.name || apt.walk_in_customer_name || 'Walk-in';

  const customerPhone = (apt: Appointment) =>
    apt.customer?.phone || apt.walk_in_customer_phone || null;

  const sourceLabel = (source?: string) => {
    switch (source) {
      case 'online': return 'Customer app';
      case 'walk_in': return 'Walk-in';
      case 'phone': return 'Phone';
      default: return source || '—';
    }
  };

  const money = (value?: string | number | null) =>
    value === null || value === undefined || value === '' ? '—' : `₹${Number(value).toFixed(2)}`;

  const dateTime = (value?: string | null) =>
    value ? new Date(value).toLocaleString() : '—';

  const handleAddService = async (e: React.FormEvent) => {
    e.preventDefault();
    setAddServiceError('');
    
    try {
      const token = localStorage.getItem('sa_token');
      const res = await fetch(`http://localhost:8000/api/superadmin/appointments/${selectedAppointmentId}/add-service`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
          'Accept': 'application/json'
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
        if (res.status === 401) {
          localStorage.removeItem('sa_token');
          window.location.href = '/superadmin/login';
          return;
        }
        setAddServiceError(data.message || 'Failed to add service.');
      }
    } catch (err: any) {
      setAddServiceError(err.message);
    }
  };

  // Generate date strip (-3 days to +10 days)
  const generateDateStrip = () => {
    const dates = [];
    for (let i = -3; i <= 10; i++) {
      const d = new Date();
      d.setDate(d.getDate() + i);
      dates.push(d);
    }
    return dates;
  };
  const dateStrip = generateDateStrip();

  return (
    <div className={styles.container}>
      <div className={styles.header}>
        <div>
          <h1 className={styles.title}>Global Appointments</h1>
          <p className={styles.subtitle}>View and manage all appointments across all salons.</p>
        </div>
      </div>

      <div className={styles.filters} style={{ display: 'flex', gap: '12px', flexWrap: 'wrap', marginBottom: '20px' }}>
        <select 
          className={styles.selectInput} 
          value={dateMode} 
          onChange={(e) => { setDateMode(e.target.value); setPage(1); }}
        >
          <option value="specific">Specific Date</option>
          <option value="week">Next 7 Days</option>
          <option value="month">This Month</option>
          <option value="lifetime">Lifetime</option>
        </select>

        <select 
          className={styles.selectInput} 
          value={salonId} 
          onChange={(e) => { setSalonId(e.target.value); setPage(1); }}
        >
          <option value="">All Salons</option>
          {salons.map(s => (
            <option key={s.id} value={s.id}>{s.name}</option>
          ))}
        </select>

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
          <option value="awaiting_reschedule">Awaiting Reschedule</option>
        </select>

        <input
          type="text"
          className={styles.formInput}
          style={{ width: '250px' }}
          placeholder="Search by customer name, phone, etc..."
          value={search}
          onChange={(e) => { setSearch(e.target.value); setPage(1); }}
        />
      </div>

      {dateMode === 'specific' && (
        <div className={styles.dateStripContainer}>
          <div className={styles.dateStrip}>
            {dateStrip.map((d) => {
              const dateStr = d.toISOString().split('T')[0];
              const isSelected = date === dateStr;
              const dayName = d.toLocaleDateString('en-US', { weekday: 'short' });
              const dayNum = d.getDate();
              const monthName = d.toLocaleDateString('en-US', { month: 'short' });
              const isToday = new Date().toISOString().split('T')[0] === dateStr;

              return (
                <button 
                  key={dateStr}
                  className={`${styles.dateCard} ${isSelected ? styles.dateCardSelected : ''}`}
                  onClick={() => { setDate(dateStr); setPage(1); }}
                >
                  <span className={styles.dateCardMonth}>{monthName}</span>
                  <span className={styles.dateCardNum}>{dayNum}</span>
                  <span className={styles.dateCardDay}>{isToday ? 'Today' : dayName}</span>
                </button>
              );
            })}
          </div>
          <div className={styles.datePickerWrapper}>
             <input 
                type="date" 
                className={styles.hiddenDateInput}
                value={date}
                onChange={(e) => { setDate(e.target.value); setPage(1); }}
                title="Pick a date"
             />
             <span className={styles.calendarIcon}>📅</span>
          </div>
        </div>
      )}

      <div className={styles.tableContainer}>
        <table className={styles.table}>
          <thead>
            <tr>
              <th className={styles.th}>Date & Time</th>
              <th className={styles.th}>Customer</th>
              <th className={styles.th}>Salon</th>
              <th className={styles.th}>Provider</th>
              <th className={styles.th}>Services</th>
              <th className={styles.th}>Source</th>
              <th className={styles.th}>Status</th>
              <th className={styles.th}>Amount</th>
              <th className={styles.th} style={{ textAlign: 'right' }}>Action</th>
            </tr>
          </thead>
          <tbody>
            {loading && appointments.length === 0 ? (
              <tr>
                <td colSpan={9} className={styles.emptyState}>Loading...</td>
              </tr>
            ) : error ? (
              <tr>
                <td colSpan={9} className={styles.emptyState} style={{ color: 'red' }}>{error}</td>
              </tr>
            ) : appointments.length === 0 ? (
              <tr>
                <td colSpan={9} className={styles.emptyState}>No appointments found.</td>
              </tr>
            ) : (
              appointments.map((apt) => (
                <tr key={apt.id} className={styles.tr}>
                  <td className={styles.td}>
                    {new Date(apt.appointment_date).toLocaleDateString()} <br/>
                    <small style={{ color: '#6B7280' }}>
                      {apt.start_time}{apt.end_time ? ` – ${apt.end_time}` : ''}
                    </small>
                  </td>
                  <td className={styles.td}>
                    {customerName(apt)}
                    {apt.customer && (
                      <button
                        style={{ marginLeft: '8px', cursor: 'pointer', background: 'none', border: 'none', color: '#3B82F6' }}
                        onClick={() => setInfoModalData({ type: 'customer', data: apt.customer })}
                        title="View Customer Info"
                      >
                        &#9432;
                      </button>
                    )}
                    {customerPhone(apt) && (
                      <>
                        <br/>
                        <small style={{ color: '#6B7280' }}>{customerPhone(apt)}</small>
                      </>
                    )}
                  </td>
                  <td className={styles.td}>
                    {apt.salon.name}
                    <button
                      style={{ marginLeft: '8px', cursor: 'pointer', background: 'none', border: 'none', color: '#3B82F6' }}
                      onClick={() => setInfoModalData({ type: 'salon', data: apt.salon })}
                      title="View Salon Info"
                    >
                      &#9432;
                    </button>
                  </td>
                  <td className={styles.td}>
                    {providerName(apt) || <span style={{ color: '#9CA3AF' }}>Unassigned</span>}
                    {apt.serving_provider?.user?.name &&
                      apt.appointed_provider?.user?.name &&
                      apt.serving_provider.user.name !== apt.appointed_provider.user.name && (
                        <>
                          <br/>
                          <small style={{ color: '#6B7280' }}>
                            booked with {apt.appointed_provider.user.name}
                          </small>
                        </>
                      )}
                  </td>
                  <td className={styles.td}>
                    {serviceNames(apt).length === 0
                      ? <span style={{ color: '#9CA3AF' }}>—</span>
                      : (
                        <>
                          {serviceNames(apt).slice(0, 2).join(', ')}
                          {serviceNames(apt).length > 2 && (
                            <small style={{ color: '#6B7280' }}>
                              {' '}+{serviceNames(apt).length - 2} more
                            </small>
                          )}
                        </>
                      )}
                  </td>
                  <td className={styles.td}>{sourceLabel(apt.booking_source)}</td>
                  <td className={styles.td}>
                    <span className={`${styles.badge} ${getStatusBadgeClass(apt.status)}`}>
                      {formatStatus(apt.status)}
                    </span>
                  </td>
                  <td className={styles.td}>
                    {money(apt.total_amount)}
                    <br/>
                    <small style={{ color: '#6B7280' }}>
                      adv {money(apt.advance_amount)} · bal {money(apt.balance_amount)}
                    </small>
                  </td>
                  <td className={styles.td} style={{ textAlign: 'right', whiteSpace: 'nowrap' }}>
                    <button
                      className={styles.secondaryButton}
                      style={{ padding: '6px 12px', fontSize: '13px' }}
                      onClick={() => setDetailsAppointment(apt)}
                    >
                      Details
                    </button>
                    {apt.status === 'in_progress' && (
                        <button
                            className={styles.secondaryButton}
                            style={{ padding: '6px 12px', fontSize: '13px', marginLeft: '8px' }}
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

      {/* Full appointment record */}
      {detailsAppointment && (
        <div className={styles.modalOverlay} onClick={() => setDetailsAppointment(null)}>
          <div
            className={`${styles.modalContent} ${styles.detailsModal}`}
            onClick={(e) => e.stopPropagation()}
          >
            <div className={styles.modalHeader}>
              <h2 className={styles.modalTitle}>Appointment details</h2>
              <button className={styles.closeButton} onClick={() => setDetailsAppointment(null)}>&times;</button>
            </div>
            <div className={styles.modalBody}>
              {(() => {
                const apt = detailsAppointment;
                const lines = apt.services || [];
                const additions = apt.service_additions || [];

                return (
                  <>
                    <h3 className={styles.detailsSectionTitle}>Booking</h3>
                    <dl className={styles.detailsGrid}>
                      <dt>Appointment ID</dt><dd className={styles.detailsMono}>{apt.id}</dd>
                      <dt>Status</dt>
                      <dd>
                        <span className={`${styles.badge} ${getStatusBadgeClass(apt.status)}`}>
                          {formatStatus(apt.status)}
                        </span>
                      </dd>
                      <dt>Date</dt><dd>{new Date(apt.appointment_date).toLocaleDateString()}</dd>
                      <dt>Time</dt><dd>{apt.start_time} – {apt.end_time || '—'}</dd>
                      <dt>Source</dt><dd>{sourceLabel(apt.booking_source)}</dd>
                      <dt>Booked on</dt><dd>{dateTime(apt.created_at)}</dd>
                    </dl>

                    <h3 className={styles.detailsSectionTitle}>Customer</h3>
                    <dl className={styles.detailsGrid}>
                      <dt>Name</dt><dd>{customerName(apt)}</dd>
                      <dt>Phone</dt><dd>{customerPhone(apt) || '—'}</dd>
                      <dt>Email</dt><dd>{apt.customer?.email || '—'}</dd>
                      {!apt.customer && (
                        <>
                          <dt>Gender</dt><dd>{apt.walk_in_customer_gender || '—'}</dd>
                        </>
                      )}
                    </dl>

                    <h3 className={styles.detailsSectionTitle}>Salon & staff</h3>
                    <dl className={styles.detailsGrid}>
                      <dt>Salon</dt><dd>{apt.salon?.name || '—'}</dd>
                      <dt>Salon phone</dt><dd>{apt.salon?.phone || '—'}</dd>
                      <dt>Address</dt><dd>{apt.salon?.address || '—'}</dd>
                      <dt>Booked with</dt>
                      <dd>
                        {apt.appointed_provider?.user?.name || 'Unassigned'}
                        {apt.appointed_provider?.user?.phone
                          ? ` · ${apt.appointed_provider.user.phone}` : ''}
                      </dd>
                      <dt>Served by</dt>
                      <dd>
                        {apt.serving_provider?.user?.name || 'Not started'}
                        {apt.serving_provider?.user?.phone
                          ? ` · ${apt.serving_provider.user.phone}` : ''}
                      </dd>
                    </dl>

                    <h3 className={styles.detailsSectionTitle}>
                      Services ({lines.length} booked
                      {additions.length > 0 ? ` + ${additions.length} added mid-appointment` : ''})
                    </h3>
                    <table className={styles.detailsTable}>
                      <thead>
                        <tr>
                          <th>Service</th>
                          <th>Provider</th>
                          <th>Duration</th>
                          <th>Price</th>
                          <th>Line status</th>
                        </tr>
                      </thead>
                      <tbody>
                        {lines.length === 0 && additions.length === 0 && (
                          <tr><td colSpan={5} style={{ color: '#9CA3AF' }}>No service lines recorded.</td></tr>
                        )}
                        {lines.map((line) => (
                          <tr key={line.id}>
                            <td>
                              {serviceName(line)}
                              {line.combo_id && <small style={{ color: '#6B7280' }}> (package)</small>}
                            </td>
                            <td>{line.serving_provider?.user?.name || providerName(apt) || '—'}</td>
                            <td>{line.duration_minutes_at_booking ? `${line.duration_minutes_at_booking} min` : '—'}</td>
                            <td>
                              {money(line.price_at_booking)}
                              {line.original_service_price !== undefined &&
                                Number(line.original_service_price) !== Number(line.price_at_booking) && (
                                  <small style={{ color: '#6B7280' }}>
                                    {' '}(list {money(line.original_service_price)})
                                  </small>
                                )}
                            </td>
                            <td>{line.line_status || '—'}</td>
                          </tr>
                        ))}
                        {additions.map((add) => (
                          <tr key={add.id}>
                            <td>
                              {serviceName(add)}
                              <small style={{ color: '#6B7280' }}> (added mid-appointment)</small>
                            </td>
                            <td>{add.provider?.user?.name || '—'}</td>
                            <td>{add.duration_minutes_at_addition ? `${add.duration_minutes_at_addition} min` : '—'}</td>
                            <td>{money(add.price_at_addition)}</td>
                            <td>
                              {/* Reads as a line status so a settled extra
                                  matches the booked lines beside it. */}
                              {add.status === 'voided' ? 'removed' : (add.status || '—')}
                              {add.added_by?.name && (
                                <>
                                  <br/>
                                  <small style={{ color: '#6B7280' }}>
                                    by {add.added_by.name}
                                    {add.added_at ? ` · ${dateTime(add.added_at)}` : ''}
                                  </small>
                                </>
                              )}
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>

                    <h3 className={styles.detailsSectionTitle}>Payment</h3>
                    <dl className={styles.detailsGrid}>
                      <dt>Option</dt><dd>{apt.payment_option?.replace(/_/g, ' ') || '—'}</dd>
                      <dt>Total</dt><dd>{money(apt.total_amount)}</dd>
                      <dt>Advance paid</dt><dd>{money(apt.advance_amount)}</dd>
                      <dt>Balance due</dt><dd>{money(apt.balance_amount)}</dd>
                      <dt>Final billed</dt><dd>{money(apt.final_billed_amount)}</dd>
                    </dl>

                    <h3 className={styles.detailsSectionTitle}>Lifecycle</h3>
                    <dl className={styles.detailsGrid}>
                      <dt>Verification</dt><dd>{apt.verification_method || '—'}</dd>
                      <dt>QR verified</dt><dd>{dateTime(apt.qr_verified_at)}</dd>
                      <dt>Started</dt><dd>{dateTime(apt.started_at)}</dd>
                      <dt>Completed</dt><dd>{dateTime(apt.completed_at)}</dd>
                      <dt>No show</dt><dd>{dateTime(apt.no_show_at)}</dd>
                      {apt.cancelled_at && (
                        <>
                          <dt>Cancelled</dt>
                          <dd>
                            {dateTime(apt.cancelled_at)}
                            {apt.cancelled_by ? ` by ${apt.cancelled_by}` : ''}
                            {apt.cancelled_by_user?.name ? ` (${apt.cancelled_by_user.name})` : ''}
                          </dd>
                          <dt>Reason</dt><dd>{apt.cancellation_reason || '—'}</dd>
                        </>
                      )}
                      {apt.rescheduled_from_id && (
                        <>
                          <dt>Rescheduled from</dt>
                          <dd className={styles.detailsMono}>{apt.rescheduled_from_id}</dd>
                          <dt>Reschedule reason</dt><dd>{apt.reschedule_reason || '—'}</dd>
                        </>
                      )}
                      {apt.salon_closure_id && (
                        <>
                          <dt>Released by closure</dt>
                          <dd>
                            {apt.salon_closure?.closed_date || 'Emergency closure'}
                            {apt.salon_closure?.reason ? ` — ${apt.salon_closure.reason}` : ''}
                          </dd>
                          <dt>Customer notified</dt><dd>{dateTime(apt.closure_notified_at)}</dd>
                        </>
                      )}
                    </dl>
                  </>
                );
              })()}
            </div>
            <div className={styles.modalFooter}>
              <button className={styles.primaryButton} onClick={() => setDetailsAppointment(null)}>Close</button>
            </div>
          </div>
        </div>
      )}

      {/* Info Modal */}
      {infoModalData && (
        <div className={styles.modalOverlay}>
          <div className={styles.modalContent}>
            <div className={styles.modalHeader}>
              <h2 className={styles.modalTitle}>
                {infoModalData.type === 'salon' ? 'Salon Info' : 'Customer Info'}
              </h2>
              <button className={styles.closeButton} onClick={() => setInfoModalData(null)}>&times;</button>
            </div>
            <div className={styles.modalBody}>
              <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
                <p><strong>Name:</strong> {infoModalData.data.name}</p>
                {infoModalData.data.phone && <p><strong>Phone:</strong> {infoModalData.data.phone}</p>}
                {infoModalData.data.email && <p><strong>Email:</strong> {infoModalData.data.email}</p>}
                {infoModalData.data.address && <p><strong>Address:</strong> {infoModalData.data.address}</p>}
                {infoModalData.data.status && <p><strong>Status:</strong> {infoModalData.data.status}</p>}
              </div>
            </div>
            <div className={styles.modalFooter}>
              <button className={styles.primaryButton} onClick={() => setInfoModalData(null)}>Close</button>
            </div>
          </div>
        </div>
      )}

    </div>
  );
}
