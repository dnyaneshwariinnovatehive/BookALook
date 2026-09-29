/**
 * Unsigned Cloudinary upload.
 *
 * The browser posts the file straight to Cloudinary using the unsigned upload
 * preset, so the file never passes through this server and no API secret is
 * ever exposed to the client. What comes back is only a `secure_url`, which is
 * all any caller should ever keep.
 */

/** Configured in the site's `.env`; both are public by design. */
function cloudinaryConfig(): { cloudName: string; uploadPreset: string } {
  const cloudName = process.env.NEXT_PUBLIC_CLOUDINARY_CLOUD_NAME;
  const uploadPreset = process.env.NEXT_PUBLIC_CLOUDINARY_UPLOAD_PRESET;

  if (!cloudName || !uploadPreset) {
    throw new Error(
      'Cloudinary is not configured. Set NEXT_PUBLIC_CLOUDINARY_CLOUD_NAME and NEXT_PUBLIC_CLOUDINARY_UPLOAD_PRESET.',
    );
  }

  return { cloudName, uploadPreset };
}

export class UploadError extends Error {}

/**
 * Upload one image and return its public https URL.
 *
 * @throws {UploadError} with a message fit to show a SuperAdmin, carrying
 *   Cloudinary's own wording when Cloudinary gave one.
 */
export async function uploadImage(file: File): Promise<string> {
  if (!file.type.startsWith('image/')) {
    throw new UploadError('That file is not an image.');
  }

  // 5 MB. A letterhead logo is a few KB; anything larger is a photograph that
  // was picked by mistake, and rejecting it here is kinder than uploading it.
  if (file.size > 5 * 1024 * 1024) {
    throw new UploadError('That image is larger than 5 MB.');
  }

  const { cloudName, uploadPreset } = cloudinaryConfig();

  const body = new FormData();
  body.append('file', file);
  body.append('upload_preset', uploadPreset);

  let res: Response;
  try {
    res = await fetch(`https://api.cloudinary.com/v1_1/${cloudName}/image/upload`, {
      method: 'POST',
      body,
    });
  } catch {
    throw new UploadError('Could not reach Cloudinary. Check your connection.');
  }

  const data = await res.json().catch(() => null);

  if (!res.ok) {
    throw new UploadError(
      data?.error?.message ?? `Upload failed (${res.status}). Please try again.`,
    );
  }

  if (typeof data?.secure_url !== 'string' || data.secure_url === '') {
    throw new UploadError('Upload finished but returned no image URL.');
  }

  return data.secure_url;
}
