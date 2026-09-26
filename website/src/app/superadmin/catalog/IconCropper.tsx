'use client';

import ImageCropper, { type CropSource } from '@/components/admin/ImageCropper';

/**
 * The square half of the shared crop box.
 *
 * A category icon is painted into a square tile, so 1:1 is the only ratio that
 * can be cropped to, and the delivered PNG is never below what the server will
 * accept. Everything about how the crop behaves lives in `ImageCropper`; this
 * only states what a category icon needs.
 */

export type { CropSource };

/** Icons are delivered at 512×512; anything under that is scaled up to it. */
const OUTPUT = 512;

export default function IconCropper({
  source,
  onApply,
  onCancel,
}: {
  source: CropSource;
  onApply: (file: File, detail: string) => void;
  onCancel: () => void;
}) {
  return (
    <ImageCropper
      source={source}
      ratio={1}
      frameWidth={340}
      checkerboard
      minOutput={OUTPUT}
      outputType="image/png"
      title="Crop the icon"
      help="The frame is square because the app shows every icon square. Drag to reposition, scroll or use the slider to zoom."
      hint="Empty margins are trimmed afterwards, so leaving some space around the subject is fine."
      onApply={onApply}
      onCancel={onCancel}
    />
  );
}
