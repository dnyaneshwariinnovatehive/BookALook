import { NextResponse } from 'next/server';
import { cookies } from 'next/headers';

const BACKEND_URL = 'http://localhost:8000/api/superadmin/banners';

export async function GET(request: Request) {
  const cookieStore = await cookies();
  const token = cookieStore.get('superadmin_token')?.value;

  if (!token) {
    return NextResponse.json({ message: 'Unauthenticated' }, { status: 401 });
  }

  const { searchParams } = new URL(request.url);
  const queryString = searchParams.toString();
  const backendUrl = queryString ? `${BACKEND_URL}?${queryString}` : BACKEND_URL;

  try {
    const backendRes = await fetch(backendUrl, {
      method: 'GET',
      headers: {
        'Accept': 'application/json',
        'Authorization': `Bearer ${token}`
      },
      cache: 'no-store'
    });

    const textData = await backendRes.text();
    console.log("Backend Status:", backendRes.status);
    console.log("Backend Response:", textData);
    
    let data;
    try {
      data = JSON.parse(textData);
    } catch(e) {
      data = { message: "Invalid JSON from backend", text: textData };
    }
    return NextResponse.json(data, { status: backendRes.status });
  } catch (error) {
    return NextResponse.json({ message: 'Internal server error' }, { status: 500 });
  }
}

export async function POST(request: Request) {
  const cookieStore = await cookies();
  const token = cookieStore.get('superadmin_token')?.value;

  if (!token) {
    return NextResponse.json({ message: 'Unauthenticated' }, { status: 401 });
  }

  try {
    const body = await request.json();
    
    const backendRes = await fetch(BACKEND_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': `Bearer ${token}`
      },
      body: JSON.stringify(body)
    });

    const textData = await backendRes.text();
    console.log("POST Backend Status:", backendRes.status);
    console.log("POST Backend Response:", textData);
    
    let data;
    try {
      data = JSON.parse(textData);
    } catch(e) {
      data = { message: "Invalid JSON from backend", text: textData };
    }
    return NextResponse.json(data, { status: backendRes.status });
  } catch (error) {
    return NextResponse.json({ message: 'Internal server error' }, { status: 500 });
  }
}
