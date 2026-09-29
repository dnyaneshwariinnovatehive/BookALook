/**
 * Outbound links that both the landing page and the site footer need.
 *
 * These live here rather than in a component because the footer and the landing
 * page each render store badges: the footer has them under "Download", the
 * landing page has them in the customer and salon sections. Two copies of the
 * same placeholder URL is one more thing to forget when the real listings go
 * live.
 */

// [PLACEHOLDER] App store listing URLs — replace with the real live listings.
// Mirrors the same placeholders used in the superadmin settings policy page.
export const CUSTOMER_APP_STORE_URL = 'https://apps.apple.com/in/app/bookalook/id0000000000'; // [PLACEHOLDER]
export const CUSTOMER_PLAY_STORE_URL = 'https://play.google.com/store/apps/details?id=com.bookalook.customer'; // [PLACEHOLDER]
export const PARTNER_APP_STORE_URL = 'https://apps.apple.com/in/app/bookalook-partner/id0000000000'; // [PLACEHOLDER]
export const PARTNER_PLAY_STORE_URL = 'https://play.google.com/store/apps/details?id=com.bookalook.partner'; // [PLACEHOLDER]

// [PLACEHOLDER] Social handles — replace with the real branded profiles.
export const SOCIAL_URLS = {
  instagram: 'https://www.instagram.com/bookalook', // [PLACEHOLDER]
  facebook: 'https://www.facebook.com/bookalook', // [PLACEHOLDER]
  x: 'https://x.com/bookalook', // [PLACEHOLDER]
};

/**
 * Contact details for the legal pages.
 *
 * [PLACEHOLDER] The approved policy documents name only an email address and a
 * registered address — no phone number — so there is nothing to put here yet.
 * Once a support number exists, add it to the four legal documents and show it
 * under "Contact us" on each of them.
 */
export const CONTACT_EMAIL = 'bookalook01@gmail.com';
export const CONTACT_ADDRESS =
  'Ambikanagar Mukundwadi N-2 CIDCO, Chhatrapati Sambhajinagar, Maharashtra, India';
