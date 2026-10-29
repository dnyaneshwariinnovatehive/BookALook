'use client';

import { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import {
  Alert, Badge, Button, DataTable, DescriptionList, Modal, PageHeader, SearchInput, Segmented,
  formatINR, useDebounced, type DataColumn,
} from '@/components/admin/ui';
import styles from './requests.module.css';

/**
 * What salon owners have written to BookALook from the Partner App — most
 * often from the lock screen, about a settlement. A reply reaches the owner
 * as a Partner App notification and shows under their message in the app.
 */

interface SalonRequest {
  id: string;
  topic: string;
  topic_label: string;
  message: string;
  status: 'open' | 'resolved';
  reply: string | null;
  replied_at: string | null;
  resolved_at: string | null;
  created_at: string;
  salon: { id: string; name: string; city: string | null } | null;
  owner: { name: string; phone: string } | null;
  payout: { id: string; cycle_start_date: string; cycle_end_date: string; net_amount: number; status: string } | null;
}

type StatusFilter = 'open' | 'resolved' | 'all';

const fmt = (v: string | null) =>
  v ? new Date(v).toLocaleString('en-IN', { day: '2-digit', month: 'short', year: 'numeric', hour: 'numeric', minute: '2-digit' }) : '—';
const fmtDay = (v: string) => new Date(v).toLocaleDateString('en-IN', { day: '2-digit', month: 'short' });

const payoutText = (p: NonNullable<SalonRequest['payout']>) =>
  `${fmtDay(p.cycle_start_date)} – ${fmtDay(p.cycle_end_date)} · ${p.net_amount < 0 ? 'salon owes' : 'owed to salon'} ${formatINR(Math.abs(p.net_amount))} · ${p.status}`;

export default function SalonRequestsPage() {
  const [status, setStatus] = useState<StatusFilter>('open');
  const [topic, setTopic] = useState('');
  const [search, setSearch] = useState('');
  const debounced = useDebounced(search);
  const [page, setPage] = useState(1);
  const [rows, setRows] = useState<SalonRequest[]>([]);
  const [meta, setMeta] = useState({ current_page: 1, last_page: 1, total: 0 });
  const [counts, setCounts] = useState({ open: 0, resolved: 0 });
  const [topics, setTopics] = useState<{ key: string; label: string }[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [selected, setSelected] = useState<SalonRequest | null>(null);
  const [reply, setReply] = useState('');
  const [resolve, setResolve] = useState(true);
  const [saving, setSaving] = useState(false);
  const [notice, setNotice] = useState('');

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const params = new URLSearchParams({ status, page: String(page) });
      if (topic) params.set('topic', topic);
      if (debounced.trim()) params.set('search', debounced.trim());
      const res = await fetch(`/api/proxy/superadmin/salon-requests?${params}`, { cache: 'no-store' });
      const json = await res.json();
      if (!res.ok || !json.success) throw new Error(json.message || 'Could not load requests.');
      setRows(json.data);
      setMeta(json.meta);
      setCounts(json.counts);
      setTopics(json.topics ?? []);
      setError('');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not load requests.');
    } finally {
      setLoading(false);
    }
  }, [status, topic, debounced, page]);

  useEffect(() => {
    const t = setTimeout(load, 0);
    return () => clearTimeout(t);
  }, [load]);

  const open = (r: SalonRequest) => {
    setSelected(r);
    setReply(r.reply ?? '');
    setResolve(true);
  };

  const sendReply = async () => {
    if (!selected || reply.trim().length < 2) return;
    setSaving(true);
    try {
      const res = await fetch(`/api/proxy/superadmin/salon-requests/${selected.id}/reply`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ reply: reply.trim(), resolve }),
      });
      const json = await res.json();
      if (!res.ok || !json.success) throw new Error(json.message || 'Could not send the reply.');
      setNotice(`Reply sent to ${selected.salon?.name ?? 'the salon'}.`);
      window.dispatchEvent(new Event('salon-requests-changed'));
      setSelected(null);
      load();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not send the reply.');
    } finally {
      setSaving(false);
    }
  };

  const setRequestStatus = async (r: SalonRequest, next: 'open' | 'resolved') => {
    setSaving(true);
    try {
      const res = await fetch(`/api/proxy/superadmin/salon-requests/${r.id}/status`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ status: next }),
      });
      const json = await res.json();
      if (!res.ok || !json.success) throw new Error(json.message || 'Could not update the request.');
      setSelected(null);
      setNotice(next === 'resolved' ? 'Marked resolved.' : 'Reopened.');
      window.dispatchEvent(new Event('salon-requests-changed'));
      load();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not update the request.');
    } finally {
      setSaving(false);
    }
  };

  const columns: DataColumn<SalonRequest>[] = [
    {
      key: 'salon',
      header: 'Salon',
      render: (r) => (
        <div className={styles.salonCell}>
          <b>{r.salon?.name ?? 'Salon'}</b>
          <span>{[r.salon?.city, r.owner?.name].filter(Boolean).join(' · ')}</span>
        </div>
      ),
      csvValue: (r) => r.salon?.name,
    },
    {
      key: 'topic',
      header: 'About',
      render: (r) => (
        <div className={styles.topicCell}>
          <b>{r.topic_label}</b>
          {r.payout && <span>{payoutText(r.payout)}</span>}
        </div>
      ),
      csvValue: (r) => r.topic_label,
    },
    {
      key: 'message',
      header: 'Message',
      render: (r) => <p className={styles.messageCell}>{r.message}</p>,
      csvValue: (r) => r.message,
    },
    {
      key: 'created',
      header: 'Sent',
      render: (r) => <span className={styles.when}>{fmt(r.created_at)}</span>,
      csvValue: (r) => r.created_at,
    },
    {
      key: 'status',
      header: 'Status',
      render: (r) =>
        r.status === 'open' ? (
          <Badge tone={r.reply ? 'info' : 'warning'} pulse={!r.reply}>{r.reply ? 'Replied' : 'Waiting'}</Badge>
        ) : (
          <Badge tone="success">Resolved</Badge>
        ),
      csvValue: (r) => r.status,
    },
  ];

  return (
    <div className={styles.page}>
      <PageHeader
        eyebrow="Salons"
        title="Salon requests"
        subtitle="Messages salon owners send BookALook from the Partner App — settlement questions, payout requests, renewal help. Your reply reaches them as a notification."
      />

      {notice && <Alert tone="success" onClose={() => setNotice('')}>{notice}</Alert>}

      <DataTable
        columns={columns}
        rows={rows}
        rowKey={(r) => r.id}
        loading={loading && rows.length === 0}
        error={error || undefined}
        noun="requests"
        exportName="salon-requests"
        page={meta.current_page}
        lastPage={meta.last_page}
        total={meta.total}
        onPage={setPage}
        onRowClick={open}
        empty={{
          title: status === 'open' ? 'No open requests' : 'No requests here',
          hint: 'Salon owners write in from the lock screen or More → Contact BookALook in the Partner App.',
        }}
        toolbar={
          <div className={styles.toolbar}>
            <Segmented<StatusFilter>
              ariaLabel="Status"
              value={status}
              onChange={(v) => { setStatus(v); setPage(1); }}
              options={[
                { value: 'open', label: 'Open', count: counts.open },
                { value: 'resolved', label: 'Resolved', count: counts.resolved },
                { value: 'all', label: 'All' },
              ]}
            />
            <select
              className={styles.select}
              value={topic}
              onChange={(e) => { setTopic(e.target.value); setPage(1); }}
              aria-label="Topic"
            >
              <option value="">All topics</option>
              {topics.map((t) => <option key={t.key} value={t.key}>{t.label}</option>)}
            </select>
            <SearchInput
              value={search}
              onChange={(v) => { setSearch(v); setPage(1); }}
              placeholder="Search salon or message"
              className={styles.search}
            />
          </div>
        }
      />

      <Modal
        open={!!selected}
        onClose={() => setSelected(null)}
        title={selected ? `${selected.topic_label} · ${selected.salon?.name ?? 'Salon'}` : ''}
        description={selected ? `Sent ${fmt(selected.created_at)}` : undefined}
        size="lg"
        footer={selected && (
          <div className={styles.modalFoot}>
            {selected.status === 'resolved' ? (
              <Button onClick={() => setRequestStatus(selected, 'open')} disabled={saving}>Reopen</Button>
            ) : (
              <Button onClick={() => setRequestStatus(selected, 'resolved')} disabled={saving}>Mark resolved without reply</Button>
            )}
            <Button variant="primary" icon="message" onClick={sendReply} loading={saving} disabled={reply.trim().length < 2}>
              {selected.reply ? 'Send updated reply' : 'Send reply'}
            </Button>
          </div>
        )}
      >
        {selected && (
          <div className={styles.modalBody}>
            <DescriptionList
              items={[
                ['Salon', selected.salon ? <Link href={`/superadmin/salons/${selected.salon.id}`}>{selected.salon.name}</Link> : '—'],
                ['Owner', selected.owner ? `${selected.owner.name} · ${selected.owner.phone}` : '—'],
                ['Settlement', selected.payout ? <Link href="/superadmin/payouts">{payoutText(selected.payout)}</Link> : 'Not about a specific one'],
                ['Status', selected.status === 'resolved' ? `Resolved ${fmt(selected.resolved_at)}` : 'Open'],
              ]}
            />
            <div className={styles.messageBox}>
              <span>Message</span>
              <p>{selected.message}</p>
            </div>
            {selected.reply && (
              <div className={styles.replyBox}>
                <span>Your last reply · {fmt(selected.replied_at)}</span>
                <p>{selected.reply}</p>
              </div>
            )}
            <label className={styles.replyLabel} htmlFor="salon-request-reply">Reply to the owner</label>
            <textarea
              id="salon-request-reply"
              className={styles.textarea}
              rows={5}
              maxLength={2000}
              value={reply}
              onChange={(e) => setReply(e.target.value)}
              placeholder="e.g. Your payout for 19–25 Oct was released today, UTR 1234…"
            />
            <label className={styles.check}>
              <input type="checkbox" checked={resolve} onChange={(e) => setResolve(e.target.checked)} />
              Mark as resolved when sending
            </label>
          </div>
        )}
      </Modal>
    </div>
  );
}
