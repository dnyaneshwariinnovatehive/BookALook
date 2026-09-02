import { NextResponse } from 'next/server';

const BACKEND_URL = process.env.NEXT_PUBLIC_BACKEND_URL || 'http://127.0.0.1:8000';

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const search = searchParams.get('search') || '';

  try {
    const res = await fetch(`${BACKEND_URL}/api/cities?search=${encodeURIComponent(search)}`, {
      headers: {
        'Accept': 'application/json',
      },
    });

    const data = await res.json();
    return NextResponse.json(data, { status: res.status });
  } catch (error) {
    console.error('Error fetching cities:', error);
    return NextResponse.json({ message: 'Internal Server Error' }, { status: 500 });
  }
}
