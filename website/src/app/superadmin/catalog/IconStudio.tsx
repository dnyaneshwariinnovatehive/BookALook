'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import styles from './page.module.css';

/**
 * Category icons, made consistent before they are uploaded.
 *
 * Every icon in the customer app sits in the same square tile, so the only way
 * they look like a set is if they arrive the same size, with the same margins,
 * in the same style. Left to hand-uploaded files they never do: one is 900×740
 * with its own built-in padding, the next is a tight 64×64 crop, and the grid
 * ends up looking broken.
 *
 * Two halves solve that. A prompt that tells an image generator exactly what to
 * draw, so the *style* matches, and a canvas pass that trims and re-centres
 * whatever comes back, so the *geometry* matches. The server cannot do the
 * second part — this deployment has neither GD nor Imagick — and the browser
 * can, instantly, with the file already in hand.
 */

/** Every icon is delivered at this size. */
const CANVAS = 512;

/** Share of the tile the artwork fills, leaving an even margin all round. */
const CONTENT = 0.74;

/** Alpha below this counts as empty space when trimming. */
const EMPTY = 12;

export interface NormalisedIcon {
  file: File;
  previewUrl: string;
  /** What the pass actually did, shown so nothing happens invisibly. */
  note: string;
  opaque: boolean;
}

export function buildIconPrompt(categoryName: string): string {
  const name = categoryName.trim() || 'the category';

  return [
    `A single flat vector icon representing "${name}" for a salon and spa booking app.`,
    '',
    'Style: modern flat illustration, rounded geometry, medium-weight strokes,',
    'friendly and simple. No gradients, no photorealism, no 3D.',
    'Colour: deep purple #9C54F2 as the primary, soft lavender #F3EBFE for fills.',
    'Use at most three colours in total.',
    'Composition: one centred subject only. No text, no letters, no numbers,',
    'no background, no container, no circle or square frame, no drop shadow.',
    'Canvas: perfectly square, 1:1, fully transparent background, PNG with alpha.',
    'Margins: keep the subject inside the middle 74% of the canvas.',
    'Detail: readable at 48 pixels — avoid thin lines and small details.',
  ].join('\n');
}

function loadImage(file: File): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const image = new Image();

    image.onload = () => {
      URL.revokeObjectURL(url);
      resolve(image);
    };
    image.onerror = () => {
      URL.revokeObjectURL(url);
      reject(new Error('That file could not be read as an image.'));
    };
    image.src = url;
  });
}

/**
 * The box the artwork actually occupies, ignoring transparent margins.
 *
 * This is what lets a tightly cropped icon and a generously padded one end up
 * the same visual size in the grid: both are measured by their content rather
 * than by their file.
 */
function contentBounds(ctx: CanvasRenderingContext2D, width: number, height: number) {
  const { data } = ctx.getImageData(0, 0, width, height);

  let minX = width;
  let minY = height;
  let maxX = -1;
  let maxY = -1;
  let transparentPixels = 0;

  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const alpha = data[(y * width + x) * 4 + 3];

      if (alpha < 250) transparentPixels++;

      if (alpha > EMPTY) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }

  // Nothing but empty pixels.
  if (maxX < 0) return null;

  return {
    x: minX,
    y: minY,
    width: maxX - minX + 1,
    height: maxY - minY + 1,
    // A photo or a JPEG: no transparency to trim against, so the whole frame
    // is treated as the subject and the operator is warned.
    opaque: transparentPixels === 0,
  };
}

export async function normaliseIcon(file: File): Promise<NormalisedIcon> {
  const image = await loadImage(file);

  // An SVG without width/height attributes reports zero; fall back to the
  // target size rather than dividing by it.
  const sourceWidth = image.naturalWidth || CANVAS;
  const sourceHeight = image.naturalHeight || CANVAS;

  const source = document.createElement('canvas');
  source.width = sourceWidth;
  source.height = sourceHeight;

  const sourceCtx = source.getContext('2d', { willReadFrequently: true });
  if (!sourceCtx) throw new Error('This browser cannot process images.');

  sourceCtx.drawImage(image, 0, 0, sourceWidth, sourceHeight);

  const bounds =
    contentBounds(sourceCtx, sourceWidth, sourceHeight) ?? {
      x: 0,
      y: 0,
      width: sourceWidth,
      height: sourceHeight,
      opaque: true,
    };

  const target = document.createElement('canvas');
  target.width = CANVAS;
  target.height = CANVAS;

  const ctx = target.getContext('2d');
  if (!ctx) throw new Error('This browser cannot process images.');

  ctx.clearRect(0, 0, CANVAS, CANVAS);
  ctx.imageSmoothingEnabled = true;
  ctx.imageSmoothingQuality = 'high';

  const box = CANVAS * CONTENT;
  const scale = Math.min(box / bounds.width, box / bounds.height);
  const drawWidth = bounds.width * scale;
  const drawHeight = bounds.height * scale;

  ctx.drawImage(
    source,
    bounds.x,
    bounds.y,
    bounds.width,
    bounds.height,
    (CANVAS - drawWidth) / 2,
    (CANVAS - drawHeight) / 2,
    drawWidth,
    drawHeight,
  );

  const blob = await new Promise<Blob | null>((resolve) =>
    target.toBlob(resolve, 'image/png'),
  );

  if (!blob) throw new Error('Could not produce a PNG from that image.');

  const trimmed = bounds.width !== sourceWidth || bounds.height !== sourceHeight;

  return {
    file: new File([blob], 'category-icon.png', { type: 'image/png' }),
    previewUrl: target.toDataURL('image/png'),
    opaque: bounds.opaque,
    note: `${sourceWidth}×${sourceHeight} → ${CANVAS}×${CANVAS}` +
      (trimmed ? ', empty margins trimmed' : '') +
      ', centred with even padding.',
  };
}

