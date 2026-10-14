import { NextResponse } from 'next/server';
import { cookies } from 'next/headers';

const BACKEND_BASE = (process.env.NEXT_PUBLIC_BACKEND_URL || 'https://api.bookalook.in').replace(/\/$/, '');

export async function GET(
  request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const cookieStore = await cookies();
  const token = cookieStore.get('superadmin_token')?.value;

  if (!token) {
    return NextResponse.json({ message: 'Unauthenticated' }, { status: 401 });
  }

  try {
    const backendRes = await fetch(`${BACKEND_BASE}/api/superadmin/offers/${id}`, {
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
    console.error('Superadmin offer GET [id] error:', error);
    return NextResponse.json({ message: 'Internal server error' }, { status: 500 });
  }
}

export async function PUT(
  request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const cookieStore = await cookies();
  const token = cookieStore.get('superadmin_token')?.value;

  if (!token) {
    return NextResponse.json({ message: 'Unauthenticated' }, { status: 401 });
  }

  try {
    const body = await request.json();

    const backendRes = await fetch(`${BACKEND_BASE}/api/superadmin/offers/${id}`, {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': `Bearer ${token}`,
      },
      body: JSON.stringify(body),
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
    console.error('Superadmin offer PUT [id] error:', error);
    return NextResponse.json({ message: 'Internal server error' }, { status: 500 });
  }
}

export async function DELETE(
  request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const cookieStore = await cookies();
  const token = cookieStore.get('superadmin_token')?.value;

  if (!token) {
    return NextResponse.json({ message: 'Unauthenticated' }, { status: 401 });
  }

  try {
    const backendRes = await fetch(`${BACKEND_BASE}/api/superadmin/offers/${id}`, {
      method: 'DELETE',
      headers: {
        'Accept': 'application/json',
        'Authorization': `Bearer ${token}`,
      },
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
    console.error('Superadmin offer DELETE [id] error:', error);
    return NextResponse.json({ message: 'Internal server error' }, { status: 500 });
  }
}
