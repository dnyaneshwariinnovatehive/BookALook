'use client';

import { useEffect, useState } from 'react';
import { useCities, useCity } from '@/lib/site-city';
import { Parallax, Reveal } from '../motion';
import st from '../site.module.css';
import h from './home.module.css';

/* ============================================================================
   Top salons near you — real salons from the same public directory the
   Customer App reads (`GET /api/customer/salons`).

   Nothing here is invented: the names, areas, ratings, photos and prices are
   whatever the directory returns for the chosen city and category. With no
   city chosen the directory answers with its busiest city and says which one,
   so the heading always names the place being shown. If the directory cannot
   be reached the section says so and points at the app.
   ============================================================================ */

export interface Category {
  id: string;
  name: string;
}

interface CategoryService {
  id: string;
  name: string;
  price: number;
}

interface Salon {
  id: string;
  name: string;
  address: string | null;
  gender_focus: string | null;
  cover_photo_url: string | null;
  avg_rating: number | null;
  review_count: number | null;
  is_serviceable: boolean;
  open_status_label: string | null;
  category_services: CategoryService[] | null;
}

interface Directory {
  salons: Salon[];
  city: { id: string; name: string } | null;
  suggested_city: { id: string; name: string; salon_count: number } | null;
}

const inr = (v: number) => `₹${Math.round(v).toLocaleString('en-IN')}`;

function SalonCard({ salon }: { salon: Salon }) {
  const [photoFailed, setPhotoFailed] = useState(false);
  const services = salon.category_services ?? [];
  const from = services.length ? Math.min(...services.map((s) => Number(s.price) || 0)) : null;
  const rated = (salon.review_count ?? 0) > 0 && salon.avg_rating;

  return (
    <article className={h.salon}>
      <div className={h.salonPhoto}>
        {salon.cover_photo_url && !photoFailed ? (
          // The cover is hosted wherever the salon's photos are, so this is a
          // plain lazy image rather than a remote pattern in next.config.
          // eslint-disable-next-line @next/next/no-img-element
          <img src={salon.cover_photo_url} alt={`${salon.name} salon`} loading="lazy" onError={() => setPhotoFailed(true)} />
        ) : (
          <span className={h.salonNoPhoto} aria-hidden="true">💈</span>
        )}
        <span className={h.verified}>🛡️ Verified partner</span>
        <span className={h.rating}>{rated ? `★ ${Number(salon.avg_rating).toFixed(1)}` : 'New'}</span>
      </div>
      <div className={h.salonBody}>
        <h3>{salon.name}</h3>
        {salon.address && <p className={h.salonLoc}>{salon.address}</p>}
        <div className={h.tags}>
          {rated && <span>{salon.review_count} review{salon.review_count === 1 ? '' : 's'}</span>}
          {salon.gender_focus && <span>{salon.gender_focus}</span>}
          {services.slice(0, 2).map((s) => <span key={s.id}>{s.name}</span>)}
          {!services.length && salon.open_status_label && <span>{salon.open_status_label}</span>}
        </div>
        <div className={h.salonFoot}>
          {from !== null ? <span>Starts at <b>{inr(from)}</b></span> : <span>{salon.is_serviceable ? 'Taking bookings' : 'Listed on BookALook'}</span>}
          <a href="#download">Book in the app →</a>
        </div>
      </div>
    </article>
  );
}

