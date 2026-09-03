'use client';

import React from 'react';
import Link from 'next/link';
import styles from './dashboard.module.css';

// --- MOCK DATA ---
const pendingSalons = [
  { id: '1', name: 'Glow Up Studio', city: 'Mumbai', appliedAt: '2026-09-01', status: 'pending_approval' },
  { id: '2', name: 'Elite Cuts', city: 'Delhi', appliedAt: '2026-09-02', status: 'pending_approval' },
  { id: '3', name: 'Serenity Spa', city: 'Bangalore', appliedAt: '2026-09-02', status: 'pending_approval' },
];

const openComplaints = [
  { id: 'C-101', salonName: 'Urban Trim', subject: 'Overcharged for service', date: '2026-09-02' },
  { id: 'C-102', salonName: 'Luxe Hair', subject: 'Rude staff behavior', date: '2026-09-01' },
];
// -----------------

export default function AdminDashboard() {
  return (
    <div>
      <header className={styles.pageHeader}>
        <h1 className={styles.pageTitle}>Dashboard Overview</h1>
        <p className={styles.pageSubtitle}>Welcome back. Here is what's happening across the marketplace today.</p>
      </header>

      {/* KPI GRID */}
      <div className={styles.kpiGrid}>
        <div className={styles.kpiCard}>
          <div className={styles.kpiHeader}>
            <span className={styles.kpiLabel}>Active Salons</span>
            <div className={`${styles.kpiIcon} ${styles.kpiIconBlue}`}>🏪</div>
          </div>
          <div className={styles.kpiValue}>142</div>
          <div className={styles.kpiTrend}>
            <span className={styles.trendUp}>↑ 12%</span> vs last month
          </div>
        </div>

        <div className={styles.kpiCard}>
          <div className={styles.kpiHeader}>
            <span className={styles.kpiLabel}>Commission Earned (7d)</span>
            <div className={`${styles.kpiIcon} ${styles.kpiIconGreen}`}>₹</div>
          </div>
          <div className={styles.kpiValue}>₹42,800</div>
          <div className={styles.kpiTrend}>
            <span className={styles.trendUp}>↑ 8.4%</span> vs last week
          </div>
        </div>

        <div className={styles.kpiCard}>
          <div className={styles.kpiHeader}>
            <span className={styles.kpiLabel}>Total Appointments (7d)</span>
            <div className={`${styles.kpiIcon} ${styles.kpiIconPurple}`}>📅</div>
          </div>
          <div className={styles.kpiValue}>1,465</div>
          <div className={styles.kpiTrend}>
            <span className={styles.trendUp}>↑ 15%</span> vs last week
          </div>
        </div>

        <div className={styles.kpiCard}>
          <div className={styles.kpiHeader}>
            <span className={styles.kpiLabel}>Pending Approvals</span>
            <div className={`${styles.kpiIcon} ${styles.kpiIconOrange}`}>⏳</div>
          </div>
          <div className={styles.kpiValue}>8</div>
          <div className={styles.kpiTrend}>
            <span className={styles.trendNeutral}>Requires Attention</span>
          </div>
        </div>
      </div>

      {/* CHARTS GRID (CSS Based to avoid React 19 SSR issues) */}
      <div className={styles.chartsGrid}>
        <div className={styles.chartCard}>
          <h2 className={styles.cardTitle}>Revenue Trends (Last 7 Days)</h2>
          <div style={{ width: '100%', height: 300, display: 'flex', alignItems: 'flex-end', gap: '2%', paddingBottom: '30px', position: 'relative' }}>
            {/* Simple CSS Bar Chart Mock */}
            {[42, 38, 51, 48, 65, 89, 95].map((val, i) => (
              <div key={i} style={{ flex: 1, display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', alignItems: 'center', height: '100%' }}>
                <div style={{ width: '60%', height: `${val}%`, backgroundColor: '#cbd5e1', borderRadius: '4px 4px 0 0', position: 'relative' }}>
                  <div style={{ position: 'absolute', bottom: 0, width: '100%', height: `${val * 0.1}%`, backgroundColor: '#3b82f6', borderRadius: '0' }} title="Platform Commission"></div>
                </div>
                <div style={{ marginTop: '10px', fontSize: '0.75rem', color: 'var(--text-body)', opacity: 0.7 }}>
                  {['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][i]}
                </div>
              </div>
            ))}
          </div>
        </div>

        <div className={styles.chartCard}>
          <h2 className={styles.cardTitle}>Booking Status</h2>
          <div style={{ width: '100%', height: 300, display: 'flex', flexDirection: 'column', justifyContent: 'center', gap: '1.5rem' }}>
            <div>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '0.5rem', fontSize: '0.875rem', color: 'var(--text-body)', fontWeight: 500 }}>
                <span>Completed (1240)</span>
                <span>85%</span>
              </div>
              <div style={{ width: '100%', height: '8px', backgroundColor: 'var(--border-color)', borderRadius: '4px', overflow: 'hidden' }}>
                <div style={{ width: '85%', height: '100%', backgroundColor: '#16a34a' }}></div>
              </div>
            </div>
            
            <div>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '0.5rem', fontSize: '0.875rem', color: 'var(--text-body)', fontWeight: 500 }}>
                <span>Cancelled (180)</span>
                <span>12%</span>
              </div>
              <div style={{ width: '100%', height: '8px', backgroundColor: 'var(--border-color)', borderRadius: '4px', overflow: 'hidden' }}>
                <div style={{ width: '12%', height: '100%', backgroundColor: '#f97316' }}></div>
              </div>
            </div>
            
            <div>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '0.5rem', fontSize: '0.875rem', color: 'var(--text-body)', fontWeight: 500 }}>
                <span>No-Show (45)</span>
                <span>3%</span>
              </div>
              <div style={{ width: '100%', height: '8px', backgroundColor: 'var(--border-color)', borderRadius: '4px', overflow: 'hidden' }}>
                <div style={{ width: '3%', height: '100%', backgroundColor: '#dc2626' }}></div>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* TABLES GRID */}
      <div className={styles.tablesGrid}>
        <div className={styles.tableContainer}>
          <div className={styles.tableHeader}>
            <h2 className={styles.tableTitle}>Pending Salon Approvals</h2>
            <Link href="/superadmin/salon-approval" className={styles.viewAllBtn}>View All</Link>
          </div>
          <table className={styles.table}>
            <thead>
              <tr>
                <th className={styles.th}>Salon Name</th>
                <th className={styles.th}>City</th>
                <th className={styles.th}>Applied Date</th>
                <th className={styles.th}>Status</th>
              </tr>
            </thead>
            <tbody>
              {pendingSalons.map((salon) => (
                <tr key={salon.id} className={styles.tr}>
                  <td className={styles.td} style={{ fontWeight: 500 }}>{salon.name}</td>
                  <td className={styles.td}>{salon.city}</td>
                  <td className={styles.td}>{salon.appliedAt}</td>
                  <td className={styles.td}>
                    <span className={`${styles.badge} ${styles.badgeWarning}`}>Pending</span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        <div className={styles.tableContainer}>
          <div className={styles.tableHeader}>
            <h2 className={styles.tableTitle}>Open Complaints</h2>
            <Link href="/superadmin/complaints" className={styles.viewAllBtn}>View All</Link>
          </div>
          <table className={styles.table}>
            <thead>
              <tr>
                <th className={styles.th}>ID</th>
                <th className={styles.th}>Salon</th>
                <th className={styles.th}>Subject</th>
                <th className={styles.th}>Status</th>
              </tr>
            </thead>
            <tbody>
              {openComplaints.map((complaint) => (
                <tr key={complaint.id} className={styles.tr}>
                  <td className={styles.td} style={{ fontWeight: 500 }}>{complaint.id}</td>
                  <td className={styles.td}>{complaint.salonName}</td>
                  <td className={styles.td}>{complaint.subject}</td>
                  <td className={styles.td}>
                    <span className={`${styles.badge} ${styles.badgeDanger}`}>Open</span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
