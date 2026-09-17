/**
 * Reading a locality list out of whatever file someone exported.
 *
 * Both formats are decoded in the browser and sent to the API as plain rows,
 * which is not the obvious arrangement — the usual one posts the file and lets
 * the server parse it. It is done this way because PHP's zip extension is
 * switched off on this deployment, and an .xlsx is a zip. Rather than make the
 * feature wait on a server rebuild, or pull in a parsing library for one admin
 * page, the unpacking happens where the file already is.
 *
 * Nothing here needs a dependency: a zip's directory is a documented structure,
 * and every browser this dashboard runs in can inflate a deflate stream.
 */

export interface SheetRow {
  /** The row's own number in the file, so errors can be pointed at. */
  line: number;
  city: string;
  state: string;
  area: string;
}

export interface ReadResult {
  rows: SheetRow[];
  /** Which columns were recognised, to show back as confirmation. */
  columns: { city: string; state: string | null; area: string };
  /** Rows that were entirely blank and silently dropped. */
  skippedBlank: number;
}

/** Spellings of each column that a person might reasonably have used. */
const CITY_HEADERS = ['city', 'cityname', 'town'];
const STATE_HEADERS = ['state', 'province', 'region'];
const AREA_HEADERS = [
  'area',
  'areaname',
  'subarea',
  'subareaname',
  'sublocality',
  'locality',
  'neighbourhood',
  'neighborhood',
  'name',
];

const normalise = (value: string) => value.toLowerCase().replace(/[^a-z0-9]/g, '');

// ---------------------------------------------------------------- entry point

export async function readSpreadsheet(file: File): Promise<ReadResult> {
  const name = file.name.toLowerCase();

  if (name.endsWith('.xls')) {
    throw new Error(
      'That is the old binary .xls format. Open it in Excel and save as .xlsx or CSV.'
    );
  }

  const grid = name.endsWith('.xlsx')
    ? await readXlsx(await file.arrayBuffer())
    : readDelimited(await file.text());

  return toRows(grid);
}

/** The file to hand someone who asks what the format is. */
export function templateCsv(): string {
  return [
    'city,state,area',
    'Pune,Maharashtra,Kothrud',
    'Pune,Maharashtra,Baner',
    'Mumbai,Maharashtra,Andheri East',
    'Bangalore,Karnataka,Koramangala',
  ].join('\r\n');
}

// ------------------------------------------------------------ CSV and friends

/**
 * Comma, semicolon, tab or pipe separated text, with quoting.
 *
 * Quoted fields matter more than they look: "Andheri East, Mumbai" in one cell
 * is exactly the kind of thing a naive split on commas turns into two columns
 * and a corrupted import.
 */
export function readDelimited(text: string): string[][] {
  // Excel writes a byte order mark on CSV export, which otherwise becomes part
  // of the first header and stops "city" matching.
  const clean = text.replace(/^﻿/, '');
  const delimiter = detectDelimiter(clean);

  const grid: string[][] = [];
  let row: string[] = [];
  let field = '';
  let quoted = false;

  for (let i = 0; i < clean.length; i++) {
    const char = clean[i];

    if (quoted) {
      if (char === '"') {
        // A doubled quote is an escaped one, anything else ends the field.
        if (clean[i + 1] === '"') {
          field += '"';
          i++;
        } else {
          quoted = false;
        }
      } else {
        field += char;
      }
      continue;
    }

    if (char === '"') {
      quoted = true;
    } else if (char === delimiter) {
      row.push(field);
      field = '';
    } else if (char === '\n') {
      row.push(field);
      grid.push(row);
      row = [];
      field = '';
    } else if (char !== '\r') {
      field += char;
    }
  }

  if (field !== '' || row.length > 0) {
    row.push(field);
    grid.push(row);
  }

  return grid;
}

/** Whichever separator appears most on the first line, outside quotes. */
function detectDelimiter(text: string): string {
  let firstLine = '';
  let quoted = false;

  for (const char of text) {
    if (char === '"') quoted = !quoted;
    if (char === '\n' && !quoted) break;
    firstLine += char;
  }

  const counts = [',', ';', '\t', '|'].map((candidate) => {
    let inQuotes = false;
    let total = 0;
    for (const char of firstLine) {
      if (char === '"') inQuotes = !inQuotes;
      else if (char === candidate && !inQuotes) total++;
    }
    return { candidate, total };
  });

  const best = counts.sort((a, b) => b.total - a.total)[0];
  return best.total > 0 ? best.candidate : ',';
}

