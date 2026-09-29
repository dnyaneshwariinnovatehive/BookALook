import { NextResponse } from 'next/server';
import { cookies } from 'next/headers';

const BACKEND_URL = (process.env.NEXT_PUBLIC_BACKEND_URL || 'https://api.bookalook.in').replace(/\/$/, '');

/**
 * Proxy for the invoice format settings.
 *
 * Same shape as the policy proxy: the browser never sees the backend token, it
 * only ever sees this route, and the httpOnly cookie stays where it is.
 */
/**
 * Read the backend's answer without ever losing it.
 *
 * `res.json()` throws on anything that is not JSON — and a 500 from Laravel is
 * an HTML error page, not JSON. Letting that throw landed in the catch below,
 * which replaced the real status and the real message with a generic
 * "Internal Server Error", so a database or deployment problem was
 * indistinguishable from a bad request. Reading as text and parsing by hand
 * keeps the status and, when the body really is JSON, the message.
 */
async function readBackend(res: Response): Promise<unknown> {
  const raw = await res.text();

  try {
    return JSON.parse(raw);
  } catch {
    console.error(
      `Invoice settings: backend returned ${res.status} with a non-JSON body.`,
      raw.slice(0, 1000),
    );

    return {
      message: `The server responded with ${res.status} ${res.statusText || 'error'}. See the server logs for the cause.`,
    };
  }
}

export async function GET() {
  const cookieStore = await cookies();
  const token = cookieStore.get('superadmin_token')?.value;

  if (!token) {
    return NextResponse.json({ message: 'Unauthenticated' }, { status: 401 });
  }

  try {
    const res = await fetch(`${BACKEND_URL}/api/superadmin/settings/invoice`, {
      headers: {
        'Authorization': `Bearer ${token}`,
        'Accept': 'application/json',
      },
      cache: 'no-store',
    });

    return NextResponse.json(await readBackend(res), { status: res.status });
  } catch (error) {
    console.error('Error fetching invoice settings:', error);
    return NextResponse.json({ message: 'Could not reach the server.' }, { status: 502 });
  }
}

export async function PUT(request: Request) {
  const cookieStore = await cookies();
  const token = cookieStore.get('superadmin_token')?.value;

  if (!token) {
    return NextResponse.json({ message: 'Unauthenticated' }, { status: 401 });
  }

  const body = await request.json();

  try {
    const res = await fetch(`${BACKEND_URL}/api/superadmin/settings/invoice`, {
      method: 'PUT',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    });

    return NextResponse.json(await readBackend(res), { status: res.status });
  } catch (error) {
    console.error('Error updating invoice settings:', error);
    return NextResponse.json({ message: 'Could not reach the server.' }, { status: 502 });
  }
}
