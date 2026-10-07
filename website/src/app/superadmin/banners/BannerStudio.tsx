'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import styles from './banners.module.css';
import ImageCropper, { type CropSource } from '@/components/admin/ImageCropper';

/**
 * Banner artwork, framed the way the customer app frames it.
 *
 * A banner is the one place in the app where the image is cropped to fit
 * something rather than fitted inside it: `BannerCarousel` puts every banner
 * in a 160px-tall box and hands it `BoxFit.cover`, so whatever falls outside
 * that box is simply gone. The box is not a fixed shape either — it is as wide
 * as the phone minus the page's 20px padding and the card's own 1px margins,
 * which is 333px on a small phone and 388px on a large one. Two consequences
 * follow, and they are what this panel exists to make visible:
 *
 *  - the frame is not square, so a square crop is the wrong tool here, and
 *  - there is no single crop that is lossless on every phone, so there has to
 *    be a safe area and a way to see what each device actually shows.
 *
 * The preview is therefore a reproduction, not a thumbnail: the real height,
 * the real 26px corner radius, the real `cover`, the real bottom gradient and
 * the real title treatment, switchable between the phone widths people
 * actually own. A banner judged as a 200px-tall strip in a form tells you
 * nothing about whether the offer text survives.
 *
 * Cropping stays optional. The picked file is already the finished image
 * before any of this appears, exactly as it was before this panel existed.
 *
 * An animated banner (GIF or WebP) is the exception to the cropping: any
 * resample flattens the animation to its first frame, so an animated pick is
 * validated to fit the frame as-is and the crop controls step aside for it.
 */

/** What the artwork does: sits still, or moves. Mirrors the backend column. */
export type MediaKind = 'image' | 'animated';

/** File types the picker and drop zone will accept, and nothing else. */
export const ACCEPTED_IMAGE_TYPES = 'image/jpeg,image/png,image/gif,image/webp';

const STATIC_MIME = ['image/jpeg', 'image/png'];
const ANIMATED_MIME = ['image/gif', 'image/webp'];
const STATIC_EXTENSIONS = ['jpg', 'jpeg', 'png'];
const ANIMATED_EXTENSIONS = ['gif', 'webp'];

/** Animated banners are uploaded as-is, so they carry the tighter budget. */
const ANIMATED_MAX_BYTES = 2 * 1024 * 1024;
const STATIC_MAX_BYTES = 5 * 1024 * 1024;

/** The banner frame's own proportions — animated art must fit inside them. */
const FRAME_WIDTH = 1600;
const FRAME_HEIGHT = 736;
const FRAME_PIXELS = FRAME_WIDTH * FRAME_HEIGHT;

/** Static sources beyond either of these are shrunk before they are worth a pick. */
const STATIC_MAX_SIDE = 4000;
const STATIC_MAX_PIXELS = 24_000_000;

/**
 * What kind of file this is, from the MIME type with an extension fallback
 * for pickers that leave the type blank. Returns null for anything that is
 * not one of the four accepted banner formats.
 */
export function detectMediaKind(file: File): MediaKind | null {
  const type = (file.type || '').toLowerCase();

  if (STATIC_MIME.includes(type)) return 'image';
  if (ANIMATED_MIME.includes(type)) return 'animated';
  if (type) return null;

  const extension = file.name.includes('.') ? file.name.split('.').pop()!.toLowerCase() : '';
  if (STATIC_EXTENSIONS.includes(extension)) return 'image';
  if (ANIMATED_EXTENSIONS.includes(extension)) return 'animated';
  return null;
}

/**
 * The kind a saved URL implies, or null when the extension says nothing
 * useful — Cloudinary transform URLs carry no extension, and those are left
 * to the stored column.
 */
export function mediaKindFromUrl(url: string | null | undefined): MediaKind | null {
  if (!url) return null;

  let path: string;
  try {
    path = new URL(url).pathname;
  } catch {
    return null;
  }

  const last = path.split('/').pop() || '';
  if (!last.includes('.')) return null;

  const extension = last.split('.').pop()!.toLowerCase();
  if (STATIC_EXTENSIONS.includes(extension)) return 'image';
  if (ANIMATED_EXTENSIONS.includes(extension)) return 'animated';
  return null;
}

