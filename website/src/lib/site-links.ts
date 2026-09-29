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
 * The registered entity name is kept apart from the street address rather than
 * being folded into one string. The policies set this out as a letterhead, and
 * a single "\n"-joined value renders as one run-on line in HTML and in Flutter
 * unless every consumer is taught about line breaks. Separate values stay
 * separate wherever they are printed.
 *
 * [PLACEHOLDER] The approved policy documents name no phone number, so there is
 * nothing to print under "Contact us" yet. Once a support number exists, add it
 * to the policy documents and to this file.
 */
export const CONTACT_COMPANY = 'BOOKALOOK PRIVATE LIMITED';
export const CONTACT_EMAIL = 'bookalook01@gmail.com';
export const CONTACT_ADDRESS =
  'PLOT NO 44 SR NO 17/22, DEVGIRI COLONY N-2, Aurangabad (MH), Aurangabad, Aurangabad- 431001, Maharashtra';
