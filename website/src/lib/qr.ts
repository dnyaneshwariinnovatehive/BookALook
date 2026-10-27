/**
 * A small QR Code encoder: byte mode, error correction level M, versions 1–10
 * (up to 213 bytes — plenty for a download link). Written here rather than
 * pulled in as a package so the site keeps building with no new dependency.
 *
 * Returns the module grid: true = dark. Follows ISO/IEC 18004.
 */

// [total codewords, ec codewords per block, blocks in group 1, data cw per block g1, blocks g2, data cw g2]
const LEVEL_M: [number, number, number, number, number, number][] = [
  [26, 10, 1, 16, 0, 0],
  [44, 16, 1, 28, 0, 0],
  [70, 26, 1, 44, 0, 0],
  [100, 18, 2, 32, 0, 0],
  [134, 24, 2, 43, 0, 0],
  [172, 16, 4, 27, 0, 0],
  [196, 18, 4, 31, 0, 0],
  [242, 22, 2, 38, 2, 39],
  [292, 22, 3, 36, 2, 37],
  [346, 26, 4, 43, 1, 44],
];

const ALIGNMENT: number[][] = [
  [], [6, 18], [6, 22], [6, 26], [6, 30], [6, 34],
  [6, 22, 38], [6, 24, 42], [6, 26, 46], [6, 28, 50],
];

// ---------------------------------------------------------------- GF(256)

const EXP = new Array<number>(512);
const LOG = new Array<number>(256);
(() => {
  let x = 1;
  for (let i = 0; i < 255; i++) {
    EXP[i] = x;
    LOG[x] = i;
    x <<= 1;
    if (x & 0x100) x ^= 0x11d;
  }
  for (let i = 255; i < 512; i++) EXP[i] = EXP[i - 255];
})();

const gfMul = (a: number, b: number) => (a === 0 || b === 0 ? 0 : EXP[LOG[a] + LOG[b]]);

function generator(degree: number): number[] {
  let poly = [1];
  for (let i = 0; i < degree; i++) {
    const next = new Array<number>(poly.length + 1).fill(0);
    for (let j = 0; j < poly.length; j++) {
      next[j] ^= poly[j];
      next[j + 1] ^= gfMul(poly[j], EXP[i]);
    }
    poly = next;
  }
  return poly;
}

function reedSolomon(data: number[], degree: number): number[] {
  const gen = generator(degree);
  const rem = new Array<number>(degree).fill(0);
  for (const byte of data) {
    const factor = byte ^ rem[0];
    rem.shift();
    rem.push(0);
    for (let i = 0; i < degree; i++) rem[i] ^= gfMul(gen[i + 1], factor);
  }
  return rem;
}

// ---------------------------------------------------------------- encoding

function utf8(text: string): number[] {
  return Array.from(new TextEncoder().encode(text));
}

function codewords(bytes: number[], version: number): number[] {
  const [, , g1, d1, g2, d2] = LEVEL_M[version - 1];
  const dataCapacity = g1 * d1 + g2 * d2;
  const bits: number[] = [];
  const push = (value: number, length: number) => {
    for (let i = length - 1; i >= 0; i--) bits.push((value >>> i) & 1);
  };

  push(0b0100, 4); // byte mode
  push(bytes.length, version < 10 ? 8 : 16);
  bytes.forEach((b) => push(b, 8));
  push(0, Math.min(4, dataCapacity * 8 - bits.length)); // terminator
  while (bits.length % 8) bits.push(0);
  const out: number[] = [];
  for (let i = 0; i < bits.length; i += 8) out.push(parseInt(bits.slice(i, i + 8).join(''), 2));
  for (let pad = 0; out.length < dataCapacity; pad++) out.push(pad % 2 === 0 ? 0xec : 0x11);
  return out;
}

