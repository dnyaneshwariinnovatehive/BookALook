'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
import styles from './ImageCropper.module.css';

/**
 * A crop box locked to a fixed aspect ratio, for artwork destined for a
 * surface that sizes it a particular way.
 *
 * Both places that need this are the same problem. A category icon is painted
 * into a square tile, a promo banner into a wide 160px-tall box, and in both
 * cases the surface crops whatever it is given to fit. Deciding what survives
 * that crop is the only decision the operator actually makes, so the frame here
 * is the surface's own ratio and cannot be dragged out of shape: what you
 * leave inside the frame is exactly what the app will show.
 *
 * The crop happens here, in the browser, because the server cannot do it — the
 * deployment has neither GD nor Imagick. And it is a distinct step from
 * anything the form does afterwards on purpose: cropping chooses *what is in
 * frame*, while whatever normalising pass follows still decides the geometry
 * every other image in the same set is held to.
 *
 * The optional guide is for surfaces whose ratio moves with the device. A
 * banner is 348×160 on a 390pt phone and 318×160 on a 360pt one, so there is
 * no single crop that is lossless everywhere; the guide marks the region that
 * survives on the narrowest screen, and the rest is the overflow that wider
 * phones simply reveal.
 */

/** Zoom of 1 is the whole image just fitting inside the frame. */
const MIN_ZOOM = 1;
const MAX_ZOOM = 4;

/** Never rasterise beyond this, however enormous the source. */
const MAX_OUTPUT = 2400;

export interface CropSource {
  /** The untouched file, kept so the crop can always be redone from scratch. */
  file: File;
  image: HTMLImageElement;
  /** What is being cropped, phrased for the operator. */
  label: string;
}

/** Intrinsic size, with the same SVG guard the icon normaliser uses. */
function sourceSize(image: HTMLImageElement) {
  return {
    width: image.naturalWidth || 512,
    height: image.naturalHeight || 512,
  };
}

function clamp(value: number, min: number, max: number) {
  return Math.min(max, Math.max(min, value));
}

/**
 * Where the image sits for a given frame size and zoom.
 *
 * The image is scaled to *fit* at zoom 1 rather than cover, so a landscape or
 * portrait upload starts with the whole thing on screen and nothing is
 * silently cut off before the operator has touched anything.
 */
function geometry(
  frame: { width: number; height: number },
  zoom: number,
  image: HTMLImageElement,
) {
  const { width, height } = sourceSize(image);
  const fit = Math.min(frame.width / width, frame.height / height);
  const scale = fit * zoom;

  return { scale, drawWidth: width * scale, drawHeight: height * scale };
}

/**
 * Pan limits, so the frame can never be dragged off the artwork and leave a
 * gap. An axis the image already overfills cannot move at all.
 */
function clampOffset(
  offset: { x: number; y: number },
  frame: { width: number; height: number },
  zoom: number,
  image: HTMLImageElement,
) {
  const { drawWidth, drawHeight } = geometry(frame, zoom, image);

  return {
    x: clamp(offset.x, -Math.max(0, (drawWidth - frame.width) / 2), Math.max(0, (drawWidth - frame.width) / 2)),
    y: clamp(offset.y, -Math.max(0, (drawHeight - frame.height) / 2), Math.max(0, (drawHeight - frame.height) / 2)),
  };
}

