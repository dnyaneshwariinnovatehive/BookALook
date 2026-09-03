import { NextRequest, NextResponse } from 'next/server';
import { cookies } from 'next/headers';

async function handleRequest(req: NextRequest, { params }: { params: Promise<{ path: string[] }> }) {
  const resolvedParams = await params;
  const path = resolvedParams.path.join('/');
  const cookieStore = await cookies();
  const token = cookieStore.get('superadmin_token')?.value;
  
  const backendUrl = `http://localhost:8000/api/${path}${req.nextUrl.search}`;
  
  const headers: Record<string, string> = {
    'Accept': 'application/json',
  };

  if (token) {
    headers['Authorization'] = `Bearer ${token}`;
  }
  
  const contentType = req.headers.get('content-type');
  if (contentType) {
    headers['Content-Type'] = contentType;
  }

  let body: any;
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    if (contentType?.includes('multipart/form-data')) {
      // Reconstruct FormData to ensure Next.js fetch sends it with the correct boundary
      body = await req.formData();
      delete headers['Content-Type']; // Let fetch automatically set the boundary
    } else {
      body = await req.text();
    }
  }

  try {
    const backendRes = await fetch(backendUrl, {
      method: req.method,
      headers,
      body,
    });

    const data = await backendRes.text();
    return new NextResponse(data, {
      status: backendRes.status,
      headers: {
        'Content-Type': backendRes.headers.get('content-type') || 'application/json',
      }
    });
  } catch (error) {
    console.error('Proxy error:', error);
    return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
  }
}

export const GET = handleRequest;
export const POST = handleRequest;
export const PUT = handleRequest;
export const DELETE = handleRequest;
export const PATCH = handleRequest;
