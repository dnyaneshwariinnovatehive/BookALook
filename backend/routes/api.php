<?php

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;
use App\Http\Controllers\Api\Customer\CustomerAuthController;
use App\Http\Controllers\Api\SuperAdmin\SuperAdminAuthController;

Route::prefix('customer')->group(function () {
    Route::post('/auth/send-otp', [CustomerAuthController::class, 'sendOtp']);
    Route::post('/auth/verify-otp', [CustomerAuthController::class, 'verifyOtp']);
    Route::post('/auth/complete-profile', [CustomerAuthController::class, 'completeProfile']);

    // Protected customer routes
    Route::middleware('auth:sanctum')->group(function () {
        Route::post('/auth/logout', [CustomerAuthController::class, 'logout']);
        Route::get('/profile', function (Request $request) {
            return $request->user();
        });
    });
});

Route::prefix('superadmin')->group(function () {
    Route::post('/auth/login', [SuperAdminAuthController::class, 'login']);

    // Protected superadmin routes
    Route::middleware('auth:sanctum')->group(function () {
        Route::post('/auth/logout', [SuperAdminAuthController::class, 'logout']);
    });
});
