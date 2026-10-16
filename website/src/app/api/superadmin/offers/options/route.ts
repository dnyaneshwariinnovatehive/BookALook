import { NextResponse } from 'next/server';
import { cookies } from 'next/headers';

const BACKEND_BASE = (process.env.NEXT_PUBLIC_BACKEND_URL || 'https://api.bookalook.in').replace(/\/$/, '');

async function resolveToken(request: Request): Promise<string | undefined> {
  const cookieStore = await cookies();
  const tokenFromCookie = cookieStore.get('superadmin_token')?.value;
  if (tokenFromCookie) return tokenFromCookie;

  const authHeader = request.headers.get('authorization');
  if (authHeader?.startsWith('Bearer ')) {
    return authHeader.substring(7);
  }
  return undefined;
}

export async function GET(request: Request) {
  const token = await resolveToken(request);

  if (!token) {
    return NextResponse.json({ message: 'Unauthenticated' }, { status: 401 });
  }

  try {
    const backendRes = await fetch(`${BACKEND_BASE}/api/superadmin/offers/options`, {
      method: 'GET',
      headers: {
        'Accept': 'application/json',
        'Authorization': `Bearer ${token}`,
      },
      cache: 'no-store',
    });

    const textData = await backendRes.text();
    let data;
    try {
      data = JSON.parse(textData);
    } catch {
      data = { message: 'Invalid JSON from backend', text: textData };
    }

    return NextResponse.json(data, { status: backendRes.status });
  } catch (error) {
    console.error('Superadmin offers options GET error:', error);
    return NextResponse.json({ message: 'Internal server error' }, { status: 500 });
  }
}
