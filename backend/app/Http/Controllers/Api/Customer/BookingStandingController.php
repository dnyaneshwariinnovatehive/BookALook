<?php

namespace App\Http\Controllers\Api\Customer;

use App\Http\Controllers\Controller;
use App\Services\CustomerStandingService;
use Illuminate\Http\Request;

/**
 * Where the signed-in customer stands against the cancellation and no-show
 * limits, so checkout can say so before they try to book.
 */
class BookingStandingController extends Controller
{
    public function show(Request $request, CustomerStandingService $standing)
    {
        return response()->json(['standing' => $standing->standing($request->user())]);
    }
}
