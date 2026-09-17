'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import styles from './page.module.css';
import { readSpreadsheet, templateCsv } from './spreadsheet';

interface SubArea {
  id: string;
  name: string;
  is_active: boolean;
  city_id: string;
  city_name: string;
  state: string | null;
  salon_count: number;
  people_count: number;
  in_use: boolean;
}

interface City {
  id: string;
  name: string;
  state: string;
}

interface CityNode {
  id: string;
  name: string;
  state: string;
  areas: SubArea[];
}

interface StateNode {
  name: string;
  cities: CityNode[];
  areaCount: number;
}

/** What the import endpoint decided about one line of the file. */
type ImportStatus =
  | 'ready'
  | 'duplicate'
  | 'repeated'
  | 'unknown_city'
  | 'ambiguous_city'
  | 'invalid';

interface PreviewRow {
  line: number;
  city: string;
  state: string;
  area: string;
  status: ImportStatus;
  message: string;
  resolved_city?: string;
}

type PreviewSummary = Record<'total' | ImportStatus, number>;

const STATUS_LABEL: Record<ImportStatus, string> = {
  ready: 'Will be added',
  duplicate: 'Already there',
  repeated: 'Repeated in file',
  unknown_city: 'Unknown city',
  ambiguous_city: 'Ambiguous city',
  invalid: 'Invalid',
};

const NO_STATE = 'Unassigned';

/** Cities with localities first, then alphabetical. */
const byCoverageThenName = (a: CityNode, b: CityNode) =>
  b.areas.length - a.areas.length || a.name.localeCompare(b.name);

