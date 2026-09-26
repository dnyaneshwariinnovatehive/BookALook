'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import styles from './page.module.css';
import IconCropper, { type CropSource } from './IconCropper';

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
 *
 * The automatic pass only ever centres what it finds, which is right when the
 * subject is dead centre and wrong when it is not. `IconCropper` is the manual
 * half for those cases: it chooses what is in frame, and the same pass then
 * runs over the result, so cropping never costs an icon its place in the set.
 */

/** Every icon is delivered at this size. */
const CANVAS = 512;

/** Share of the tile the artwork fills, leaving an even margin all round. */
const CONTENT = 0.74;

/** Alpha below this counts as empty space when trimming. */
const EMPTY = 12;

/**
 * The tints the customer app cycles its category tiles through, in order.
 *
 * Copied from `CategoryGrid._tints` in the Flutter app. The app assigns them
 * by position rather than by category, so no single colour belongs to an icon —
 * which is why all six are shown rather than one guess.
 */
const APP_TINTS = [
  { name: 'Lavender', background: '#F3EBFE', foreground: '#9C54F2' },
  { name: 'Peach', background: '#FFF1E6', foreground: '#EF6C00' },
  { name: 'Mint', background: '#E6F6EF', foreground: '#2E7D32' },
  { name: 'Rose', background: '#FDE8EF', foreground: '#D81B60' },
  { name: 'Sky', background: '#E7F0FD', foreground: '#1565C0' },
  { name: 'Honey', background: '#FFF6DA', foreground: '#F59E0B' },
];

/** A stand-in for the glyph the app draws when an icon is missing or fails. */
const FallbackGlyph = ({ color }: { color: string }) => (
  <svg
    xmlns="http://www.w3.org/2000/svg"
    width="26"
    height="26"
    viewBox="0 0 24 24"
    fill="none"
    stroke={color}
    strokeWidth="2"
    strokeLinecap="round"
    strokeLinejoin="round"
    aria-hidden="true"
  >
    <path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />
  </svg>
);

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