export default function IconStudio({
  categoryName,
  existingUrl,
  onIcon,
}: {
  categoryName: string;
  existingUrl: string;
  onIcon: (icon: NormalisedIcon | null) => void;
}) {
  const [icon, setIcon] = useState<NormalisedIcon | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const [dragging, setDragging] = useState(false);
  const [busy, setBusy] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  const prompt = useMemo(() => buildIconPrompt(categoryName), [categoryName]);

  useEffect(() => {
    if (!copied) return;
    const timer = setTimeout(() => setCopied(false), 2000);
    return () => clearTimeout(timer);
  }, [copied]);

  const take = useCallback(
    async (file: File) => {
      setError(null);
      setBusy(true);

      try {
        const normalised = await normaliseIcon(file);
        setIcon(normalised);
        onIcon(normalised);
      } catch (e) {
        setIcon(null);
        onIcon(null);
        setError(e instanceof Error ? e.message : 'Could not read that image.');
      } finally {
        setBusy(false);
      }
    },
    [onIcon],
  );

  const copyPrompt = async () => {
    try {
      await navigator.clipboard.writeText(prompt);
      setCopied(true);
    } catch {
      setError('Could not reach the clipboard — select the prompt and copy it by hand.');
    }
  };

  const shown = icon?.previewUrl || existingUrl;

  return (
    <div className={styles.studio}>
      <div className={styles.studioStep}>
        <span className={styles.studioStepNumber}>1</span>
        <div className={styles.studioStepBody}>
          <p className={styles.studioStepTitle}>Generate an icon</p>
          <p className={styles.studioStepHelp}>
            Paste this into ChatGPT, Gemini, Midjourney or any image generator. It fixes the
            style, colours and margins so every category matches.
          </p>

          <div className={styles.promptBox}>
            <pre className={styles.promptText}>{prompt}</pre>
            <button type="button" className={styles.copyBtn} onClick={copyPrompt}>
              {copied ? 'Copied' : 'Copy prompt'}
            </button>
          </div>
        </div>
      </div>

      <div className={styles.studioStep}>
        <span className={styles.studioStepNumber}>2</span>
        <div className={styles.studioStepBody}>
          <p className={styles.studioStepTitle}>Drop it here</p>
          <p className={styles.studioStepHelp}>
            Whatever the size, it is trimmed, centred and saved at {CANVAS}×{CANVAS} so it lines
            up with every other category.
          </p>

          <div className={styles.studioRow}>
            <div
              className={`${styles.dropZone} ${dragging ? styles.dropZoneActive : ''}`}
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
              onClick={() => inputRef.current?.click()}
              role="button"
              tabIndex={0}
              onKeyDown={(e) => {
                if (e.key === 'Enter' || e.key === ' ') inputRef.current?.click();
              }}
            >
              <input
                ref={inputRef}
                type="file"
                accept="image/png,image/svg+xml,image/webp,image/jpeg"
                className={styles.hiddenInput}
                onChange={(e) => {
                  const file = e.target.files?.[0];
                  e.target.value = '';
                  if (file) take(file);
                }}
              />
              <span className={styles.dropTitle}>
                {busy ? 'Preparing…' : 'Drop a PNG, or click to choose'}
              </span>
              <span className={styles.dropHint}>Transparent background works best</span>
            </div>

            {/* The customer app's tile, at its real size, so the operator sees
                what a customer will see rather than a bare thumbnail. */}
            <div className={styles.previewColumn}>
              <div className={styles.previewTile}>
                {shown ? (
                  <img src={shown} alt="" className={styles.previewImage} />
                ) : (
                  <span className={styles.previewEmpty}>No icon</span>
                )}
              </div>
              <span className={styles.previewLabel}>{categoryName || 'Category'}</span>
              <span className={styles.previewCaption}>As customers see it</span>
            </div>
          </div>

          {icon && (
            <p className={styles.studioNote}>
              {icon.note}
              {icon.opaque && (
                <>
                  {' '}
                  <strong>This image has no transparent background</strong>, so it will show as a
                  solid square in the tile. A transparent PNG looks much better here.
                </>
              )}
            </p>
          )}

          {error && <p className={styles.studioError}>{error}</p>}
        </div>
      </div>
    </div>
  );
}
