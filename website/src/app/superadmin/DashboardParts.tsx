'use client';

import Link from 'next/link';
import Icon, { type IconName } from '@/components/admin/Icon';
import styles from './dashboard.module.css';

/* Shared by the dashboard's Overview and BookALook revenue tabs. */


const TONES = {
  violet: styles.toneViolet,
  teal: styles.toneTeal,
  amber: styles.toneAmber,
  blue: styles.toneBlue,
} as const;

export function KpiCard({
  href, label, icon, tone, loading, value, delta, sub,
}: {
  href?: string;
  label: string;
  icon: IconName;
  tone: keyof typeof TONES;
  loading: boolean;
  value: string;
  delta?: { pct: number; dir: 'up' | 'down' | 'flat' };
  sub: string;
}) {
  const body = (
    <>
      <div className={styles.kpiHeader}>
        <span className={`${styles.kpiIcon} ${TONES[tone]}`}><Icon name={icon} size={20} /></span>
        {href && <Icon name="arrowRight" size={16} className={styles.kpiArrow} />}
      </div>
      <div className={styles.kpiLabel}>{label}</div>
      {loading ? (
        <div className={`${styles.skeleton} ${styles.skeletonValue}`} />
      ) : (
        <div className={styles.kpiValue}>{value}</div>
      )}
      <div className={styles.kpiTrend}>
        {delta && !loading && (
          <span className={`${styles.deltaChip} ${delta.dir === 'up' ? styles.deltaUp : delta.dir === 'down' ? styles.deltaDown : styles.deltaFlat}`}>
            {delta.dir !== 'flat' && <Icon name={delta.dir === 'up' ? 'trendUp' : 'trendDown'} size={13} strokeWidth={2.2} />}
            {delta.pct}%
          </span>
        )}
        <span className={styles.trendSub}>{sub}</span>
      </div>
    </>
  );

  return href ? (
    <Link href={href} className={`${styles.kpiCard} ${styles.clickableCard}`}>{body}</Link>
  ) : (
    <div className={styles.kpiCard}>{body}</div>
  );
}

export function EmptyState({ icon, title, hint }: { icon: IconName; title: string; hint: string }) {
  return (
    <div className={styles.empty}>
      <span className={styles.emptyIcon}><Icon name={icon} size={20} /></span>
      <div className={styles.emptyTitle}>{title}</div>
      <div className={styles.emptyHint}>{hint}</div>
    </div>
  );
}

