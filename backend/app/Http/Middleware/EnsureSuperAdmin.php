<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Lets only the platform owner through.
 *
 * `auth:sanctum` alone proves a token is valid, not whose it is: a salon
 * owner's or a customer's token would pass it just as well. Anything that
 * changes what every salon sees — the master catalog above all — sits behind
 * this as well.
 */
class EnsureSuperAdmin
{
    public function handle(Request $request, Closure $next): Response
    {
        if ($request->user()?->role !== 'superadmin') {
            return response()->json([
                'message' => 'Unauthorized. Super Admin access required.',
            ], 403);
        }

        return $next($request);
    }
}