export default function ImageCropper({
  source,
  ratio,
  guideRatio,
  frameWidth = 420,
  checkerboard = false,
  minOutput = 0,
  outputType = 'image/png',
  outputQuality,
  flatten = 'none',
  title,
  help,
  hint,
  onApply,
  onCancel,
}: {
  source: CropSource;
  /** Frame width / height. */
  ratio: number;
  /** Dashed inner guide, as its own width / height. */
  guideRatio?: number;
  /** Widest the frame is allowed to grow, in CSS pixels. */
  frameWidth?: number;
  /** Grey checkerboard behind the artwork, to show what has alpha. */
  checkerboard?: boolean;
  /** A crop smaller than this is scaled up to reach it, and flagged. */
  minOutput?: number;
  outputType?: string;
  outputQuality?: number;
  /** Painted under the crop first, so a transparent source does not go black. */
  flatten?: 'none' | 'white' | 'black';
  title: string;
  help: string;
  hint?: string;
  onApply: (file: File, detail: string) => void;
  onCancel: () => void;
}) {
  const { image, label } = source;

  const frameRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);

  const [width, setWidth] = useState(0);
  const [zoom, setZoom] = useState(MIN_ZOOM);
  const [offset, setOffset] = useState({ x: 0, y: 0 });
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const drag = useRef<{ pointer: number; x: number; y: number; ox: number; oy: number } | null>(
    null,
  );

  const { width: sourceWidth, height: sourceHeight } = sourceSize(image);

  const frame = useMemo(
    () => ({ width, height: width / ratio }),
    [width, ratio],
  );

  const offsetNow = useMemo(
    () => clampOffset(offset, frame, zoom, image),
    [offset, frame, zoom, image],
  );

  /**
   * The rectangle that will be kept, in image pixels. Shown live so the
   * operator can see they are zooming in rather than resizing the file.
   */
  const kept = useMemo(() => {
    if (!width) return { cropWidth: 0, cropHeight: 0, outWidth: 0, outHeight: 0 };

    const { scale } = geometry(frame, zoom, image);
    const cropWidth = Math.min(sourceWidth, frame.width / scale);
    const cropHeight = Math.min(sourceHeight, frame.height / scale);
    const outWidth = clamp(Math.round(cropWidth), minOutput || 1, MAX_OUTPUT);

    return {
      cropWidth,
      cropHeight,
      outWidth,
      outHeight: Math.round(outWidth / ratio),
    };
  }, [width, frame, zoom, image, sourceWidth, sourceHeight, minOutput, ratio]);

  const enlarged = kept.cropWidth > 0 && kept.cropWidth < minOutput;

  /**
   * The guide, as offsets from the frame's edges. A guide wider than the frame
   * (or taller) cannot be expressed as an inset, so the frame grows around it
   * instead — which is why the ratio passed in is compared, not assumed.
   */
  const guide = useMemo(() => {
    if (!guideRatio) return null;

    if (guideRatio <= ratio) {
      const fraction = (guideRatio / ratio) * 100;
      return {
        width: `${fraction}%`,
        height: '100%',
        left: `${(100 - fraction) / 2}%`,
        top: '0%',
      };
    }

    const fraction = (ratio / guideRatio) * 100;
    return {
      width: '100%',
      height: `${fraction}%`,
      left: '0%',
      top: `${(100 - fraction) / 2}%`,
    };
  }, [guideRatio, ratio]);

  useEffect(() => {
    const element = frameRef.current;
    if (!element) return;

    const observer = new ResizeObserver(([entry]) => {
      setWidth(clamp(entry.contentRect.width, 0, frameWidth));
    });

    observer.observe(element);
    return () => observer.disconnect();
  }, [frameWidth]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!frame.width) return;

    // Drawn on a device-pixel canvas so the artwork is not softened on a
    // high-density screen, but panning still works in plain CSS pixels.
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    canvas!.width = Math.round(frame.width * dpr);
    canvas!.height = Math.round(frame.height * dpr);

    const ctx = canvas!.getContext('2d');
    if (!ctx) return;

    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, frame.width, frame.height);

    const { drawWidth, drawHeight } = geometry(frame, zoom, image);
    const placed = clampOffset(offset, frame, zoom, image);

    ctx.imageSmoothingEnabled = true;
    ctx.imageSmoothingQuality = 'high';

    ctx.drawImage(
      image,
      (frame.width - drawWidth) / 2 + placed.x,
      (frame.height - drawHeight) / 2 + placed.y,
      drawWidth,
      drawHeight,
    );
  }, [image, frame, zoom, offset]);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') onCancel();
    };

    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [onCancel]);

  /**
   * Zoom anchored on the pointer, so the detail being inspected stays under
   * the cursor instead of sliding out from under it.
   */
  const zoomAt = (nextZoom: number, anchor?: { x: number; y: number }) => {
    const target = clamp(nextZoom, MIN_ZOOM, MAX_ZOOM);

    if (target === zoom || !frame.width || !anchor) {
      setZoom(target);
      return;
    }

    const from = geometry(frame, zoom, image);
    const to = geometry(frame, target, image);
    const current = clampOffset(offset, frame, zoom, image);

    // Where the anchor sits within the image, in image pixels.
    const at = {
      x: (anchor.x - current.x + (from.drawWidth - frame.width) / 2) / from.scale,
      y: (anchor.y - current.y + (from.drawHeight - frame.height) / 2) / from.scale,
    };

    setZoom(target);
    setOffset(
      clampOffset(
        {
          x: anchor.x - (at.x * to.scale - (to.drawWidth - frame.width) / 2),
          y: anchor.y - (at.y * to.scale - (to.drawHeight - frame.height) / 2),
        },
        frame,
        target,
        image,
      ),
    );
  };

  const onPointerDown = (event: React.PointerEvent<HTMLCanvasElement>) => {
    event.currentTarget.setPointerCapture(event.pointerId);
    drag.current = {
      pointer: event.pointerId,
      x: event.clientX,
      y: event.clientY,
      ox: offsetNow.x,
      oy: offsetNow.y,
    };
  };

  const onPointerMove = (event: React.PointerEvent<HTMLCanvasElement>) => {
    if (!drag.current || drag.current.pointer !== event.pointerId) return;

    setOffset({
      x: drag.current.ox + (event.clientX - drag.current.x),
      y: drag.current.oy + (event.clientY - drag.current.y),
    });
  };

  const endDrag = (event: React.PointerEvent<HTMLCanvasElement>) => {
    if (drag.current?.pointer === event.pointerId) drag.current = null;
  };

  const nudge = (event: React.KeyboardEvent) => {
    const step = event.shiftKey ? 24 : 8;

    const moves: Record<string, { x: number; y: number }> = {
      ArrowLeft: { x: step, y: 0 },
      ArrowRight: { x: -step, y: 0 },
      ArrowUp: { x: 0, y: step },
      ArrowDown: { x: 0, y: -step },
    };

    const move = moves[event.key];

    if (move) {
      event.preventDefault();
      setOffset({ x: offsetNow.x + move.x, y: offsetNow.y + move.y });
      return;
    }

    if (event.key === '+' || event.key === '=') {
      event.preventDefault();
      zoomAt(zoom + 0.2);
    }

    if (event.key === '-' || event.key === '_') {
      event.preventDefault();
      zoomAt(zoom - 0.2);
    }
  };

  const apply = () => {
    if (!frame.width) return;

    setBusy(true);
    setError(null);

    try {
      const { scale } = geometry(frame, zoom, image);
      const placed = clampOffset(offset, frame, zoom, image);

      // The frame, measured backwards into the image's own pixels.
      const cropWidth = Math.min(sourceWidth, frame.width / scale);
      const cropHeight = Math.min(sourceHeight, frame.height / scale);
      const centreX = sourceWidth / 2 - placed.x / scale;
      const centreY = sourceHeight / 2 - placed.y / scale;

      const sx = clamp(centreX - cropWidth / 2, 0, sourceWidth - cropWidth);
      const sy = clamp(centreY - cropHeight / 2, 0, sourceHeight - cropHeight);

      const outWidth = kept.outWidth;
      const outHeight = kept.outHeight;

      const target = document.createElement('canvas');
      target.width = outWidth;
      target.height = outHeight;

      const ctx = target.getContext('2d');
      if (!ctx) throw new Error('This browser cannot process images.');

      if (flatten !== 'none') {
        // A JPEG has no alpha, so a transparent source would otherwise go black.
        ctx.fillStyle = flatten;
        ctx.fillRect(0, 0, outWidth, outHeight);
      }

      ctx.imageSmoothingEnabled = true;
      ctx.imageSmoothingQuality = 'high';
      ctx.drawImage(image, sx, sy, cropWidth, cropHeight, 0, 0, outWidth, outHeight);

      target.toBlob(
        (blob) => {
          setBusy(false);

          if (!blob) {
            setError('Could not produce a cropped image from that file.');
            return;
          }

          const extension = outputType === 'image/jpeg' ? 'jpg' : 'png';
          const name = `banner-crop.${extension}`;

          onApply(
            new File([blob], name, { type: outputType }),
            `${outWidth}×${outHeight} crop of ${sourceWidth}×${sourceHeight}`,
          );
        },
        outputType,
        outputQuality,
      );
    } catch {
      setBusy(false);
      setError('Could not crop that image.');
    }
  };

  const reset = () => {
    setZoom(MIN_ZOOM);
    setOffset({ x: 0, y: 0 });
  };

  return (
    <div className={styles.cropOverlay} onClick={onCancel}>
      <div
        className={styles.cropPanel}
        onClick={(event) => event.stopPropagation()}
        role="dialog"
        aria-modal="true"
        aria-label={title}
      >
        <div className={styles.cropHeader}>
          <div>
            <h3 className={styles.cropTitle}>{title}</h3>
            <p className={styles.cropHelp}>{help}</p>
          </div>
          <span className={styles.cropBadge}>Cropping {label}</span>
        </div>

        <div className={styles.cropBody}>
          <div className={styles.cropStage} style={{ maxWidth: frameWidth }}>
            <div
              className={styles.cropFrame}
              ref={frameRef}
              style={{ aspectRatio: `${ratio}` }}
            >
              {/* The checkerboard is the transparency an icon is expected to
                  have, so a solid block reads immediately as "no alpha". */}
              {checkerboard && <div className={styles.cropChecker} />}
              <canvas
                ref={canvasRef}
                className={styles.cropCanvas}
                style={{ touchAction: 'none' }}
                onPointerDown={onPointerDown}
                onPointerMove={onPointerMove}
                onPointerUp={endDrag}
                onPointerCancel={endDrag}
                onWheel={(event) => {
                  event.preventDefault();
                  const rect = event.currentTarget.getBoundingClientRect();
                  zoomAt(zoom + (event.deltaY < 0 ? 0.12 : -0.12), {
                    x: event.clientX - rect.left - frame.width / 2,
                    y: event.clientY - rect.top - frame.height / 2,
                  });
                }}
                onKeyDown={nudge}
                tabIndex={0}
                role="group"
                aria-label="Crop frame — drag, or use the arrow keys, to reposition"
              />
              <div className={styles.cropThirds} />
              {guide && (
                <div
                  className={styles.cropGuide}
                  style={guide}
                  aria-hidden="true"
                />
              )}
            </div>
          </div>

          <div className={styles.cropControls}>
            <div className={styles.cropReadout}>
              <span className={styles.cropReadoutLabel}>Source</span>
              <span className={styles.cropReadoutValue}>
                {sourceWidth}×{sourceHeight}
              </span>
            </div>

            <div className={styles.cropReadout}>
              <span className={styles.cropReadoutLabel}>Uploading</span>
              <span className={styles.cropReadoutValue}>
                {kept.outWidth ? `${kept.outWidth}×${kept.outHeight}` : '—'}
              </span>
            </div>

            <label className={styles.cropSlider}>
              <span className={styles.cropReadoutLabel}>Zoom</span>
              <input
                type="range"
                min={MIN_ZOOM}
                max={MAX_ZOOM}
                step={0.01}
                value={zoom}
                onChange={(event) => zoomAt(Number(event.target.value))}
              />
              <span className={styles.cropReadoutValue}>{Math.round(zoom * 100)}%</span>
            </label>

            {(hint || enlarged) && (
              <div className={styles.cropHint}>
                {hint}
                {enlarged && (
                  <>
                    {' '}
                    <strong>
                      This is smaller than the {minOutput}px the app likes, so it is being scaled
                      up and will look soft.
                    </strong>
                  </>
                )}
              </div>
            )}

            {error && <p className={styles.cropError}>{error}</p>}

            <div className={styles.cropActions}>
              <button type="button" className={styles.cropSecondaryBtn} onClick={reset}>
                Reset
              </button>
              <button type="button" className={styles.cropSecondaryBtn} onClick={onCancel}>
                Cancel
              </button>
              <button
                type="button"
                className={styles.cropPrimaryBtn}
                onClick={apply}
                disabled={busy || !frame.width}
              >
                {busy ? 'Cropping…' : 'Use this crop'}
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
