import type { IconName } from '@/components/admin/Icon';

export interface NavItem {
  name: string;
  path: string;
  icon: IconName;
  /** Extra words the command palette should match on. */
  keywords?: string;
}

export interface NavGroup {
  label: string;
  items: NavItem[];
}

export const navGroups: NavGroup[] = [
  {
    label: 'Overview',
    items: [
      { name: 'Dashboard', path: '/superadmin', icon: 'dashboard', keywords: 'home kpi overview' },
      { name: 'Appointments', path: '/superadmin/appointments', icon: 'calendar', keywords: 'bookings schedule' },
      { name: 'Platform Reporting', path: '/superadmin/reports', icon: 'chart', keywords: 'analytics reports revenue' },
    ],
  },
  {
    label: 'Salons',
    items: [
      { name: 'Salon Approval Queue', path: '/superadmin/salon-approval', icon: 'approval', keywords: 'enquiries onboarding pending' },
      { name: 'Salon Directory', path: '/superadmin/salons', icon: 'store', keywords: 'partners list' },
      { name: 'Collaborators', path: '/superadmin/collaborators', icon: 'userPlus', keywords: 'onboarding team' },
      { name: 'Subscriptions', path: '/superadmin/subscriptions', icon: 'crown', keywords: 'plans billing commission' },
      { name: 'Wallet Schemes', path: '/superadmin/wallet-schemes', icon: 'coins', keywords: 'coins rewards' },
      { name: 'Payouts & Distribution', path: '/superadmin/payouts', icon: 'wallet', keywords: 'settlements money' },
    ],
  },
  {
    label: 'Customers',
    items: [
      { name: 'Customers', path: '/superadmin/customers', icon: 'users', keywords: 'users clients' },
      { name: 'Ratings', path: '/superadmin/reviews', icon: 'star', keywords: 'reviews feedback' },
      { name: 'Complaints', path: '/superadmin/complaints', icon: 'alert', keywords: 'issues disputes' },
    ],
  },
  {
    label: 'Platform',
    items: [
      { name: 'Master Catalog', path: '/superadmin/catalog', icon: 'catalog', keywords: 'services categories templates' },
      { name: 'Areas', path: '/superadmin/areas', icon: 'pin', keywords: 'localities cities sub-areas' },
      { name: 'Banners', path: '/superadmin/banners', icon: 'image', keywords: 'promotions ads' },
      { name: 'WhatsApp Marketing', path: '/superadmin/marketing', icon: 'message', keywords: 'campaigns templates' },
      { name: 'Policy Settings', path: '/superadmin/settings/policy', icon: 'sliders', keywords: 'rules configuration' },
      { name: 'Audit Log', path: '/superadmin/audit-log', icon: 'history', keywords: 'activity trail' },
    ],
  },
];

export const allNavItems: NavItem[] = navGroups.flatMap((g) => g.items);

/** The nav entry a path belongs to — the longest matching prefix wins, so
 *  detail pages like /superadmin/salons/123 still light up their section. */
export function matchNav(pathname: string): { item: NavItem; group: NavGroup; isDetail: boolean } | null {
  let best: { item: NavItem; group: NavGroup } | null = null;
  for (const group of navGroups) {
    for (const item of group.items) {
      const hit = pathname === item.path || (item.path !== '/superadmin' && pathname.startsWith(item.path + '/'));
      if (hit && (!best || item.path.length > best.item.path.length)) best = { item, group };
    }
  }
  return best ? { ...best, isDetail: pathname !== best.item.path } : null;
}
