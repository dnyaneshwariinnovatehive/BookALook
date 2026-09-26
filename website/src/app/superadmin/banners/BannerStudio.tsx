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
 */

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
}: {
  imageUrl: string;
  title: string;
  screenWidth: number;
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
  onFile,
  onPreview,
}: {
  /** The pending upload, already cropped if the operator chose to crop it. */
  file: File | null;
  /** What to show: an object URL for a pending file, or the saved image. */
  previewUrl: string | null;
  /** The image already on the record, so a pick can be undone. */
  savedUrl: string | null;
  /** Live, because the app paints the title over the image. */
  title: string;
  onFile: (file: File | null) => void;
  onPreview: (url: string | null) => void;
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
    (picked: File) => {
      if (objectUrl.current) URL.revokeObjectURL(objectUrl.current);

      const url = URL.createObjectURL(picked);
      objectUrl.current = url;

      setOriginal(picked);
      setCropNote(null);
      setError(null);

      onFile(picked);
      onPreview(url);
    },
    [onFile, onPreview],
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
    },
    [onFile, onPreview],
  );

  /**
   * Crop something already chosen. Prefers the file in hand, and otherwise
   * reaches for the image already on the record, so tidying up an existing
   * banner does not mean going and re-downloading it.
   */
  const adjust = useCallback(async () => {
    setError(null);

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
  }, [original, savedUrl]);

  const revert = useCallback(() => {
    if (!original) return;

    if (objectUrl.current) URL.revokeObjectURL(objectUrl.current);

    const url = URL.createObjectURL(original);
    objectUrl.current = url;

    setCropNote(null);
    onFile(original);
    onPreview(url);
  }, [original, onFile, onPreview]);

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
  }, [onFile, onPreview, savedUrl]);

  const showsImage = Boolean(previewUrl);

  return (
    <div className={styles.studio}>
      {showsImage ? (
        <>
          <div className={styles.studioToolbar}>
            <span className={styles.studioFilename} title={file?.name || savedUrl || ''}>
              {cropNote ? `Cropped — ${cropNote}` : file?.name || 'Saved banner'}
            </span>

            <div className={styles.studioButtons}>
              <button
                type="button"
                className={styles.studioSecondaryBtn}
                onClick={adjust}
                disabled={busy}
              >
                Crop &amp; adjust
              </button>

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

          <AppPreview imageUrl={previewUrl!} title={title} screenWidth={device.width} />
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
            if (dropped) take(dropped);
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
            )}:100
          </span>
        </div>
      )}

      <input
        ref={inputRef}
        type="file"
        accept="image/*"
        className={styles.hiddenInput}
        onChange={(e) => {
          const picked = e.target.files?.[0];
          e.target.value = '';
          if (picked) take(picked);
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
