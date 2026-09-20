'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import styles from './page.module.css';

interface TemplateVariable {
  key: string;
  label: string;
  example?: string;
  source: 'input' | 'customer' | 'salon';
}

interface Template {
  id: string;
  key: string;
  name: string;
  category: string;
  category_label: string;
  description: string | null;
  body_preview: string;
  variables: TemplateVariable[];
  meta_template_name: string | null;
  language: string;
  min_plan: 'starter' | 'growth';
  is_active: boolean;
  campaigns_count: number;
  sendable: boolean;
}

interface Overview {
  window_days: number;
  campaigns: number;
  messages_sent: number;
  messages_failed: number;
  messages_queued: number;
  opted_out: number;
  opted_in: number;
  opt_outs_this_window: number;
  top_salons: { salon: string; campaigns: number; messages: number }[];
  provider: string;
}

/**
 * WhatsApp marketing, from the platform's side.
 *
 * Two jobs on one page, and they belong together. The catalogue decides what
 * every salon is allowed to say — there is one WhatsApp Business account behind
 * the whole platform, so a template is approved once, here, and not by each
 * salon. The overview watches what that account is being used for, because the
 * number that ends a WhatsApp Business account is the opt-out rate, and nobody
 * notices it climbing unless it is on a screen somebody looks at.
 */