// ------------------------------------------------------------------- the xlsx

interface ZipEntry {
  name: string;
  method: number;
  start: number;
  compressedSize: number;
}

/**
 * The first worksheet of an .xlsx, as a grid of strings.
 *
 * An .xlsx is a zip of XML. Only three parts of it are interesting here: the
 * worksheet, the shared string table its cells point into, and nothing else.
 * Formatting, formulas and dates are all ignored — a locality is a piece of
 * text, and a cell that held a formula is read as whatever it last evaluated to.
 */
export async function readXlsx(buffer: ArrayBuffer): Promise<string[][]> {
  const bytes = new Uint8Array(buffer);
  const entries = readZipDirectory(bytes);

  if (entries.length === 0) {
    throw new Error('That file is not a readable .xlsx — it has no zip directory.');
  }

  // sheet1.xml is the first sheet in everything that writes these files.
  const sheets = entries
    .filter((entry) => /^xl\/worksheets\/sheet\d+\.xml$/.test(entry.name))
    .sort((a, b) => sheetNumber(a.name) - sheetNumber(b.name));

  if (sheets.length === 0) {
    throw new Error('No worksheet found inside that .xlsx.');
  }

  const sharedEntry = entries.find((entry) => entry.name === 'xl/sharedStrings.xml');
  const shared = sharedEntry ? readSharedStrings(await inflate(bytes, sharedEntry)) : [];

  return readWorksheet(await inflate(bytes, sheets[0]), shared);
}

const sheetNumber = (name: string) => Number(name.replace(/\D/g, '')) || 0;

/**
 * Walk the zip's central directory.
 *
 * The directory sits at the end of the file and points backwards at each entry,
 * which is why this reads from the end rather than streaming forwards.
 */
function readZipDirectory(bytes: Uint8Array): ZipEntry[] {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);

  // End-of-central-directory record. It is last in the file, but a trailing
  // comment can follow it, so scan back over the largest a comment may be.
  let eocd = -1;
  const earliest = Math.max(0, bytes.length - 0xffff - 22);
  for (let i = bytes.length - 22; i >= earliest; i--) {
    if (view.getUint32(i, true) === 0x06054b50) {
      eocd = i;
      break;
    }
  }

  if (eocd < 0) return [];

  const count = view.getUint16(eocd + 10, true);
  let cursor = view.getUint32(eocd + 16, true);
  const entries: ZipEntry[] = [];

  for (let n = 0; n < count; n++) {
    if (cursor + 46 > bytes.length || view.getUint32(cursor, true) !== 0x02014b50) break;

    const method = view.getUint16(cursor + 10, true);
    const compressedSize = view.getUint32(cursor + 20, true);
    const nameLength = view.getUint16(cursor + 28, true);
    const extraLength = view.getUint16(cursor + 30, true);
    const commentLength = view.getUint16(cursor + 32, true);
    const localHeader = view.getUint32(cursor + 42, true);

    const name = new TextDecoder().decode(bytes.subarray(cursor + 46, cursor + 46 + nameLength));

    // The local header repeats the name and carries its own extra field, and
    // the two lengths need not match the ones in the directory — so the start
    // of the data can only be worked out from the local header itself.
    const localNameLength = view.getUint16(localHeader + 26, true);
    const localExtraLength = view.getUint16(localHeader + 28, true);

    entries.push({
      name,
      method,
      compressedSize,
      start: localHeader + 30 + localNameLength + localExtraLength,
    });

    cursor += 46 + nameLength + extraLength + commentLength;
  }

  return entries;
}

async function inflate(bytes: Uint8Array, entry: ZipEntry): Promise<string> {
  const slice = bytes.subarray(entry.start, entry.start + entry.compressedSize);

  if (entry.method === 0) return new TextDecoder().decode(slice);

  if (entry.method !== 8) {
    throw new Error(`That .xlsx uses an unsupported compression method (${entry.method}).`);
  }

  if (typeof DecompressionStream === 'undefined') {
    throw new Error('This browser cannot unpack .xlsx files. Save the sheet as CSV instead.');
  }

  const stream = new Blob([slice as BlobPart])
    .stream()
    .pipeThrough(new DecompressionStream('deflate-raw'));

  return new Response(stream).text();
}