function interleave(data: number[], version: number): number[] {
  const [, ec, g1, d1, g2, d2] = LEVEL_M[version - 1];
  const blocks: number[][] = [];
  let at = 0;
  for (let i = 0; i < g1; i++) { blocks.push(data.slice(at, at + d1)); at += d1; }
  for (let i = 0; i < g2; i++) { blocks.push(data.slice(at, at + d2)); at += d2; }
  const ecBlocks = blocks.map((b) => reedSolomon(b, ec));

  const out: number[] = [];
  const longest = Math.max(d1, d2);
  for (let i = 0; i < longest; i++) blocks.forEach((b) => { if (i < b.length) out.push(b[i]); });
  for (let i = 0; i < ec; i++) ecBlocks.forEach((b) => out.push(b[i]));
  return out;
}

// ---------------------------------------------------------------- matrix

type Grid = (boolean | null)[][];

function bch(value: number, poly: number, polyBits: number): number {
  let v = value << (polyBits - 1);
  for (let i = 31 - Math.clz32(v); i >= polyBits - 1; i = 31 - Math.clz32(v)) {
    v ^= poly << (i - (polyBits - 1));
    if (v === 0) break;
  }
  return v;
}

function baseGrid(version: number): { grid: Grid; reserved: boolean[][] } {
  const size = version * 4 + 17;
  const grid: Grid = Array.from({ length: size }, () => new Array(size).fill(null));
  const reserved = Array.from({ length: size }, () => new Array(size).fill(false));
  const set = (r: number, c: number, dark: boolean) => {
    if (r < 0 || c < 0 || r >= size || c >= size) return;
    grid[r][c] = dark;
    reserved[r][c] = true;
  };

  // finders + separators
  for (const [fr, fc] of [[0, 0], [0, size - 7], [size - 7, 0]]) {
    for (let r = -1; r <= 7; r++) {
      for (let c = -1; c <= 7; c++) {
        const ring = Math.max(Math.abs(r - 3), Math.abs(c - 3));
        set(fr + r, fc + c, ring !== 2 && ring !== 4);
      }
    }
  }
  // timing
  for (let i = 8; i < size - 8; i++) {
    set(6, i, i % 2 === 0);
    set(i, 6, i % 2 === 0);
  }
  // alignment
  const pos = ALIGNMENT[version - 1];
  const last = pos[pos.length - 1];
  for (const r of pos) {
    for (const c of pos) {
      // Only the three corners sit on a finder; the others may cross timing.
      if ((r === 6 && c === 6) || (r === 6 && c === last) || (r === last && c === 6)) continue;
      for (let dr = -2; dr <= 2; dr++) {
        for (let dc = -2; dc <= 2; dc++) set(r + dr, c + dc, Math.max(Math.abs(dr), Math.abs(dc)) !== 1);
      }
    }
  }
  // dark module + format/version areas (filled later)
  set(size - 8, 8, true);
  for (let i = 0; i < 9; i++) {
    if (!reserved[8][i]) reserved[8][i] = true;
    if (!reserved[i][8]) reserved[i][8] = true;
  }
  for (let i = 0; i < 8; i++) {
    reserved[8][size - 1 - i] = true;
    reserved[size - 1 - i][8] = true;
  }
  if (version >= 7) {
    for (let i = 0; i < 6; i++) {
      for (let j = 0; j < 3; j++) {
        reserved[i][size - 11 + j] = true;
        reserved[size - 11 + j][i] = true;
      }
    }
  }
  return { grid, reserved };
}

function placeData(grid: Grid, reserved: boolean[][], data: number[]): void {
  const size = grid.length;
  let bit = 0;
  const total = data.length * 8;
  for (let right = size - 1; right >= 1; right -= 2) {
    if (right === 6) right = 5;
    const upward = ((right + 1) & 2) === 0;
    for (let i = 0; i < size; i++) {
      const row = upward ? size - 1 - i : i;
      for (let k = 0; k < 2; k++) {
        const col = right - k;
        if (reserved[row][col]) continue;
        const dark = bit < total ? ((data[bit >>> 3] >>> (7 - (bit & 7))) & 1) === 1 : false;
        grid[row][col] = dark;
        bit++;
      }
    }
  }
}