export default function TrendingSalons({
  categories,
  category,
  onCategory,
}: {
  categories: Category[];
  category: string;
  onCategory: (id: string) => void;
}) {
  const [cityId, setCityId] = useCity();
  const cities = useCities();
  const [data, setData] = useState<Directory | null>(null);
  const [state, setState] = useState<'loading' | 'ready' | 'failed'>('loading');

  useEffect(() => {
    let live = true;
    const params = new URLSearchParams();
    if (cityId) params.set('city_id', cityId);
    if (category) params.set('category_id', category);
    const started = setTimeout(() => live && setState('loading'), 0);

    fetch(`${process.env.NEXT_PUBLIC_BACKEND_URL}/api/customer/salons?${params}`, { headers: { Accept: 'application/json' } })
      .then((r) => (r.ok ? r.json() : Promise.reject(new Error(String(r.status)))))
      .then((json: Directory) => {
        if (!live) return;
        setData({ salons: Array.isArray(json?.salons) ? json.salons : [], city: json?.city ?? null, suggested_city: json?.suggested_city ?? null });
        setState('ready');
      })
      .catch(() => live && setState('failed'));

    return () => {
      live = false;
      clearTimeout(started);
    };
  }, [cityId, category]);

  const cityName = data?.city?.name ?? cities.find((c) => c.id === cityId)?.name ?? null;
  const salons = (data?.salons ?? []).slice(0, 6);

  return (
    <section id="salons" className={`${st.sec} ${h.salons}`}>
      <Parallax speed={0.16} className={h.salonsOrb} />
      <div className={st.wrap}>
        <div className={h.salonsHead}>
          <Reveal>
            <p className={st.kicker}>Top salons near you</p>
            <h2 className={st.big}>
              {cityName ? <>Trending in <em>{cityName}.</em></> : <>Trending <em>near you.</em></>}
            </h2>
          </Reveal>
          {categories.length > 0 && (
            <div className={h.pills} role="tablist" aria-label="Filter salons by service">
              <button type="button" role="tab" aria-selected={!category} className={`${h.pill} ${!category ? h.pillOn : ''}`} onClick={() => onCategory('')}>All</button>
              {categories.map((c) => (
                <button key={c.id} type="button" role="tab" aria-selected={category === c.id} className={`${h.pill} ${category === c.id ? h.pillOn : ''}`} onClick={() => onCategory(c.id)}>
                  {c.name}
                </button>
              ))}
            </div>
          )}
        </div>

        {state === 'failed' ? (
          <div className={h.salonsEmpty}>
            <b>We could not load salons just now.</b>
            <p>The full list, with live slots and prices, is always in the app.</p>
            <a className={st.btn} href="#download">Get the app</a>
          </div>
        ) : state === 'loading' && !data ? (
          <div className={h.cards} aria-busy="true">
            {[0, 1, 2].map((i) => <div key={i} className={`${h.salon} ${h.salonSkeleton}`} />)}
          </div>
        ) : salons.length === 0 ? (
          <div className={h.salonsEmpty}>
            <b>No salons listed {category ? 'for this service ' : ''}{cityName ? `in ${cityName} ` : ''}yet.</b>
            {data?.suggested_city ? (
              <>
                <p>{data.suggested_city.name} has {data.suggested_city.salon_count} salon{data.suggested_city.salon_count === 1 ? '' : 's'} on BookALook.</p>
                <button type="button" className={st.btn} onClick={() => setCityId(data.suggested_city!.id)}>See salons in {data.suggested_city.name}</button>
              </>
            ) : category ? (
              <>
                <p>Try another service, or see every salon in this city.</p>
                <button type="button" className={st.btn} onClick={() => onCategory('')}>Show all salons</button>
              </>
            ) : (
              <p>We are adding salons city by city. Own one? <a href="/partner">Partner with us</a>.</p>
            )}
          </div>
        ) : (
          <div className={`${h.cards} ${state === 'loading' ? h.cardsBusy : ''}`} aria-busy={state === 'loading'}>
            {salons.map((salon, i) => (
              <Parallax key={salon.id} speed={[0.06, -0.03, 0.06][i % 3]}>
                <Reveal delay={(i % 3) * 100}>
                  <SalonCard salon={salon} />
                </Reveal>
              </Parallax>
            ))}
          </div>
        )}

        {state === 'ready' && (data?.salons.length ?? 0) > salons.length && (
          <p className={h.salonsMore}>
            Showing {salons.length} of {data!.salons.length} salons{cityName ? ` in ${cityName}` : ''}. <a href="#download">See them all in the app →</a>
          </p>
        )}
      </div>
    </section>
  );
}
