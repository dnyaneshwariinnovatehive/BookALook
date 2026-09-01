<?php

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;
use App\Http\Controllers\Api\Customer\CustomerAuthController;

Route::prefix('customer')->group(function () {
    Route::post('/auth/send-otp', [CustomerAuthController::class, 'sendOtp']);
    Route::post('/auth/verify-otp', [CustomerAuthController::class, 'verifyOtp']);

    // Protected customer routes
    Route::middleware('auth:sanctum')->group(function () {
        Route::post('/auth/logout', [CustomerAuthController::class, 'logout']);
        Route::get('/profile', function (Request $request) {
            return $request->user();
        });
    });
});
