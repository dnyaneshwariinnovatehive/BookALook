import { Outfit } from 'next/font/google';
import SiteFooter from '@/components/site/SiteFooter';
import SiteHeader from '@/components/site/SiteHeader';
import st from './site.module.css';

// The Customer App's typeface, so the site and the app read as one product.
const outfit = Outfit({ subsets: ['latin'], display: 'swap', variable: '--font-outfit' });

/**
 * The public marketing/legal site shell.
 *
 * This is a route group rather than a change to the root layout on purpose.
 * `/login`, `/superadmin/*` and `/s/[slug]` are also under the root layout, and
 * a public header and footer on the admin login is not a thing anyone wants. A
 * group gives the public pages a shell while leaving every other route exactly
 * as it was.
 *
 * Group segments are excluded from the URL, so this layout serves `/`,
 * `/partner` and `/terms` — the header and footer are rendered once here.
 */
export default function SiteLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className={`blk-site ${outfit.variable} ${st.site}`}>
      <SiteHeader />
      {children}
      <SiteFooter />
    </div>
  );
}
