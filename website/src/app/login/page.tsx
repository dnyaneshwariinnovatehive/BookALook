'use client';

import Image from 'next/image';
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import styles from './login.module.css';

const HIGHLIGHTS = [
  { title: 'Every salon, one view', desc: 'Approvals, directory and payouts in a single place.' },
  { title: 'Live marketplace pulse', desc: 'Bookings and revenue as they happen, city by city.' },
  { title: 'Built-in audit trail', desc: 'Every admin action is logged and traceable.' },
];

export default function LoginPage() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [error, setError] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const router = useRouter();

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsLoading(true);
    setError('');

    try {
      const res = await fetch('/api/auth/login', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ email, password }),
      });

      const data = await res.json();

      if (res.ok && data.success) {
        router.push('/superadmin');
        router.refresh(); // Refresh to ensure middleware state is updated
      } else {
        setError(data.message || 'Login failed. Please try again.');
      }
    } catch (err) {
      setError('An unexpected error occurred. Please try again.');
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className={styles.container}>
      <aside className={styles.brandPanel} aria-hidden="true">
        <div className={styles.brandGlow} />
        <div className={styles.brandInner}>
          <span className={styles.brandKicker}>BookALook Admin</span>
          <h2 className={styles.brandTitle}>
            Run the whole <em>marketplace</em> from one calm place.
          </h2>
          <ul className={styles.highlights}>
            {HIGHLIGHTS.map((h) => (
              <li key={h.title} className={styles.highlight}>
                <span className={styles.highlightMark}>
                  <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round"><path d="M20 6 9 17l-5-5" /></svg>
                </span>
                <div>
                  <div className={styles.highlightTitle}>{h.title}</div>
                  <div className={styles.highlightDesc}>{h.desc}</div>
                </div>
              </li>
            ))}
          </ul>
        </div>
        <p className={styles.brandFoot}>No waiting. Just booking.</p>
      </aside>

      <main className={styles.formPanel}>
        <div className={styles.loginCard}>
          <div className={styles.header}>
            <Image src="/logo.png" alt="BookALook" width={180} height={32} className={`${styles.logo} ${styles.logoLight}`} priority />
            <Image src="/logo-dark.png" alt="" width={180} height={32} className={`${styles.logo} ${styles.logoDark}`} priority />
            <h1 className={styles.title}>Welcome back</h1>
            <p className={styles.subtitle}>Sign in to the Super Admin portal</p>
          </div>

          {error && <div className={styles.error} role="alert">{error}</div>}

          <form className={styles.form} onSubmit={handleLogin}>
            <div className={styles.inputGroup}>
              <label htmlFor="email" className={styles.label}>
                Email address
              </label>
              <input
                id="email"
                type="email"
                className={styles.input}
                placeholder="admin@bookalook.com"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                autoComplete="username"
                autoFocus
                required
                disabled={isLoading}
              />
            </div>

            <div className={styles.inputGroup}>
              <label htmlFor="password" className={styles.label}>
                Password
              </label>
              <div className={styles.passwordWrapper}>
                <input
                  id="password"
                  type={showPassword ? "text" : "password"}
                  className={styles.input}
                  placeholder="Enter your password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  autoComplete="current-password"
                  required
                  disabled={isLoading}
                />
                <button
                  type="button"
                  className={styles.eyeButton}
                  onClick={() => setShowPassword(!showPassword)}
                  aria-label={showPassword ? "Hide password" : "Show password"}
                  aria-pressed={showPassword}
                >
                  {showPassword ? (
                    <svg xmlns="http://www.w3.org/2000/svg" width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24"></path><line x1="1" y1="1" x2="23" y2="23"></line></svg>
                  ) : (
                    <svg xmlns="http://www.w3.org/2000/svg" width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"></path><circle cx="12" cy="12" r="3"></circle></svg>
                  )}
                </button>
              </div>
            </div>

            <button type="submit" className={styles.button} disabled={isLoading}>
              {isLoading ? <><span className={styles.spinner} /> Signing in…</> : 'Sign in'}
            </button>
          </form>

          <p className={styles.footNote}>
            <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><rect x="4" y="11" width="16" height="10" rx="2" /><path d="M8 11V7a4 4 0 0 1 8 0v4" /></svg>
            Restricted area — access is logged.
          </p>
        </div>
      </main>
    </div>
  );
}
