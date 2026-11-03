// BookALook — read-only browsing load test (k6).
//
//   k6 run -e STAGE=smoke deploy/loadtest/browse.js
//   k6 run -e STAGE=ramp  deploy/loadtest/browse.js
//
// Only GET requests a customer makes while browsing: app version, categories,
// cities, the salon list of a city, salon pages. No login (that would send
// real WhatsApp codes), no bookings, nothing written.
//
// "ramp" climbs 10 -> 50 -> 100 -> 200 -> 400 virtual users and STOPS BY ITSELF
// if more than 2% of requests fail or the slowest 5% take over 2 s.

import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { Trend } from 'k6/metrics';

const BASE = __ENV.BASE || 'https://api.bookalook.in/api';
const STAGE = __ENV.STAGE || 'smoke';

const listTime = new Trend('salon_list_ms', true);
const detailTime = new Trend('salon_detail_ms', true);

const stages = {
  smoke: [{ duration: '30s', target: 5 }, { duration: '30s', target: 5 }],
  ramp: [
    { duration: '1m', target: 10 },
    { duration: '1m', target: 50 },
    { duration: '1m30s', target: 100 },
    { duration: '1m30s', target: 200 },
    { duration: '2m', target: 400 },
    { duration: '1m', target: 400 },
    { duration: '30s', target: 0 },
  ],
};

export const options = {
  stages: stages[STAGE],
  thresholds: {
    // Abort the run (and stop loading the live server) when it is struggling.
    http_req_failed: [{ threshold: 'rate<0.02', abortOnFail: true, delayAbortEval: '30s' }],
    http_req_duration: [{ threshold: 'p(95)<2000', abortOnFail: true, delayAbortEval: '30s' }],
  },
  summaryTrendStats: ['avg', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
  userAgent: 'BookALook-loadtest/1.0 (k6)',
};

export function setup() {
  const v = http.get(`${BASE}/app-version/customer`).json();
  const latest = (v && (v.latest || (v.data && v.data.latest))) || {};
  const cities = http.get(`${BASE}/cities?serviceable=1`).json() || [];
  const withSalons = cities.filter((c) => (c.salon_count || 0) > 0).map((c) => c.id);
  return {
    headers: {
      Accept: 'application/json',
      'X-App-Id': 'customer',
      'X-App-Version': latest.version || '1.0.0',
      'X-App-Build': String(latest.build_number || 1),
    },
    cityIds: withSalons.length ? withSalons : cities.map((c) => c.id),
  };
}

function pick(list) {
  return list[Math.floor(Math.random() * list.length)];
}

export default function (data) {
  const h = { headers: data.headers };
  const city = pick(data.cityIds);

  group('open app', () => {
    http.get(`${BASE}/app-version/customer`, h);
    http.get(`${BASE}/customer/categories`, h);
    http.get(`${BASE}/cities?serviceable=1`, h);
  });
  sleep(1 + Math.random() * 2);

  let salons = [];
  group('salon list', () => {
    const res = http.get(`${BASE}/customer/salons?city_id=${city}`, h);
    listTime.add(res.timings.duration);
    check(res, { 'list 200': (r) => r.status === 200 });
    try {
      salons = (res.json('salons') || []).map((s) => s.id);
    } catch (_) {
      salons = [];
    }
  });
  sleep(1 + Math.random() * 3);

  const pages = 1 + Math.floor(Math.random() * 2);
  for (let i = 0; i < pages && salons.length; i++) {
    group('salon page', () => {
      const res = http.get(`${BASE}/customer/salons/${pick(salons)}`, h);
      detailTime.add(res.timings.duration);
      check(res, { 'detail 200': (r) => r.status === 200 });
    });
    sleep(2 + Math.random() * 2);
  }
}
