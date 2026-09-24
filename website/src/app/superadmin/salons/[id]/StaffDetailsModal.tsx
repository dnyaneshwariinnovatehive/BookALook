'use client';

import React, { useEffect, useState } from 'react';
import styles from './page.module.css';

interface StaffDetailsModalProps {
  salonId: string;
  providerId: string;
  onClose: () => void;
}

export default function StaffDetailsModal({ salonId, providerId, onClose }: StaffDetailsModalProps) {
  const [data, setData] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [activeTab, setActiveTab] = useState<'basic' | 'services' | 'financial' | 'leaves'>('basic');

  useEffect(() => {
    async function fetchDetails() {
      try {
        const res = await fetch(`${process.env.NEXT_PUBLIC_BACKEND_URL}/api/superadmin/salons/${salonId}/staff/${providerId}`);
        if (!res.ok) throw new Error('Failed to fetch staff details');
        const json = await res.json();
        if (json.success) {
          setData(json);
        } else {
          throw new Error(json.message);
        }
      } catch (err: any) {
        setError(err.message);
      } finally {
        setLoading(false);
      }
    }
    fetchDetails();
  }, [salonId, providerId]);

  if (loading) {
    return (
      <div className={styles.modalOverlay}>
        <div className={styles.modalContent}>
          <div className={styles.modalBody}>Loading details...</div>
        </div>
      </div>
    );
  }

  if (error || !data) {
    return (
      <div className={styles.modalOverlay}>
        <div className={styles.modalContent}>
          <div className={styles.modalHeader}>
            <h3>Error</h3>
            <button onClick={onClose} className={styles.closeBtn}>×</button>
          </div>
          <div className={styles.modalBody} style={{ color: 'red' }}>{error || 'Not found'}</div>
        </div>
      </div>
    );
  }

  const { provider, payroll, leaves } = data;

  const renderBasic = () => {
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return (
      <div className={styles.tabPane}>
        <div className={styles.infoGroup}>
          <span className={styles.label}>Name</span>
          <div className={styles.value}>{provider.user.name}</div>
        </div>
        <div className={styles.infoGroup}>
          <span className={styles.label}>Phone</span>
          <div className={styles.value}>{provider.user.phone}</div>
        </div>
        <div className={styles.infoGroup}>
          <span className={styles.label}>Email</span>
          <div className={styles.value}>{provider.user.email || 'N/A'}</div>
        </div>
        <div className={styles.infoGroup}>
          <span className={styles.label}>Specialization</span>
          <div className={styles.value}>{provider.specialization || 'N/A'}</div>
        </div>
        <div className={styles.infoGroup}>
          <span className={styles.label}>Auto-approve leaves</span>
          <div className={styles.value}>{provider.auto_approve_leave ? 'Yes' : 'No'}</div>
        </div>

        <h4 style={{ marginTop: '20px', marginBottom: '10px' }}>Working Hours</h4>
        <table className={styles.dataTable}>
          <thead>
            <tr>
              <th>Day</th>
              <th>Status</th>
              <th>Shift</th>
              <th>Break</th>
            </tr>
          </thead>
          <tbody>
            {provider.working_hours?.map((wh: any, i: number) => (
              <tr key={i}>
                <td>{days[wh.day_of_week]}</td>
                <td>{wh.is_weekly_off ? 'Off' : 'Working'}</td>
                <td>{wh.is_weekly_off ? '-' : `${wh.shift_start} - ${wh.shift_end}`}</td>
                <td>{wh.break_start ? `${wh.break_start} - ${wh.break_end}` : '-'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    );
  };

  const renderServices = () => {
    return (
      <div className={styles.tabPane}>
        {provider.services?.length ? (
          <table className={styles.dataTable}>
            <thead>
              <tr>
                <th>Service Name</th>
                <th>Category</th>
              </tr>
            </thead>
            <tbody>
              {provider.services.map((s: any, i: number) => (
                <tr key={i}>
                  <td>{s.template.name}</td>
                  <td>{s.template.category?.name || '-'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        ) : (
          <p>No services assigned.</p>
        )}
      </div>
    );
  };

  const renderFinancial = () => {
    return (
      <div className={styles.tabPane}>
        <div className={styles.financialSummary}>
          <div className={styles.infoGroup}>
            <span className={styles.label}>Base Salary</span>
            <div className={styles.value}>₹{provider.base_salary}</div>
          </div>
          <div className={styles.infoGroup}>
            <span className={styles.label}>Commission Rate</span>
            <div className={styles.value}>{provider.commission_percentage}%</div>
          </div>
        </div>

        <h4 style={{ marginTop: '20px', marginBottom: '10px' }}>Current Month ({payroll.current.salary_month})</h4>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: '15px', marginBottom: '20px' }}>
            <div className={styles.statBox}>
                <div className={styles.statLabel}>Base</div>
                <div className={styles.statVal}>₹{payroll.current.base_salary}</div>
            </div>
            <div className={styles.statBox}>
                <div className={styles.statLabel}>Commission</div>
                <div className={styles.statVal}>₹{payroll.current.commission_earned}</div>
            </div>
            <div className={styles.statBox}>
                <div className={styles.statLabel}>Total Payable</div>
                <div className={styles.statVal}>₹{payroll.current.total_payable}</div>
            </div>
        </div>

        <h4 style={{ marginTop: '20px', marginBottom: '10px' }}>History (Last 12 Months)</h4>
        {payroll.history?.length ? (
          <table className={styles.dataTable}>
            <thead>
              <tr>
                <th>Month</th>
                <th>Base</th>
                <th>Commission</th>
                <th>Deductions</th>
                <th>Total Paid</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              {payroll.history.map((p: any, i: number) => (
                <tr key={i}>
                  <td>{p.salary_month}</td>
                  <td>₹{p.base_salary}</td>
                  <td>₹{p.commission_earned}</td>
                  <td>₹{p.unpaid_leave_deduction}</td>
                  <td>₹{p.total_payable}</td>
                  <td>{p.status}</td>
                </tr>
              ))}
            </tbody>
          </table>
        ) : (
          <p>No historical payroll data.</p>
        )}
      </div>
    );
  };

  const renderLeaves = () => {
    return (
      <div className={styles.tabPane}>
        {leaves?.length ? (
          <table className={styles.dataTable}>
            <thead>
              <tr>
                <th>Date</th>
                <th>Type</th>
                <th>Duration</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              {leaves.map((l: any, i: number) => (
                <tr key={i}>
                  <td>{new Date(l.leave_date).toLocaleDateString()}</td>
                  <td>{l.leave_type}</td>
                  <td>{l.is_full_day ? 'Full Day' : `${l.start_time} - ${l.end_time}`}</td>
                  <td>{l.status}</td>
                </tr>
              ))}
            </tbody>
          </table>
        ) : (
          <p>No leaves recorded.</p>
        )}
      </div>
    );
  };

  return (
    <div className={styles.modalOverlay} onClick={onClose}>
      <div className={styles.modalContent} onClick={e => e.stopPropagation()}>
        <div className={styles.modalHeader}>
          <h3>{provider.user.name}</h3>
          <button onClick={onClose} className={styles.closeBtn}>×</button>
        </div>
        
        <div className={styles.modalTabs}>
          <button className={activeTab === 'basic' ? styles.activeTab : ''} onClick={() => setActiveTab('basic')}>Basic Info</button>
          <button className={activeTab === 'services' ? styles.activeTab : ''} onClick={() => setActiveTab('services')}>Services</button>
          <button className={activeTab === 'financial' ? styles.activeTab : ''} onClick={() => setActiveTab('financial')}>Financial</button>
          <button className={activeTab === 'leaves' ? styles.activeTab : ''} onClick={() => setActiveTab('leaves')}>Leaves</button>
        </div>

        <div className={styles.modalBody}>
          {activeTab === 'basic' && renderBasic()}
          {activeTab === 'services' && renderServices()}
          {activeTab === 'financial' && renderFinancial()}
          {activeTab === 'leaves' && renderLeaves()}
        </div>
      </div>
    </div>
  );
}
