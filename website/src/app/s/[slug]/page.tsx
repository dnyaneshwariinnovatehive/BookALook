import { notFound } from 'next/navigation';
import SalonLanding from './SalonLanding';

const BACKEND_URL = process.env.NEXT_PUBLIC_BACKEND_URL || 'http://127.0.0.1:8000';

/**
 * Where a salon's printed QR code lands.
 *
 * Somebody is standing in front of the salon holding a phone. They scanned a
 * poster with the camera or Google Lens, which is why this is an ordinary web
 * page on https rather than a custom scheme — a scheme would simply do nothing
 * in either of those.
 *
 * Rendered on the server so the salon's name and photo are in the HTML before
 * any JavaScript runs. A page that flashes a spinner at somebody in a doorway
 * has already lost them.
 */

interface Props {
  params: Promise<{ slug: string }>;
}

async function fetchSalon(slug: string) {
  try {
    const res = await fetch(`${BACKEND_URL}/api/public/salons/${encodeURIComponent(slug)}`, {
      headers: { Accept: 'application/json' },
      // The salon's details and the store links both change without a deploy,
      // so this is revalidated rather than baked in at build time.
      next: { revalidate: 60 },
    });

    if (!res.ok) return null;

    const data = await res.json();
    return data.success ? data : null;
  } catch {
    return null;
  }
}

export async function generateMetadata({ params }: Props) {
  const { slug } = await params;
  const data = await fetchSalon(slug);

  if (!data) return { title: 'Salon not found · BookALook' };

  const { salon } = data;

  return {
    title: `${salon.name} · Book on BookALook`,
    description:
      salon.description ||
      `Book an appointment at ${salon.name}${salon.city ? `, ${salon.city}` : ''} on BookALook.`,
    openGraph: {
      title: `${salon.name} · BookALook`,
      description: salon.description || `Book an appointment at ${salon.name}.`,
      images: salon.cover_photo_url ? [salon.cover_photo_url] : [],
    },
  };
}

export default async function SalonQrLandingPage({ params }: Props) {
  const { slug } = await params;
  const data = await fetchSalon(slug);

  if (!data) notFound();

  return (
    <SalonLanding
      salon={data.salon}
      deepLink={data.deep_link}
      androidIntentLink={data.android_intent_link}
      appLinks={data.app_links}
    />
  );
}
