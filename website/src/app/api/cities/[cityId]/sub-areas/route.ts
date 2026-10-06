import { NextResponse } from 'next/server';

const BACKEND_URL = (process.env.NEXT_PUBLIC_BACKEND_URL || 'https://api.bookalook.in').replace(/\/$/, '');

export async function GET(request: Request, { params }: { params: Promise<{ cityId: string }> }) {
  const { cityId } = await params;
  const search = new URL(request.url).searchParams.get('search') || '';

  try {
    const url = new URL(`${BACKEND_URL}/api/cities/${cityId}/sub-areas`);
    if (search) url.searchParams.set('search', search);

    const res = await fetch(url, {
      headers: {
        'Accept': 'application/json',
      },
    });

    const data = await res.json();
    return NextResponse.json(data, { status: res.status });
  } catch (error) {
    console.error('Error fetching sub-areas:', error);
    return NextResponse.json({ message: 'Internal Server Error' }, { status: 500 });
  }
}