export default function SubAreasPage() {
  const [areas, setAreas] = useState<SubArea[]>([]);
  const [cities, setCities] = useState<City[]>([]);

  const [loading, setLoading] = useState(true);
  const [banner, setBanner] = useState<{ tone: 'ok' | 'bad'; text: string } | null>(null);

  // Where in the hierarchy we are standing.
  const [stateName, setStateName] = useState<string | null>(null);
  const [cityId, setCityId] = useState<string | null>(null);
  const [cityQuery, setCityQuery] = useState('');

  // Searching cuts across the hierarchy, so it replaces the browser entirely
  // rather than filtering one column of it.
  const [query, setQuery] = useState('');

  const [importing, setImporting] = useState(false);

  const [newName, setNewName] = useState('');
  const [adding, setAdding] = useState(false);

  const [editingId, setEditingId] = useState<string | null>(null);
  const [editName, setEditName] = useState('');

  // Removal asks in place instead of through a browser dialog, so the warning
  // about attached salons can be read next to the thing it is warning about.
  const [confirmId, setConfirmId] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);

  /**
   * Everything at once.
   *
   * It is 80-odd localities against 500 cities — small enough that one fetch
   * beats a round trip per keystroke, and it makes every filter on this page
   * instant.
   */
  const load = useCallback(async () => {
    try {
      const res = await fetch('/api/proxy/superadmin/sub-areas', { cache: 'no-store' });
      const json = await res.json();
      if (!json.success) throw new Error(json.message || 'Could not load areas');

      setAreas(json.data || []);
      setCities(json.cities || []);
    } catch (e) {
      setBanner({ tone: 'bad', text: e instanceof Error ? e.message : 'Could not load areas' });
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  // A success notice that stays on screen stops meaning anything.
  useEffect(() => {
    if (banner?.tone !== 'ok') return;
    const timer = setTimeout(() => setBanner(null), 4000);
    return () => clearTimeout(timer);
  }, [banner]);

  const say = (tone: 'ok' | 'bad', text: string) => setBanner({ tone, text });

  /** State → city → locality, built once from the two flat lists. */
  const tree = useMemo<StateNode[]>(() => {
    const cityById = new Map<string, CityNode>();

    // Every city, including the empty ones: a city you cannot reach is a city
    // that can never be given its first locality.
    cities.forEach((c) =>
      cityById.set(c.id, { id: c.id, name: c.name, state: c.state || NO_STATE, areas: [] })
    );

    areas.forEach((a) => {
      let node = cityById.get(a.city_id);
      if (!node) {
        // Its city is switched off, but the locality still exists and still
        // has to be reachable.
        node = { id: a.city_id, name: a.city_name, state: a.state || NO_STATE, areas: [] };
        cityById.set(a.city_id, node);
      }
      node.areas.push(a);
    });

    const byState = new Map<string, CityNode[]>();
    cityById.forEach((c) => byState.set(c.state, [...(byState.get(c.state) ?? []), c]));

    return [...byState.entries()]
      .map(([name, list]) => ({
        name,
        cities: list.sort(byCoverageThenName),
        areaCount: list.reduce((sum, c) => sum + c.areas.length, 0),
      }))
      .sort((a, b) => b.areaCount - a.areaCount || a.name.localeCompare(b.name));
  }, [areas, cities]);

  // Open on somewhere worth looking at, and never leave a dead selection
  // pointing at a state or city that a reload has removed.
  useEffect(() => {
    if (tree.length === 0) return;
    setStateName((prev) => (prev && tree.some((s) => s.name === prev) ? prev : tree[0].name));
  }, [tree]);

  const currentState = useMemo(
    () => tree.find((s) => s.name === stateName) ?? null,
    [tree, stateName]
  );

  useEffect(() => {
    if (!currentState) return;
    setCityId((prev) => {
      if (prev && currentState.cities.some((c) => c.id === prev)) return prev;
      const firstUseful = currentState.cities.find((c) => c.areas.length > 0);
      return (firstUseful ?? currentState.cities[0])?.id ?? null;
    });
  }, [currentState]);

  const currentCity = useMemo(
    () => currentState?.cities.find((c) => c.id === cityId) ?? null,
    [currentState, cityId]
  );

  // A half-typed name, an open rename or a pending delete all belonged to the
  // city you just left. Carrying them over is how "Kothrud" ends up in Mumbai.
  useEffect(() => {
    setNewName('');
    setEditingId(null);
    setConfirmId(null);
  }, [cityId]);

  const visibleCities = useMemo(() => {
    const q = cityQuery.trim().toLowerCase();
    const list = currentState?.cities ?? [];
    return q ? list.filter((c) => c.name.toLowerCase().includes(q)) : list;
  }, [currentState, cityQuery]);

  const results = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return [];
    return areas.filter(
      (a) =>
        a.name.toLowerCase().includes(q) ||
        a.city_name.toLowerCase().includes(q) ||
        (a.state ?? '').toLowerCase().includes(q)
    );
  }, [areas, query]);

  const stats = useMemo(
    () => ({
      total: areas.length,
      cities: new Set(areas.map((a) => a.city_id)).size,
      states: new Set(areas.map((a) => a.state || NO_STATE)).size,
    }),
    [areas]
  );

  const goTo = (area: SubArea) => {
    setQuery('');
    setCityQuery('');
    setStateName(area.state || NO_STATE);
    setCityId(area.city_id);
  };

  const add = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!currentCity || !newName.trim()) return;

    setAdding(true);
    try {
      const res = await fetch('/api/proxy/superadmin/sub-areas', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ city_id: currentCity.id, name: newName.trim() }),
      });
      const json = await res.json();
      if (!res.ok || !json.success) {
        const first = json?.errors ? Object.values(json.errors)[0] : null;
        throw new Error(Array.isArray(first) ? String(first[0]) : json.message || 'Could not add it');
      }

      setNewName('');
      say('ok', json.message);
      await load();
    } catch (err) {
      say('bad', err instanceof Error ? err.message : 'Could not add it');
    } finally {
      setAdding(false);
    }
  };

  const rename = async (area: SubArea) => {
    const name = editName.trim();
    if (!name || name === area.name) {
      setEditingId(null);
      return;
    }

    try {
      const res = await fetch(`/api/proxy/superadmin/sub-areas/${area.id}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name }),
      });
      const json = await res.json();
      if (!res.ok || !json.success) {
        const first = json?.errors ? Object.values(json.errors)[0] : null;
        throw new Error(Array.isArray(first) ? String(first[0]) : json.message || 'Could not rename it');
      }
      setEditingId(null);
      say('ok', `Renamed to ${name}.`);
      await load();
    } catch (err) {
      say('bad', err instanceof Error ? err.message : 'Could not rename it');
    }
  };

  const toggleActive = async (area: SubArea) => {
    setBusyId(area.id);
    try {
      const res = await fetch(`/api/proxy/superadmin/sub-areas/${area.id}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ is_active: !area.is_active }),
      });
      if (!res.ok) throw new Error('Could not change it');
      say('ok', `${area.name} is now ${area.is_active ? 'hidden from' : 'available in'} the dropdowns.`);
      await load();
    } catch (err) {
      say('bad', err instanceof Error ? err.message : 'Could not change it');
    } finally {
      setBusyId(null);
    }
  };

  const remove = async (area: SubArea) => {
    setBusyId(area.id);
    try {
      const res = await fetch(`/api/proxy/superadmin/sub-areas/${area.id}`, { method: 'DELETE' });
      const json = await res.json();
      if (!res.ok || !json.success) throw new Error(json.message || 'Could not remove it');
      setConfirmId(null);
      say('ok', json.message);
      await load();
    } catch (err) {
      say('bad', err instanceof Error ? err.message : 'Could not remove it');
    } finally {
      setBusyId(null);
    }
  };

  const cardProps = (area: SubArea) => ({
    area,
    editing: editingId === area.id,
    editName,
    onEditName: setEditName,
    onStartEdit: () => {
      setConfirmId(null);
      setEditingId(area.id);
      setEditName(area.name);
    },
    onCancelEdit: () => setEditingId(null),
    onCommitEdit: () => rename(area),
    onToggle: () => toggleActive(area),
    confirming: confirmId === area.id,
    onAskRemove: () => {
      setEditingId(null);
      setConfirmId(area.id);
    },
    onCancelRemove: () => setConfirmId(null),
    onConfirmRemove: () => remove(area),
    busy: busyId === area.id,
  });

  return (
    <div className={styles.container}>
      <header className={styles.header}>
        <div>
          <h1 className={styles.title}>Areas</h1>
          <p className={styles.subtitle}>
            Localities inside each city. Customers browse by them, salons are listed in them, and
            an enquiry is matched to the collaborator who already works in the same one. Keep the
            spelling consistent — two versions of a neighbourhood split it in half everywhere it is
            used.
          </p>
        </div>

        <div className={styles.headerSide}>
          <div className={styles.statRow}>
            <div className={styles.stat}>
              <span className={styles.statValue}>{stats.total}</span>
              <span className={styles.statLabel}>Areas</span>
            </div>
            <div className={styles.stat}>
              <span className={styles.statValue}>{stats.cities}</span>
              <span className={styles.statLabel}>Cities covered</span>
            </div>
            <div className={styles.stat}>
              <span className={styles.statValue}>{stats.states}</span>
              <span className={styles.statLabel}>States covered</span>
            </div>
          </div>

          <button type="button" className={styles.button} onClick={() => setImporting(true)}>
            Import from file
          </button>
        </div>
      </header>

      {importing && (
        <ImportDialog
          onClose={() => setImporting(false)}
          onImported={async (message) => {
            setImporting(false);
            say('ok', message);
            await load();
          }}
        />
      )}

      <div className={styles.searchWrap}>
        <span className={styles.searchIcon} aria-hidden="true">
          ⌕
        </span>
        <input
          className={styles.searchInput}
          placeholder="Search every area, city or state…"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          aria-label="Search areas"
        />
        {query && (
          <button type="button" className={styles.searchClear} onClick={() => setQuery('')}>
            Clear
          </button>
        )}
      </div>

      {banner && (
        <div
          className={`${styles.banner} ${banner.tone === 'ok' ? styles.bannerOk : styles.bannerBad}`}
        >
          <span>{banner.text}</span>
          <button type="button" className={styles.bannerClose} onClick={() => setBanner(null)}>
            ✕
          </button>
        </div>
      )}

      {loading ? (
        <div className={styles.empty}>Loading…</div>
      ) : query.trim() ? (
        /* ---------- Search results ---------- */
        <section className={styles.resultsPane}>
          <h2 className={styles.paneTitle}>
            {results.length} {results.length === 1 ? 'match' : 'matches'} for “{query.trim()}”
          </h2>

          {results.length === 0 ? (
            <div className={styles.empty}>
              Nothing matches that. Clear the search to browse by state instead.
            </div>
          ) : (
            <div className={styles.grid}>
              {results.map((area) => (
                <AreaCard key={area.id} {...cardProps(area)} onGoTo={() => goTo(area)} />
              ))}
            </div>
          )}
        </section>
      ) : (
        /* ---------- State → city → area ---------- */
        <div className={styles.browser}>
          <section className={styles.pane}>
            <header className={styles.paneHead}>
              <h2 className={styles.paneTitle}>State</h2>
              <span className={styles.paneCount}>{tree.length}</span>
            </header>

            <div className={styles.paneBody}>
              <ColumnGroups
                label="With areas"
                emptyLabel="Not set up yet"
                withItems={tree.filter((s) => s.areaCount > 0)}
                withoutItems={tree.filter((s) => s.areaCount === 0)}
                renderItem={(s) => (
                  <button
                    key={s.name}
                    type="button"
                    className={`${styles.row} ${stateName === s.name ? styles.rowActive : ''}`}
                    onClick={() => {
                      setStateName(s.name);
                      setCityQuery('');
                    }}
                  >
                    <span className={styles.rowName}>{s.name}</span>
                    {s.areaCount > 0 && <span className={styles.rowCount}>{s.areaCount}</span>}
                    <span className={styles.chevron} aria-hidden="true">
                      ›
                    </span>
                  </button>
                )}
              />
            </div>
          </section>

          <section className={styles.pane}>
            <header className={styles.paneHead}>
              <h2 className={styles.paneTitle}>City</h2>
              <span className={styles.paneCount}>{currentState?.cities.length ?? 0}</span>
            </header>

            <div className={styles.paneFilter}>
              <input
                className={styles.filterInput}
                placeholder="Filter cities…"
                value={cityQuery}
                onChange={(e) => setCityQuery(e.target.value)}
                aria-label="Filter cities"
              />
            </div>

            <div className={styles.paneBody}>
              {visibleCities.length === 0 ? (
                <p className={styles.paneEmpty}>No city matches that.</p>
              ) : (
                <ColumnGroups
                  label="With areas"
                  emptyLabel="No areas yet"
                  withItems={visibleCities.filter((c) => c.areas.length > 0)}
                  withoutItems={visibleCities.filter((c) => c.areas.length === 0)}
                  renderItem={(c) => (
                    <button
                      key={c.id}
                      type="button"
                      className={`${styles.row} ${cityId === c.id ? styles.rowActive : ''}`}
                      onClick={() => setCityId(c.id)}
                    >
                      <span className={styles.rowName}>{c.name}</span>
                      {c.areas.length > 0 && (
                        <span className={styles.rowCount}>{c.areas.length}</span>
                      )}
                      <span className={styles.chevron} aria-hidden="true">
                        ›
                      </span>
                    </button>
                  )}
                />
              )}
            </div>
          </section>

          <section className={`${styles.pane} ${styles.areaPane}`}>
            {!currentCity ? (
              <div className={styles.empty}>Pick a city on the left to see its areas.</div>
            ) : (
              <>
                <header className={styles.paneHead}>
                  <div>
                    <p className={styles.crumb}>{currentState?.name}</p>
                    <h2 className={styles.cityTitle}>{currentCity.name}</h2>
                  </div>
                  <span className={styles.paneCount}>
                    {currentCity.areas.length} {currentCity.areas.length === 1 ? 'area' : 'areas'}
                  </span>
                </header>

                <form onSubmit={add} className={styles.addRow}>
                  <input
                    className={styles.input}
                    placeholder={`Add an area to ${currentCity.name}, e.g. Kothrud`}
                    value={newName}
                    onChange={(e) => setNewName(e.target.value)}
                    maxLength={120}
                    required
                  />
                  <button className={styles.button} type="submit" disabled={adding}>
                    {adding ? 'Adding…' : 'Add'}
                  </button>
                </form>

                <div className={styles.paneBody}>
                  {currentCity.areas.length === 0 ? (
                    <p className={styles.paneEmpty}>
                      {currentCity.name} has no areas yet. Add the first one above — every address
                      form on the platform reads this list.
                    </p>
                  ) : (
                    <div className={styles.grid}>
                      {currentCity.areas.map((area) => (
                        <AreaCard key={area.id} {...cardProps(area)} />
                      ))}
                    </div>
                  )}
                </div>
              </>
            )}
          </section>
        </div>
      )}
    </div>
  );
}

