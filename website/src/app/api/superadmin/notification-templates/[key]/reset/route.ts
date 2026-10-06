import { NextResponse } from 'next/server';
import { cookies } from 'next/headers';

const getBackendUrl = (key: string) => `${(process.env.NEXT_PUBLIC_BACKEND_URL || 'https://api.bookalook.in').replace(/\/$/, '')}/api/superadmin/notification-templates/${key}/reset`;

export async function POST(request: Request, { params }: { params: Promise<{ key: string }> }) {
  const cookieStore = await cookies();
  const token = cookieStore.get('superadmin_token')?.value;

  if (!token) {
    return NextResponse.json({ message: 'Unauthenticated' }, { status: 401 });
  }

  try {
    const { key } = await params;
    const backendRes = await fetch(getBackendUrl(key), {
      method: 'POST',
      headers: {
        'Accept': 'application/json',
        'Authorization': `Bearer ${token}`
      }
    });

    const data = await backendRes.json();
    return NextResponse.json(data, { status: backendRes.status });
  } catch (error) {
    return NextResponse.json({ message: 'Internal server error' }, { status: 500 });
  }
}
