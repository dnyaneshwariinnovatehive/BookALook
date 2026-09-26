'use client';

import { useLayoutEffect } from 'react';
import { usePathname } from 'next/navigation';
import { applyThemeClass, resolveIsDark } from '@/lib/theme';

/**
 * Re-evaluates the theme on client-side navigation, so dark mode never leaks
 * from the admin onto the public pages (and comes back when returning).
 */
export default function ThemeScope() {
  const pathname = usePathname();

  useLayoutEffect(() => {
    applyThemeClass(resolveIsDark(pathname));
  }, [pathname]);

  return null;
}
