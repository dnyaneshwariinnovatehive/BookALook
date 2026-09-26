'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import Link from 'next/link';
import {
  Badge, DataTable, SearchInput, cx, useConfirm, useDebounced, useTableState,
  type DataColumn, type Tone,
} from '@/components/admin/ui';
import styles from './page.module.css';

interface Salon {
  id: string;
  name: string;
  status: string;
  created_at: string;
  city?: { name: string };
  admin?: { name: string };
  assigned_collaborator?: { id: string; name: string } | null;
}

interface Collaborator {
  id: string;
  name: string;
}

interface Meta {
  current_page: number;
  last_page: number;
  per_page: number;
  total: number;
}

const STATUS_TONE: Record<string, Tone> = {
  active: 'success',
  pending_approval: 'warning',
  rejected: 'danger',
  suspended: 'neutral',
  deactivated: 'neutral',
};

const formatStatus = (value: string) => value.replace(/_/g, ' ');

const formatDate = (value: string) => {
  const d = new Date(value);
  return Number.isNaN(d.getTime())
    ? '—'
    : d.toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' });
};

export default function SalonDirectory() {
  const [salons, setSalons] = useState<Salon[]>([]);
  const [meta, setMeta] = useState<Meta>({ current_page: 1, last_page: 1, per_page: 20, total: 0 });
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [collaborators, setCollaborators] = useState<Collaborator[]>([]);
  const [assigningId, setAssigningId] = useState<string | null>(null);
  const [justAssignedIds, setJustAssignedIds] = useState<string[]>([]);

  const [search, setSearch] = useState('');
  const [status, setStatus] = useState('');
  const [collaboratorId, setCollaboratorId] = useState('');

  const debouncedSearch = useDebounced(search, 400);
  const [confirm, confirmDialog] = useConfirm();

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const res = await fetch('/api/proxy/superadmin/collaborators');
        if (!res.ok) return;
        const json = await res.json();
        if (!cancelled) setCollaborators(json.data || []);
      } catch {
        // The filter falls back to "All collaborators"; not worth an alert.
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  const handleAssign = useCallback(
    async (salon: Salon, collId: string) => {
      const current = salon.assigned_collaborator?.id || '';
      if (collId === current) return;

      const nextName = collaborators.find((c) => c.id === collId)?.name;
      const ok = await confirm({
        title: current ? 'Change assigned collaborator?' : 'Assign a collaborator?',
        body: `${salon.name} will move to ${nextName || 'Unassigned'}.`,
        confirmLabel: 'Save',
        tone: 'accent',
      });
      if (!ok) return;

      setAssigningId(salon.id);
      const previous = salon.assigned_collaborator ?? null;
      // Optimistic: the select already shows the new value, so reflect it now
      // and put it back if the save fails.
      setSalons((prev) =>
        prev.map((s) =>
          s.id === salon.id
            ? { ...s, assigned_collaborator: collId ? { id: collId, name: nextName || '' } : null }
            : s,
        ),
      );

      try {
        const res = await fetch(`/api/proxy/superadmin/salons/${salon.id}/assign-collaborator`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ collaborator_id: collId || null }),
        });
        const json = await res.json();
        if (!res.ok || !json.success) throw new Error(json.message || 'Failed to assign');

        setJustAssignedIds((prev) => [...prev, salon.id]);
        setTimeout(() => {
          setJustAssignedIds((prev) => prev.filter((id) => id !== salon.id));
        }, 2000);
      } catch (err) {
        setSalons((prev) =>
          prev.map((s) => (s.id === salon.id ? { ...s, assigned_collaborator: previous } : s)),
        );
        setError(err instanceof Error ? err.message : 'Failed to assign collaborator');
      } finally {
        setAssigningId(null);
      }
    },
    [collaborators, confirm],
  );

  const columns = useMemo<DataColumn<Salon>[]>(
    () => [
      {
        key: 'name',
        header: 'Salon Name',
        sortValue: (s) => s.name,
        render: (s) => <span className={styles.salonName}>{s.name}</span>,
      },
      {
        key: 'city',
        header: 'City',
        sortValue: (s) => s.city?.name,
        render: (s) => s.city?.name || 'N/A',
      },
      {
        key: 'admin',
        header: 'Owner / Admin',
        sortValue: (s) => s.admin?.name,
        render: (s) => s.admin?.name || 'N/A',
      },
      {
        key: 'collaborator',
        header: 'Collaborator',
        sortValue: (s) => s.assigned_collaborator?.name,
        // The cell is a control, so spell out the value for the CSV instead.
        csvValue: (s) => s.assigned_collaborator?.name || 'Unassigned',
        render: (s) => (
          <div className={styles.collaboratorCell}>
            <select
              className={styles.cellSelect}
              value={s.assigned_collaborator?.id || ''}
              onChange={(e) => handleAssign(s, e.target.value)}
              disabled={assigningId === s.id}
              aria-label={`Collaborator for ${s.name}`}
            >
              <option value="">Unassigned</option>
              {collaborators.map((c) => (
                <option key={c.id} value={c.id}>{c.name}</option>
              ))}
            </select>
            {justAssignedIds.includes(s.id) && <span className={styles.savedFlag}>Saved</span>}
          </div>
        ),
      },
      {
        key: 'status',
        header: 'Status',
        sortValue: (s) => s.status,
        csvValue: (s) => formatStatus(s.status),
        render: (s) => (
          <Badge tone={STATUS_TONE[s.status] ?? 'neutral'} dot={false}>{formatStatus(s.status)}</Badge>
        ),
      },
      {
        key: 'created_at',
        header: 'Joined',
        sortValue: (s) => new Date(s.created_at).getTime(),
        csvValue: (s) => s.created_at,
        render: (s) => <span className={styles.dateCell}>{formatDate(s.created_at)}</span>,
      },
      {
        key: 'action',
        header: 'Action',
        align: 'right',
        render: (s) => (
          <Link href={`/superadmin/salons/${s.id}`} className={styles.actionButton}>
            View Profile
          </Link>
        ),
      },
    ],
    [collaborators, assigningId, justAssignedIds, handleAssign],
  );

  // Server mode: the directory can hold every salon on the platform.
  const table = useTableState<Salon>({
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
      const params = new URLSearchParams({ page: String(page), per_page: String(perPage) });
      if (debouncedSearch) params.set('search', debouncedSearch);
      if (status) params.set('status', status);
      if (collaboratorId) params.set('collaborator_id', collaboratorId);
      if (sort) {
        params.set('column', sort.key);
        params.set('direction', sort.dir);
      }

      const res = await fetch(`/api/proxy/superadmin/salons?${params}`, { cache: 'no-store' });
      const json = await res.json();
      if (id !== requestId.current) return;
      if (!json.success) throw new Error(json.message || 'Error loading salons');

      setSalons(json.data || []);
      if (json.meta) setMeta(json.meta);
      setError('');
    } catch (err) {
      if (id !== requestId.current) return;
      setError(err instanceof Error ? err.message : 'Error loading salons');
    } finally {
      if (id === requestId.current) setLoading(false);
    }
  }, [debouncedSearch, status, collaboratorId, sort, page, perPage]);

  useEffect(() => {
    const timer = setTimeout(load, 0);
    return () => clearTimeout(timer);
  }, [load]);

  const resetTo = <T,>(setter: (v: T) => void) => (value: T) => {
    setter(value);
    table.setPage(1);
  };

  return (
    <div className={styles.container}>
      {confirmDialog}

      <div className={styles.header}>
        <div>
          <h1 className={styles.title}>Salon Directory</h1>
          <p className={styles.subtitle}>Master list of every salon on the platform.</p>
        </div>
      </div>

      <div className={styles.tableShell}>
        <DataTable
        columns={columns}
        rows={salons}
        rowKey={(s) => s.id}
        loading={loading && salons.length === 0}
        error={error || undefined}
        sort={sort}
        onSort={table.toggleSort}
        page={page}
        lastPage={meta.last_page}
        total={meta.total}
        onPage={table.setPage}
        perPage={perPage}
        onPerPageChange={table.changePerPage}
        noun="salons"
        exportName="salon-directory"
        caption="Every salon on the platform"
        rowClassName={(s) => cx(justAssignedIds.includes(s.id) && styles.rowSuccess)}
        empty={{
          title: search ? `No salon matches “${search}”` : 'No salons found',
          hint: search || status || collaboratorId ? 'Try clearing the filters above.' : undefined,
        }}
        toolbar={
          <>
            <SearchInput
              value={search}
              onChange={resetTo(setSearch)}
              placeholder="Search by salon name or city…"
              ariaLabel="Search salons"
              className={styles.searchField}
            />
            <select
              className={styles.selectInput}
              value={status}
              onChange={(e) => resetTo(setStatus)(e.target.value)}
              aria-label="Filter by status"
            >
              <option value="">All Statuses</option>
              <option value="active">Active</option>
              <option value="pending_approval">Pending Approval</option>
              <option value="suspended">Suspended</option>
              <option value="deactivated">Deactivated</option>
              <option value="rejected">Rejected</option>
            </select>
            <select
              className={styles.selectInput}
              value={collaboratorId}
              onChange={(e) => resetTo(setCollaboratorId)(e.target.value)}
              aria-label="Filter by collaborator"
            >
              <option value="">All Collaborators</option>
              <option value="unassigned">Only Unassigned</option>
              {collaborators.map((c) => (
                <option key={c.id} value={c.id}>{c.name}</option>
              ))}
            </select>
          </>
        }
      />
      </div>
    </div>
  );
}
