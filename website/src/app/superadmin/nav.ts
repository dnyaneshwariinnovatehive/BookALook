import type { IconName } from '@/components/admin/Icon';

export interface NavItem {
  name: string;
  path: string;
  icon: IconName;
  /** Extra words the command palette should match on. */
  keywords?: string;
  /** Parts of the page the command palette can jump straight to. */
  sections?: NavSection[];
}

/**
 * A card, panel or tab inside a page. The palette opens the page, switches to
 * `tab` when given (matched on the tab's visible text), then scrolls to the
 * heading (an h1–h3, or an element with data-section) named `heading`,
 * defaulting to `name`. A tab-only entry sets `heading: ''`.
 */
export interface NavSection {
  name: string;
  tab?: string;
  heading?: string;
  keywords?: string;
}

const tabSections = (tab: string, names: string[], keywords = ''): NavSection[] =>
  names.map((name) => ({ name, tab, keywords }));

export interface NavGroup {
  label: string;
  items: NavItem[];
}

export const navGroups: NavGroup[] = [
  {
    label: 'Overview',
    items: [
      { name: 'Dashboard', path: '/superadmin', icon: 'dashboard', keywords: 'home kpi overview', sections: [
        ...tabSections('Marketplace overview', ['Revenue & bookings', 'Booking mix', 'Top salons', 'Top services', 'Awaiting approval']),
        { name: 'Money in pocket', tab: 'BookALook revenue', keywords: 'cash held balance owed bank kept' },
        ...tabSections('BookALook revenue', ['Revenue over time', 'Where it comes from', 'Top paying salons', 'Revenue by city', 'Monthly ledger', 'Latest money in'], 'earnings income'),
      ] },
      { name: 'Appointments', path: '/superadmin/appointments', icon: 'calendar', keywords: 'bookings schedule' },
      { name: 'Platform Reporting', path: '/superadmin/reports', icon: 'chart', keywords: 'analytics reports revenue', sections: [
        ...['Overview', 'Money', 'Bookings', 'Cities & areas', 'Salons & teams', 'Services', 'Customers', 'Engagement']
          .map((tab) => ({ name: `${tab} tab`, tab, heading: '', keywords: 'analytics report' })),
        ...tabSections('Overview', ['GMV and bookings', 'Booking outcomes', 'Money in and money earned', 'Highlights']),
        ...tabSections('Money', ['Money movement over time', 'Money in pocket — right now', 'How bookings were paid', 'Payment channels', 'What BookALook earned', 'Plan payments by plan', 'Refunds', 'Refunds by salon', 'Payouts for cycles that closed in range'], 'money finance'),
        ...tabSections('Bookings', ['Outcomes over time', 'Where bookings end up', 'App booking funnel', 'Peak times', 'By weekday', 'How far ahead people book', 'Who cancels', 'Other signals'], 'heatmap busy hours'),
        ...tabSections('Cities & areas', ['GMV by city', 'GMV by area', 'Cities', 'Areas', 'Demand against supply', 'Reliability by area'], 'location sub-area'),
        ...tabSections('Salons & teams', ['Salon leaderboard', 'Top by GMV', 'Fastest growing', 'Most loyal customers', 'Watch list', 'Best rated in range', 'Quiet salons', 'Team utilisation'], 'staff stylist providers'),
        ...tabSections('Services', ['Revenue by category', 'Categories', 'Top services by revenue', 'Fastest growing services', 'Best earners per chair-hour', 'Services', 'Combos', 'Added at the counter', 'First-time offers'], 'catalog'),
        ...tabSections('Customers', ['New and returning customers', 'Visits per customer', 'Cohort retention', 'Who visits', 'Top customers', 'App sign-ups'], 'retention'),
        ...tabSections('Engagement', ['Reviews and rating over time', 'Rating spread', 'Lowest rated salons', 'Complaints', 'Campaign reach', 'Campaigns by template', 'Most active marketers', 'WhatsApp messages', 'In-app notifications', 'Reward coins']),
      ] },
    ],
  },
  {
    label: 'Salons',
    items: [
      { name: 'Salon Approval Queue', path: '/superadmin/salon-approval', icon: 'approval', keywords: 'enquiries onboarding pending' },
      { name: 'Salon Directory', path: '/superadmin/salons', icon: 'store', keywords: 'partners list' },
      { name: 'Collaborators', path: '/superadmin/collaborators', icon: 'userPlus', keywords: 'onboarding team', sections: [{ name: 'Add new collaborator' }, { name: 'All collaborators' }] },
      { name: 'Subscriptions', path: '/superadmin/subscriptions', icon: 'crown', keywords: 'plans billing commission', sections: [
        ...['Overview', 'Requests', 'Payments', 'Salons', 'Plans', 'Commission model']
          .map((tab) => ({ name: `${tab} tab`, tab, heading: '' })),
        { name: 'Plan mix', tab: 'Overview' },
        { name: 'Recent payments', tab: 'Overview' },
      ] },
      { name: 'Wallet Schemes', path: '/superadmin/wallet-schemes', icon: 'coins', keywords: 'coins rewards' },
      { name: 'Payouts & Distribution', path: '/superadmin/payouts', icon: 'wallet', keywords: 'settlements money', sections: [{ name: 'Needs action', tab: 'Needs action', heading: '', keywords: 'inbox verify approve' }, { name: 'Salon settlements', tab: 'By cycle', keywords: 'weekly monthly cycle' }] },
      { name: 'Overdue Salons', path: '/superadmin/commission-dues', icon: 'clock', keywords: 'commission dues unpaid owes overdue grace lock collections' },
      { name: 'Salon Requests', path: '/superadmin/salon-requests', icon: 'message', keywords: 'support contact messages settlement query payout request help' },
    ],
  },
  {
    label: 'Customers',
    items: [
      { name: 'Customers', path: '/superadmin/customers', icon: 'users', keywords: 'users clients', sections: ['Customer growth', 'Account status', 'Where customers are', 'Most valuable', 'No-show watch', 'Directory'].map((name) => ({ name })) },
      { name: 'First-Time Offers', path: '/superadmin/offers', icon: 'percent', keywords: 'offers discounts promotions first-time deals first time customer acquisition' },
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
      { name: 'Policy Settings', path: '/superadmin/settings/policy', icon: 'sliders', keywords: 'rules configuration', sections: [
        { name: 'Service Catalog', tab: 'Services', keywords: 'combos limit' },
        { name: 'Customer payments', tab: 'Bookings', keywords: 'advance full payment razorpay online' },
        { name: 'Bookings & cancellations', tab: 'Bookings' },
        { name: 'Customer cancellation & no-show limits', tab: 'Bookings', keywords: 'block standing' },
        { name: 'Subscriptions & reminders', tab: 'Subscriptions' },
        { name: 'Commission dues', tab: 'Commission dues', keywords: 'overdue ladder lock' },
        { name: 'Rewards & coins', tab: 'Coins', keywords: 'wallet coin value' },
        { name: 'Salon QR codes & the app', tab: 'Links & QR', keywords: 'play store link' },
        { name: 'Where salons pay BookALook', tab: 'Payments', keywords: 'bank upi account' },
        { name: 'WhatsApp Notifications', tab: 'WhatsApp' },
      ] },
      { name: 'App Versions', path: '/superadmin/app-versions', icon: 'smartphone', keywords: 'releases updates force update version build customer partner', sections: [{ name: 'App Distribution Status' }, { name: 'Version Management Audit Trail' }] },
      { name: 'Invoice Format', path: '/superadmin/settings/invoice', icon: 'receipt', keywords: 'invoice receipt branding tax letterhead' },
      { name: 'Notifications', path: '/superadmin/notifications', icon: 'bell', keywords: 'messages alerts templates' },
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
