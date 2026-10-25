<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\PhoneChangeService;
use Illuminate\Http\Request;

/**
 * "Change phone number" for whoever is signed in — customer, salon owner,
 * staff member or collaborator. Two steps: send a code to the new number,
 * then confirm it. Mounted under both the customer and partner prefixes.
 */
class AccountPhoneController extends Controller
{
    public function __construct(private PhoneChangeService $phones)
    {
    }

    public function sendCode(Request $request)
    {
        $request->validate(['phone' => 'required|string|max:20']);

        $message = $this->phones->sendCode($request->user(), $request->input('phone'));

        return response()->json([
            'message' => $message,
            'phone' => $this->phones->normalise($request->input('phone')),
        ]);
    }

    public function confirm(Request $request)
    {
        $request->validate([
            'phone' => 'required|string|max:20',
            'otp' => 'required|string|max:10',
        ]);

        $user = $this->phones->confirm($request->user(), $request->input('phone'), $request->input('otp'));

        return response()->json([
            'message' => 'Phone number updated.',
            'user' => $user,
        ]);
    }
}