/**
 * Bulk import, in two deliberate halves.
 *
 * The file is read here in the browser and sent to the API as rows; the API is
 * then asked what it *would* do, and only once that has been read and accepted
 * is it asked to do it. Nothing writes until the second request, so there is no
 * arrangement of clicks that adds two hundred localities to the wrong city
 * without showing them first.
 */
function ImportDialog({
  onClose,
  onImported,
}: {
  onClose: () => void;
  onImported: (message: string) => void | Promise<void>;
}) {
  const [stage, setStage] = useState<'choose' | 'checking' | 'preview' | 'saving'>('choose');
  const [fileName, setFileName] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [note, setNote] = useState<string | null>(null);
  const [dragging, setDragging] = useState(false);
  const [problemsOnly, setProblemsOnly] = useState(false);

  const [rows, setRows] = useState<PreviewRow[]>([]);
  const [summary, setSummary] = useState<PreviewSummary | null>(null);
  const [payload, setPayload] = useState<unknown[]>([]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [onClose]);

  const reset = () => {
    setStage('choose');
    setFileName('');
    setError(null);
    setNote(null);
    setRows([]);
    setSummary(null);
    setPayload([]);
    setProblemsOnly(false);
  };

  /** Read the file, then ask the server what it makes of it. */
  const take = async (file: File) => {
    setError(null);
    setFileName(file.name);
    setStage('checking');

    try {
      if (file.size > 5 * 1024 * 1024) {
        throw new Error('That file is over 5 MB. This list is text; something is wrong with it.');
      }

      const { rows: parsed, columns, skippedBlank } = await readSpreadsheet(file);

      if (parsed.length === 0) {
        throw new Error('Found the header but no rows under it.');
      }

      if (parsed.length > 2000) {
        throw new Error(
          `${parsed.length} rows — the import takes 2000 at a time. Split the file and run it twice.`
        );
      }

      const res = await fetch('/api/proxy/superadmin/sub-areas/import', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ rows: parsed, commit: false }),
      });
      const json = await res.json();
      if (!res.ok || !json.success) throw new Error(json.message || 'Could not read that file.');

      setRows(json.rows || []);
      setSummary(json.summary || null);
      setPayload(parsed);
      setStage('preview');

      // Worth saying out loud — a column read as the wrong thing is the one
      // mistake a preview of correct-looking rows would not reveal.
      const read = [
        `Read “${columns.city}” as the city`,
        columns.state ? `“${columns.state}” as the state` : null,
        `“${columns.area}” as the area`,
      ]
        .filter(Boolean)
        .join(', ');

      setNote(`${read}.${skippedBlank > 0 ? ` Skipped ${skippedBlank} blank row(s).` : ''}`);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not read that file.');
      setStage('choose');
    }
  };

  const commit = async () => {
    setStage('saving');
    try {
      const res = await fetch('/api/proxy/superadmin/sub-areas/import', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ rows: payload, commit: true }),
      });
      const json = await res.json();
      if (!res.ok || !json.success) throw new Error(json.message || 'Could not import them.');

      const skipped = (json.summary?.total ?? 0) - (json.created ?? 0);
      await onImported(
        skipped > 0 ? `${json.message} ${skipped} row(s) skipped.` : json.message
      );
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not import them.');
      setStage('preview');
    }
  };

  const downloadTemplate = () => {
    const url = URL.createObjectURL(new Blob([templateCsv()], { type: 'text/csv' }));
    const link = document.createElement('a');
    link.href = url;
    link.download = 'areas-template.csv';
    link.click();
    URL.revokeObjectURL(url);
  };

  const shown = problemsOnly ? rows.filter((row) => row.status !== 'ready') : rows;
  const ready = summary?.ready ?? 0;

  return (
    <div
      className={styles.overlay}
      role="dialog"
      aria-modal="true"
      aria-label="Import areas from a file"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div className={styles.modal}>
        <header className={styles.modalHead}>
          <h2 className={styles.modalTitle}>Import areas</h2>
          <button type="button" className={styles.modalClose} onClick={onClose} aria-label="Close">
            ✕
          </button>
        </header>

        <div className={styles.modalBody}>
          {stage === 'choose' && (
            <>
              <div
                className={`${styles.drop} ${dragging ? styles.dropActive : ''}`}
                onDragOver={(e) => {
                  e.preventDefault();
                  setDragging(true);
                }}
                onDragLeave={() => setDragging(false)}
                onDrop={(e) => {
                  e.preventDefault();
                  setDragging(false);
                  const file = e.dataTransfer.files?.[0];
                  if (file) take(file);
                }}
              >
                <p className={styles.dropTitle}>Drop a CSV or Excel file here</p>
                <p className={styles.dropHint}>.csv, .tsv or .xlsx — up to 2000 rows</p>

                <label className={styles.button}>
                  Choose a file
                  <input
                    type="file"
                    accept=".csv,.tsv,.txt,.xlsx,text/csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
                    className={styles.hiddenFile}
                    onChange={(e) => {
                      const file = e.target.files?.[0];
                      // Cleared so choosing the same file twice still fires.
                      e.target.value = '';
                      if (file) take(file);
                    }}
                  />
                </label>
              </div>

              <div className={styles.formatHelp}>
                <p className={styles.formatTitle}>What the file needs</p>
                <p className={styles.formatText}>
                  A header row with a <strong>city</strong> column and an <strong>area</strong>{' '}
                  column. A <strong>state</strong> column is optional but catches typos — a row
                  saying Pune is in Kerala is reported rather than guessed at. Column order does not
                  matter, and a title row above the header is fine.
                </p>
                <p className={styles.formatText}>
                  Cities are never created by an import. A city the platform does not know is
                  reported and its rows are left out.
                </p>
                <button type="button" className={styles.linkButton} onClick={downloadTemplate}>
                  Download a template
                </button>
              </div>
            </>
          )}

          {stage === 'checking' && <p className={styles.working}>Reading {fileName}…</p>}

          {(stage === 'preview' || stage === 'saving') && summary && (
            <>
              <div className={styles.previewHead}>
                <div>
                  <p className={styles.fileName}>{fileName}</p>
                  {note && <p className={styles.note}>{note}</p>}
                </div>
                <button type="button" className={styles.linkButton} onClick={reset}>
                  Choose another file
                </button>
              </div>

              <div className={styles.chips}>
                {(Object.keys(STATUS_LABEL) as ImportStatus[])
                  .filter((status) => (summary[status] ?? 0) > 0)
                  .map((status) => (
                    <span key={status} className={`${styles.chip} ${styles[status]}`}>
                      {summary[status]} {STATUS_LABEL[status].toLowerCase()}
                    </span>
                  ))}
              </div>

              {summary.total > ready && (
                <label className={styles.toggle}>
                  <input
                    type="checkbox"
                    checked={problemsOnly}
                    onChange={(e) => setProblemsOnly(e.target.checked)}
                  />
                  Show only the rows that will not be added
                </label>
              )}

              <div className={styles.tableWrap}>
                <table className={styles.table}>
                  <thead>
                    <tr>
                      <th>Row</th>
                      <th>City</th>
                      <th>Area</th>
                      <th>What happens</th>
                    </tr>
                  </thead>
                  <tbody>
                    {shown.map((row) => (
                      <tr key={row.line} className={row.status === 'ready' ? '' : styles.rowMuted}>
                        <td className={styles.lineCell}>{row.line}</td>
                        <td>
                          {row.resolved_city || row.city || <em>—</em>}
                          {!row.resolved_city && row.state ? `, ${row.state}` : ''}
                        </td>
                        <td>{row.area || <em>—</em>}</td>
                        <td>
                          <span className={`${styles.chip} ${styles[row.status]}`}>
                            {STATUS_LABEL[row.status]}
                          </span>{' '}
                          <span className={styles.rowMessage}>{row.message}</span>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </>
          )}

          {error && <p className={styles.modalError}>{error}</p>}
        </div>

        <footer className={styles.modalFoot}>
          <button type="button" className={styles.linkButton} onClick={onClose}>
            Cancel
          </button>

          {(stage === 'preview' || stage === 'saving') && (
            <button
              type="button"
              className={styles.button}
              onClick={commit}
              disabled={ready === 0 || stage === 'saving'}
            >
              {stage === 'saving'
                ? 'Importing…'
                : ready === 0
                  ? 'Nothing to add'
                  : `Add ${ready} area${ready === 1 ? '' : 's'}`}
            </button>
          )}
        </footer>
      </div>
    </div>
  );
}

/**
 * One column, split into the entries that carry localities and the ones that do
 * not. Six cities out of five hundred are in use, so without the split the six
 * that matter are lost in the alphabet.
 */
function ColumnGroups<T>({
  label,
  emptyLabel,
  withItems,
  withoutItems,
  renderItem,
}: {
  label: string;
  emptyLabel: string;
  withItems: T[];
  withoutItems: T[];
  renderItem: (item: T) => React.ReactNode;
}) {
  return (
    <>
      {withItems.length > 0 && (
        <>
          <p className={styles.groupLabel}>{label}</p>
          {withItems.map(renderItem)}
        </>
      )}
      {withoutItems.length > 0 && (
        <>
          <p className={styles.groupLabel}>{emptyLabel}</p>
          {withoutItems.map(renderItem)}
        </>
      )}
    </>
  );
}

function AreaCard({
  area,
  editing,
  editName,
  onEditName,
  onStartEdit,
  onCancelEdit,
  onCommitEdit,
  onToggle,
  confirming,
  onAskRemove,
  onCancelRemove,
  onConfirmRemove,
  busy,
  onGoTo,
}: {
  area: SubArea;
  editing: boolean;
  editName: string;
  onEditName: (value: string) => void;
  onStartEdit: () => void;
  onCancelEdit: () => void;
  onCommitEdit: () => void;
  onToggle: () => void;
  confirming: boolean;
  onAskRemove: () => void;
  onCancelRemove: () => void;
  onConfirmRemove: () => void;
  busy: boolean;
  onGoTo?: () => void;
}) {
  const usage = [
    area.salon_count > 0 && `${area.salon_count} salon${area.salon_count === 1 ? '' : 's'}`,
    area.people_count > 0 &&
      `${area.people_count} ${area.people_count === 1 ? 'person' : 'people'}`,
  ].filter(Boolean);

  return (
    <div className={`${styles.area} ${area.is_active ? '' : styles.areaOff}`}>
      <div className={styles.areaTop}>
        {editing ? (
          <input
            className={styles.inlineInput}
            value={editName}
            autoFocus
            maxLength={120}
            // Clicking a name to rename it almost always means replacing it, so
            // the whole thing arrives selected and one keystroke starts over.
            onFocus={(e) => e.target.select()}
            onChange={(e) => onEditName(e.target.value)}
            onBlur={onCommitEdit}
            onKeyDown={(e) => {
              if (e.key === 'Enter') onCommitEdit();
              if (e.key === 'Escape') onCancelEdit();
            }}
          />
        ) : (
          <button type="button" className={styles.areaName} onClick={onStartEdit} title="Click to rename">
            {area.name}
          </button>
        )}

        {!area.is_active && <span className={styles.hiddenTag}>Hidden</span>}
      </div>

      {onGoTo && (
        <button type="button" className={styles.where} onClick={onGoTo}>
          {area.city_name}
          {area.state ? `, ${area.state}` : ''} ↗
        </button>
      )}

      <span className={styles.usage}>{usage.length > 0 ? usage.join(' · ') : 'Not used yet'}</span>

      {confirming ? (
        <div className={styles.confirm}>
          <p className={styles.confirmText}>
            {area.in_use
              ? 'In use, so it will be switched off instead of deleted. Existing addresses keep it.'
              : 'Delete this area?'}
          </p>
          <div className={styles.areaActions}>
            <button
              type="button"
              className={`${styles.iconButton} ${styles.iconDanger}`}
              onClick={onConfirmRemove}
              disabled={busy}
            >
              {busy ? 'Working…' : area.in_use ? 'Switch off' : 'Delete'}
            </button>
            <button type="button" className={styles.iconButton} onClick={onCancelRemove}>
              Cancel
            </button>
          </div>
        </div>
      ) : (
        <div className={styles.areaActions}>
          <button
            type="button"
            className={styles.iconButton}
            onClick={onToggle}
            disabled={busy}
            title={area.is_active ? 'Hide from every dropdown' : 'Offer it in the dropdowns again'}
          >
            {area.is_active ? 'Hide' : 'Show'}
          </button>
          <button
            type="button"
            className={`${styles.iconButton} ${styles.iconDanger}`}
            onClick={onAskRemove}
            disabled={busy}
          >
            Remove
          </button>
        </div>
      )}
    </div>
  );
}
