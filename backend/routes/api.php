<?php

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;
use App\Http\Controllers\Api\Customer\CustomerAuthController;
use App\Http\Controllers\Api\SuperAdmin\SuperAdminAuthController;

Route::prefix('customer')->group(function () {
    Route::post('/auth/send-otp', [CustomerAuthController::class, 'sendOtp']);
    Route::post('/auth/verify-otp', [CustomerAuthController::class, 'verifyOtp']);
    Route::post('/auth/complete-profile', [CustomerAuthController::class, 'completeProfile']);
    
    // Public routes
    Route::get('/banners', [\App\Http\Controllers\Api\Customer\BannerController::class, 'index']);

    // Protected customer routes
    Route::middleware('auth:sanctum')->group(function () {
        Route::post('/auth/logout', [CustomerAuthController::class, 'logout']);
        Route::get('/profile', function (Request $request) {
            return $request->user();
        });
    });
});

// Public global routes
Route::get('/cities', [\App\Http\Controllers\Api\CityController::class, 'index']);
Route::get('/cities', [\App\Http\Controllers\Api\CityController::class, 'index']);

Route::prefix('superadmin')->group(function () {
    Route::post('/auth/login', [SuperAdminAuthController::class, 'login']);

    // Protected superadmin routes
    Route::middleware('auth:sanctum')->group(function () {
        Route::post('/auth/logout', [SuperAdminAuthController::class, 'logout']);
        Route::get('/salons', [\App\Http\Controllers\Api\SuperAdmin\SalonController::class, 'index']);
        Route::apiResource('banners', \App\Http\Controllers\Api\SuperAdmin\BannerController::class);
    });
});

Route::prefix('partner')->group(function () {
    Route::post('/register', [\App\Http\Controllers\Api\Partner\SalonRegistrationController::class, 'register']);
});
