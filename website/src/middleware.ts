import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';

export function middleware(request: NextRequest) {
  // Check if the user has an auth cookie
  const authCookie = request.cookies.get('superadmin_token');
  const { pathname } = request.nextUrl;

  const isAdminRoute = pathname.startsWith('/superadmin');
  const isLoginRoute = pathname === '/login';

  if (isAdminRoute && !authCookie) {
    // Redirect to login if not authenticated and trying to access an admin route
    return NextResponse.redirect(new URL('/login', request.url));
  }

  if (isLoginRoute && authCookie) {
    // Redirect to admin dashboard if already authenticated
    return NextResponse.redirect(new URL('/superadmin', request.url));
  }

  return NextResponse.next();
}

export const config = {
  // Run middleware on all routes except static files and next internals
  matcher: ['/((?!_next/static|_next/image|favicon.ico).*)'],
};