function megabytes(bytes: number) {
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

/**
 * Size and dimension rules for a pick, checked before anything is accepted.
 * Animated files are held to the frame itself because nothing downstream can
 * shrink them; static ones only face a ceiling, since the cropper does the
 * fitting afterwards.
 */
async function mediaProblem(file: File, kind: MediaKind): Promise<string | null> {
  if (kind === 'animated') {
    if (file.size > ANIMATED_MAX_BYTES) {
      return `Animated banners must be 2 MB or smaller — this one is ${megabytes(
        file.size,
      )}. Aim for 1.5 MB: fewer frames or a smaller loop compresses better.`;
    }
  } else if (file.size > STATIC_MAX_BYTES) {
    return `Images must be 5 MB or smaller — this one is ${megabytes(file.size)}.`;
  }

  let image: HTMLImageElement;
  try {
    image = await loadImage(file);
  } catch {
    return 'That file could not be read as an image.';
  }

  const width = image.naturalWidth;
  const height = image.naturalHeight;

  if (kind === 'animated') {
    if (width > FRAME_WIDTH || height > FRAME_HEIGHT || width * height > FRAME_PIXELS) {
      return `Animated banners must fit inside ${FRAME_WIDTH}×${FRAME_HEIGHT} px — this one is ${width}×${height}. Cropping is skipped so the animation survives, so the file has to arrive at the right size.`;
    }
    if (width < MIN_WIDTH) {
      return `Animated banners cannot be cropped, so they need to be at least ${MIN_WIDTH} px wide — this one is ${width} px and would be scaled up until it showed.`;
    }
    return null;
  }

  if ((width > STATIC_MAX_SIDE && height > STATIC_MAX_SIDE) || width * height > STATIC_MAX_PIXELS) {
    return `That image is ${width}×${height} (${(
      (width * height) /
      1_000_000
    ).toFixed(1)} megapixels), which is more than this form will take — 24 megapixels and 4000 px a side are the limits. Export it smaller and pick it again.`;
  }

  return null;
}

/** The card is 160 logical pixels tall, whatever the device. */
const BANNER_HEIGHT = 160;

/** `EdgeInsets.symmetric(horizontal: 20)` around the carousel on the home tab. */
const PAGE_PADDING = 20;

/** The card's own `margin: EdgeInsets.symmetric(horizontal: 1)`. */
const CARD_MARGIN = 1;

/** The colour behind a banner while — or instead of — its image loading. */
const PLACEHOLDER = '#F3EBFE';

/** Real logical widths, so the preview is not a guess at "a phone". */
const DEVICES = [
  { name: 'SE / 8', width: 375 },
  { name: '11–15', width: 390 },
  { name: 'Pixel 7', width: 412 },
  { name: 'Pro Max', width: 430 },
];

/** The width one card gets: the screen, less the page padding and its margins. */
function cardWidth(screenWidth: number) {
  return screenWidth - PAGE_PADDING * 2 - CARD_MARGIN * 2;
}

/**
 * The frame the crop is made to: the most common phone, which is also the
 * middle of the range, so anything kept inside the guide survives the rest.
 */
const RATIO = cardWidth(390) / BANNER_HEIGHT;

/** The narrowest card, and so the region every other phone still shows. */
const GUIDE_RATIO = cardWidth(375) / BANNER_HEIGHT;

/** Below this the app has to scale the banner up, and it shows. */
const MIN_WIDTH = 800;

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
 * The banner exactly as the app draws it.
 *
 * The gradient and the title are not decoration added for the preview — they
 * are in the app, and they change what artwork works. The gradient darkens
 * only the bottom fifth, which is nowhere near the title, so a pale title on a
 * pale photo is the failure this makes visible.
 */
function AppPreview({
  imageUrl,
  title,
  screenWidth,
  mediaKind,
}: {
  imageUrl: string;
  title: string;
  screenWidth: number;
  mediaKind: MediaKind;
}) {
  const [broken, setBroken] = useState<string | null>(null);
  const shows = Boolean(imageUrl) && broken !== imageUrl;
  const width = cardWidth(screenWidth);

  return (
    <div className={styles.appPreview}>
      <div className={styles.appPreviewScreen} style={{ width }}>
        <div className={styles.appCard} style={{ height: BANNER_HEIGHT, background: PLACEHOLDER }}>
          {shows && (
            <img
              src={imageUrl}
              alt=""
              className={styles.appCardImage}
              onError={() => setBroken(imageUrl)}
            />
          )}
          <div className={styles.appCardScrim} />
          <span className={styles.appCardTitle}>{title.trim() || 'Banner title'}</span>
          {mediaKind === 'animated' && (
            <span className={`${styles.animatedBadge} ${styles.appCardBadge}`}>ANIMATED</span>
          )}
        </div>
      </div>

      <div className={styles.appPreviewMeta}>
        <span className={styles.appPreviewSize}>
          {width}×{BANNER_HEIGHT} · radius 26 · cover
        </span>
        <span className={styles.appPreviewNote}>
          Banners slide left to right, one at a time, so each one is seen alone and small.
        </span>
      </div>
    </div>
  );
}

export default function BannerStudio({
  file,
  previewUrl,
  savedUrl,
  title,
  mediaKind,
  onFile,
  onPreview,
  onMediaKind,
}: {
  /** The pending upload, already cropped if the operator chose to crop it. */
  file: File | null;
  /** What to show: an object URL for a pending file, or the saved image. */
  previewUrl: string | null;
  /** The image already on the record, so a pick can be undone. */
  savedUrl: string | null;
  /** Live, because the app paints the title over the image. */
  title: string;
  /** Owned by the page: it is what gets posted as `media_kind`. */
  mediaKind: MediaKind;
  onFile: (file: File | null) => void;
  onPreview: (url: string | null) => void;
  onMediaKind: (kind: MediaKind) => void;
}) {
  const [device, setDevice] = useState(DEVICES[1]);
  const [cropSource, setCropSource] = useState<CropSource | null>(null);
  const [original, setOriginal] = useState<File | null>(null);
  const [cropNote, setCropNote] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [dragging, setDragging] = useState(false);
  const [busy, setBusy] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);
  const objectUrl = useRef<string | null>(null);

  // Object URLs are not garbage collected on their own, and this one is replaced
  // on every pick, so the previous one is released rather than leaked.
  useEffect(
    () => () => {
      if (objectUrl.current) URL.revokeObjectURL(objectUrl.current);
    },
    [],
  );

  const take = useCallback(
    async (picked: File) => {
      const kind = detectMediaKind(picked);

      if (!kind) {
        setError('Banners must be a JPG, PNG, GIF or WebP image.');
        return;
      }

      const problem = await mediaProblem(picked, kind);
      if (problem) {
        setError(problem);
        return;
      }

      if (objectUrl.current) URL.revokeObjectURL(objectUrl.current);

      const url = URL.createObjectURL(picked);
      objectUrl.current = url;

      setOriginal(picked);
      setCropNote(null);
      setError(null);

      onFile(picked);
      onPreview(url);
      onMediaKind(kind);
    },
    [onFile, onPreview, onMediaKind],
  );

  const applyCrop = useCallback(
    (cropped: File, detail: string) => {
      if (objectUrl.current) URL.revokeObjectURL(objectUrl.current);

      const url = URL.createObjectURL(cropped);
      objectUrl.current = url;

      setCropSource(null);
      setCropNote(detail);

      onFile(cropped);
      onPreview(url);
      // The cropper only ever emits a flattened JPEG, whatever went in.
      onMediaKind('image');
    },
    [onFile, onPreview, onMediaKind],
  );

  /**
   * Crop something already chosen. Prefers the file in hand, and otherwise
   * reaches for the image already on the record, so tidying up an existing
   * banner does not mean going and re-downloading it.
   *
   * An animated banner never gets here: cropping resamples the frames away.
   */
  const adjust = useCallback(async () => {
    setError(null);

    if (mediaKind === 'animated') {
      setError(
        'Cropping would freeze an animated banner on its first frame, so it is turned off here. The file itself must fit the frame.',
      );
      return;
    }

    if (original) {
      const image = await loadImage(original);
      setCropSource({ file: original, image, label: 'your last pick' });
      return;
    }

    if (!savedUrl) return;

    setBusy(true);

    try {
      const response = await fetch(savedUrl);

      if (!response.ok) throw new Error('unreachable');

      const blob = await response.blob();
      const fetched = new File([blob], 'banner', { type: blob.type || 'image/jpeg' });

      setCropSource({
        file: fetched,
        image: await loadImage(fetched),
        label: 'the saved banner',
      });
    } catch {
      setError(
        'The saved banner could not be read back from Cloudinary, so it cannot be cropped here. ' +
          'Choose the file again and it will be.',
      );
    } finally {
      setBusy(false);
    }
  }, [original, savedUrl, mediaKind]);

  const revert = useCallback(() => {
    if (!original) return;

    if (objectUrl.current) URL.revokeObjectURL(objectUrl.current);

    const url = URL.createObjectURL(original);
    objectUrl.current = url;

    setCropNote(null);
    onFile(original);
    onPreview(url);
    // The crop is undone, so the file — and with it the media kind — is the
    // original pick again.
    onMediaKind(detectMediaKind(original) ?? 'image');
  }, [original, onFile, onPreview, onMediaKind]);

  const discard = useCallback(() => {
    if (objectUrl.current) {
      URL.revokeObjectURL(objectUrl.current);
      objectUrl.current = null;
    }

    setOriginal(null);
    setCropNote(null);
    setError(null);
    onFile(null);
    onPreview(savedUrl);
    onMediaKind(mediaKindFromUrl(savedUrl) ?? 'image');
  }, [onFile, onPreview, onMediaKind, savedUrl]);

  const showsImage = Boolean(previewUrl);

  return (
    <div className={styles.studio}>
      {showsImage ? (
        <>
          <div className={styles.studioToolbar}>
            <span className={styles.studioFilename} title={file?.name || savedUrl || ''}>
              {cropNote ? `Cropped — ${cropNote}` : file?.name || 'Saved banner'}
            </span>

            <span
              className={`${styles.mediaKind} ${
                mediaKind === 'animated' ? styles.mediaKindAnimated : ''
              }`}
            >
              {mediaKind === 'animated' ? 'Animated image' : 'Static image'}
            </span>

            <div className={styles.studioButtons}>
              {mediaKind !== 'animated' && (
                <button
                  type="button"
                  className={styles.studioSecondaryBtn}
                  onClick={adjust}
                  disabled={busy}
                >
                  Crop &amp; adjust
                </button>
              )}

              {original && (
                <>
                  <button
                    type="button"
                    className={styles.studioGhostBtn}
                    onClick={revert}
                    disabled={busy}
                  >
                    Undo crop
                  </button>
                  <button
                    type="button"
                    className={styles.studioGhostBtn}
                    onClick={discard}
                    disabled={busy}
                  >
                    {savedUrl ? 'Keep saved' : 'Remove'}
                  </button>
                </>
              )}

              <button
                type="button"
                className={styles.studioGhostBtn}
                onClick={() => inputRef.current?.click()}
                disabled={busy}
              >
                Replace
              </button>
            </div>
          </div>

          <div className={styles.studioDevices}>
            <span className={styles.studioDevicesLabel}>Preview on</span>
            {DEVICES.map((option) => (
              <button
                key={option.name}
                type="button"
                className={`${styles.studioDeviceBtn} ${
                  option.name === device.name ? styles.studioDeviceBtnActive : ''
                }`}
                onClick={() => setDevice(option)}
              >
                {option.name}
                <span className={styles.studioDeviceWidth}>{option.width}px</span>
              </button>
            ))}
          </div>

          <AppPreview
            imageUrl={previewUrl!}
            title={title}
            screenWidth={device.width}
            mediaKind={mediaKind}
          />
        </>
      ) : (
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
            const dropped = e.dataTransfer.files?.[0];
            if (dropped) void take(dropped);
          }}
          onClick={() => inputRef.current?.click()}
          role="button"
          tabIndex={0}
          onKeyDown={(e) => {
            if (e.key === 'Enter' || e.key === ' ') inputRef.current?.click();
          }}
        >
          <span className={styles.dropTitle}>
            {busy ? 'Preparing…' : 'Drop a banner image, or click to choose'}
          </span>
          <span className={styles.dropHint}>
            Wide image, no text in the corners — the app crops it to {Math.round(
              RATIO * 100,
            )}
            :100. JPG or PNG up to 5 MB; a GIF or WebP loop up to 2 MB.
          </span>
        </div>
      )}

      <input
        ref={inputRef}
        type="file"
        accept={ACCEPTED_IMAGE_TYPES}
        className={styles.hiddenInput}
        onChange={(e) => {
          const picked = e.target.files?.[0];
          e.target.value = '';
          if (picked) void take(picked);
        }}
      />

      {error && <p className={styles.studioError}>{error}</p>}

      {cropSource && (
        <ImageCropper
          source={cropSource}
          ratio={RATIO}
          guideRatio={GUIDE_RATIO}
          frameWidth={440}
          minOutput={MIN_WIDTH}
          outputType="image/jpeg"
          outputQuality={0.92}
          flatten="white"
          title="Crop the banner"
          help="The frame matches the size the app gives a banner. Drag to reposition, scroll or use the slider to zoom."
          hint="The dashed line is the part that still shows on a small phone. Keep the offer and any text inside it; wider phones simply reveal more."
          onApply={applyCrop}
          onCancel={() => setCropSource(null)}
        />
      )}
    </div>
  );
}