export default function MarketingPage() {
  const [templates, setTemplates] = useState<Template[]>([]);
  const [summary, setSummary] = useState({ total: 0, sendable: 0, awaiting_approval: 0 });
  const [overview, setOverview] = useState<Overview | null>(null);

  const [loading, setLoading] = useState(true);
  const [banner, setBanner] = useState<{ tone: 'ok' | 'bad'; text: string } | null>(null);
  const [editing, setEditing] = useState<string | null>(null);
  const [draft, setDraft] = useState<Partial<Template>>({});
  const [saving, setSaving] = useState(false);

  const load = useCallback(async () => {
    try {
      const [templateRes, overviewRes] = await Promise.all([
        fetch('/api/proxy/superadmin/campaign-templates', { cache: 'no-store' }),
        fetch('/api/proxy/superadmin/marketing/overview', { cache: 'no-store' }),
      ]);

      const templateJson = await templateRes.json();
      const overviewJson = await overviewRes.json();

      if (!templateJson.success) throw new Error(templateJson.message || 'Could not load templates');

      setTemplates(templateJson.data || []);
      setSummary(templateJson.summary || { total: 0, sendable: 0, awaiting_approval: 0 });
      if (overviewJson.success) setOverview(overviewJson.data);
    } catch (e) {
      setBanner({ tone: 'bad', text: e instanceof Error ? e.message : 'Could not load this page' });
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  useEffect(() => {
    if (banner?.tone !== 'ok') return;
    const timer = setTimeout(() => setBanner(null), 4000);
    return () => clearTimeout(timer);
  }, [banner]);

  const save = async (id: string, changes: Partial<Template>) => {
    setSaving(true);
    try {
      const res = await fetch(`/api/proxy/superadmin/campaign-templates/${id}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(changes),
      });
      const json = await res.json();

      if (!res.ok || !json.success) throw new Error(json.message || 'Could not save it');

      setBanner({ tone: 'ok', text: json.message });
      setEditing(null);
      setDraft({});
      await load();
    } catch (e) {
      setBanner({ tone: 'bad', text: e instanceof Error ? e.message : 'Could not save it' });
    } finally {
      setSaving(false);
    }
  };

  const grouped = useMemo(() => {
    const map = new Map<string, Template[]>();
    templates.forEach((template) => {
      map.set(template.category_label, [...(map.get(template.category_label) ?? []), template]);
    });
    return [...map.entries()];
  }, [templates]);

  return (
    <div className={styles.container}>
      <header className={styles.header}>
        <div>
          <h1 className={styles.title}>WhatsApp Marketing</h1>
          <p className={styles.subtitle}>
            Every salon sends through one WhatsApp Business account, so templates are approved by
            Meta once and listed here. A salon fills in the blanks; it never writes its own copy,
            because Meta reviews templates rather than messages.
          </p>
        </div>

        <div className={styles.statRow}>
          <div className={styles.stat}>
            <span className={styles.statValue}>{summary.sendable}</span>
            <span className={styles.statLabel}>Ready to send</span>
          </div>
          <div className={styles.stat}>
            <span className={styles.statValue}>{summary.awaiting_approval}</span>
            <span className={styles.statLabel}>Awaiting approval</span>
          </div>
        </div>
      </header>

      {banner && (
        <div
          className={`${styles.banner} ${banner.tone === 'ok' ? styles.bannerOk : styles.bannerBad}`}
        >
          {banner.text}
        </div>
      )}

      {/* The provider warning is first because nothing else on this page
          matters while messages are only being written to a log. */}
      {overview && overview.provider !== 'meta_cloud' && (
        <div className={`${styles.banner} ${styles.bannerWarn}`}>
          <strong>No WhatsApp provider is connected.</strong> Campaigns can be built and previewed,
          but messages stay queued instead of going out. Set <code>WHATSAPP_DRIVER=meta_cloud</code>{' '}
          with a phone number id and access token to start sending.
        </div>
      )}

      {overview && (
        <section className={styles.overview}>
          <h2 className={styles.sectionTitle}>Last {overview.window_days} days</h2>
          <div className={styles.overviewGrid}>
            <div className={styles.metric}>
              <span className={styles.metricValue}>{overview.campaigns}</span>
              <span className={styles.metricLabel}>Campaigns</span>
            </div>
            <div className={styles.metric}>
              <span className={styles.metricValue}>{overview.messages_sent}</span>
              <span className={styles.metricLabel}>Messages sent</span>
            </div>
            <div className={styles.metric}>
              <span className={styles.metricValue}>{overview.messages_queued}</span>
              <span className={styles.metricLabel}>Queued</span>
            </div>
            <div className={styles.metric}>
              <span className={styles.metricValue}>{overview.messages_failed}</span>
              <span className={styles.metricLabel}>Failed</span>
            </div>
            {/* The one to watch. A rising opt-out rate is how a WhatsApp
                Business account gets restricted. */}
            <div className={`${styles.metric} ${styles.metricAlert}`}>
              <span className={styles.metricValue}>{overview.opt_outs_this_window}</span>
              <span className={styles.metricLabel}>
                New opt-outs ({overview.opted_out} total)
              </span>
            </div>
            <div className={styles.metric}>
              <span className={styles.metricValue}>{overview.opted_in}</span>
              <span className={styles.metricLabel}>Opted in</span>
            </div>
          </div>

          {overview.top_salons.length > 0 && (
            <div className={styles.topSalons}>
              <h3 className={styles.subTitle}>Busiest senders</h3>
              <table className={styles.table}>
                <thead>
                  <tr>
                    <th>Salon</th>
                    <th>Campaigns</th>
                    <th>Messages</th>
                  </tr>
                </thead>
                <tbody>
                  {overview.top_salons.map((row) => (
                    <tr key={row.salon}>
                      <td>{row.salon}</td>
                      <td>{row.campaigns}</td>
                      <td>{row.messages}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </section>
      )}

      <h2 className={styles.sectionTitle}>Template catalogue</h2>

      {loading ? (
        <p className={styles.empty}>Loading…</p>
      ) : (
        grouped.map(([category, list]) => (
          <section key={category} className={styles.categorySection}>
            <h3 className={styles.categoryHeading}>{category}</h3>

            {list.map((template) => (
              <div
                key={template.id}
                className={`${styles.template} ${template.sendable ? '' : styles.templateOff}`}
              >
                <div className={styles.templateHead}>
                  <div>
                    <div className={styles.templateName}>
                      {template.name}
                      {template.min_plan === 'growth' && (
                        <span className={styles.growthTag}>Growth</span>
                      )}
                      {template.sendable ? (
                        <span className={styles.liveTag}>Live</span>
                      ) : (
                        <span className={styles.pendingTag}>Not approved</span>
                      )}
                    </div>
                    {template.description && (
                      <p className={styles.templateDescription}>{template.description}</p>
                    )}
                  </div>

                  <button
                    type="button"
                    className={styles.linkButton}
                    onClick={() => {
                      setEditing(editing === template.id ? null : template.id);
                      setDraft({
                        meta_template_name: template.meta_template_name,
                        min_plan: template.min_plan,
                        is_active: template.is_active,
                      });
                    }}
                  >
                    {editing === template.id ? 'Close' : 'Edit'}
                  </button>
                </div>

                <pre className={styles.body}>{template.body_preview}</pre>

                <div className={styles.meta}>
                  <span>
                    {template.variables.length} placeholder
                    {template.variables.length === 1 ? '' : 's'}
                  </span>
                  <span>·</span>
                  <span>{template.campaigns_count} campaign{template.campaigns_count === 1 ? '' : 's'} sent</span>
                  {template.meta_template_name && (
                    <>
                      <span>·</span>
                      <code className={styles.code}>{template.meta_template_name}</code>
                    </>
                  )}
                </div>

                {editing === template.id && (
                  <div className={styles.editor}>
                    <label className={styles.field}>
                      <span className={styles.fieldLabel}>Approved WhatsApp template name</span>
                      <input
                        className={styles.input}
                        value={draft.meta_template_name ?? ''}
                        placeholder="e.g. combo_promotion_v1"
                        onChange={(e) =>
                          setDraft((prev) => ({ ...prev, meta_template_name: e.target.value }))
                        }
                      />
                      <span className={styles.fieldHelp}>
                        Exactly as Meta approved it. A mismatch here makes every send fail.
                      </span>
                    </label>

                    <label className={styles.field}>
                      <span className={styles.fieldLabel}>Available on</span>
                      <select
                        className={styles.input}
                        value={draft.min_plan ?? 'starter'}
                        onChange={(e) =>
                          setDraft((prev) => ({
                            ...prev,
                            min_plan: e.target.value as 'starter' | 'growth',
                          }))
                        }
                      >
                        <option value="starter">All paid plans</option>
                        <option value="growth">Growth only</option>
                      </select>
                    </label>

                    <label className={styles.toggle}>
                      <input
                        type="checkbox"
                        checked={draft.is_active ?? false}
                        onChange={(e) =>
                          setDraft((prev) => ({ ...prev, is_active: e.target.checked }))
                        }
                      />
                      Offer this template to salons
                    </label>

                    <div className={styles.editorActions}>
                      <button
                        type="button"
                        className={styles.button}
                        disabled={saving}
                        onClick={() =>
                          save(template.id, {
                            meta_template_name: draft.meta_template_name?.trim() || null,
                            min_plan: draft.min_plan,
                            is_active: draft.is_active,
                          })
                        }
                      >
                        {saving ? 'Saving…' : 'Save'}
                      </button>
                      <button
                        type="button"
                        className={styles.linkButton}
                        onClick={() => {
                          setEditing(null);
                          setDraft({});
                        }}
                      >
                        Cancel
                      </button>
                    </div>
                  </div>
                )}
              </div>
            ))}
          </section>
        ))
      )}
    </div>
  );
}
