'use client';

import { useEffect, useState, useSyncExternalStore } from 'react';

/**
 * The city a visitor is browsing, shared by the header's city picker, the
 * hero search and the salon list on the home page.
 *
 * Kept in localStorage so it survives a reload, and announced with a window
 * event so every picker on the page stays in step without a context provider
 * around the whole site.
 */

const KEY = 'blk-city';
const EVENT = 'blk-city-change';

export interface City {
  id: string;
  name: string;
  state: string;
  salon_count?: number;
}

function read(): string {
  try {
    return window.localStorage.getItem(KEY) ?? '';
  } catch {
    return '';
  }
}

function subscribe(onChange: () => void) {
  window.addEventListener(EVENT, onChange);
  window.addEventListener('storage', onChange);
  return () => {
    window.removeEventListener(EVENT, onChange);
    window.removeEventListener('storage', onChange);
  };
}

export function setCity(id: string) {
  try {
    if (id) window.localStorage.setItem(KEY, id);
    else window.localStorage.removeItem(KEY);
  } catch {
    // Private mode: the choice simply lasts for this page.
  }
  window.dispatchEvent(new Event(EVENT));
}

/** The chosen city id ('' until one is picked) and its setter. */
export function useCity(): [string, (id: string) => void] {
  const id = useSyncExternalStore(subscribe, read, () => '');
  return [id, setCity];
}

// One request for the city list, however many pickers ask for it.
let citiesRequest: Promise<City[]> | null = null;

function loadCities(): Promise<City[]> {
  citiesRequest ??= fetch(`${process.env.NEXT_PUBLIC_BACKEND_URL}/api/cities`, { headers: { Accept: 'application/json' } })
    .then((r) => r.json())
    .then((list) => (Array.isArray(list) ? (list as City[]) : []))
    .catch(() => {
      citiesRequest = null;
      return [];
    });
  return citiesRequest;
}

/**
 * The cities a customer can actually browse: the ones with salons listed. The
 * full list (every city a salon could register from) is far too long for a
 * picker, and choosing a city with nothing in it is a dead end. Falls back to
 * every city if the counts are missing.
 */
export function useSalonCities(): City[] {
  const cities = useCities();
  const withSalons = cities.filter((c) => (c.salon_count ?? 0) > 0);
  return withSalons.length > 0 ? withSalons : cities;
}

/** The cities BookALook lists, from the same endpoint the registration form uses. */
export function useCities(): City[] {
  const [cities, setCities] = useState<City[]>([]);
  useEffect(() => {
    let live = true;
    loadCities().then((list) => live && setCities(list));
    return () => {
      live = false;
    };
  }, []);
  return cities;
}