function loadImage(file: File | Blob): Promise<HTMLImageElement> {
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

/**
 * The category row as the app actually paints it, reproduced rather than
 * approximated: one tile at the width a phone really gives it, the real
 * corner radius and padding, the real label weight and line height, and every
 * tint it will cycle through. Judging an icon against a bare thumbnail hides
 * exactly the things that go wrong — an off-centre subject, a subject that is
 * too small inside the tile, a label that wraps to three lines.
 */
function CustomerAppPreview({ iconUrl, name }: { iconUrl: string; name: string }) {
  // The URL that failed to load, rather than a plain flag, so replacing the
  // icon with a different one clears the failure without an effect to reset it.
  const [broken, setBroken] = useState<string | null>(null);

  const shows = Boolean(iconUrl) && broken !== iconUrl;
  const label = name.trim() || 'Category';

  return (
    <div className={styles.appPreview}>
      <div className={styles.appPreviewScreen}>
        <p className={styles.appScreenHeading}>What would you like to book?</p>

        <div className={styles.appRow}>
          <div className={styles.appTile}>
            <div className={styles.appTileArt} style={{ background: APP_TINTS[0].background }}>
              {shows ? (
                <img
                  src={iconUrl}
                  alt=""
                  className={styles.appTileImage}
                  onError={() => setBroken(iconUrl)}
                />
              ) : (
                <FallbackGlyph color={APP_TINTS[0].foreground} />
              )}
            </div>
            <span className={styles.appTileLabel}>{label}</span>
          </div>
        </div>

        <p className={styles.appScreenFootnote}>
          Four of these fit across a phone and slide slowly left to right, so the icon is seen
          small, next to a name, in a tinted square.
        </p>

        <div className={styles.appTints}>
          {APP_TINTS.map((tint) => (
            <div
              key={tint.name}
              className={styles.appTint}
              style={{ background: tint.background }}
              title={tint.name}
            >
              {shows ? (
                <img
                  src={iconUrl}
                  alt=""
                  className={styles.appTintImage}
                  onError={() => setBroken(iconUrl)}
                />
              ) : (
                <FallbackGlyph color={tint.foreground} />
              )}
            </div>
          ))}
        </div>

        <p className={styles.appPreviewNote}>
          Every category takes the tints in turn, so the icon has to hold up on all of them.
        </p>
      </div>
    </div>
  );
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
  const [cropSource, setCropSource] = useState<CropSource | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  const prompt = useMemo(() => buildIconPrompt(categoryName), [categoryName]);

  useEffect(() => {
    if (!copied) return;
    const timer = setTimeout(() => setCopied(false), 2000);
    return () => clearTimeout(timer);
  }, [copied]);

  /** Runs the geometry pass and hands the result up to the form. */
  const settle = useCallback(
    async (file: File, prefix?: string) => {
      const normalised = await normaliseIcon(file);

      const result = prefix
        ? { ...normalised, note: `${prefix}, then ${normalised.note}` }
        : normalised;

      setIcon(result);
      onIcon(result);

      return result;
    },
    [onIcon],
  );

  const take = useCallback(
    async (file: File) => {
      setError(null);
      setBusy(true);

      try {
        // Kept so the cropper can be reopened on the original, and cancelled
        // back to it, without the operator having to find the file again.
        const image = await loadImage(file);
        setCropSource({ file, image, label: 'the file you just added' });

        await settle(file);
      } catch (e) {
        setIcon(null);
        onIcon(null);
        setError(e instanceof Error ? e.message : 'Could not read that image.');
      } finally {
        setBusy(false);
      }
    },
    [onIcon, settle],
  );

  const applyCrop = useCallback(
    async (cropped: File, detail: string) => {
      setCropSource(null);
      setError(null);
      setBusy(true);

      try {
        await settle(cropped, detail);
      } catch (e) {
        setError(e instanceof Error ? e.message : 'Could not use that crop.');
      } finally {
        setBusy(false);
      }
    },
    [settle],
  );

  /**
   * Crop something already chosen. Prefers the file in hand, and otherwise
   * reaches for the icon already on the record, so an operator tidying up an
   * existing category does not have to go and re-download anything.
   */
  const adjust = useCallback(async () => {
    setError(null);

    if (cropSource) {
      setCropSource({ ...cropSource, label: 'your last pick' });
      return;
    }

    if (!existingUrl) return;

    setBusy(true);

    try {
      const response = await fetch(existingUrl);

      if (!response.ok) throw new Error('unreachable');

      const blob = await response.blob();
      const file = new File([blob], 'category-icon', {
        type: blob.type || 'image/png',
      });

      setCropSource({ file, image: await loadImage(file), label: 'the saved icon' });
    } catch {
      setError(
        'The saved icon could not be read back from the server, so it cannot be cropped here. ' +
          'Drop the file in again and it will be.',
      );
    } finally {
      setBusy(false);
    }
  }, [cropSource, existingUrl]);

  /** Drops back to the uncropped original, which is the escape hatch. */
  const undoCrop = useCallback(async () => {
    if (!cropSource) return;

    setError(null);
    setBusy(true);

    try {
      await settle(cropSource.file);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not read that image.');
    } finally {
      setBusy(false);
    }
  }, [cropSource, settle]);

  const closeCropper = useCallback(() => setCropSource(null), []);

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

          {/* Cropping is offered, never required: the file already on the form
              is a finished icon before this row appears. */}
          {shown && (
            <div className={styles.studioActions}>
              <button
                type="button"
                className={styles.studioSecondaryBtn}
                onClick={adjust}
                disabled={busy}
              >
                Crop &amp; adjust
              </button>
              {icon && cropSource && (
                <button
                  type="button"
                  className={styles.studioGhostBtn}
                  onClick={undoCrop}
                  disabled={busy}
                >
                  Undo crop
                </button>
              )}
              <span className={styles.studioActionsHint}>
                The subject sits off-centre or too small? Crop it before saving.
              </span>
            </div>
          )}

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

      <div className={styles.studioStep}>
        <span className={styles.studioStepNumber}>3</span>
        <div className={styles.studioStepBody}>
          <p className={styles.studioStepTitle}>Check it in the app</p>
          <p className={styles.studioStepHelp}>
            The same icon in the tile the customer sees, on every tint the app cycles through.
          </p>

          <CustomerAppPreview iconUrl={shown} name={categoryName} />
        </div>
      </div>

      {cropSource && (
        <IconCropper
          source={cropSource}
          onApply={applyCrop}
          onCancel={closeCropper}
        />
      )}
    </div>
  );
}
