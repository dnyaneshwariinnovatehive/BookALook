import type { Metadata } from 'next';

// The page itself is a client component, so its title lives here.
export const metadata: Metadata = {
  title: 'For salons',
  description: 'List your salon on BookALook: online bookings, staff, walk-ins, billing and reports in one Partner App. Register your salon in two minutes.',
};

export default function PartnerLayout({ children }: { children: React.ReactNode }) {
  return children;
}
