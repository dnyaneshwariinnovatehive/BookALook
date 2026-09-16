'use client';

import { useCallback, useEffect, useState } from 'react';
import styles from './page.module.css';

interface SalonRating {
  id: string;
  name: string;
  status: string;
  review_count: number;
  average: number;
  is_credible: boolean;
}

interface Platform {
  total_reviews: number;
  average: number;
  rated_salons: number;
  salons_below_three: number;
}

interface Review {
  id: string;
  rating: number;
  comment: string | null;
  customer_name: string;
  age_label: string;
}

const SORTS = [
  { key: 'worst', label: 'Worst rated' },
  { key: 'best', label: 'Best rated' },
  { key: 'most_rated', label: 'Most rated' },
];

export default function PlatformReviewsPage() {
  const [salons, setSalons] = useState<SalonRating[]>([]);
  const [platform, setPlatform] = useState<Platform | null>(null);
  const [sort, setSort] = useState('worst');
  const [search, setSearch] = useState('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  // The salon whose reviews are being read.
  const [openSalon, setOpenSalon] = useState<SalonRating | null>(null);
  const [reviews, setReviews] = useState<Review[]>([]);
  const [loadingReviews, setLoadingReviews] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const params = new URLSearchParams({ sort });
      if (search.trim()) params.set('search', search.trim());

      const res = await fetch(`/api/proxy/superadmin/reviews?${params}`, { cache: 'no-store' });
      const json = await res.json();
      if (!json.success) throw new Error(json.message || 'Could not load ratings');

      setSalons(json.data || []);
      setPlatform(json.platform || null);
      setError('');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not load ratings');
    } finally {
      setLoading(false);
    }
  }, [sort, search]);

  useEffect(() => {
    const timer = setTimeout(load, search ? 400 : 0);
    return () => clearTimeout(timer);
  }, [load, search]);

  const readReviews = async (salon: SalonRating) => {
    setOpenSalon(salon);
    setReviews([]);
    setLoadingReviews(true);

    try {
      const res = await fetch(`/api/proxy/superadmin/salons/${salon.id}/reviews?with_comment=1`, {
        cache: 'no-store',
      });
      const json = await res.json();
      if (json.success) setReviews(json.reviews || []);
    } catch {
      // Left empty; the modal says so.
    } finally {
      setLoadingReviews(false);
    }
  };

  return (
    <div className={styles.container}>
      <div className={styles.header}>
        <h1 className={styles.title}>Ratings</h1>
        <p className={styles.subtitle}>
          Every salon customers have rated, worst first. A salon needs at least
          three ratings before its average is worth acting on — the rest are
          marked.
        </p>
      </div>

      {platform && (
        <div className={styles.statRow}>
          <div className={styles.stat}>
            <span className={styles.statValue}>{platform.average || '—'}</span>
            <span className={styles.statLabel}>Platform average</span>
          </div>
          <div className={styles.stat}>
            <span className={styles.statValue}>{platform.total_reviews}</span>
            <span className={styles.statLabel}>Ratings given</span>
          </div>
          <div className={styles.stat}>
            <span className={styles.statValue}>{platform.rated_salons}</span>
            <span className={styles.statLabel}>Salons rated</span>
          </div>
          <div className={`${styles.stat} ${platform.salons_below_three > 0 ? styles.statAlert : ''}`}>
            <span className={styles.statValue}>{platform.salons_below_three}</span>
            <span className={styles.statLabel}>Below 3 stars</span>
          </div>
        </div>
      )}

      <div className={styles.filters}>
        <input
          className={styles.searchInput}
          placeholder="Search salons…"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        <div className={styles.sortGroup}>
          {SORTS.map((option) => (
            <button
              key={option.key}
              className={`${styles.filterChip} ${sort === option.key ? styles.filterChipActive : ''}`}
              onClick={() => setSort(option.key)}
            >
              {option.label}
            </button>
          ))}
        </div>
      </div>

      {loading ? (
        <div className={styles.empty}>Loading…</div>
      ) : error ? (
        <div className={styles.empty} style={{ color: 'var(--color-danger)' }}>{error}</div>
      ) : salons.length === 0 ? (
        <div className={styles.empty}>No salon has been rated yet.</div>
      ) : (
        <div className={styles.tableWrap}>
          <table className={styles.table}>
            <thead>
              <tr>
                <th className={styles.th}>Salon</th>
                <th className={styles.th}>Rating</th>
                <th className={styles.th}>Ratings</th>
                <th className={styles.th}>Status</th>
                <th className={styles.th} style={{ textAlign: 'right' }}>Action</th>
              </tr>
            </thead>
            <tbody>
              {salons.map((salon) => (
                <tr key={salon.id} className={styles.tr}>
                  <td className={`${styles.td} ${styles.salonName}`}>{salon.name}</td>
                  <td className={styles.td}>
                    <span
                      className={`${styles.rating} ${
                        salon.is_credible && salon.average < 3 ? styles.ratingBad : ''
                      }`}
                    >
                      ★ {salon.average.toFixed(1)}
                    </span>
                    {!salon.is_credible && (
                      <span className={styles.tooFew}>too few to judge</span>
                    )}
                  </td>
                  <td className={styles.td}>{salon.review_count}</td>
                  <td className={styles.td}>
                    <span className={styles.status}>{salon.status.replace('_', ' ')}</span>
                  </td>
                  <td className={styles.td} style={{ textAlign: 'right' }}>
                    <button className={styles.linkButton} onClick={() => readReviews(salon)}>
                      Read reviews
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {openSalon && (
        <div className={styles.overlay} onClick={() => setOpenSalon(null)}>
          <div className={styles.modal} onClick={(e) => e.stopPropagation()}>
            <h2 className={styles.modalTitle}>{openSalon.name}</h2>
            <p className={styles.modalSub}>
              ★ {openSalon.average.toFixed(1)} from {openSalon.review_count}{' '}
              {openSalon.review_count === 1 ? 'rating' : 'ratings'} · showing those with comments
            </p>

            {loadingReviews ? (
              <p className={styles.modalNote}>Loading…</p>
            ) : reviews.length === 0 ? (
              <p className={styles.modalNote}>No written reviews for this salon.</p>
            ) : (
              <div className={styles.reviewList}>
                {reviews.map((review) => (
                  <div key={review.id} className={styles.reviewItem}>
                    <div className={styles.reviewHead}>
                      <strong>{review.customer_name}</strong>
                      <span>{review.age_label}</span>
                    </div>
                    <div className={styles.reviewStars}>
                      {'★'.repeat(review.rating)}
                      <span className={styles.dimStars}>{'★'.repeat(5 - review.rating)}</span>
                    </div>
                    {review.comment && <p className={styles.reviewComment}>{review.comment}</p>}
                  </div>
                ))}
              </div>
            )}

            <div className={styles.modalActions}>
              <button className={styles.secondaryButton} onClick={() => setOpenSalon(null)}>
                Close
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
