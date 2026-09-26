'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { DataTable, SearchInput, cx, useDebounced, useTableState, type DataColumn } from '@/components/admin/ui';
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

interface PageMeta {
  current_page: number;
  last_page: number;
  per_page: number;
  total: number;
}

export default function PlatformReviewsPage() {
  const [salons, setSalons] = useState<SalonRating[]>([]);
  const [platform, setPlatform] = useState<Platform | null>(null);
  const [meta, setMeta] = useState<PageMeta>({ current_page: 1, last_page: 1, per_page: 20, total: 0 });
  // Null once a column header has been clicked — the header sort then wins.
  const [preset, setPreset] = useState<string | null>('worst');
  const [search, setSearch] = useState('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const debouncedSearch = useDebounced(search, 400);

  // The salon whose reviews are being read.
  const [openSalon, setOpenSalon] = useState<SalonRating | null>(null);
  const [reviews, setReviews] = useState<Review[]>([]);
  const [loadingReviews, setLoadingReviews] = useState(false);

  const readReviews = useCallback(async (salon: SalonRating) => {
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
  }, []);

  const columns = useMemo<DataColumn<SalonRating>[]>(
    () => [
      {
        key: 'name',
        header: 'Salon',
        sortValue: (s) => s.name,
        render: (s) => <span className={styles.salonName}>{s.name}</span>,
      },
      {
        key: 'average',
        header: 'Rating',
        align: 'right',
        sortValue: (s) => s.average,
        render: (s) => (
          <span className={cx(styles.rating, s.is_credible && s.average < 3 && styles.ratingBad)}>
            ★ {s.average.toFixed(1)}
            {!s.is_credible && <span className={styles.tooFew}>too few to judge</span>}
          </span>
        ),
      },
      {
        key: 'review_count',
        header: 'Ratings',
        align: 'right',
        sortValue: (s) => s.review_count,
        render: (s) => s.review_count.toLocaleString('en-IN'),
      },
      {
        key: 'status',
        header: 'Status',
        sortValue: (s) => s.status,
        render: (s) => <span className={styles.status}>{s.status.replace('_', ' ')}</span>,
      },
      {
        key: 'action',
        header: 'Action',
        align: 'right',
        render: (s) => (
          <button className={styles.linkButton} onClick={() => readReviews(s)}>
            Read reviews
          </button>
        ),
      },
    ],
    [readReviews],
  );

  // Server mode: ratings are aggregated in PHP, so ordering and paging happen there.
  const table = useTableState<SalonRating>({
    rows: salons,
    columns,
    mode: 'server',
    total: meta.total,
    lastPage: meta.last_page,
  });

  const { page, perPage, sort } = table;

  // Rapid paging or header clicks can land out of order; only the newest wins.
  const requestId = useRef(0);

  const load = useCallback(async () => {
    const id = ++requestId.current;
    setLoading(true);
    try {
      const params = new URLSearchParams({
        sort: preset ?? 'worst',
        page: String(page),
        per_page: String(perPage),
      });
      if (debouncedSearch.trim()) params.set('search', debouncedSearch.trim());
      if (sort) {
        params.set('column', sort.key);
        params.set('direction', sort.dir);
      }

      const res = await fetch(`/api/proxy/superadmin/reviews?${params}`, { cache: 'no-store' });
      const json = await res.json();
      if (id !== requestId.current) return;
      if (!json.success) throw new Error(json.message || 'Could not load ratings');

      setSalons(json.data || []);
      setPlatform(json.platform || null);
      if (json.meta) setMeta(json.meta);
      setError('');
    } catch (e) {
      if (id !== requestId.current) return;
      setError(e instanceof Error ? e.message : 'Could not load ratings');
    } finally {
      if (id === requestId.current) setLoading(false);
    }
  }, [preset, debouncedSearch, page, perPage, sort]);

  useEffect(() => {
    const timer = setTimeout(load, 0);
    return () => clearTimeout(timer);
  }, [load]);

  // A curated view and a header sort are alternatives, never both.
  const pickPreset = (key: string) => {
    setPreset(key);
    table.clearSort();
  };

  const onSortColumn = (key: string) => {
    table.toggleSort(key);
    setPreset(null);
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
        <div className={styles.searchField}>
          <SearchInput
            value={search}
            onChange={(v) => {
              setSearch(v);
              table.setPage(1);
            }}
            placeholder="Search salons…"
            ariaLabel="Search salons"
          />
        </div>
        <div className={styles.sortGroup}>
          {SORTS.map((option) => (
            <button
              key={option.key}
              className={`${styles.filterChip} ${preset === option.key ? styles.filterChipActive : ''}`}
              onClick={() => pickPreset(option.key)}
            >
              {option.label}
            </button>
          ))}
        </div>
      </div>

      <div className={styles.tableWrap}>
        <DataTable
          columns={columns}
          rows={salons}
          rowKey={(s) => s.id}
          loading={loading && salons.length === 0}
          error={error || undefined}
          sort={sort}
          onSort={onSortColumn}
          page={page}
          lastPage={meta.last_page}
          total={meta.total}
          onPage={table.setPage}
          perPage={perPage}
          onPerPageChange={table.changePerPage}
          noun="salons"
          exportName="ratings"
          caption="Salon ratings, worst first"
          empty={{
            title: search ? `No salon matches “${search}”` : 'No salon has been rated yet',
            hint: search ? 'Try a different name, or clear the search.' : 'Ratings appear here once customers start rating salons.',
          }}
        />
      </div>

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
