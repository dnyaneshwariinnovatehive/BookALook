'use client';

import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import styles from './layout.module.css';

const navItems = [
  { name: 'Dashboard', path: '/superadmin' },
  { name: 'Salon Approval Queue', path: '/superadmin/salon-approval' },
  { name: 'Salon Directory', path: '/superadmin/salons' },
  { name: 'Master Catalog', path: '/superadmin/catalog' },
  { name: 'Policy Settings', path: '/superadmin/settings/policy' },
  { name: 'Payment Settings', path: '/superadmin/settings/payment' },
  { name: 'Banners', path: '/superadmin/banners' },
  { name: 'Platform Reporting', path: '/superadmin/reports' },
  { name: 'Payments & Payouts', path: '/superadmin/payments' },
  { name: 'Subscriptions', path: '/superadmin/subscriptions' },
  { name: 'Wallet Schemes', path: '/superadmin/wallet' },
  { name: 'Lead Management', path: '/superadmin/enquiries' },
  { name: 'Collaborators', path: '/superadmin/collaborators' },
  { name: 'Complaints', path: '/superadmin/complaints' },
  { name: 'Audit Log', path: '/superadmin/audit-log' },
];

export default function SuperAdminLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const pathname = usePathname();
  const router = useRouter();

  const handleLogout = async () => {
    try {
      const res = await fetch('/api/auth/logout', { method: 'POST' });
      if (res.ok) {
        router.push('/login');
        router.refresh();
      }
    } catch (error) {
      console.error('Logout failed', error);
    }
  };

  return (
    <div className={styles.layoutContainer}>
      {/* Sidebar */}
      <aside className={styles.sidebar}>
        <div className={styles.sidebarHeader}>
          <div className={styles.logoText}>BookALook</div>
        </div>
        
        <nav className={styles.navMenu}>
          {navItems.map((item) => (
            <Link
              key={item.path}
              href={item.path}
              className={`${styles.navItem} ${
                pathname === item.path ? styles.activeNavItem : ''
              }`}
            >
              {item.name}
            </Link>
          ))}
        </nav>

        <div className={styles.sidebarFooter}>
          <button onClick={handleLogout} className={styles.logoutButton}>
            Sign Out
          </button>
        </div>
      </aside>

      {/* Main Content Area */}
      <div className={styles.mainContentWrapper}>
        <header className={styles.topbar}>
          <div className={styles.userProfile}>
            <div style={{ textAlign: 'right' }}>
              <div className={styles.userName}>Super Admin</div>
              <div className={styles.userRole}>Portal Manager</div>
            </div>
            <div className={styles.userAvatar}>SA</div>
          </div>
        </header>

        <main className={styles.mainContent}>
          {children}
        </main>
      </div>
    </div>
  );
}
