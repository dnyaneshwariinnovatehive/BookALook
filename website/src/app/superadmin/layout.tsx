'use client';

import { useCallback, useEffect, useLayoutEffect, useState } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import Icon from '@/components/admin/Icon';
import CommandPalette from '@/components/admin/CommandPalette';
import { useRootAttribute, useTheme } from '@/lib/theme';
import { matchNav, navGroups } from './nav';
import styles from './layout.module.css';

const SIDEBAR_KEY = 'sa_sidebar';

export default function SuperAdminLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const pathname = usePathname();
  const router = useRouter();
  const { isDark, toggle: toggleTheme } = useTheme();

  // The collapsed rail lives on <html data-sidebar-collapsed> (set before paint
  // by the inline script); React just reads it.
  const collapsed = useRootAttribute('data-sidebar-collapsed');
  // The drawer remembers the page it was opened on, so navigating closes it.
  const [drawerPath, setDrawerPath] = useState<string | null>(null);
  const drawerOpen = drawerPath === pathname;
  const setDrawerOpen = (open: boolean) => setDrawerPath(open ? pathname : null);
  const [paletteOpen, setPaletteOpen] = useState(false);
  const [pendingCount, setPendingCount] = useState(0);

  // Re-apply after React's dev-mode remount clears <html> attributes.
  useLayoutEffect(() => {
    let stored: string | null = null;
    try { stored = localStorage.getItem(SIDEBAR_KEY); } catch {}
    document.documentElement.toggleAttribute('data-sidebar-collapsed', stored === 'collapsed');
  }, []);

  const toggleCollapsed = () => {
    const next = !collapsed;
    document.documentElement.toggleAttribute('data-sidebar-collapsed', next);
    try { localStorage.setItem(SIDEBAR_KEY, next ? 'collapsed' : 'expanded'); } catch {}
  };

  // Ctrl/⌘ + K opens the command palette from anywhere.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault();
        setPaletteOpen((o) => !o);
      } else if (e.key === 'Escape') {
        setDrawerPath(null);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  // Pending approvals badge — refreshed on navigation so it drops as soon as
  // a salon is approved.
  useEffect(() => {
    let cancelled = false;
    fetch('/api/proxy/superadmin/salons/pending')
      .then((r) => (r.ok ? r.json() : null))
      .then((p) => {
        if (cancelled || !p) return;
        const list = Array.isArray(p.data) ? p.data : Array.isArray(p.salons) ? p.salons : [];
        setPendingCount(list.length);
      })
      .catch(() => {});
    return () => { cancelled = true; };
  }, [pathname]);

  const handleLogout = useCallback(async () => {
    try {
      const res = await fetch('/api/auth/logout', { method: 'POST' });
      if (res.ok) {
        router.push('/login');
        router.refresh();
      }
    } catch (error) {
      console.error('Logout failed', error);
    }
  }, [router]);

  const current = matchNav(pathname);

  return (
    <div className={styles.layoutContainer}>
      <a href="#main-content" className={styles.skipLink}>Skip to content</a>

      {drawerOpen && <div className={styles.scrim} onClick={() => setDrawerOpen(false)} aria-hidden="true" />}

      <aside className={`${styles.sidebar} ${drawerOpen ? styles.sidebarOpen : ''}`} aria-label="Primary">
        <div className={styles.sidebarHeader}>
          <Link href="/superadmin" className={styles.brand} aria-label="BookALook admin home">
            <Image src="/logo.png" alt="BookALook" width={150} height={26} className={`${styles.logoFull} ${styles.logoLight}`} priority />
            <Image src="/logo-dark.png" alt="" width={150} height={26} className={`${styles.logoFull} ${styles.logoDark}`} priority />
            <span className={styles.logoMark} aria-hidden="true">B</span>
          </Link>
          <button
            type="button"
            className={`${styles.iconBtn} ${styles.drawerClose}`}
            onClick={() => setDrawerOpen(false)}
            aria-label="Close menu"
          >
            <Icon name="close" />
          </button>
        </div>

        <nav className={styles.navMenu}>
          {navGroups.map((group) => (
            <div key={group.label} className={styles.navGroup}>
              <div className={styles.navGroupLabel}>{group.label}</div>
              {group.items.map((item) => {
                const active = current?.item.path === item.path;
                const badge = item.path === '/superadmin/salon-approval' && pendingCount > 0 ? pendingCount : 0;
                return (
                  <Link
                    key={item.path}
                    href={item.path}
                    className={`${styles.navItem} ${active ? styles.activeNavItem : ''}`}
                    aria-current={active ? 'page' : undefined}
                    title={collapsed ? item.name : undefined}
                  >
                    <Icon name={item.icon} className={styles.navIcon} />
                    <span className={styles.navLabel}>{item.name}</span>
                    {badge > 0 && <span className={styles.navBadge}>{badge > 99 ? '99+' : badge}</span>}
                  </Link>
                );
              })}
            </div>
          ))}
        </nav>

        <div className={styles.sidebarFooter}>
          <div className={styles.userCard}>
            <div className={styles.userAvatar}>SA</div>
            <div className={styles.userMeta}>
              <div className={styles.userName}>Super Admin</div>
              <div className={styles.userRole}>Portal Manager</div>
            </div>
            <button type="button" onClick={handleLogout} className={styles.logoutButton} title="Sign out" aria-label="Sign out">
              <Icon name="logout" size={17} />
            </button>
          </div>
        </div>
      </aside>

      <div className={styles.mainContentWrapper}>
        <header className={styles.topbar}>
          <button type="button" className={`${styles.iconBtn} ${styles.menuBtn}`} onClick={() => setDrawerOpen(true)} aria-label="Open menu">
            <Icon name="menu" />
          </button>
          <button
            type="button"
            className={`${styles.iconBtn} ${styles.collapseBtn}`}
            onClick={toggleCollapsed}
            aria-label={collapsed ? 'Expand sidebar' : 'Collapse sidebar'}
            title={collapsed ? 'Expand sidebar' : 'Collapse sidebar'}
          >
            <Icon name="panel" />
          </button>

          <nav className={styles.breadcrumb} aria-label="Breadcrumb">
            {current?.group.label !== current?.item.name && (
              <>
                <span className={styles.crumbGroup}>{current?.group.label ?? 'Admin'}</span>
                <Icon name="chevronRight" size={14} className={styles.crumbSep} />
              </>
            )}
            {current?.isDetail ? (
              <>
                <Link href={current.item.path} className={styles.crumbLink}>{current.item.name}</Link>
                <Icon name="chevronRight" size={14} className={styles.crumbSep} />
                <span className={styles.crumbCurrent}>Details</span>
              </>
            ) : (
              <span className={styles.crumbCurrent}>{current?.item.name ?? 'Dashboard'}</span>
            )}
          </nav>

          <div className={styles.topbarActions}>
            <button type="button" className={styles.searchTrigger} onClick={() => setPaletteOpen(true)}>
              <Icon name="search" size={16} />
              <span className={styles.searchText}>Search or jump to…</span>
              <kbd className={styles.searchKbd}>Ctrl K</kbd>
            </button>

            <button
              type="button"
              onClick={toggleTheme}
              className={styles.themeToggleBtn}
              aria-label={`Switch to ${isDark ? 'light' : 'dark'} mode`}
              title={`Switch to ${isDark ? 'light' : 'dark'} mode`}
            >
              <span className={`${styles.themeIcon} ${isDark ? styles.themeIconHidden : ''}`}><Icon name="moon" /></span>
              <span className={`${styles.themeIcon} ${isDark ? '' : styles.themeIconHidden}`}><Icon name="sun" /></span>
            </button>
          </div>
        </header>

        <main id="main-content" className={styles.mainContent}>
          <div className={styles.pageFrame} key={pathname}>
            {children}
          </div>
        </main>
      </div>

      {paletteOpen && (
        <CommandPalette
          open
          onClose={() => setPaletteOpen(false)}
          isDark={isDark}
          onToggleTheme={toggleTheme}
          onSignOut={handleLogout}
        />
      )}
    </div>
  );
}
