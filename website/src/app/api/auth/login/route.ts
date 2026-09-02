import { NextResponse } from 'next/server';

export async function POST(request: Request) {
  try {
    const { email, password } = await request.json();

    // Call the Laravel backend
    const backendRes = await fetch('http://localhost:8000/api/superadmin/auth/login', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: JSON.stringify({ email, password }),
    });

    const data = await backendRes.json();

    if (backendRes.ok && data.success) {
      const response = NextResponse.json({ success: true }, { status: 200 });
      
      // Set the returned Sanctum token in a cookie
      response.cookies.set({
        name: 'superadmin_token',
        value: data.token,
        httpOnly: true,
        secure: process.env.NODE_ENV === 'production',
        sameSite: 'lax',
        path: '/',
        maxAge: 60 * 60 * 24 * 7, // 1 week
      });

      return response;
    }

    return NextResponse.json(
      { success: false, message: data.message || 'Invalid credentials' },
      { status: backendRes.status }
    );
  } catch (error) {
    return NextResponse.json(
      { success: false, message: 'Internal server error' },
      { status: 500 }
    );
  }
}