const MASKS: ((r: number, c: number) => boolean)[] = [
  (r, c) => (r + c) % 2 === 0,
  (r) => r % 2 === 0,
  (_r, c) => c % 3 === 0,
  (r, c) => (r + c) % 3 === 0,
  (r, c) => (Math.floor(r / 2) + Math.floor(c / 3)) % 2 === 0,
  (r, c) => ((r * c) % 2) + ((r * c) % 3) === 0,
  (r, c) => (((r * c) % 2) + ((r * c) % 3)) % 2 === 0,
  (r, c) => (((r + c) % 2) + ((r * c) % 3)) % 2 === 0,
];

function applyFormat(grid: boolean[][], version: number, mask: number): void {
  const size = grid.length;
  const data = (0b00 << 3) | mask; // level M = 00
  const format = ((data << 10) | bch(data, 0x537, 11)) ^ 0x5412;
  const bitAt = (i: number) => ((format >>> i) & 1) === 1;

  // First copy, around the top-left finder.
  for (let i = 0; i <= 5; i++) grid[i][8] = bitAt(i);
  grid[7][8] = bitAt(6);
  grid[8][8] = bitAt(7);
  grid[8][7] = bitAt(8);
  for (let i = 9; i < 15; i++) grid[8][14 - i] = bitAt(i);
  // Second copy, split between the other two finders.
  for (let i = 0; i < 8; i++) grid[8][size - 1 - i] = bitAt(i);
  for (let i = 8; i < 15; i++) grid[size - 15 + i][8] = bitAt(i);
  grid[size - 8][8] = true;

  if (version >= 7) {
    const info = (version << 12) | bch(version, 0x1f25, 13);
    for (let i = 0; i < 18; i++) {
      const dark = ((info >>> i) & 1) === 1;
      const a = Math.floor(i / 3);
      const b = (i % 3) + size - 11;
      grid[a][b] = dark;
      grid[b][a] = dark;
    }
  }
}

function penalty(g: boolean[][]): number {
  const n = g.length;
  let score = 0;
  const line = (get: (i: number, j: number) => boolean) => {
    for (let i = 0; i < n; i++) {
      let run = 1;
      for (let j = 1; j < n; j++) {
        if (get(i, j) === get(i, j - 1)) run++;
        else { if (run >= 5) score += run - 2; run = 1; }
      }
      if (run >= 5) score += run - 2;
      for (let j = 0; j + 10 < n; j++) {
        const seq = Array.from({ length: 11 }, (_, k) => (get(i, j + k) ? 1 : 0)).join('');
        if (seq === '10111010000' || seq === '00001011101') score += 40;
      }
    }
  };
  line((i, j) => g[i][j]);
  line((i, j) => g[j][i]);
  let dark = 0;
  for (let r = 0; r < n; r++) {
    for (let c = 0; c < n; c++) {
      if (g[r][c]) dark++;
      if (r < n - 1 && c < n - 1 && g[r][c] === g[r + 1][c] && g[r][c] === g[r][c + 1] && g[r][c] === g[r + 1][c + 1]) score += 3;
    }
  }
  score += Math.floor(Math.abs((dark * 100) / (n * n) - 50) / 5) * 10;
  return score;
}

/** The QR modules for [text], or null if it is too long for version 10-M. */
export function qrMatrix(text: string): boolean[][] | null {
  const bytes = utf8(text);
  const version = LEVEL_M.findIndex(([, , g1, d1, g2, d2], i) => {
    const capacityBits = (g1 * d1 + g2 * d2) * 8;
    return 4 + (i + 1 < 10 ? 8 : 16) + bytes.length * 8 <= capacityBits;
  }) + 1;
  if (version === 0) return null;

  const all = interleave(codewords(bytes, version), version);
  const { grid, reserved } = baseGrid(version);
  placeData(grid, reserved, all);

  let best: boolean[][] | null = null;
  let bestScore = Infinity;
  MASKS.forEach((mask, m) => {
    const g = grid.map((row, r) => row.map((cell, c) => {
      const v = Boolean(cell);
      return reserved[r][c] ? v : v !== mask(r, c);
    }));
    applyFormat(g, version, m);
    const s = penalty(g);
    if (s < bestScore) { bestScore = s; best = g; }
  });
  return best;
}
