'use client';

import styles from './ThemeGlyph.module.css';

/**
 * The sun/moon on the theme toggle.
 *
 * Both are always in the DOM, so the swap is a single morph rather than a
 * cross-fade of two opacity tweens running on separate clocks. [data-glyph]
 * picks the resting state and the transitions in the module run from it in
 * whichever direction the theme actually moved.
 *
 * Sun leaving: the core collapses to the centre, the eight rays scatter on a
 * stagger, and the whole shape turns a quarter turn on the way out.
 * Moon arriving: the crescent rises and rotates in, overshooting its size
 * slightly before it settles.
 *
 * Durations are set in the stylesheet and sized to --theme-wipe-dur, so the
 * glyph finishes with the colour wipe rather than trailing it.
 */

/** Clockwise from the top, which is the order the rays unravel in. */
const RAYS = [0, 45, 90, 135, 180, 225, 270, 315];

export default function ThemeGlyph({ isDark }: { isDark: boolean }) {
  return (
    <span className={styles.glyph} data-glyph={isDark ? 'moon' : 'sun'}>
      <svg
        className={styles.sun}
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth={1.7}
        strokeLinecap="round"
        aria-hidden="true"
        focusable="false"
      >
        <circle className={styles.sunCore} cx="12" cy="12" r="4.1" fill="currentColor" stroke="none" />
        {RAYS.map((deg, i) => (
          <line
            key={deg}
            className={styles.sunRay}
            style={{ ['--ray-angle' as string]: `${deg}deg`, ['--ray-index' as string]: String(i) }}
            x1="12"
            y1="2.4"
            x2="12"
            y2="4.6"
          />
        ))}
      </svg>

      <svg
        className={styles.moon}
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth={1.7}
        strokeLinecap="round"
        strokeLinejoin="round"
        aria-hidden="true"
        focusable="false"
      >
        <path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z" fill="currentColor" stroke="none" />
        <circle className={styles.moonCrater} cx="9.4" cy="14.2" r="1.05" fill="currentColor" stroke="none" />
        <circle className={styles.moonCrater} cx="13.4" cy="16.6" r="0.7" fill="currentColor" stroke="none" />
      </svg>
    </span>
  );
}
