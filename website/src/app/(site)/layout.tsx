import SiteFooter from '@/components/site/SiteFooter';
import SiteHeader from '@/components/site/SiteHeader';

/**
 * The public marketing/legal site shell.
 *
 * This is a route group rather than a change to the root layout on purpose.
 * `/login`, `/superadmin/*` and `/s/[slug]` are also under the root layout, and
 * a public header, footer and gold-on-cream background on the admin login is not
 * a thing anyone wants. A group gives the public pages a shell while leaving
 * every other route exactly as it was.
 *
 * Group segments are excluded from the URL, so this layout serves `/` and
 * `/terms` exactly as before — the only change is that the header and footer
 * are rendered once here instead of being inlined in the landing page.
 */
export default function SiteLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="blk-site">
      <SiteHeader />
      {children}
      <SiteFooter />
    </div>
  );
}
