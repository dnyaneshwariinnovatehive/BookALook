'use client'; // Error boundaries must be Client Components

import { useEffect } from 'react';
import Link from 'next/link';
import Icon from '@/components/admin/Icon';
import styles from './error.module.css';

/**
 * Catches a crash inside any admin page so the shell (sidebar, search,
 * theme) stays usable and the admin can retry instead of facing a blank
 * screen.
 */
export default function AdminError({
  error,
  retry,
}: {
  error: Error & { digest?: string };
  retry: () => void;
}) {
  useEffect(() => {
    console.error(error);
  }, [error]);

  return (
    <div className={styles.wrap} role="alert">
      <span className={styles.icon}><Icon name="alert" size={24} /></span>
      <h1 className={styles.title}>This page ran into a problem</h1>
      <p className={styles.text}>
        Something unexpected came back while loading it. The rest of the admin still works — try again, or head back to the dashboard.
      </p>
      {error?.digest && <code className={styles.digest}>Ref: {error.digest}</code>}
      <div className={styles.actions}>
        <button type="button" className={styles.primary} onClick={() => retry()}>
          <Icon name="refresh" size={16} /> Try again
        </button>
        <Link href="/superadmin" className={styles.secondary}>Go to dashboard</Link>
      </div>
    </div>
  );
}
