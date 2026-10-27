'use client';

import { useEffect, useRef, useState, type CSSProperties, type ReactNode } from 'react';
import { qrMatrix } from '@/lib/qr';
import m from './motion.module.css';

/* Scroll-driven motion for the landing page: parallax layers, reveal-on-
   scroll, counters and a rotating word. Everything stands still for people
   who ask their system for reduced motion. */

const reducedMotion = () =>
  typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

// One scroll listener for every parallax layer on the page.
type Layer = () => void;
const layers = new Set<Layer>();
let ticking = false;
function onScroll() {
  if (ticking) return;
  ticking = true;
  requestAnimationFrame(() => {
    layers.forEach((update) => update());
    ticking = false;
  });
}
function subscribe(layer: Layer) {
  if (layers.size === 0) {
    window.addEventListener('scroll', onScroll, { passive: true });
    window.addEventListener('resize', onScroll);
  }
  layers.add(layer);
  layer();
  return () => {
    layers.delete(layer);
    if (layers.size === 0) {
      window.removeEventListener('scroll', onScroll);
      window.removeEventListener('resize', onScroll);
    }
  };
}

/**
 * Moves with the scroll at its own speed, like a layer at a different depth.
 * [speed] is how far it travels per pixel scrolled (negative rises faster);
 * [rotate] turns it a little as it goes.
 */
export function Parallax({
  speed = 0.2,
  rotate = 0,
  className,
  style,
  children,
}: {
  speed?: number;
  rotate?: number;
  className?: string;
  style?: CSSProperties;
  children?: ReactNode;
}) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const el = ref.current;
    if (!el || reducedMotion()) return;
    return subscribe(() => {
      const rect = el.getBoundingClientRect();
      // Distance of the element's centre from the middle of the screen.
      const offset = rect.top + rect.height / 2 - window.innerHeight / 2;
      el.style.transform = `translate3d(0, ${(offset * speed).toFixed(1)}px, 0) rotate(${(offset * rotate * 0.05).toFixed(2)}deg)`;
    });
  }, [speed, rotate]);

  return (
    <div ref={ref} className={`${m.parallax} ${className ?? ''}`} style={style}>
      {children}
    </div>
  );
}

/** Fades and slides in the first time it scrolls into view. */
export function Reveal({
  children,
  delay = 0,
  variant = 'up',
  className,
  as: Tag = 'div',
}: {
  children: ReactNode;
  delay?: number;
  variant?: 'up' | 'left' | 'right' | 'zoom';
  className?: string;
  as?: 'div' | 'li' | 'article' | 'section';
}) {
  const ref = useRef<HTMLElement>(null);
  const [shown, setShown] = useState(false);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    if (reducedMotion() || typeof IntersectionObserver === 'undefined') {
      const t = setTimeout(() => setShown(true), 0);
      return () => clearTimeout(t);
    }
    const io = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          setShown(true);
          io.disconnect();
        }
      },
      { threshold: 0.15, rootMargin: '0px 0px -40px 0px' },
    );
    io.observe(el);
    return () => io.disconnect();
  }, []);

  return (
    <Tag
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      ref={ref as any}
      className={`${m.reveal} ${m[`reveal_${variant}`]} ${shown ? m.shown : ''} ${className ?? ''}`}
      style={{ transitionDelay: `${delay}ms` }}
    >
      {children}
    </Tag>
  );
}

/** Counts up to [to] once it is on screen. */
export function CountUp({ to, prefix = '', suffix = '', duration = 1400 }: {
  to: number;
  prefix?: string;
  suffix?: string;
  duration?: number;
}) {
  const ref = useRef<HTMLSpanElement>(null);
  const [value, setValue] = useState(0);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    let raf = 0;
    const start = () => {
      if (reducedMotion() || to === 0) {
        raf = requestAnimationFrame(() => setValue(to));
        return;
      }
      const t0 = performance.now();
      const step = (now: number) => {
        const p = Math.min(1, (now - t0) / duration);
        setValue(Math.round(to * (1 - Math.pow(1 - p, 3))));
        if (p < 1) raf = requestAnimationFrame(step);
      };
      raf = requestAnimationFrame(step);
    };
    const io = new IntersectionObserver(([e]) => {
      if (e.isIntersecting) {
        start();
        io.disconnect();
      }
    }, { threshold: 0.5 });
    io.observe(el);
    return () => {
      io.disconnect();
      cancelAnimationFrame(raf);
    };
  }, [to, duration]);

  return <span ref={ref}>{prefix}{value.toLocaleString('en-IN')}{suffix}</span>;
}

/** Cycles through [words], sliding each one up into place. */
export function RotatingWord({ words, interval = 2200 }: { words: string[]; interval?: number }) {
  const [i, setI] = useState(0);

  useEffect(() => {
    if (reducedMotion()) return;
    const id = setInterval(() => setI((n) => (n + 1) % words.length), interval);
    return () => clearInterval(id);
  }, [words.length, interval]);

  return (
    <span className={m.rotator} aria-live="polite">
      <span key={i} className={m.rotatorWord}>{words[i]}</span>
    </span>
  );
}

/**
 * A scannable QR code for [value], drawn as SVG. Falls back to nothing if the
 * link were ever too long to encode.
 */
export function QrCode({ value, size = 168, label }: { value: string; size?: number; label: string }) {
  const matrix = qrMatrix(value);
  if (!matrix) return null;
  const n = matrix.length;
  const quiet = 2;
  const dim = n + quiet * 2;
  let path = '';
  matrix.forEach((row, r) => row.forEach((dark, c) => {
    if (dark) path += `M${c + quiet} ${r + quiet}h1v1h-1z`;
  }));

  return (
    <svg
      role="img"
      aria-label={label}
      width={size}
      height={size}
      viewBox={`0 0 ${dim} ${dim}`}
      shapeRendering="crispEdges"
      className={m.qr}
    >
      <rect width={dim} height={dim} fill="#FFFFFF" />
      <path d={path} fill="#18151D" />
    </svg>
  );
}

/** The site's own address, once known in the browser — for QR links. */
export function useOrigin(fallback = 'https://bookalook.in') {
  const [origin, setOrigin] = useState(fallback);
  useEffect(() => {
    const t = setTimeout(() => setOrigin(window.location.origin), 0);
    return () => clearTimeout(t);
  }, []);
  return origin;
}
