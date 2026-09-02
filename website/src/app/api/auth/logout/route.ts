import { NextResponse } from 'next/server';
import { cookies } from 'next/headers';

export async function POST() {
  const cookieStore = await cookies();
  const token = cookieStore.get('superadmin_token')?.value;

  if (token) {
    try {
      // Call the Laravel backend to revoke the token
      await fetch('http://localhost:8000/api/superadmin/auth/logout', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`,
          'Accept': 'application/json',
        },
      });
    } catch (error) {
      console.error('Failed to logout from backend', error);
    }
  }

  const response = NextResponse.json({ success: true }, { status: 200 });
  
  // Clear the authentication cookie
  response.cookies.delete('superadmin_token');

  return response;
}