function parseXml(text: string): Document {
  const doc = new DOMParser().parseFromString(text, 'application/xml');

  if (doc.getElementsByTagName('parsererror').length > 0) {
    throw new Error('The XML inside that .xlsx could not be read.');
  }

  return doc;
}

/** Cells do not hold their own text; they hold an index into this table. */
function readSharedStrings(xml: string): string[] {
  const doc = parseXml(xml);

  return Array.from(doc.getElementsByTagNameNS('*', 'si')).map((si) =>
    // A styled cell splits its text across several runs, each with its own <t>.
    Array.from(si.getElementsByTagNameNS('*', 't'))
      .map((node) => node.textContent ?? '')
      .join('')
  );
}

function readWorksheet(xml: string, shared: string[]): string[][] {
  const doc = parseXml(xml);

  return Array.from(doc.getElementsByTagNameNS('*', 'row')).map((row) => {
    const cells: string[] = [];

    for (const cell of Array.from(row.getElementsByTagNameNS('*', 'c'))) {
      const type = cell.getAttribute('t');
      let value: string;

      if (type === 'inlineStr') {
        value = Array.from(cell.getElementsByTagNameNS('*', 't'))
          .map((node) => node.textContent ?? '')
          .join('');
      } else {
        const raw = cell.getElementsByTagNameNS('*', 'v')[0]?.textContent ?? '';
        value = type === 's' ? shared[Number(raw)] ?? '' : raw;
      }

      // An empty cell is simply absent from the XML, so B and D arriving in a
      // row means C was blank and the columns would otherwise shift left.
      const column = columnIndex(cell.getAttribute('r'), cells.length);
      while (cells.length < column) cells.push('');
      cells[column] = value;
    }

    return cells;
  });
}

/** "C7" is the third column. Falls back to position if the cell has no ref. */
function columnIndex(ref: string | null, fallback: number): number {
  const letters = (ref ?? '').replace(/[^A-Za-z]/g, '').toUpperCase();
  if (letters === '') return fallback;

  let index = 0;
  for (const letter of letters) index = index * 26 + (letter.charCodeAt(0) - 64);
  return index - 1;
}

// -------------------------------------------------------- grid to typed rows

/**
 * Find the header and read everything under it.
 *
 * The header is not assumed to be the first line. Exports routinely carry a
 * title or a blank row above the real one, and refusing those files teaches
 * people to hand-edit spreadsheets before uploading, which is its own source of
 * mistakes.
 */
function toRows(grid: string[][]): ReadResult {
  const limit = Math.min(grid.length, 10);

  for (let index = 0; index < limit; index++) {
    const headers = grid[index].map(normalise);

    const city = headers.findIndex((header) => CITY_HEADERS.includes(header));
    const area = headers.findIndex((header) => AREA_HEADERS.includes(header));
    const state = headers.findIndex((header) => STATE_HEADERS.includes(header));

    // "name" alone is ambiguous — in a one-column-per-thing file it is the
    // area, but next to a city column it could be either. Requiring both to
    // resolve separately keeps that from mattering.
    if (city === -1 || area === -1 || city === area) continue;

    const rows: SheetRow[] = [];
    let skippedBlank = 0;

    for (let r = index + 1; r < grid.length; r++) {
      const cells = grid[r];
      const value = (at: number) => (at >= 0 ? (cells[at] ?? '').trim() : '');

      if (cells.every((cell) => (cell ?? '').trim() === '')) {
        skippedBlank++;
        continue;
      }

      rows.push({
        // Spreadsheet row numbers are 1-based and the user is looking at them.
        line: r + 1,
        city: value(city),
        state: value(state),
        area: value(area),
      });
    }

    return {
      rows,
      columns: {
        city: grid[index][city] || 'city',
        state: state >= 0 ? grid[index][state] || 'state' : null,
        area: grid[index][area] || 'area',
      },
      skippedBlank,
    };
  }

  const found = (grid[0] ?? []).filter((cell) => cell.trim() !== '').join(', ');

  throw new Error(
    found
      ? `Could not find a city column and an area column. The first row reads: ${found}.`
      : 'That file appears to be empty.'
  );
}
